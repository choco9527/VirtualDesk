mod agent_manager;

use agent_manager::AgentManager;
use tauri::Manager;

#[tauri::command]
async fn agent_status(app: tauri::AppHandle) -> Result<serde_json::Value, String> {
    let manager = app.state::<AgentManager>();
    manager.request("status", serde_json::json!({})).await
}

#[tauri::command]
async fn list_apps(app: tauri::AppHandle) -> Result<Vec<serde_json::Value>, String> {
    let manager = app.state::<AgentManager>();
    let response = manager.request("list_apps", serde_json::json!({})).await?;
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
    let manager = app.state::<AgentManager>();
    manager
        .request(
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
    let manager = app.state::<AgentManager>();
    manager
        .request("stop_workspace", serde_json::json!({}))
        .await
}

#[tauri::command]
async fn capture_screen(app: tauri::AppHandle) -> Result<serde_json::Value, String> {
    let manager = app.state::<AgentManager>();
    manager
        .request("capture_screen", serde_json::json!({}))
        .await
}

pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .manage(AgentManager::default())
        .invoke_handler(tauri::generate_handler![
            agent_status,
            list_apps,
            start_workspace,
            stop_workspace,
            capture_screen
        ])
        .setup(|app| {
            let manager = app.state::<AgentManager>();
            manager.start(app.handle().clone())?;
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
