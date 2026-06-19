import { useEffect, useMemo, useState } from 'react'
import { isTauri } from '@tauri-apps/api/core'
import {
  AppEntry,
  AgentEventPayload,
  AgentStatus,
  AGENT_TERMINATED_EVENT,
  DISPLAY_LOST_EVENT,
  PermissionStatus,
  VirtualDisplaySpec,
  getAccessibilityStatus,
  getStatus,
  listenAgentEvents,
  listApps,
  openPrivacySettings,
  requestAccessibility,
  startDisplay,
  startWorkspace,
  stopWorkspace,
  WORKSPACE_FAILED_EVENT,
} from './agent'

const DEFAULT_PRESET_ID = 'desktop-1440x900'
const DEFAULT_PROFILE = 'codex_mobile_1440x900'

interface DisplayPreset {
  id: string
  label: string
  spec: VirtualDisplaySpec
}

const DEFAULT_DISPLAY_PRESET: DisplayPreset = {
  id: DEFAULT_PRESET_ID,
  label: '桌面',
  spec: {
    width: 1440,
    height: 900,
    refresh_rate: 60,
    hidpi: true,
    profile: DEFAULT_PROFILE,
  },
}

const STATIC_DISPLAY_PRESETS: DisplayPreset[] = [
  DEFAULT_DISPLAY_PRESET,
  {
    id: 'phone-iphone-15',
    label: 'iPhone',
    spec: {
      width: 390,
      height: 844,
      refresh_rate: 60,
      hidpi: true,
      profile: DEFAULT_PROFILE,
    },
  },
  {
    id: 'phone-pro-max',
    label: '大屏手机',
    spec: {
      width: 430,
      height: 932,
      refresh_rate: 60,
      hidpi: true,
      profile: DEFAULT_PROFILE,
    },
  },
  {
    id: 'phone-android',
    label: 'Android',
    spec: {
      width: 412,
      height: 915,
      refresh_rate: 60,
      hidpi: true,
      profile: DEFAULT_PROFILE,
    },
  },
]

