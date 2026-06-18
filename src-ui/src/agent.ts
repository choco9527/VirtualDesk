import { invoke } from '@tauri-apps/api/core'
import { listen, type UnlistenFn } from '@tauri-apps/api/event'

export const AGENT_EVENT_CHANNEL = 'virtualdesk://agent-event'
export const AGENT_TERMINATED_EVENT = 'agent_terminated'
export const DISPLAY_LOST_EVENT = 'display_lost'
export const WORKSPACE_FAILED_EVENT = 'workspace_failed'

export interface AppEntry {
  name: string
  bundle_id?: string
  app_path: string
  pid: number
  is_running?: boolean
  icon_png_base64?: string
}

export interface AgentStatus {
  state: 'stopped' | 'starting' | 'running' | 'stopping' | 'failed'
  display?: {
    id: number
    name: string
    frame?: {
      width: number
      height: number
    }
  }
  target_app?: {
    path: string
    bundle_id?: string
  }
  window?: {
    pid: number
  }
  guard_status?: {
    enabled: boolean
    interval_ms: number
  }
  message?: string
}

export interface DisplaySnapshot {
  id: number
  name: string
  frame: {
    x: number
    y: number
    width: number
    height: number
  }
  visible_frame: {
    x: number
    y: number
    width: number
    height: number
  }
  is_virtual: boolean
}

export interface VirtualDisplaySpec {
  width: number
  height: number
  refresh_rate: number
  hidpi: boolean
  profile?: string
}

export interface AgentEventPayload {
  event: string
  data?: {
    status?: AgentStatus
    reason?: string
  }
}

export interface PermissionStatus {
  trusted: boolean
  prompt_shown: boolean
  message?: string
}

export async function getStatus(): Promise<AgentStatus> {
  return invoke<AgentStatus>('agent_status')
}

export async function getAccessibilityStatus(): Promise<PermissionStatus> {
  return invoke<PermissionStatus>('accessibility_status')
}

export async function requestAccessibility(): Promise<PermissionStatus> {
  return invoke<PermissionStatus>('request_accessibility')
}

export async function openPrivacySettings(
  pane: 'accessibility'
): Promise<void> {
  return invoke<void>('open_privacy_settings', { pane })
}

export async function listApps(): Promise<AppEntry[]> {
  return invoke<AppEntry[]>('list_apps')
}

export async function listDisplays(): Promise<DisplaySnapshot[]> {
  return invoke<DisplaySnapshot[]>('list_displays')
}

export async function startDisplay(params?: VirtualDisplaySpec): Promise<AgentStatus> {
  return invoke<AgentStatus>('start_display', { params })
}

export async function startWorkspace(
  appPath?: string,
  params?: VirtualDisplaySpec
): Promise<AgentStatus> {
  return invoke<AgentStatus>('start_workspace', { appPath, params })
}

export async function stopWorkspace(): Promise<AgentStatus> {
  return invoke<AgentStatus>('stop_workspace')
}

export async function listenAgentEvents(
  handler: (event: AgentEventPayload) => void
): Promise<UnlistenFn> {
  return listen<AgentEventPayload>(AGENT_EVENT_CHANNEL, agentEvent => {
    handler(agentEvent.payload)
  })
}
