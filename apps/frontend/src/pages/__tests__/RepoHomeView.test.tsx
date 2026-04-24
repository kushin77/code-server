/** @vitest-environment jsdom */

import { cleanup, fireEvent, render, screen, within } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'

import { RepoHomeView, RepoHomeViewState } from '../RepoHomeView'
import { createDefaultRepoHomeSnapshot } from '../../utils/repoHomeData'
import { assessMultiRepoPolicyConformance, resolveMultiRepoPolicy } from '../../utils/multiRepoPolicy'

afterEach(() => {
  cleanup()
})

function buildWorkspaceState(overrides: Partial<RepoHomeViewState> = {}): RepoHomeViewState {
  const repoHomeSnapshot = createDefaultRepoHomeSnapshot(1_700_000_000_000)

  return {
    activeWorkspace: { id: 'portal-main', label: 'Portal main', branch: 'main', pinned: true },
    activeRepoCard: repoHomeSnapshot.cards.find((card) => card.id === 'portal-main'),
    sessionSnapshot: {
      activeRepoId: 'portal-main',
      recentRepoIds: ['dev-sandbox'],
      savedAt: 1_700_000_000_000,
    },
    restoreNotice: null,
    actionNotice: null,
    repoHomeSnapshot,
    performRepoAction: vi.fn(),
    restoreSavedSession: vi.fn(),
    forgetSavedSession: vi.fn(),
    restorePreferences: {
      files: true,
      editors: true,
      terminals: false,
      tasks: true,
      debugConfigs: true,
    },
    setRestorePreference: vi.fn(),
    workspacePolicy: {
      schemaVersion: 1,
      policyVersion: 'multi-repo-policy-v1',
      label: 'Developer',
      canSwitchWorkspace: true,
      canUseQuickSwitcher: true,
      canRestoreSession: true,
      canPinWorkspace: false,
      maxRecentWorkspaces: 3,
    },
    policyReport: assessMultiRepoPolicyConformance(resolveMultiRepoPolicy(['developer']), {
      recentRepoIds: ['dev-sandbox'],
      requestedCapabilities: {
        tabs: true,
        switcher: true,
        persistence: true,
      },
    }),
    rolloutDecision: {
      mode: 'on',
      enabled: true,
      cohort: 'full',
      capabilities: {
        tabs: true,
        switcher: true,
        persistence: true,
      },
      reason: 'multi-repo navigation is fully enabled',
    },
    multiRepoNavigationEnabled: true,
    multiRepoTabsEnabled: true,
    multiRepoSwitcherEnabled: true,
    multiRepoPersistenceEnabled: true,
    ...overrides,
  }
}

describe('RepoHomeView', () => {
  it('renders repo status badges and remediation hints', () => {
    render(<RepoHomeView workspaceState={buildWorkspaceState()} />)

    expect(screen.getByText('Repo cards and jump actions')).toBeTruthy()
    expect(screen.getByText('Favorite repos')).toBeTruthy()
    expect(screen.getByText(/Schema v1 · multi-repo-policy-v1/i)).toBeTruthy()
    expect(screen.getByText('CI: blocked')).toBeTruthy()
    expect(screen.getByText('Repository access needs renewed credentials')).toBeTruthy()
    expect(screen.getByText(/Re-authenticate GitHub access for this repo/i)).toBeTruthy()
  })

  it('routes card actions through the shared action handler', () => {
    const performRepoAction = vi.fn()
    render(<RepoHomeView workspaceState={buildWorkspaceState({ performRepoAction })} />)

    const sandboxCard = screen.getByTestId('repo-card-dev-sandbox')

    const switchButton = within(sandboxCard).getByRole('button', { name: 'Switch' })
    fireEvent.click(switchButton)

    expect(performRepoAction).toHaveBeenCalledWith('dev-sandbox', 'switch')
  })

  it('disables privileged actions when policy does not allow them', () => {
    render(
      <RepoHomeView
        workspaceState={buildWorkspaceState({
          workspacePolicy: {
            schemaVersion: 1,
            policyVersion: 'multi-repo-policy-v1',
            label: 'Reviewer',
            canSwitchWorkspace: true,
            canUseQuickSwitcher: true,
            canRestoreSession: false,
            canPinWorkspace: false,
            maxRecentWorkspaces: 2,
          },
          policyReport: assessMultiRepoPolicyConformance(resolveMultiRepoPolicy(['reviewer']), {
            recentRepoIds: ['dev-sandbox'],
          }),
        })}
      />
    )

    const portalCard = screen.getByTestId('repo-card-portal-main')

    const pullButton = within(portalCard).getByRole('button', { name: 'Pull' })
    expect((pullButton as HTMLButtonElement).disabled).toBe(true)
  })
})