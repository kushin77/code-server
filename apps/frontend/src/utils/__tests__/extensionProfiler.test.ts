/** @vitest-environment jsdom */

import { afterEach, describe, expect, it } from 'vitest'

import {
  getExtensionProfilerSnapshot,
  measureAsyncExtensionProfiler,
  recordExtensionProfilerSample,
  resetExtensionProfilerSamples,
} from '../extensionProfiler'

afterEach(() => {
  resetExtensionProfilerSamples()
})

describe('extensionProfiler', () => {
  it('records and clears profiler samples', () => {
    recordExtensionProfilerSample({
      id: 'ticket-linking',
      label: 'Ticket linking extension',
      category: 'integration',
      kind: 'activation',
      durationMs: 24,
    })

    const snapshot = getExtensionProfilerSnapshot()

    expect(snapshot.samples).toHaveLength(1)
    expect(snapshot.samples[0]).toMatchObject({
      id: 'ticket-linking',
      label: 'Ticket linking extension',
      category: 'integration',
      kind: 'activation',
      status: 'success',
    })

    resetExtensionProfilerSamples()
    expect(getExtensionProfilerSnapshot().samples).toHaveLength(0)
  })

  it('captures async profiler timings', async () => {
    const result = await measureAsyncExtensionProfiler(
      {
        id: 'cicd-status',
        label: 'CI/CD status sidebar',
        category: 'operations',
        kind: 'load',
      },
      async () => 'done'
    )

    expect(result).toBe('done')
    expect(getExtensionProfilerSnapshot().samples[0]?.id).toBe('cicd-status')
  })
})
