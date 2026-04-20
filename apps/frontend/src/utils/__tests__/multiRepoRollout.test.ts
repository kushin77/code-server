import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

type RolloutModule = typeof import('../multiRepoRollout')

async function loadRolloutModule(env: Record<string, string | undefined> = {}): Promise<RolloutModule> {
  vi.resetModules()
  vi.unstubAllEnvs()

  for (const [key, value] of Object.entries(env)) {
    if (value === undefined) {
      continue
    }

    vi.stubEnv(key, value)
  }

  return import('../multiRepoRollout')
}

describe('resolveMultiRepoRollout', () => {
  beforeEach(() => {
    vi.resetModules()
    vi.unstubAllEnvs()
  })

  afterEach(() => {
    vi.unstubAllEnvs()
  })

  it('disables the rollout when mode is off', async () => {
    const { resolveMultiRepoRollout } = await loadRolloutModule({
      VITE_MULTI_REPO_NAVIGATION_MODE: 'off',
    })

    expect(resolveMultiRepoRollout('user-1')).toEqual({
      mode: 'off',
      enabled: false,
      cohort: 'control',
      capabilities: {
        tabs: false,
        switcher: false,
        persistence: false,
      },
      reason: 'multi-repo navigation rollout is disabled',
    })
  })

  it('fails safe when the navigation mode is unset', async () => {
    const { resolveMultiRepoRollout } = await loadRolloutModule({})

    const first = resolveMultiRepoRollout('user-1')
    const second = resolveMultiRepoRollout('user-1')

    expect(first).toEqual(second)
    expect(first).toEqual({
      mode: 'off',
      enabled: false,
      cohort: 'control',
      capabilities: {
        tabs: false,
        switcher: false,
        persistence: false,
      },
      reason: 'multi-repo navigation mode is not configured',
    })
  })

  it('fails safe when the navigation mode is invalid', async () => {
    const { resolveMultiRepoRollout } = await loadRolloutModule({
      VITE_MULTI_REPO_NAVIGATION_MODE: 'banana',
    })

    expect(resolveMultiRepoRollout('user-1')).toEqual({
      mode: 'off',
      enabled: false,
      cohort: 'control',
      capabilities: {
        tabs: false,
        switcher: false,
        persistence: false,
      },
      reason: "invalid multi-repo navigation mode 'banana'",
    })
  })

  it('enables the rollout for everyone when mode is on', async () => {
    const { resolveMultiRepoRollout } = await loadRolloutModule({
      VITE_MULTI_REPO_NAVIGATION_MODE: 'on',
      VITE_MULTI_REPO_PILOT_PERCENTAGE: '0',
    })

    expect(resolveMultiRepoRollout('user-1')).toEqual({
      mode: 'on',
      enabled: true,
      cohort: 'full',
      capabilities: {
        tabs: true,
        switcher: true,
        persistence: true,
      },
      reason: 'multi-repo navigation is fully enabled',
    })
  })

  it('keeps pilot mode closed without a user identity', async () => {
    const { resolveMultiRepoRollout } = await loadRolloutModule({
      VITE_MULTI_REPO_NAVIGATION_MODE: 'pilot',
      VITE_MULTI_REPO_PILOT_PERCENTAGE: '100',
    })

    expect(resolveMultiRepoRollout(null)).toEqual({
      mode: 'pilot',
      enabled: false,
      cohort: 'control',
      capabilities: {
        tabs: false,
        switcher: false,
        persistence: false,
      },
      reason: 'pilot mode requires a user identity for stable assignment',
    })
  })

  it('assigns users deterministically into the pilot cohort', async () => {
    const { resolveMultiRepoRollout } = await loadRolloutModule({
      VITE_MULTI_REPO_NAVIGATION_MODE: 'pilot',
      VITE_MULTI_REPO_PILOT_PERCENTAGE: '100',
    })

    const first = resolveMultiRepoRollout('user-42')
    const second = resolveMultiRepoRollout('user-42')

    expect(first).toEqual(second)
    expect(first).toEqual({
      mode: 'pilot',
      enabled: true,
      cohort: 'pilot',
      capabilities: {
        tabs: true,
        switcher: true,
        persistence: true,
      },
      reason: 'user assigned to pilot cohort (100% rollout)',
    })
  })

  it('assigns users to the control cohort when the pilot percentage is zero', async () => {
    const { resolveMultiRepoRollout } = await loadRolloutModule({
      VITE_MULTI_REPO_NAVIGATION_MODE: 'pilot',
      VITE_MULTI_REPO_PILOT_PERCENTAGE: '0',
    })

    expect(resolveMultiRepoRollout('user-42')).toEqual({
      mode: 'pilot',
      enabled: false,
      cohort: 'control',
      capabilities: {
        tabs: true,
        switcher: true,
        persistence: true,
      },
      reason: 'user assigned to control cohort (0% rollout)',
    })
  })

  it('clamps pilot percentage values above 100', async () => {
    const { resolveMultiRepoRollout } = await loadRolloutModule({
      VITE_MULTI_REPO_NAVIGATION_MODE: 'pilot',
      VITE_MULTI_REPO_PILOT_PERCENTAGE: '999',
    })

    expect(resolveMultiRepoRollout('user-42').reason).toBe('user assigned to pilot cohort (100% rollout)')
  })

  it('falls back to the default percentage when the pilot percentage is invalid', async () => {
    const { resolveMultiRepoRollout } = await loadRolloutModule({
      VITE_MULTI_REPO_NAVIGATION_MODE: 'pilot',
      VITE_MULTI_REPO_PILOT_PERCENTAGE: 'not-a-number',
    })

    expect(resolveMultiRepoRollout('user-42').reason).toContain('(25% rollout)')
  })

  it('applies cohort capability overrides from remote config', async () => {
    const { resolveMultiRepoRollout } = await loadRolloutModule({
      VITE_MULTI_REPO_NAVIGATION_MODE: 'pilot',
      VITE_MULTI_REPO_PILOT_PERCENTAGE: '100',
      VITE_MULTI_REPO_REMOTE_CONFIG: JSON.stringify({
        defaultCapabilities: { tabs: true, switcher: true, persistence: true },
        cohortCapabilities: {
          pilot: { persistence: false },
          control: { tabs: false, switcher: false, persistence: false },
        },
      }),
    })

    expect(resolveMultiRepoRollout('user-42').capabilities).toEqual({
      tabs: true,
      switcher: true,
      persistence: false,
    })
  })
})