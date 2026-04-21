/** @vitest-environment jsdom */

import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { FeatureFlagsPage } from '../FeatureFlagsPage'

const flagsResponse = [
  {
    key: 'new_dashboard',
    name: 'New dashboard',
    description: 'Enable the new dashboard experience',
    enabled: true,
    provider: 'local',
    createdAt: '2026-04-21T12:00:00Z',
    modifiedAt: '2026-04-21T12:30:00Z',
  },
  {
    key: 'beta_search',
    name: 'Beta search',
    description: 'LaunchDarkly managed flag',
    enabled: false,
    provider: 'launchdarkly',
    createdAt: '2026-04-20T09:00:00Z',
    modifiedAt: '2026-04-21T08:00:00Z',
  },
] as const

const fetchMock = vi.fn()
const confirmMock = vi.fn(() => true)

vi.stubGlobal('fetch', fetchMock)
vi.stubGlobal('confirm', confirmMock)

afterEach(() => {
  cleanup()
  fetchMock.mockReset()
  confirmMock.mockClear()
})

beforeEach(() => {
  fetchMock.mockImplementation((input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input)

    if (url.endsWith('/api/flags') && (!init || !init.method || init.method === 'GET')) {
      return Promise.resolve({
        ok: true,
        status: 200,
        json: async () => ({ flags: [...flagsResponse] }),
      } as Response)
    }

    if (url.endsWith('/api/flags/export')) {
      return Promise.resolve({
        ok: true,
        status: 200,
        json: async () => ({ flags: { new_dashboard: true, beta_search: false } }),
      } as Response)
    }

    if (url.includes('/api/flags/') && init?.method === 'PUT') {
      return Promise.resolve({ ok: true, status: 200, json: async () => ({}) } as Response)
    }

    if (url.includes('/api/flags/') && init?.method === 'DELETE') {
      return Promise.resolve({ ok: true, status: 204, json: async () => ({}) } as Response)
    }

    if (url.endsWith('/api/flags') && init?.method === 'POST') {
      return Promise.resolve({ ok: true, status: 201, json: async () => ({}) } as Response)
    }

    return Promise.reject(new Error(`Unexpected fetch: ${url}`))
  })
})

describe('FeatureFlagsPage', () => {
  it('renders flags and issues API requests', async () => {
    render(<FeatureFlagsPage />)

    expect(screen.getByText('Release controls with local, LaunchDarkly, and Unleash visibility')).toBeTruthy()
    expect(await screen.findByText('New dashboard')).toBeTruthy()
    expect(screen.getByText('Beta search')).toBeTruthy()
    expect(screen.getByText('L:1 | U:0 | Local:1')).toBeTruthy()
    expect(fetchMock).toHaveBeenCalledWith('http://localhost:3100/api/flags')
  })

  it('toggles a flag through the shared API contract', async () => {
    render(<FeatureFlagsPage />)

    await screen.findByText('New dashboard')

    fireEvent.click(screen.getByRole('button', { name: 'Disable' }))

    await waitFor(() => {
      expect(fetchMock).toHaveBeenCalledWith(
        'http://localhost:3100/api/flags/new_dashboard',
        expect.objectContaining({ method: 'PUT' })
      )
    })
  })
})