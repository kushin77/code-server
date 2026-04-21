/** @vitest-environment jsdom */

import { cleanup, render, screen } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { PagerDutyIncidentsPage } from '../PagerDutyIncidentsPage'

const getMock = vi.fn().mockResolvedValue({
  data: {
    incidents: [
      {
        id: 'incident-1',
        incident_number: 101,
        title: 'API latency spike',
        status: 'triggered',
        urgency: 'high',
        created_at: '2026-04-21T12:00:00Z',
        last_status_update_at: '2026-04-21T12:05:00Z',
        html_url: 'https://pagerduty.com/incidents/incident-1',
        service: {
          id: 'service-1',
          summary: 'API Service',
        },
        assignments: [
          {
            assignee: {
              id: 'user-1',
              summary: 'John Doe',
              email: 'john@example.com',
            },
          },
        ],
      },
    ],
    total: 1,
  },
})

vi.mock('axios', () => ({
  default: {
    create: vi.fn(() => ({
      get: getMock,
    })),
  },
}))

vi.mock('vscode', () => ({
  workspace: {
    getConfiguration: vi.fn(() => ({
      get: vi.fn(),
    })),
  },
  window: {
    showWarningMessage: vi.fn(),
    showErrorMessage: vi.fn(),
  },
  commands: {
    executeCommand: vi.fn(),
  },
  Uri: {
    parse: vi.fn((value: string) => ({ value })),
  },
  EventEmitter: class {
    event = vi.fn()
    fire = vi.fn()
    dispose = vi.fn()
  },
  TreeItem: class {},
  TreeItemCollapsibleState: {
    None: 0,
    Collapsed: 1,
  },
}))

const storage = new Map<string, string>()

vi.stubGlobal('localStorage', {
  getItem: vi.fn((key: string) => storage.get(key) ?? null),
  setItem: vi.fn((key: string, value: string) => {
    storage.set(key, value)
  }),
  removeItem: vi.fn((key: string) => {
    storage.delete(key)
  }),
  clear: vi.fn(() => {
    storage.clear()
  }),
  key: vi.fn((index: number) => Array.from(storage.keys())[index] ?? null),
  length: 0,
})

afterEach(() => {
  cleanup()
  storage.clear()
  getMock.mockClear()
})

beforeEach(() => {
  storage.set('pagerduty.token', 'test-token-pagerduty')
  storage.set('pagerduty.refreshInterval', '30000')
})

describe('PagerDutyIncidentsPage', () => {
  it('renders triggered incidents from the PagerDuty API', async () => {
    render(<PagerDutyIncidentsPage />)

    expect(screen.getByText('Live incident monitoring & management')).toBeTruthy()
    expect(await screen.findByText('API latency spike')).toBeTruthy()
    expect(screen.getByText('1 loaded')).toBeTruthy()
    expect(screen.getByText('API Service')).toBeTruthy()
    expect(getMock).toHaveBeenCalledWith(
      '/incidents',
      expect.objectContaining({
        params: expect.objectContaining({
          limit: 25,
          statuses: ['triggered'],
          include: ['assignees', 'services'],
          sort_by: 'created_at:desc',
        }),
      })
    )
  })

  it('renders not configured state when token is missing', () => {
    storage.clear()
    render(<PagerDutyIncidentsPage />)

    expect(screen.getByText('PagerDuty is not configured')).toBeTruthy()
    expect(screen.getByText(/pagerduty.token/)).toBeTruthy()
  })
})
