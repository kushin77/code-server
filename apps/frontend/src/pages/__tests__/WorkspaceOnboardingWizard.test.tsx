/** @vitest-environment jsdom */

import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { WorkspaceOnboardingWizard } from '../WorkspaceOnboardingWizard'
import { RECENT_STORAGE_KEY, WORKSPACE_STORAGE_KEY } from '@/utils/workspaceCatalog'

const memoryStorage = (() => {
  const store = new Map<string, string>()

  return {
    getItem(key: string) {
      return store.get(key) ?? null
    },
    setItem(key: string, value: string) {
      store.set(key, value)
    },
    removeItem(key: string) {
      store.delete(key)
    },
    clear() {
      store.clear()
    },
  }
})()

vi.stubGlobal('localStorage', memoryStorage)

const { setMockAuthState, mockAuthStore } = vi.hoisted(() => {
  let authState = {
    token: 'token-1',
    user: null,
    org: null,
    isAuthenticated: true,
    isLoading: false,
    error: null,
  }

  const hook = ((selector?: (state: typeof authState) => unknown) => {
    if (typeof selector === 'function') {
      return selector(authState)
    }

    return authState
  }) as any as {
    setState: (nextState: Partial<typeof authState>) => void
    getState: () => typeof authState
  }

  hook.setState = (nextState) => {
    authState = { ...authState, ...nextState }
  }

  hook.getState = () => authState

  return {
    mockAuthStore: hook,
    setMockAuthState: (nextState: Partial<typeof authState>) => {
      authState = { ...authState, ...nextState }
    },
  }
})

vi.mock('@/store', () => ({
  useAuthStore: mockAuthStore,
}))

afterEach(() => {
  cleanup()
})

beforeEach(() => {
  memoryStorage.clear()
  setMockAuthState({
    token: 'token-1',
    user: {
      id: 'user-1',
      email: 'dev@example.com',
      fullName: 'Dev Example',
      status: 'active',
      mfaEnabled: true,
      roles: [
        {
          id: 'user-role-1',
          roleId: 'developer',
          userId: 'user-1',
          granted_at: new Date('2026-04-21T10:00:00.000Z'),
        },
      ],
      createdAt: new Date('2026-04-21T10:00:00.000Z'),
      updatedAt: new Date('2026-04-21T10:00:00.000Z'),
    },
    org: {
      id: 'org-1',
      slug: 'acme',
      name: 'Acme',
      createdAt: new Date('2026-04-21T10:00:00.000Z'),
    },
    isAuthenticated: true,
    isLoading: false,
    error: null,
  })
})

describe('WorkspaceOnboardingWizard', () => {
  it('guides a new teammate through workspace selection and completion', async () => {
    render(
      <MemoryRouter>
        <WorkspaceOnboardingWizard />
      </MemoryRouter>
    )

    expect(screen.getByText('Bring a new teammate from login to a ready workspace.')).toBeTruthy()

    fireEvent.click(screen.getByRole('button', { name: /next/i }))

    fireEvent.click(screen.getByRole('button', { name: /docs review/i }))

    expect(localStorage.getItem(WORKSPACE_STORAGE_KEY)).toBe('docs-review')

    fireEvent.click(screen.getByRole('button', { name: /next/i }))

    const mfaCheckbox = screen.getByRole('checkbox', { name: /confirm mfa is enabled/i }) as HTMLInputElement
    if (!mfaCheckbox.checked) {
      fireEvent.click(mfaCheckbox)
    }

    const workspaceCheckbox = screen.getByRole('checkbox', { name: /select the starter workspace/i }) as HTMLInputElement
    if (!workspaceCheckbox.checked) {
      fireEvent.click(workspaceCheckbox)
    }

    const handoffCheckbox = screen.getByRole('checkbox', { name: /read the handoff notes/i }) as HTMLInputElement
    if (!handoffCheckbox.checked) {
      fireEvent.click(handoffCheckbox)
    }

    const sessionsCheckbox = screen.getByRole('checkbox', { name: /open the sessions view/i }) as HTMLInputElement
    if (!sessionsCheckbox.checked) {
      fireEvent.click(sessionsCheckbox)
    }

    await waitFor(() => {
      expect((screen.getByRole('button', { name: /finish onboarding/i }) as HTMLButtonElement).disabled).toBe(false)
    })

    fireEvent.click(screen.getByRole('button', { name: /finish onboarding/i }))

    expect(screen.getAllByText(/Onboarding complete/i).length).toBeGreaterThan(0)
    expect(JSON.parse(localStorage.getItem('workspace-onboarding:v1') ?? '{}').completed).toBe(true)
    expect(localStorage.getItem(RECENT_STORAGE_KEY)).toContain('docs-review')
  })
})