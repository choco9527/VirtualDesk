import { invoke } from '@tauri-apps/api/core'

export interface AppEntry {
  name: string
  bundle_id?: string
  app_path: string
  pid: number
}

export interface AgentStatus {
  state: 'stopped' | 'starting' | 'running' | 'stopping' | 'failed'
  message?: string
}

export interface ScreenCapture {
  display_id: number
  mime_type: string
  image_base64: string
}

export async function getStatus(): Promise<AgentStatus> {
  return invoke<AgentStatus>('agent_status')
}

export async function listApps(): Promise<AppEntry[]> {
  return invoke<AppEntry[]>('list_apps')
}

export async function startWorkspace(appPath?: string): Promise<AgentStatus> {
  return invoke<AgentStatus>('start_workspace', { appPath })
}

export async function stopWorkspace(): Promise<AgentStatus> {
  return invoke<AgentStatus>('stop_workspace')
}

export async function captureScreen(): Promise<ScreenCapture> {
  return invoke<ScreenCapture>('capture_screen')
}
