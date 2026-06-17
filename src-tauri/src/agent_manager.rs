use serde_json::{json, Value};
use std::{
    collections::HashMap,
    sync::{
        atomic::{AtomicU64, Ordering},
        mpsc, Arc, Mutex,
    },
    thread,
    time::Duration,
};
use tauri::AppHandle;
use tauri_plugin_shell::{
    process::{CommandChild, CommandEvent},
    ShellExt,
};

const MAX_STDOUT_BUFFER_BYTES: usize = 50 * 1024 * 1024;

#[derive(Default)]
pub struct AgentManager {
    child: Arc<Mutex<Option<CommandChild>>>,
    pending: Arc<Mutex<HashMap<String, mpsc::Sender<Result<Value, String>>>>>,
    stdout_buffer: Arc<Mutex<String>>,
    next_id: AtomicU64,
}

impl AgentManager {
    pub fn start(&self, app: AppHandle) -> Result<(), Box<dyn std::error::Error>> {
        let mut child_slot = self.child.lock().map_err(|_| "agent child lock poisoned")?;
        if child_slot.is_some() {
            return Ok(());
        }

        let (mut rx, child) = app.shell().sidecar("virtualdesk-agent")?.spawn()?;
        let pending = Arc::clone(&self.pending);
        let stdout_buffer = Arc::clone(&self.stdout_buffer);
        let child_ref = Arc::clone(&self.child);

        tauri::async_runtime::spawn(async move {
            while let Some(event) = rx.recv().await {
                match event {
                    CommandEvent::Stdout(bytes) => {
                        handle_stdout(&pending, &stdout_buffer, bytes);
                    }
                    CommandEvent::Stderr(bytes) => {
                        eprintln!("[virtualdesk-agent] {}", String::from_utf8_lossy(&bytes));
                    }
                    CommandEvent::Terminated(payload) => {
                        eprintln!("[virtualdesk-agent] terminated: {:?}", payload);
                        if let Ok(mut child_slot) = child_ref.lock() {
                            *child_slot = None;
                        }
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
        let child = self.child.lock().ok().and_then(|mut child| child.take());
        if let Some(mut child) = child {
            let _ =
                child.write(b"{\"id\":\"shutdown\",\"method\":\"stop_workspace\",\"params\":{}}\n");
            thread::sleep(Duration::from_millis(800));
            let _ = child.kill();
        }
        if let Ok(mut buffer) = self.stdout_buffer.lock() {
            buffer.clear();
        }
        reject_pending_requests(&self.pending, "VirtualDesk agent was shut down");
    }
}

fn handle_stdout(
    pending: &Arc<Mutex<HashMap<String, mpsc::Sender<Result<Value, String>>>>>,
    stdout_buffer: &Arc<Mutex<String>>,
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
            eprintln!("[virtualdesk-agent-event] {}", event_name);
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

#[cfg(test)]
mod tests {
    use super::collect_stdout_lines;

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
}
