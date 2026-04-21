/** @vitest-environment jsdom */

import { cleanup, render, screen } from '@testing-library/react'
import { afterEach, describe, expect, it } from 'vitest'

import { IDEPerformanceProfilerPage } from '../IDEPerformanceProfilerPage'
import { recordExtensionProfilerSample, resetExtensionProfilerSamples } from '../../utils/extensionProfiler'

afterEach(() => {
  cleanup()
  resetExtensionProfilerSamples()
})

describe('IDEPerformanceProfilerPage', () => {
  it('renders the extension profiler catalog and recorded samples', () => {
    recordExtensionProfilerSample({
      id: 'ticket-linking',
      label: 'Ticket linking extension',
      category: 'integration',
      kind: 'activation',
      durationMs: 18,
    })

    render(
      <IDEPerformanceProfilerPage
        workspaceState={{
          activeWorkspace: { id: 'portal-main', label: 'Portal main' },
        }}
      />
    )

    expect(screen.getByText('Per-extension overhead, captured from live mounts')).toBeTruthy()
    expect(screen.getByText('Ticket linking')).toBeTruthy()
    expect(screen.getAllByText('18ms').length).toBeGreaterThan(0)
    expect(screen.getByRole('button', { name: 'Reset samples' })).toBeTruthy()
  })
})
