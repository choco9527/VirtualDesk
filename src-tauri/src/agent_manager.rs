use serde_json::{json, Value};
use std::{
    collections::HashMap,
    fs,
    io::{Read, Write},
    os::unix::net::UnixStream,
    process::Command,
    sync::{
        atomic::{AtomicBool, AtomicU64, Ordering},
        mpsc, Arc, Mutex,
    },
    thread,
    time::{Duration, Instant},
};
use tauri::{AppHandle, Emitter};
use tauri_plugin_shell::{
    process::{CommandChild, CommandEvent},
    ShellExt,
};

const MAX_STDOUT_BUFFER_BYTES: usize = 50 * 1024 * 1024;
pub const AGENT_EVENT_CHANNEL: &str = "virtualdesk://agent-event";
const AGENT_TERMINATED_EVENT: &str = "agent_terminated";
const AGENT_LOCK_PATH: &str = "/tmp/virtualdesk-agent.lock";
const AGENT_STATE_PATH: &str = "/tmp/virtualdesk-agent-state.json";
const AGENT_SOCKET_PATH: &str = "/tmp/virtualdesk-agent.sock";
const AGENT_SHUTDOWN_GRACE: Duration = Duration::from_millis(1_500);

#[derive(Default)]
pub struct AgentManager {
    child: Arc<Mutex<Option<CommandChild>>>,
    pending: Arc<Mutex<HashMap<String, mpsc::Sender<Result<Value, String>>>>>,
    stdout_buffer: Arc<Mutex<String>>,
    last_status: Arc<Mutex<Option<Value>>>,
    shutting_down: Arc<AtomicBool>,
    next_id: AtomicU64,
}

impl AgentManager {
    pub fn start(&self, app: AppHandle) -> Result<(), Box<dyn std::error::Error>> {
        let mut child_slot = self.child.lock().map_err(|_| "agent child lock poisoned")?;
        if child_slot.is_some() {
            return Ok(());
        }
        preflight_agent_runtime();
        clear_last_status(&self.last_status);
        clear_stdout_buffer(&self.stdout_buffer);
        self.shutting_down.store(false, Ordering::SeqCst);

        let (mut rx, child) = app
            .shell()
            .sidecar("virtualdesk-agent")?
            .args(["agent"])
            .spawn()?;
        let pending = Arc::clone(&self.pending);
        let stdout_buffer = Arc::clone(&self.stdout_buffer);
        let child_ref = Arc::clone(&self.child);
        let last_status = Arc::clone(&self.last_status);
        let shutting_down = Arc::clone(&self.shutting_down);
        let app_handle = app.clone();

        tauri::async_runtime::spawn(async move {
            while let Some(event) = rx.recv().await {
                match event {
                    CommandEvent::Stdout(bytes) => {
                        handle_stdout(&app_handle, &pending, &stdout_buffer, &last_status, bytes);
                    }
                    CommandEvent::Stderr(bytes) => {
                        eprintln!("[virtualdesk-agent] {}", String::from_utf8_lossy(&bytes));
                    }
                    CommandEvent::Terminated(payload) => {
                        eprintln!("[virtualdesk-agent] terminated: {:?}", payload);
                        if let Ok(mut child_slot) = child_ref.lock() {
                            *child_slot = None;
                        }
                        clear_stdout_buffer(&stdout_buffer);
                        if shutting_down.swap(false, Ordering::SeqCst) {
                            reject_pending_requests(&pending, "VirtualDesk agent was shut down");
                            break;
                        }
                        let payload = last_status
                            .lock()
                            .ok()
                            .and_then(|status| status.clone())
                            .map(terminated_event_payload)
                            .unwrap_or_else(|| terminated_event_payload(Value::Null));
                        let _ = app_handle.emit(AGENT_EVENT_CHANNEL, payload);
                        reject_pending_requests(&pending, "VirtualDesk agent terminated");
                        break;
                    }
                    _ => {}
                }
            }
        });

        *child_slot = Some(child);
        Ok(())
    }

