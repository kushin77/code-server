export type MultiRepoRolloutMode = 'off' | 'pilot' | 'on'

export type MultiRepoRolloutDecision = {
  mode: MultiRepoRolloutMode
  enabled: boolean
  cohort: 'pilot' | 'control' | 'full'
  reason: string
}

const VALID_MODES: MultiRepoRolloutMode[] = ['off', 'pilot', 'on']

function hashString(input: string): number {
  let hash = 0

  for (let index = 0; index < input.length; index += 1) {
    hash = (hash * 31 + input.charCodeAt(index)) >>> 0
  }

  return hash
}

export function resolveMultiRepoRollout(userId?: string | null): MultiRepoRolloutDecision {
  const rawMode = import.meta.env.VITE_MULTI_REPO_NAVIGATION_MODE
  const mode = rawMode === undefined ? 'off' : VALID_MODES.includes(rawMode as MultiRepoRolloutMode) ? (rawMode as MultiRepoRolloutMode) : null
  const rawPercentage = import.meta.env.VITE_MULTI_REPO_PILOT_PERCENTAGE
  const parsedPercentage = Number(rawPercentage ?? '25')

  if (!mode) {
    return {
      mode: 'off',
      enabled: false,
      cohort: 'control',
      reason: rawMode
        ? `invalid multi-repo navigation mode '${rawMode}'`
        : 'multi-repo navigation mode is not configured',
    }
  }

  if (mode === 'off') {
    return {
      mode,
      enabled: false,
      cohort: 'control',
      reason: rawMode ? 'multi-repo navigation rollout is disabled' : 'multi-repo navigation mode is not configured',
    }
  }

  if (mode === 'on') {
    return {
      mode,
      enabled: true,
      cohort: 'full',
      reason: 'multi-repo navigation is fully enabled',
    }
  }

  if (!userId) {
    return {
      mode,
      enabled: false,
      cohort: 'control',
      reason: 'pilot mode requires a user identity for stable assignment',
    }
  }

  const normalizedPercentage = Number.isFinite(parsedPercentage)
    ? Math.min(100, Math.max(0, parsedPercentage))
    : 25
  const hash = hashString(`multi-repo:${userId}`)
  const score = hash % 100
  const enabled = score < normalizedPercentage

  return {
    mode,
    enabled,
    cohort: enabled ? 'pilot' : 'control',
    reason: enabled
      ? `user assigned to pilot cohort (${normalizedPercentage}% rollout)`
      : `user assigned to control cohort (${normalizedPercentage}% rollout)`,
  }
}