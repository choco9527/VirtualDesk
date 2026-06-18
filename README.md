# VirtualDesk

Pin any app to a dedicated remote workspace display.

VirtualDesk is currently a macOS CLI proof of concept. It creates a lightweight macOS virtual display with `CGVirtualDisplay`, then moves and guards a target app window on that display.

## Current Scope

- Default profile is `codex_mobile_1440x900`.
- Default target app is `/Applications/Codex.app`, but agent requests can override `app_path`.
- Virtual display defaults to `VirtualDesk Virtual Display` at `1440x900 @ 60Hz`.
- Existing external virtual displays can still be targeted by names containing `BetterDisplay` or `Virtual`.
- Window control uses macOS Accessibility APIs.
- Virtual display creation uses undocumented CoreGraphics runtime classes and is treated as a POC boundary.

## Commands

```bash
swift run VirtualDesk start
swift run VirtualDesk stop
swift run VirtualDesk status
swift run VirtualDesk create-screen
swift run VirtualDesk list
swift run VirtualDesk list-apps
swift run VirtualDesk pin
swift run VirtualDesk watch
```

## App Shell

The repository now includes a Tauri + React shell that moves toward the final product UI:

- Left panel: installed app list in a two-column layout with app icon + name, plus a running badge when applicable.
- Top switch: starts or stops the virtual display through the agent sidecar.
- Right panel: phone-sized virtual screen frame.
- The switch only calls `start_display`; it does not move any app by default.
- Dragging an app into the phone frame calls `start_workspace`; users must enable the virtual display first, then drag an app into it.
- Current preview: polls `capture_screen` and renders PNG snapshots from the virtual display. ScreenCaptureKit is still the future path for smoother preview.
- Windows is not implemented in this phase; current work remains macOS-only, with future Windows support reserved at the architecture level.

```bash
npm install --prefix src-ui
npm install --prefix src-tauri
npm run build:agent
npm --prefix src-ui run build
cargo check --manifest-path src-tauri/Cargo.toml
```

### Build Requirements

- No full Xcode install is required.
- macOS Command Line Tools must be healthy enough for SwiftPM to build the package.
- `xcrun --sdk macosx --show-sdk-platform-path` may warn on Command Line Tools-only installs; the build script reports this as a warning and continues. Xcode is not required.

## Agent Mode

`agent` runs a persistent NDJSON protocol over stdin/stdout. Logs stay on stderr.

```bash
swift run VirtualDesk agent
```

Supported requests:

```json
{"id":"0","method":"capabilities","params":{}}
{"id":"1","method":"status","params":{}}
{"id":"2","method":"accessibility_status","params":{}}
{"id":"3","method":"request_accessibility","params":{}}
{"id":"4","method":"screen_capture_status","params":{}}
{"id":"5","method":"request_screen_capture","params":{}}
{"id":"6","method":"list_displays","params":{}}
{"id":"7","method":"list_apps","params":{}}
{"id":"8","method":"capture_screen","params":{}}
{"id":"9","method":"start_display","params":{"width":1440,"height":900,"refresh_rate":60,"hidpi":true,"profile":"codex_mobile_1440x900"}}
{"id":"10","method":"start_workspace","params":{"app_path":"/Applications/Codex.app","width":1440,"height":900,"refresh_rate":60,"hidpi":true,"profile":"codex_mobile_1440x900"}}
{"id":"11","method":"stop_workspace","params":{}}
```

Responses and events are single-line JSON:

```json
{"id":"0","ok":true,"result":{"platform":"macos","protocol_version":"1.0","supports":{"virtual_display":true,"window_control":true,"stop_workspace":true,"list_apps":true,"capture_screen":true,"start_display":true}}}
{"id":"1","ok":false,"error":{"code":"INVALID_PARAMS","message":"Invalid params: refresh_rate must be one of: 30, 60, 120."}}
{"event":"workspace_stopped","data":{"status":{"state":"stopped"},"reason":null}}
```

## Validation Flow

1. Run `swift run VirtualDesk create-screen` and confirm macOS sees `VirtualDesk Virtual Display`.
2. Confirm the remote desktop tool can connect to that display.
3. Stop `create-screen`, then run `swift run VirtualDesk start`.
4. Grant Accessibility permission when prompted.
5. Confirm Codex is created or activated, moved to the virtual display, and recovered if dragged away.

## Agent Runtime

- `start` holds an exclusive lock at `/tmp/virtualdesk-agent.lock`.
- `agent` also opens a local UDS control socket at `/tmp/virtualdesk-agent.sock`.
- `stop` uses the control socket and does not mutate the state file directly.
- Repeated `start` calls fail while another VirtualDesk agent is running.
- `status` prints JSON to stdout and reads `/tmp/virtualdesk-agent-state.json`.
- Last-used config is stored at `/tmp/virtualdesk-config.json`.
- Runtime logs are written to stderr so future IPC can reserve stdout for protocol data.
- On `SIGINT`, `SIGTERM`, or normal `start` shutdown, VirtualDesk tries to move the target window back to the primary display before releasing the virtual display.

## Existing Display Mode

If you want to test window control against BetterDisplay first:

```bash
swift run VirtualDesk list
swift run VirtualDesk pin
swift run VirtualDesk watch
```

## Future Shape

- `Core`: workspace orchestration, display lifecycle, target app policy, guard state.
- `MacPlatform`: `NSScreen`, `CGDisplay`, `AXUIElement`, `NSWorkspace`.
- `WindowsPlatform`: future `EnumDisplayMonitors`, `SetWindowPos`, UI Automation.
- `MacApp`: future menu bar app wrapping the same core.

## License

MIT
