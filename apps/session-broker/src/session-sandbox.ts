export type SessionSandboxMode = 'default' | 'gvisor'

export interface SessionSandboxDecision {
  enabled: boolean
  mode: SessionSandboxMode
  runtime?: string
  required: boolean
}

const GVISOR_RUNTIME_ALIASES = new Set(['gvisor', 'runsc'])

export const normalizeSessionSandboxRuntime = (value?: string | null): string | undefined => {
  if (!value) {
    return undefined
  }

  const normalized = value.trim().toLowerCase()

  if (!normalized || normalized === 'default' || normalized === 'runc') {
    return undefined
  }

  if (GVISOR_RUNTIME_ALIASES.has(normalized)) {
    return 'runsc'
  }

  throw new Error(`[session-broker] Unsupported SESSION_SANDBOX_RUNTIME value: ${value}`)
}

export const resolveSessionSandboxDecision = (
  runtimeValue?: string | null,
  required: boolean = false,
): SessionSandboxDecision => {
  const runtime = normalizeSessionSandboxRuntime(runtimeValue)

  if (required && !runtime) {
    throw new Error('[session-broker] SESSION_SANDBOX_REQUIRED=true requires SESSION_SANDBOX_RUNTIME=runsc')
  }

  return {
    enabled: Boolean(runtime),
    mode: runtime ? 'gvisor' : 'default',
    runtime,
    required,
  }
}