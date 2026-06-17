import { useEffect, useMemo, useState } from 'react'
import { AppEntry, AgentStatus, captureScreen, getStatus, listApps, startWorkspace, stopWorkspace } from './agent'

const fallbackApps: AppEntry[] = [
  { name: 'Codex', bundle_id: 'com.openai.codex', app_path: '/Applications/Codex.app', pid: 0 },
  { name: 'Google Chrome', bundle_id: 'com.google.Chrome', app_path: '/Applications/Google Chrome.app', pid: 0 },
  { name: 'WebStorm', bundle_id: 'com.jetbrains.WebStorm', app_path: '/Applications/WebStorm.app', pid: 0 },
  { name: 'Terminal', bundle_id: 'com.apple.Terminal', app_path: '/System/Applications/Utilities/Terminal.app', pid: 0 },
]

export function App() {
  const [apps, setApps] = useState<AppEntry[]>([])
  const [selectedAppPath, setSelectedAppPath] = useState('/Applications/Codex.app')
  const [status, setStatus] = useState<AgentStatus>({ state: 'stopped' })
  const [previewUrl, setPreviewUrl] = useState<string | null>(null)
  const [dragActive, setDragActive] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const running = status.state === 'running' || status.state === 'starting'

  useEffect(() => {
    void refresh()
  }, [])

  useEffect(() => {
    if (!running) {
      setPreviewUrl(null)
      return
    }

    let cancelled = false
    const refreshPreview = async () => {
      try {
        const capture = await captureScreen()
        if (!cancelled) {
          setPreviewUrl(`data:${capture.mime_type};base64,${capture.image_base64}`)
        }
      } catch {
        if (!cancelled) setPreviewUrl(null)
      }
    }

    void refreshPreview()
    const timer = window.setInterval(refreshPreview, 1200)
    return () => {
      cancelled = true
      window.clearInterval(timer)
    }
  }, [running])

  const appGroups = useMemo(() => {
    const source = apps.length > 0 ? apps : fallbackApps
    const midpoint = Math.ceil(source.length / 2)
    return [source.slice(0, midpoint), source.slice(midpoint)]
  }, [apps])

  async function refresh() {
    setError(null)
    try {
      const [nextStatus, nextApps] = await Promise.all([getStatus(), listApps()])
      setStatus(nextStatus)
      setApps(nextApps)
    } catch (nextError) {
      setError((nextError as Error).message)
      setApps(fallbackApps)
    }
  }

  async function toggleWorkspace() {
    setError(null)
    try {
      const nextStatus = running
        ? await stopWorkspace()
        : await startWorkspace(selectedAppPath)
      setStatus(nextStatus)
      if (!running) await refresh()
    } catch (nextError) {
      setError((nextError as Error).message)
    }
  }

  async function launchWorkspace(appPath: string) {
    setSelectedAppPath(appPath)
    setError(null)
    try {
      const nextStatus = await startWorkspace(appPath)
      setStatus(nextStatus)
      await refresh()
    } catch (nextError) {
      setError((nextError as Error).message)
    }
  }

  function handleDragStart(event: React.DragEvent<HTMLButtonElement>, appPath: string) {
    event.dataTransfer.setData('text/plain', appPath)
    event.dataTransfer.effectAllowed = 'copyMove'
  }

  async function handleDrop(event: React.DragEvent<HTMLElement>) {
    event.preventDefault()
    setDragActive(false)
    const appPath = event.dataTransfer.getData('text/plain')
    if (appPath) await launchWorkspace(appPath)
  }

  return (
    <main className="shell">
      <section className="topbar">
        <div>
          <p className="eyebrow">VirtualDesk</p>
          <h1>Mobile Work Screen</h1>
        </div>
        <button className={running ? 'switch switch-on' : 'switch'} onClick={toggleWorkspace}>
          <span />
          {running ? '关闭虚拟屏幕' : '开启虚拟屏幕'}
        </button>
      </section>

      {error && <div className="alert">{error}</div>}

      <section className="workspace">
        <aside className="app-panel">
          <div className="panel-heading">
            <h2>应用列表</h2>
            <button onClick={refresh}>刷新</button>
          </div>
          <div className="app-grid">
            {appGroups.map((group, groupIndex) => (
              <div className="app-column" key={groupIndex}>
                {group.map(app => (
                  <button
                    className={app.app_path === selectedAppPath ? 'app-card selected' : 'app-card'}
                    draggable
                    key={`${app.app_path}-${app.pid}`}
                    onClick={() => setSelectedAppPath(app.app_path)}
                    onDragStart={event => handleDragStart(event, app.app_path)}
                  >
                    <span className="app-icon">{app.name.slice(0, 1).toUpperCase()}</span>
                    <span>
                      <strong>{app.name}</strong>
                      <small>{app.bundle_id ?? app.app_path}</small>
                    </span>
                  </button>
                ))}
              </div>
            ))}
          </div>
        </aside>

        <section className="screen-panel">
          <div
            className={dragActive ? 'phone-frame drag-active' : 'phone-frame'}
            onDragOver={event => {
              event.preventDefault()
              setDragActive(true)
            }}
            onDragLeave={() => setDragActive(false)}
            onDrop={handleDrop}
          >
            <div className="phone-status">
              <span>{running ? 'Virtual Screen Online' : 'Virtual Screen Off'}</span>
              <span>1440 × 900</span>
            </div>
            <div className={running ? 'screen-preview online' : 'screen-preview'}>
              {running && previewUrl ? (
                <img className="live-preview" src={previewUrl} alt="Virtual display preview" />
              ) : running ? (
                <>
                  <div className="screen-grid" />
                  <div className="preview-card">
                    <strong>虚拟屏幕已开启</strong>
                    <span>正在等待屏幕截图权限或实时画面。</span>
                  </div>
                </>
              ) : (
                <div className="empty-state">
                  <strong>{dragActive ? '松开以开启虚拟屏幕' : '点击开关或拖入应用'}</strong>
                  <span>把左侧应用拖到这里，会开启虚拟屏幕并把应用放进去。</span>
                </div>
              )}
            </div>
          </div>
        </section>
      </section>
    </main>
  )
}
