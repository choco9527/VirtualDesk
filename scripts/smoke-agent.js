#!/usr/bin/env node

const { spawn } = require('node:child_process')
const { execFileSync } = require('node:child_process')
const { existsSync, writeFileSync } = require('node:fs')
const { arch, platform } = require('node:os')
const { join } = require('node:path')

const root = join(__dirname, '..')
const agentPath = resolveAgentPath()
const mode = process.argv.includes('--workspace') ? 'workspace' : 'display'
const workspaceAppPath = readArg('--app') || '/System/Applications/TextEdit.app'

if (!existsSync(agentPath)) {
  fail(`missing sidecar binary: ${agentPath}. Run npm run build:agent first.`)
}

const agent = spawn(agentPath, ['agent'], { cwd: root })
const pending = new Map()
let nextID = 1
let stdoutBuffer = ''

agent.stdout.on('data', handleStdout)
agent.stderr.on('data', data => process.stderr.write(data))
agent.on('exit', code => {
  if (pending.size === 0) {
    return
  }
  const error = new Error(`agent exited before responding, code=${code}`)
  for (const reject of pending.values()) {
    reject(error)
  }
  pending.clear()
})

main().catch(error => {
  console.error(error.message)
  process.exitCode = 1
}).finally(() => {
  agent.kill('SIGTERM')
})

async function main() {
  if (mode === 'workspace') {
    await smokeWorkspace()
    return
  }

  await smokeDisplay()
}

async function smokeDisplay() {
  const start = await request('start_display', {
    width: 1440,
    height: 900,
    refresh_rate: 60,
    hidpi: true,
    profile: 'codex_mobile_1440x900',
  })
  assertOK(start, 'start_display')

  const display = start.result && start.result.display
  console.log(`start_display ok: ${display && display.name} id=${display && display.id}`)

  const status = await request('status')
  assertOK(status, 'status')
  if (!status.result || status.result.state !== 'running') {
    throw new Error(`expected running status, got ${JSON.stringify(status.result)}`)
  }
  console.log(`status ok: ${status.result.state}`)

  const capture = await request('capture_screen')
  if (capture.ok) {
    console.log(`capture_screen ok: ${capture.result.mime_type}, ${capture.result.image_base64.length} chars`)
  } else if (capture.error && capture.error.code === 'SCREEN_CAPTURE_PERMISSION_MISSING') {
    console.log('capture_screen skipped: screen recording permission is not granted')
  } else {
    throw new Error(`capture_screen failed: ${JSON.stringify(capture.error)}`)
  }

  const stop = await request('stop_workspace')
  assertOK(stop, 'stop_workspace')
  console.log(`stop_workspace ok: ${stop.result.state}`)
}

async function smokeWorkspace() {
  prepareWorkspaceApp()
  const accessibility = await request('accessibility_status')
  assertOK(accessibility, 'accessibility_status')
  if (!accessibility.result.trusted) {
    console.log('start_workspace skipped: accessibility permission is not granted')
    return
  }

  const start = await request('start_workspace', {
    app_path: workspaceAppPath,
    width: 1440,
    height: 900,
    refresh_rate: 60,
    hidpi: true,
    profile: 'codex_mobile_1440x900',
  })
  assertOK(start, 'start_workspace')
  if (!start.result.target_app || start.result.target_app.path !== workspaceAppPath) {
    throw new Error(
      `start_workspace targeted ${start.result.target_app && start.result.target_app.path}, expected ${workspaceAppPath}`
    )
  }

  const display = start.result && start.result.display
  console.log(`start_workspace ok: ${workspaceAppPath} -> ${display && display.name} id=${display && display.id}`)

  const status = await waitForWorkspaceWindow()
  console.log(`workspace window ok: pid=${status.result.window.pid}`)

  const stop = await request('stop_workspace')
  assertOK(stop, 'stop_workspace')
  console.log(`stop_workspace ok: ${stop.result.state}`)
}

function prepareWorkspaceApp() {
  if (!workspaceAppPath.endsWith('/TextEdit.app')) {
    return
  }

  const smokeFile = '/tmp/virtualdesk-smoke-workspace.txt'
  writeFileSync(smokeFile, 'VirtualDesk workspace smoke test\n')
  execFileSync('open', ['-a', workspaceAppPath, smokeFile])
}

function request(method, params = {}) {
  const id = String(nextID++)
  const payload = JSON.stringify({ id, method, params })

  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      pending.delete(id)
      reject(new Error(`timeout waiting for ${method}`))
    }, 15000)

    pending.set(id, message => {
      clearTimeout(timer)
      resolve(message)
    })

    agent.stdin.write(`${payload}\n`)
  })
}

function handleStdout(data) {
  stdoutBuffer += data.toString()
  while (stdoutBuffer.includes('\n')) {
    const index = stdoutBuffer.indexOf('\n')
    const line = stdoutBuffer.slice(0, index).trim()
    stdoutBuffer = stdoutBuffer.slice(index + 1)
    if (line.length > 0) {
      handleLine(line)
    }
  }
}

function handleLine(line) {
  const message = JSON.parse(line)
  if (message.event) {
    return
  }

  const resolve = pending.get(message.id)
  if (!resolve) {
    return
  }

  pending.delete(message.id)
  resolve(message)
}

function assertOK(response, method) {
  if (!response.ok) {
    throw new Error(`${method} failed: ${JSON.stringify(response.error)}`)
  }
}

async function waitForWorkspaceWindow() {
  for (let attempt = 0; attempt < 8; attempt += 1) {
    const status = await request('status')
    assertOK(status, 'status')
    if (status.result && status.result.window && status.result.window.pid) {
      return status
    }
    await sleep(500)
  }
  throw new Error('workspace window was not visible in status')
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms))
}

function resolveAgentPath() {
  return join(root, 'src-tauri', 'binaries', `virtualdesk-agent-${targetTriple()}`)
}

function readArg(name) {
  const index = process.argv.indexOf(name)
  if (index < 0) {
    return undefined
  }
  return process.argv[index + 1]
}

function targetTriple() {
  if (platform() !== 'darwin') {
    fail('smoke-agent currently supports macOS only')
  }

  if (arch() === 'arm64') {
    return 'aarch64-apple-darwin'
  }
  if (arch() === 'x64') {
    return 'x86_64-apple-darwin'
  }

  fail(`unsupported macOS architecture: ${arch()}`)
}

function fail(message) {
  console.error(message)
  process.exit(1)
}
