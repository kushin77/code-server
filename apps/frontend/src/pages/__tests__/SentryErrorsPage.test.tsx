/** @vitest-environment jsdom */

import { cleanup, render, screen } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { SentryErrorsPage } from '../SentryErrorsPage'

const getMock = vi.fn().mockResolvedValue({
  data: [
    {
      id: 'issue-1',
      title: 'Database timeout',
      level: 'error',
      status: 'unresolved',
      count: 42,
      userCount: 7,
      lastSeen: '2026-04-21T12:00:00Z',
      environment: 'production',
      permalink: 'https://sentry.io/organizations/acme/issues/1/',
    },
  ],
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
  storage.set('sentry.token', 'test-token')
  storage.set('sentry.organization', 'acme')
  storage.set('sentry.project', 'web')
  storage.set('sentry.environment', 'production')
  storage.set('sentry.refreshInterval', '60000')
})

describe('SentryErrorsPage', () => {
  it('renders unresolved issues from the Sentry API', async () => {
    render(<SentryErrorsPage />)

    expect(screen.getByText('Live error monitoring with release-aware context')).toBeTruthy()
    expect(await screen.findByText('Database timeout')).toBeTruthy()
    expect(screen.getByText('42 events')).toBeTruthy()
    expect(screen.getByText('7 users')).toBeTruthy()
    expect(getMock).toHaveBeenCalledWith(
      '/projects/acme/web/issues/',
      expect.objectContaining({
        params: expect.objectContaining({
          query: 'is:unresolved environment:production',
          limit: 20,
        }),
      })
    )
  })
})