    pub async fn request(&self, method: &str, params: Value) -> Result<Value, String> {
        let id = self.next_id.fetch_add(1, Ordering::Relaxed).to_string();
        let request = json!({ "id": id, "method": method, "params": params });
        let request_line = format!("{}\n", request);
        let (tx, rx) = mpsc::channel();

        self.pending
            .lock()
            .map_err(|_| "pending response lock poisoned".to_string())?
            .insert(id.clone(), tx);

        let write_result = {
            let mut child_slot = self
                .child
                .lock()
                .map_err(|_| "agent child lock poisoned".to_string())?;
            let child = child_slot
                .as_mut()
                .ok_or_else(|| "VirtualDesk agent is not running".to_string())?;
            child.write(request_line.as_bytes())
        };

        if let Err(error) = write_result {
            self.pending
                .lock()
                .ok()
                .and_then(|mut pending| pending.remove(&id));
            return Err(error.to_string());
        }

        let pending = Arc::clone(&self.pending);
        let pending_id = id.clone();
        tauri::async_runtime::spawn_blocking(move || {
            rx.recv_timeout(Duration::from_secs(20)).map_err(|_| {
                pending
                    .lock()
                    .ok()
                    .and_then(|mut pending| pending.remove(&pending_id));
                "Timed out waiting for VirtualDesk agent".to_string()
            })?
        })
        .await
        .map_err(|error| error.to_string())?
    }

    pub fn shutdown(&self) {
        self.shutting_down.store(true, Ordering::SeqCst);
        let child = self.child.lock().ok().and_then(|mut child| child.take());
        if let Some(mut child) = child {
            let _ =
                child.write(b"{\"id\":\"shutdown\",\"method\":\"stop_workspace\",\"params\":{}}\n");
            thread::sleep(Duration::from_millis(1_000));
            let _ = child.kill();
        }
        if let Ok(mut buffer) = self.stdout_buffer.lock() {
            buffer.clear();
        }
        cleanup_runtime_files();
        clear_last_status(&self.last_status);
        reject_pending_requests(&self.pending, "VirtualDesk agent was shut down");
    }
}

fn preflight_agent_runtime() {
    let _ = request_control_stop();
    wait_for_lock_pid_to_exit(AGENT_SHUTDOWN_GRACE);

    if let Some(pid) = read_lock_pid() {
        if process_looks_like_agent(pid) {
            terminate_process(pid);
            wait_for_lock_pid_to_exit(AGENT_SHUTDOWN_GRACE);
        }
    }

    cleanup_runtime_files();
}

fn request_control_stop() -> std::io::Result<String> {
    let mut stream = UnixStream::connect(AGENT_SOCKET_PATH)?;
    stream.set_read_timeout(Some(Duration::from_millis(800)))?;
    stream.set_write_timeout(Some(Duration::from_millis(800)))?;
    stream.write_all(br#"{"id":"preflight","method":"stop_workspace"}"#)?;
    let _ = stream.shutdown(std::net::Shutdown::Write);

    let mut response = String::new();
    let _ = stream.read_to_string(&mut response);
    Ok(response)
}

fn wait_for_lock_pid_to_exit(timeout: Duration) {
    let started_at = Instant::now();
    while started_at.elapsed() < timeout {
        let Some(pid) = read_lock_pid() else {
            return;
        };
        if !process_exists(pid) {
            return;
        }
        thread::sleep(Duration::from_millis(100));
    }
}

fn read_lock_pid() -> Option<u32> {
    fs::read_to_string(AGENT_LOCK_PATH)
        .ok()
        .and_then(|content| parse_lock_pid(&content))
}

fn parse_lock_pid(content: &str) -> Option<u32> {
    content.trim().parse::<u32>().ok()
}

fn process_exists(pid: u32) -> bool {
    process_command(pid).is_some()
}

fn process_looks_like_agent(pid: u32) -> bool {
    process_command(pid)
        .map(|command| is_agent_command(&command))
        .unwrap_or(false)
}

fn is_agent_command(command: &str) -> bool {
    command.contains("virtualdesk-agent")
}

fn process_command(pid: u32) -> Option<String> {
    let output = Command::new("ps")
        .args(["-p", &pid.to_string(), "-o", "command="])
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }

    let command = String::from_utf8_lossy(&output.stdout).trim().to_string();
    (!command.is_empty()).then_some(command)
}

fn terminate_process(pid: u32) {
    let _ = Command::new("kill")
        .args(["-TERM", &pid.to_string()])
        .status();
    thread::sleep(Duration::from_millis(500));
    if process_exists(pid) {
        let _ = Command::new("kill")
            .args(["-KILL", &pid.to_string()])
            .status();
    }
}

fn cleanup_runtime_files() {
    let _ = fs::remove_file(AGENT_SOCKET_PATH);
    let _ = fs::remove_file(AGENT_STATE_PATH);
    if read_lock_pid()
        .map(|pid| !process_exists(pid))
        .unwrap_or(true)
    {
        let _ = fs::remove_file(AGENT_LOCK_PATH);
    }
}

