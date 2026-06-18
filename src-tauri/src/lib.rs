mod agent_manager;

use agent_manager::AgentManager;
use tauri::Manager;

#[derive(serde::Deserialize)]
#[serde(rename_all = "snake_case")]
enum PrivacySettingsPane {
    Accessibility,
}

#[derive(serde::Deserialize)]
struct DisplayParams {
    width: Option<u32>,
    height: Option<u32>,
    refresh_rate: Option<f64>,
    hidpi: Option<bool>,
    profile: Option<String>,
}

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
async fn list_apps(app: tauri::AppHandle) -> Result<Vec<serde_json::Value>, String> {
    let response = agent_request(&app, "list_apps", serde_json::json!({})).await?;
    Ok(response
        .get("apps")
        .and_then(|apps| apps.as_array())
        .cloned()
        .unwrap_or_default())
}

#[tauri::command]
async fn list_displays(app: tauri::AppHandle) -> Result<Vec<serde_json::Value>, String> {
    let response = agent_request(&app, "list_displays", serde_json::json!({})).await?;
    Ok(response
        .get("displays")
        .and_then(|displays| displays.as_array())
        .cloned()
        .unwrap_or_default())
}

#[tauri::command]
async fn start_display(
    app: tauri::AppHandle,
    params: Option<DisplayParams>,
) -> Result<serde_json::Value, String> {
    agent_request(&app, "start_display", display_payload(params, None)).await
}

#[tauri::command]
async fn start_workspace(
    app: tauri::AppHandle,
    app_path: Option<String>,
    params: Option<DisplayParams>,
) -> Result<serde_json::Value, String> {
    let result = agent_request(&app, "start_workspace", display_payload(params, app_path)).await;

    if result.is_ok() {
        refocus_main_window(&app);
    }

    result
}

#[tauri::command]
async fn stop_workspace(app: tauri::AppHandle) -> Result<serde_json::Value, String> {
    agent_request(&app, "stop_workspace", serde_json::json!({})).await
}

fn display_payload(params: Option<DisplayParams>, app_path: Option<String>) -> serde_json::Value {
    let params = params.unwrap_or(DisplayParams {
        width: None,
        height: None,
        refresh_rate: None,
        hidpi: None,
        profile: None,
    });

    serde_json::json!({
        "app_path": app_path,
        "width": params.width.unwrap_or(1440),
        "height": params.height.unwrap_or(900),
        "refresh_rate": params.refresh_rate.unwrap_or(60.0),
        "hidpi": params.hidpi.unwrap_or(true),
        "profile": params.profile.unwrap_or_else(|| "codex_mobile_1440x900".to_string())
    })
}

#[tauri::command]
async fn open_privacy_settings(pane: PrivacySettingsPane) -> Result<(), String> {
    let url = match pane {
        PrivacySettingsPane::Accessibility => {
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        }
    };

    std::process::Command::new("open")
        .arg(url)
        .status()
        .map_err(|error| error.to_string())
        .and_then(|status| {
            if status.success() {
                Ok(())
            } else {
                Err(format!("open exited with status {status}"))
            }
        })
}

fn refocus_main_window(app: &tauri::AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.show();
        let _ = window.set_focus();
    }
}

pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .manage(AgentManager::default())
        .invoke_handler(tauri::generate_handler![
            agent_status,
            accessibility_status,
            request_accessibility,
            list_apps,
            list_displays,
            start_display,
            start_workspace,
            stop_workspace,
            open_privacy_settings
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
