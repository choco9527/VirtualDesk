use serde_json::{json, Value};
use std::{
    collections::HashMap,
    sync::{
        atomic::{AtomicU64, Ordering},
        mpsc, Arc, Mutex,
    },
    time::Duration,
};
use tauri::AppHandle;
use tauri_plugin_shell::{
    process::{CommandChild, CommandEvent},
    ShellExt,
};

#[derive(Default)]
pub struct AgentManager {
    child: Mutex<Option<CommandChild>>,
    pending: Arc<Mutex<HashMap<String, mpsc::Sender<Result<Value, String>>>>>,
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

        tauri::async_runtime::spawn(async move {
            while let Some(event) = rx.recv().await {
                match event {
                    CommandEvent::Stdout(bytes) => {
                        handle_stdout(&pending, bytes);
                    }
                    CommandEvent::Stderr(bytes) => {
                        eprintln!("[virtualdesk-agent] {}", String::from_utf8_lossy(&bytes));
                    }
                    CommandEvent::Terminated(payload) => {
                        eprintln!("[virtualdesk-agent] terminated: {:?}", payload);
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
            let mut child_slot = self.child.lock().map_err(|_| "agent child lock poisoned".to_string())?;
            let child = child_slot
                .as_mut()
                .ok_or_else(|| "VirtualDesk agent is not running".to_string())?;
            child.write(request_line.as_bytes())
        };

        if let Err(error) = write_result {
            self.pending.lock().ok().and_then(|mut pending| pending.remove(&id));
            return Err(error.to_string());
        }

        tauri::async_runtime::spawn_blocking(move || {
            rx.recv_timeout(Duration::from_secs(20))
                .map_err(|_| "Timed out waiting for VirtualDesk agent".to_string())?
        })
        .await
        .map_err(|error| error.to_string())?
    }

    pub fn shutdown(&self) {
        let child = self.child.lock().ok().and_then(|mut child| child.take());
        if let Some(mut child) = child {
            let _ = child.write(b"{\"id\":\"shutdown\",\"method\":\"stop_workspace\",\"params\":{}}\n");
            let _ = child.kill();
        }
    }
}

fn handle_stdout(
    pending: &Arc<Mutex<HashMap<String, mpsc::Sender<Result<Value, String>>>>>,
    bytes: Vec<u8>,
) {
    let chunk = String::from_utf8_lossy(&bytes);

    for line in chunk.lines() {
        let Ok(message) = serde_json::from_str::<Value>(line) else {
            continue;
        };

        if let Some(event_name) = message.get("event").and_then(Value::as_str) {
            eprintln!("[virtualdesk-agent-event] {}", event_name);
            continue;
        }

        let Some(id) = message.get("id").and_then(Value::as_str) else {
            continue;
        };

        let sender = pending.lock().ok().and_then(|mut pending| pending.remove(id));
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
