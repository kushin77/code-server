import { describe, expect, it } from 'vitest'
import {
  assertReadSafeShadowReplayTraces,
  buildShadowReplayReport,
  normalizeShadowReplayMethod,
} from './session-shadow-replay.js'

describe('session shadow replay helpers', () => {
  it('accepts read-safe methods and normalizes case', () => {
    expect(normalizeShadowReplayMethod('get')).toBe('GET')
    expect(normalizeShadowReplayMethod('HEAD')).toBe('HEAD')
    expect(normalizeShadowReplayMethod(' options ')).toBe('OPTIONS')
  })

  it('rejects non read-safe methods', () => {
    expect(() => normalizeShadowReplayMethod('POST')).toThrow(/not_read_safe/i)
  })

  it('enforces trace guardrails before replay', () => {
    expect(() => assertReadSafeShadowReplayTraces([])).toThrow(/traces_required/i)
    expect(() => assertReadSafeShadowReplayTraces([
      {
        method: 'DELETE',
        path: '/api/v1/resource',
        baselineStatus: 200,
        baselineLatencyMs: 50,
      },
    ])).toThrow(/not_read_safe/i)
  })

  it('builds a comparative diff report with mismatch and latency regression counts', () => {
    const report = buildShadowReplayReport(
      'sess-123',
      [
        {
          method: 'GET',
          path: '/healthz',
          baselineStatus: 200,
          baselineLatencyMs: 20,
        },
        {
          method: 'HEAD',
          path: 'metrics',
          baselineStatus: 200,
          baselineLatencyMs: 10,
        },
      ],
      [
        { status: 200, latencyMs: 24 },
        { status: 503, latencyMs: 30 },
      ],
      8,
    )

    expect(report.totalRequests).toBe(2)
    expect(report.statusMismatchCount).toBe(1)
    expect(report.latencyRegressionCount).toBe(1)
    expect(report.readSafeEnforced).toBe(true)
    expect(report.diffs[1]?.path).toBe('/metrics')
  })
})