fn handle_stdout(
    app: &AppHandle,
    pending: &Arc<Mutex<HashMap<String, mpsc::Sender<Result<Value, String>>>>>,
    stdout_buffer: &Arc<Mutex<String>>,
    last_status: &Arc<Mutex<Option<Value>>>,
    bytes: Vec<u8>,
) {
    let lines = stdout_buffer
        .lock()
        .map(|mut buffer| collect_stdout_lines(&mut buffer, &bytes))
        .unwrap_or_default();

    for line in lines {
        let Ok(message) = serde_json::from_str::<Value>(&line) else {
            continue;
        };

        if let Some(event_name) = message.get("event").and_then(Value::as_str) {
            remember_status_snapshot(last_status, event_status_snapshot(&message));
            eprintln!("[virtualdesk-agent-event] {}", event_name);
            let _ = app.emit(AGENT_EVENT_CHANNEL, &message);
            continue;
        }

        let Some(id) = message.get("id").and_then(Value::as_str) else {
            continue;
        };

        let sender = pending
            .lock()
            .ok()
            .and_then(|mut pending| pending.remove(id));
        if let Some(sender) = sender {
            remember_status_snapshot(last_status, response_status_snapshot(&message));
            let result = if message.get("ok").and_then(Value::as_bool).unwrap_or(false) {
                Ok(message.get("result").cloned().unwrap_or(Value::Null))
            } else {
                let error = message
                    .get("error")
                    .and_then(|error| error.get("message"))
                    .and_then(Value::as_str)
                    .unwrap_or("VirtualDesk agent request failed")
                    .to_string();
                Err(error)
            };
            let _ = sender.send(result);
        }
    }
}

fn response_status_snapshot(message: &Value) -> Option<Value> {
    let result = message.get("result")?;
    let state = result.get("state")?.as_str()?;
    if state.is_empty() {
        return None;
    }
    Some(result.clone())
}

fn event_status_snapshot(message: &Value) -> Option<Value> {
    let status = message.get("data")?.get("status")?;
    let state = status.get("state")?.as_str()?;
    if state.is_empty() {
        return None;
    }
    Some(status.clone())
}

fn remember_status_snapshot(last_status: &Arc<Mutex<Option<Value>>>, snapshot: Option<Value>) {
    let Some(snapshot) = snapshot else {
        return;
    };

    if let Ok(mut stored_status) = last_status.lock() {
        *stored_status = Some(snapshot);
    }
}

fn clear_last_status(last_status: &Arc<Mutex<Option<Value>>>) {
    if let Ok(mut stored_status) = last_status.lock() {
        *stored_status = None;
    }
}

fn clear_stdout_buffer(stdout_buffer: &Arc<Mutex<String>>) {
    if let Ok(mut buffer) = stdout_buffer.lock() {
        buffer.clear();
    }
}

fn collect_stdout_lines(buffer: &mut String, bytes: &[u8]) -> Vec<String> {
    buffer.push_str(&String::from_utf8_lossy(bytes));
    if buffer.len() > MAX_STDOUT_BUFFER_BYTES {
        buffer.clear();
        return Vec::new();
    }

    let mut lines = Vec::new();
    while let Some(newline_index) = buffer.find('\n') {
        let line = buffer[..newline_index].trim_end_matches('\r').to_string();
        buffer.drain(..=newline_index);
        if !line.is_empty() {
            lines.push(line);
        }
    }

    lines
}

