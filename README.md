# DeskBridge

Pin any app to a dedicated remote workspace display.

DeskBridge is currently a macOS CLI proof of concept. It creates a lightweight macOS virtual display with `CGVirtualDisplay`, then moves and guards a target app window on that display.

## Current POC Scope

- Target app is hardcoded to `/Applications/Codex.app`.
- Virtual display is hardcoded to `DeskBridge Virtual Display` at `1440x900 @ 60Hz`.
- Existing external virtual displays can still be targeted by names containing `BetterDisplay` or `Virtual`.
- Window control uses macOS Accessibility APIs.
- Virtual display creation uses undocumented CoreGraphics runtime classes and is treated as a POC boundary.

## Commands

```bash
swift run DeskBridge start
swift run DeskBridge status
swift run DeskBridge create-screen
swift run DeskBridge list
swift run DeskBridge pin
swift run DeskBridge watch
```

## Validation Flow

1. Run `swift run DeskBridge create-screen` and confirm macOS sees `DeskBridge Virtual Display`.
2. Confirm the remote desktop tool can connect to that display.
3. Stop `create-screen`, then run `swift run DeskBridge start`.
4. Grant Accessibility permission when prompted.
5. Confirm Codex is created or activated, moved to the virtual display, and recovered if dragged away.

## Agent Runtime

- `start` holds an exclusive lock at `/tmp/deskbridge-agent.lock`.
- Repeated `start` calls fail while another DeskBridge agent is running.
- `status` prints JSON to stdout and reads `/tmp/deskbridge-agent-state.json`.
- Runtime logs are written to stderr so future IPC can reserve stdout for protocol data.
- On `SIGINT`, `SIGTERM`, or normal `start` shutdown, DeskBridge tries to move the target window back to the primary display before releasing the virtual display.

## Existing Display Mode

If you want to test window control against BetterDisplay first:

```bash
swift run DeskBridge list
swift run DeskBridge pin
swift run DeskBridge watch
```

## Future Shape

- `Core`: workspace orchestration, display lifecycle, target app policy, guard state.
- `MacPlatform`: `NSScreen`, `CGDisplay`, `AXUIElement`, `NSWorkspace`.
- `WindowsPlatform`: future `EnumDisplayMonitors`, `SetWindowPos`, UI Automation.
- `MacApp`: future menu bar app wrapping the same core.

## License

MIT