export function App() {
  const hasTauriRuntime = detectTauriRuntime()
  const [apps, setApps] = useState<AppEntry[]>([])
  const [selectedAppPath, setSelectedAppPath] = useState('/Applications/Codex.app')
  const [status, setStatus] = useState<AgentStatus>({ state: 'stopped' })
  const [accessibility, setAccessibility] = useState<PermissionStatus | null>(null)
  const [selectedPresetId, setSelectedPresetId] = useState(DEFAULT_PRESET_ID)
  const [error, setError] = useState<string | null>(null)
  const [agentTerminated, setAgentTerminated] = useState(false)
  const [workspaceAction, setWorkspaceAction] = useState<string | null>(null)
  const sortedApps = useMemo(() => [...apps].sort(compareApps), [apps])
  const displayPresets = STATIC_DISPLAY_PRESETS
  const selectedPreset = displayPresets.find(preset => preset.id === selectedPresetId)
    ?? displayPresets.find(preset => preset.id === DEFAULT_PRESET_ID)
    ?? DEFAULT_DISPLAY_PRESET
  const selectedDisplaySpec = selectedPreset.spec
  const isRunning = status.state === 'running'
  const isStarting = status.state === 'starting'
  const isStopping = status.state === 'stopping'
  const isFailed = status.state === 'failed'
  const running = isRunning || isStarting
  const isBusy = isStarting || isStopping
  const workspaceHasPinnedApp = Boolean(status.guard_status?.enabled && status.target_app?.path)
  const workspaceWindowReady = Boolean(status.window?.pid)
  const workspaceMovePending = isRunning && workspaceHasPinnedApp && !workspaceWindowReady
  const activeApp = workspaceHasPinnedApp
    ? apps.find(app => app.app_path === status.target_app?.path)
    : undefined
  const activeAppName = workspaceHasPinnedApp
    ? activeApp?.name ?? status.target_app?.bundle_id ?? appNameFromPath(status.target_app?.path)
    : undefined
  const activeAppIcon = activeApp?.icon_png_base64
  const displayResolution = status.display?.frame
    ? `${Math.round(status.display.frame.width)} × ${Math.round(status.display.frame.height)}`
    : `${selectedDisplaySpec.width} × ${selectedDisplaySpec.height}`
  const toggleLabel = isStarting
    ? '正在开启虚拟屏幕'
    : isStopping
      ? '正在关闭虚拟屏幕'
      : isRunning
        ? '关闭虚拟屏幕'
        : '开启虚拟屏幕'
  const panelSubtitle = isRunning
    ? '单击应用放入虚拟屏幕'
    : isStarting
      ? '虚拟屏幕正在启动，启动完成后可单击应用'
      : isStopping
        ? '虚拟屏幕正在关闭，请稍候'
        : isFailed
          ? '虚拟屏幕异常中断，可重新开启'
          : '先开启右侧虚拟屏幕，再单击应用'
  const screenOffTitle = isStopping
    ? '虚拟屏幕正在关闭'
    : isFailed
      ? '虚拟屏幕异常中断'
      : '虚拟屏幕未开启'
  const screenOffMessage = isStopping
    ? (status.message ?? '正在回收虚拟屏幕和相关窗口，请稍候。')
    : isFailed
      ? (status.message ?? '虚拟屏幕已丢失或异常退出。请重新开启后再继续选择应用。')
      : '点击上方开关后，再单击左侧应用即可放入虚拟屏幕。'
  const phoneStatusLabel = isStarting
    ? 'Virtual Screen Starting'
    : workspaceAction
      ? 'Moving App Window'
    : workspaceMovePending
      ? 'Moving App Window'
      : 'Virtual Screen Online'
  const screenPanelTitle = isStarting ? '虚拟屏幕正在开启' : '虚拟屏幕已开启'
  const screenPanelMessage = isStarting
    ? (status.message ?? '正在创建虚拟屏幕，请稍候。')
    : (workspaceAction ?? status.message ?? (workspaceMovePending
      ? '正在等待应用窗口进入虚拟屏幕。'
      : '虚拟屏幕已创建。当前不显示实时画面，请通过远程软件连接该屏幕。'))

  useEffect(() => {
    if (!hasTauriRuntime) {
      return
    }
    void refresh()
  }, [hasTauriRuntime])

  useEffect(() => {
    if (!hasTauriRuntime) {
      return
    }
    const timer = window.setInterval(() => {
      void refreshStatus()
    }, 2500)
    return () => window.clearInterval(timer)
  }, [hasTauriRuntime])

  useEffect(() => {
    if (!hasTauriRuntime) {
      return
    }
    let disposed = false
    let detach: (() => void) | undefined

    void listenAgentEvents((event: AgentEventPayload) => {
      if (disposed) {
        return
      }

      if (event.event === AGENT_TERMINATED_EVENT) {
        if (event.data?.status) {
          setStatus(currentStatus => ({
            ...currentStatus,
            ...event.data?.status,
          }))
        }
        setAgentTerminated(true)
        return
      }
      if (event.event === DISPLAY_LOST_EVENT || event.event === WORKSPACE_FAILED_EVENT) {
        if (event.data?.status) {
          setStatus(currentStatus => ({
            ...currentStatus,
            ...event.data?.status,
          }))
        }
        setAgentTerminated(true)
        return
      }
      if (event.data?.status) {
        setStatus(event.data.status)
      }
      setAgentTerminated(false)
      void refreshStatus()
    }).then(unlisten => {
      if (disposed) {
        void unlisten()
        return
      }
      detach = unlisten
    })

    return () => {
      disposed = true
      if (detach) {
        void detach()
      }
    }
  }, [hasTauriRuntime])

  async function refresh() {
    if (!hasTauriRuntime) {
      setError('当前页面运行在普通浏览器里，不能调用 macOS sidecar。请使用 Tauri 打开的 VirtualDesk 应用窗口。')
      setApps([])
      return
    }
    setError(null)
    try {
      const [
        nextStatus,
        nextApps,
        nextAccessibility,
      ] = await Promise.all([
        getStatus(),
        listApps(),
        getAccessibilityStatus(),
      ])
      setStatus(nextStatus)
      setApps(nextApps)
      setAccessibility(nextAccessibility)
      setAgentTerminated(false)
    } catch (nextError) {
      setError((nextError as Error).message)
      setApps([])
    }
  }

  async function refreshStatus() {
    void agentTerminated
    if (!hasTauriRuntime) return
    try {
      const [nextStatus, nextAccessibility] = await Promise.all([
        getStatus(),
        getAccessibilityStatus(),
      ])
      setStatus(nextStatus)
      setAccessibility(nextAccessibility)
      setAgentTerminated(false)
    } catch {
      // Keep the last visible state; interactive actions surface errors.
    }
  }

  async function requestPermission() {
    setError(null)
    try {
      const result = await requestAccessibility()
      setAccessibility(result)
      await refreshStatus()
    } catch (nextError) {
      setError((nextError as Error).message)
    }
  }

  async function openPermissionSettings() {
    setError(null)
    try {
      await openPrivacySettings('accessibility')
    } catch (nextError) {
      setError((nextError as Error).message)
    }
  }

  async function toggleWorkspace() {
    setError(null)
    const nextPendingState: AgentStatus['state'] = running ? 'stopping' : 'starting'
    setStatus(currentStatus => ({
      ...currentStatus,
      state: nextPendingState,
      message: running ? '正在关闭虚拟屏幕。' : '正在创建虚拟屏幕。',
    }))
    try {
      const nextStatus = running
        ? await stopWorkspace()
        : await startDisplay(selectedDisplaySpec)
      setStatus(nextStatus)
      setAgentTerminated(false)
      if (!running) await refresh()
    } catch (nextError) {
      const message = nativeActionErrorMessage(nextError)
      setError(message)
      setStatus(currentStatus => ({
        ...currentStatus,
        state: 'failed',
        message,
      }))
      await refreshStatus()
    }
  }

  async function launchWorkspace(appPath: string) {
    if (!isRunning) {
      setError(workspaceBlockedMessage())
      return
    }
    if (accessibility?.trusted === false) {
      setError('自动移动应用需要辅助功能权限。')
      return
    }
    setSelectedAppPath(appPath)
    const appName = apps.find(app => app.app_path === appPath)?.name ?? appNameFromPath(appPath) ?? '应用'
    setWorkspaceAction(`正在移动 ${appName} 到虚拟屏幕。`)
    setError(null)
    try {
      const nextStatus = await startWorkspace(appPath)
      setStatus(nextStatus)
      setAgentTerminated(false)
      await refresh()
    } catch (nextError) {
      setError((nextError as Error).message)
    } finally {
      setWorkspaceAction(null)
    }
  }

  function handleAppClick(appPath: string) {
    setSelectedAppPath(appPath)
    if (isRunning) {
      void launchWorkspace(appPath)
    }
  }

  function workspaceBlockedMessage() {
    if (accessibility?.trusted === false) {
      return '自动移动应用需要先授权辅助功能。'
    }
    if (isStarting) {
      return '虚拟屏幕还在启动，请稍候再选择应用。'
    }
    if (isStopping) {
      return '虚拟屏幕正在关闭，请稍候。'
    }
    if (isFailed) {
      return '虚拟屏幕已异常中断，请重新开启后再选择应用。'
    }
    return '请先开启虚拟屏幕，再单击应用。'
  }

  function appNameFromPath(appPath?: string) {
    const name = appPath?.split('/').pop()
    return name ? name.replace(/\.app$/i, '') : undefined
  }

  function nativeActionErrorMessage(nextError: unknown) {
    if (!hasTauriRuntime) {
      return '当前页面没有连接到 Tauri native 后端。请关闭旧窗口后重新运行 npm run tauri:dev，并在弹出的 VirtualDesk 应用窗口里操作。'
    }
    return (nextError as Error).message
  }

  return (
    <main className="shell">
      <section className="topbar">
        <div>
          <p className="eyebrow">VirtualDesk</p>
          <h1>Mobile Work Screen</h1>
        </div>
        <div className="topbar-actions">
          <label className="display-picker">
            <span>尺寸</span>
            <select
              value={selectedPreset.id}
              disabled={running || isBusy}
              onChange={event => setSelectedPresetId(event.target.value)}
            >
              {displayPresets.map(preset => (
                <option key={preset.id} value={preset.id}>
                  {preset.label} · {preset.spec.width} × {preset.spec.height}
                </option>
              ))}
            </select>
            {(running || isBusy) && <small>关闭后调整</small>}
          </label>
          <button
            className={running ? 'switch switch-on' : 'switch'}
            disabled={isBusy}
            onClick={toggleWorkspace}
          >
            <span />
            {toggleLabel}
          </button>
        </div>
      </section>

      {!hasTauriRuntime && (
        <div className="alert">
          你现在打开的是普通浏览器页面。虚拟屏幕、应用移动和权限按钮都依赖 Tauri native 后端，请切到 `npm run tauri:dev` 弹出的 VirtualDesk 应用窗口操作。
        </div>
      )}

      {error && <div className="alert">{error}</div>}

      <section className="permission-row">
        <PermissionBadge
          label="辅助功能"
          message={accessibility?.message ?? '允许 VirtualDesk 移动和守护应用窗口。'}
          status={accessibility}
          onRequest={requestPermission}
          onOpenSettings={openPermissionSettings}
        />
      </section>

      <section className="workspace">
        <aside className="app-panel">
          <div className="panel-heading">
            <div>
              <h2>应用列表</h2>
              <p className="panel-subtitle">{panelSubtitle}</p>
            </div>
            <button onClick={refresh}>刷新</button>
          </div>
          {apps.length > 0 ? (
            <div className="app-grid">
              {sortedApps.map(app => (
                <button
                  aria-label={app.name}
                  className={[
                    'app-card',
                    app.app_path === selectedAppPath ? 'selected' : '',
                    !isRunning ? 'app-card-disabled' : '',
                  ].filter(Boolean).join(' ')}
                  key={`${app.app_path}-${app.pid}`}
                  onClick={() => handleAppClick(app.app_path)}
                  title={app.name}
                >
                  {app.icon_png_base64 ? (
                    <img
                      className="app-icon app-icon-image"
                      src={`data:image/png;base64,${app.icon_png_base64}`}
                      alt=""
                    />
                  ) : (
                    <span className="app-icon">{app.name.slice(0, 1).toUpperCase()}</span>
                  )}
                  {app.is_running && <em className="app-running-dot" title="运行中" />}
                </button>
              ))}
            </div>
          ) : (
            <div className="app-empty-state">
              <strong>没有可显示的应用</strong>
              <span>点击刷新，或确认系统 Applications 目录里有可启动的 .app。</span>
            </div>
          )}
        </aside>

        <section className="screen-panel">
          {running ? (
            <div className="phone-frame">
              <div className="phone-status">
                <span>{phoneStatusLabel}</span>
                <span>{displayResolution}</span>
              </div>
              <div className="phone-app-badge">
                <strong>当前应用</strong>
                <div className="phone-app-row">
                  {activeAppIcon ? (
                    <img
                      className="phone-app-icon"
                      src={`data:image/png;base64,${activeAppIcon}`}
                      alt={`${activeAppName ?? 'App'} icon`}
                    />
                  ) : activeAppName ? (
                    <span className="phone-app-icon phone-app-icon-fallback">
                      {activeAppName.slice(0, 1).toUpperCase()}
                    </span>
                  ) : (
                    <span className="phone-app-icon phone-app-icon-placeholder" aria-hidden="true" />
                  )}
                  <span className="phone-app-name">{activeAppName ?? '等待选择应用'}</span>
                </div>
                <small className="phone-display-name">{status.display?.name ?? 'Virtual Display'}</small>
              </div>
              <div className="screen-preview online">
                <div className="screen-grid" />
                <div className="preview-card">
                  <strong>{screenPanelTitle}</strong>
                  <span>{screenPanelMessage}</span>
                </div>
              </div>
            </div>
          ) : (
            <div
              className={[
                'screen-off-shell',
                isFailed ? 'screen-off-shell-failed' : '',
              ].filter(Boolean).join(' ')}
            >
              <div className={isFailed ? 'screen-off-card screen-off-card-failed' : 'screen-off-card'}>
                <strong>{screenOffTitle}</strong>
                <span>{screenOffMessage}</span>
              </div>
            </div>
          )}
        </section>
      </section>
    </main>
  )
}

