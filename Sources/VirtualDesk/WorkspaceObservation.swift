import AppKit
import Foundation

enum WorkspaceEventName: String, Codable {
    case workspaceStarted = "workspace_started"
    case workspaceStopped = "workspace_stopped"
    case windowRecovered = "window_recovered"
    case displayLost = "display_lost"
    case appExited = "app_exited"
    case workspaceFailed = "workspace_failed"
}

struct WorkspaceEventPayload: Codable {
    let status: AgentStatus
    let reason: String?
}

protocol WorkspaceSessionEventSink: AnyObject {
    func workspaceSessionDidEmit(event: WorkspaceEventName, payload: WorkspaceEventPayload)
}

final class WorkspaceObservers {
    private var observers: [NSObjectProtocol] = []

    func observeDisplayChange(_ handler: @escaping () -> Void) {
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: nil
            ) { _ in handler() }
        )
    }

    func observeAppLifecycle(bundleURL: URL, onTerminate: @escaping () -> Void, onLaunch: @escaping () -> Void) {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(
            center.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification,
                object: nil,
                queue: nil
            ) { notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleURL?.standardizedFileURL == bundleURL.standardizedFileURL else {
                    return
                }
                onTerminate()
            }
        )

        observers.append(
            center.addObserver(
                forName: NSWorkspace.didLaunchApplicationNotification,
                object: nil,
                queue: nil
            ) { notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleURL?.standardizedFileURL == bundleURL.standardizedFileURL else {
                    return
                }
                onLaunch()
            }
        )
    }

    func removeAll() {
        let notificationCenter = NotificationCenter.default
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers.forEach {
            notificationCenter.removeObserver($0)
            workspaceCenter.removeObserver($0)
        }
        observers.removeAll()
    }

    deinit {
        removeAll()
    }
}
