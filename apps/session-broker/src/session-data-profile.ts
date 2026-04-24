export const APPROVED_SESSION_DATA_PROFILES = ['synthetic', 'masked', 'redacted'] as const

export type SessionDataProfile = (typeof APPROVED_SESSION_DATA_PROFILES)[number]

export const DEFAULT_SESSION_DATA_PROFILE: SessionDataProfile = 'synthetic'

const APPROVED_SESSION_DATA_PROFILE_SET = new Set<string>(APPROVED_SESSION_DATA_PROFILES)

export function normalizeSessionDataProfile(value: string | null | undefined): SessionDataProfile | null {
  if (!value) {
    return null
  }

  const normalized = value.trim().toLowerCase()
  return APPROVED_SESSION_DATA_PROFILE_SET.has(normalized)
    ? (normalized as SessionDataProfile)
    : null
}

export function isApprovedSessionDataProfile(value: string | null | undefined): value is SessionDataProfile {
  return normalizeSessionDataProfile(value) !== null
}