type TauriRuntimeWindow = Window & {
  __TAURI_INTERNALS__?: {
    invoke?: unknown
    transformCallback?: unknown
  }
}

function detectTauriRuntime() {
  if (isTauri()) {
    return true
  }
  if (typeof window === 'undefined') {
    return false
  }

  const internals = (window as TauriRuntimeWindow).__TAURI_INTERNALS__
  return typeof internals?.invoke === 'function' && typeof internals?.transformCallback === 'function'
}

function compareApps(left: AppEntry, right: AppEntry) {
  const systemRank = Number(isSystemApp(left)) - Number(isSystemApp(right))
  if (systemRank !== 0) {
    return systemRank
  }

  return left.name.localeCompare(right.name, undefined, { sensitivity: 'base' })
}

function isSystemApp(app: AppEntry) {
  return app.app_path.startsWith('/System/')
    || app.app_path.startsWith('/Applications/Utilities/')
    || app.bundle_id?.startsWith('com.apple.') === true
}

interface PermissionBadgeProps {
  label: string
  message: string
  status: PermissionStatus | null
  onRequest: () => void
  onOpenSettings: () => void
}

function PermissionBadge({ label, message, status, onRequest, onOpenSettings }: PermissionBadgeProps) {
  const trusted = status?.trusted === true

  return (
    <div className={trusted ? 'permission-card permission-ok' : 'permission-card permission-needed'}>
      <div>
        <strong>{label}</strong>
        <span>{trusted ? '已授权' : message}</span>
      </div>
      {!trusted && (
        <div className="permission-actions">
          <button onClick={onRequest}>授权</button>
          <button className="secondary-action" onClick={onOpenSettings}>系统设置</button>
        </div>
      )}
    </div>
  )
}
