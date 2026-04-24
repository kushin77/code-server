export type ShadowReplayHttpMethod = 'GET' | 'HEAD' | 'OPTIONS'

export interface ShadowReplayTrace {
  method: string
  path: string
  baselineStatus: number
  baselineLatencyMs: number
  headers?: Record<string, string>
}

export interface ShadowReplayObservation {
  status: number
  latencyMs: number
}

export interface ShadowReplayDiff {
  method: ShadowReplayHttpMethod
  path: string
  baselineStatus: number
  observedStatus: number
  baselineLatencyMs: number
  observedLatencyMs: number
  statusChanged: boolean
  latencyDeltaMs: number
  latencyRegression: boolean
}

export interface ShadowReplayReport {
  generatedAt: string
  sessionId: string
  readSafeEnforced: true
  maxLatencyRegressionMs: number
  totalRequests: number
  statusMismatchCount: number
  latencyRegressionCount: number
  diffs: ShadowReplayDiff[]
}

const SAFE_METHODS: ReadonlySet<string> = new Set(['GET', 'HEAD', 'OPTIONS'])

export const normalizeShadowReplayMethod = (method: string): ShadowReplayHttpMethod => {
  const normalized = method.trim().toUpperCase()

  if (!SAFE_METHODS.has(normalized)) {
    throw new Error(`shadow_replay_method_not_read_safe:${method}`)
  }

  return normalized as ShadowReplayHttpMethod
}

export const normalizeShadowReplayPath = (input: string): string => {
  const normalized = input.trim()
  if (normalized === '') {
    throw new Error('shadow_replay_path_required')
  }

  return normalized.startsWith('/') ? normalized : `/${normalized}`
}

export const assertReadSafeShadowReplayTraces = (traces: ShadowReplayTrace[]): void => {
  if (!Array.isArray(traces) || traces.length === 0) {
    throw new Error('shadow_replay_traces_required')
  }

  traces.forEach((trace, index) => {
    normalizeShadowReplayMethod(trace.method)
    normalizeShadowReplayPath(trace.path)

    if (!Number.isInteger(trace.baselineStatus) || trace.baselineStatus < 100 || trace.baselineStatus > 599) {
      throw new Error(`shadow_replay_baseline_status_invalid:${index}`)
    }

    if (!Number.isFinite(trace.baselineLatencyMs) || trace.baselineLatencyMs < 0) {
      throw new Error(`shadow_replay_baseline_latency_invalid:${index}`)
    }
  })
}

export const buildShadowReplayReport = (
  sessionId: string,
  traces: ShadowReplayTrace[],
  observations: ShadowReplayObservation[],
  maxLatencyRegressionMs: number,
): ShadowReplayReport => {
  if (traces.length !== observations.length) {
    throw new Error('shadow_replay_length_mismatch')
  }

  const diffs = traces.map((trace, index) => {
    const method = normalizeShadowReplayMethod(trace.method)
    const path = normalizeShadowReplayPath(trace.path)
    const observation = observations[index]
    const latencyDeltaMs = Number((observation.latencyMs - trace.baselineLatencyMs).toFixed(2))

    return {
      method,
      path,
      baselineStatus: trace.baselineStatus,
      observedStatus: observation.status,
      baselineLatencyMs: Number(trace.baselineLatencyMs.toFixed(2)),
      observedLatencyMs: Number(observation.latencyMs.toFixed(2)),
      statusChanged: observation.status !== trace.baselineStatus,
      latencyDeltaMs,
      latencyRegression: latencyDeltaMs > maxLatencyRegressionMs,
    }
  })

  return {
    generatedAt: new Date().toISOString(),
    sessionId,
    readSafeEnforced: true,
    maxLatencyRegressionMs,
    totalRequests: diffs.length,
    statusMismatchCount: diffs.filter((diff) => diff.statusChanged).length,
    latencyRegressionCount: diffs.filter((diff) => diff.latencyRegression).length,
    diffs,
  }
}
