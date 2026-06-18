mod agent_manager;

use agent_manager::AgentManager;
use tauri::Manager;

async fn agent_request(
    app: &tauri::AppHandle,
    method: &str,
    params: serde_json::Value,
) -> Result<serde_json::Value, String> {
    let manager = app.state::<AgentManager>();
    manager
        .start(app.clone())
        .map_err(|error| error.to_string())?;
    manager.request(method, params).await
}

#[tauri::command]
async fn agent_status(app: tauri::AppHandle) -> Result<serde_json::Value, String> {
    agent_request(&app, "status", serde_json::json!({})).await
}

#[tauri::command]
async fn accessibility_status(app: tauri::AppHandle) -> Result<serde_json::Value, String> {
    agent_request(&app, "accessibility_status", serde_json::json!({})).await
}

#[tauri::command]
async fn request_accessibility(app: tauri::AppHandle) -> Result<serde_json::Value, String> {
    agent_request(&app, "request_accessibility", serde_json::json!({})).await
}

#[tauri::command]
async fn screen_capture_status(app: tauri::AppHandle) -> Result<serde_json::Value, String> {
    agent_request(&app, "screen_capture_status", serde_json::json!({})).await
}

#[tauri::command]
async fn request_screen_capture(app: tauri::AppHandle) -> Result<serde_json::Value, String> {
    agent_request(&app, "request_screen_capture", serde_json::json!({})).await
}

#[tauri::command]
async fn list_apps(app: tauri::AppHandle) -> Result<Vec<serde_json::Value>, String> {
    let response = agent_request(&app, "list_apps", serde_json::json!({})).await?;
    Ok(response
        .get("apps")
        .and_then(|apps| apps.as_array())
        .cloned()
        .unwrap_or_default())
}

#[tauri::command]
async fn start_workspace(
    app: tauri::AppHandle,
    app_path: Option<String>,
) -> Result<serde_json::Value, String> {
    agent_request(
        &app,
        "start_workspace",
        serde_json::json!({
            "app_path": app_path,
            "width": 1440,
            "height": 900,
            "refresh_rate": 60,
            "hidpi": true,
            "profile": "codex_mobile_1440x900"
        }),
    )
    .await
}

#[tauri::command]
async fn stop_workspace(app: tauri::AppHandle) -> Result<serde_json::Value, String> {
    agent_request(&app, "stop_workspace", serde_json::json!({})).await
}

#[tauri::command]
async fn capture_screen(app: tauri::AppHandle) -> Result<serde_json::Value, String> {
    agent_request(&app, "capture_screen", serde_json::json!({})).await
}

pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .manage(AgentManager::default())
        .invoke_handler(tauri::generate_handler![
            agent_status,
            accessibility_status,
            request_accessibility,
            screen_capture_status,
            request_screen_capture,
            list_apps,
            start_workspace,
            stop_workspace,
            capture_screen
        ])
        .setup(|app| {
            let manager = app.state::<AgentManager>();
            if let Err(error) = manager.start(app.handle().clone()) {
                eprintln!("[virtualdesk-agent] failed to start during setup: {error}");
            }
            Ok(())
        })
        .on_window_event(|window, event| {
            if matches!(event, tauri::WindowEvent::CloseRequested { .. }) {
                let manager = window.app_handle().state::<AgentManager>();
                manager.shutdown();
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running VirtualDesk");
}