fn reject_pending_requests(
    pending: &Arc<Mutex<HashMap<String, mpsc::Sender<Result<Value, String>>>>>,
    message: &str,
) {
    let requests = pending
        .lock()
        .map(|mut pending| {
            pending
                .drain()
                .map(|(_, sender)| sender)
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();

    for sender in requests {
        let _ = sender.send(Err(message.to_string()));
    }
}

fn terminated_event_payload(last_status: Value) -> Value {
    let status = if let Some(last_status_object) = last_status.as_object() {
        let mut status = last_status_object.clone();
        status.insert("state".to_string(), Value::String("failed".to_string()));
        status.insert(
            "message".to_string(),
            Value::String("VirtualDesk agent terminated unexpectedly.".to_string()),
        );
        Value::Object(status)
    } else {
        json!({
            "state": "failed",
            "message": "VirtualDesk agent terminated unexpectedly."
        })
    };

    json!({
        "event": AGENT_TERMINATED_EVENT,
        "data": {
            "reason": AGENT_TERMINATED_EVENT,
            "status": status
        }
    })
}

#[cfg(test)]
mod tests {
    use super::{
        clear_last_status, clear_stdout_buffer, collect_stdout_lines, event_status_snapshot,
        is_agent_command, parse_lock_pid, remember_status_snapshot, response_status_snapshot,
        terminated_event_payload, AGENT_TERMINATED_EVENT,
    };
    use serde_json::{json, Value};
    use std::sync::{Arc, Mutex};

    #[test]
    fn buffers_split_json_lines() {
        let mut buffer = String::new();

        assert!(collect_stdout_lines(&mut buffer, br#"{"id":"1","ok":"#).is_empty());
        let lines = collect_stdout_lines(
            &mut buffer,
            br#"true}
{"event":"workspace_started"}
"#,
        );

        assert_eq!(
            lines,
            vec![
                r#"{"id":"1","ok":true}"#.to_string(),
                r#"{"event":"workspace_started"}"#.to_string()
            ]
        );
        assert!(buffer.is_empty());
    }

    #[test]
    fn keeps_incomplete_tail_after_complete_line() {
        let mut buffer = String::new();
        let lines = collect_stdout_lines(&mut buffer, b"{\"id\":\"1\"}\n{\"id\":\"2\"");

        assert_eq!(lines, vec![r#"{"id":"1"}"#.to_string()]);
        assert_eq!(buffer, r#"{"id":"2""#);
    }

    #[test]
    fn terminated_event_payload_reports_failed_state() {
        let payload = terminated_event_payload(Value::Null);

        assert_eq!(
            payload.get("event").and_then(|value| value.as_str()),
            Some(AGENT_TERMINATED_EVENT)
        );
        assert_eq!(
            payload
                .get("data")
                .and_then(|value| value.get("reason"))
                .and_then(|value| value.as_str()),
            Some(AGENT_TERMINATED_EVENT)
        );
        assert_eq!(
            payload
                .get("data")
                .and_then(|value| value.get("status"))
                .and_then(|value| value.get("state"))
                .and_then(|value| value.as_str()),
            Some("failed")
        );
    }

    #[test]
    fn terminated_event_payload_preserves_last_known_context() {
        let payload = terminated_event_payload(json!({
            "state": "running",
            "display": { "id": 7, "name": "Virtual Display" },
            "target_app": { "path": "/Applications/Codex.app" }
        }));

        assert_eq!(
            payload
                .get("data")
                .and_then(|value| value.get("status"))
                .and_then(|value| value.get("display"))
                .and_then(|value| value.get("id"))
                .and_then(|value| value.as_u64()),
            Some(7)
        );
        assert_eq!(
            payload
                .get("data")
                .and_then(|value| value.get("status"))
                .and_then(|value| value.get("target_app"))
                .and_then(|value| value.get("path"))
                .and_then(|value| value.as_str()),
            Some("/Applications/Codex.app")
        );
        assert_eq!(
            payload
                .get("data")
                .and_then(|value| value.get("status"))
                .and_then(|value| value.get("state"))
                .and_then(|value| value.as_str()),
            Some("failed")
        );
    }

    #[test]
    fn status_snapshot_extractors_ignore_non_status_payloads() {
        assert!(
            response_status_snapshot(&json!({ "ok": true, "result": { "apps": [] } })).is_none()
        );
        assert!(
            event_status_snapshot(&json!({ "event": "workspace_started", "data": {} })).is_none()
        );
    }

    #[test]
    fn parse_lock_pid_accepts_pid_file_whitespace() {
        assert_eq!(parse_lock_pid("12345\n"), Some(12345));
        assert_eq!(parse_lock_pid(" 12345 "), Some(12345));
        assert_eq!(parse_lock_pid("not-a-pid"), None);
    }

    #[test]
    fn is_agent_command_matches_only_virtualdesk_agent_processes() {
        assert!(is_agent_command(
            "/Users/choco/my-project/VirtualDisplay/src-tauri/target/debug/virtualdesk-agent agent"
        ));
        assert!(!is_agent_command("target/debug/virtualdesk"));
        assert!(!is_agent_command("node /path/to/vite --host 127.0.0.1"));
    }

    #[test]
    fn clear_last_status_removes_stale_snapshot() {
        let last_status = Arc::new(Mutex::new(None));
        remember_status_snapshot(&last_status, Some(json!({ "state": "running" })));

        clear_last_status(&last_status);

        assert!(last_status
            .lock()
            .ok()
            .and_then(|status| status.clone())
            .is_none());
    }

    #[test]
    fn clear_stdout_buffer_removes_partial_tail() {
        let stdout_buffer = Arc::new(Mutex::new(String::from("{\"id\":\"2\"")));

        clear_stdout_buffer(&stdout_buffer);

        assert_eq!(
            stdout_buffer
                .lock()
                .ok()
                .map(|buffer| buffer.clone())
                .as_deref(),
            Some("")
        );
    }
}
