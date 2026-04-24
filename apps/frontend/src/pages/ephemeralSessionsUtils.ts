import type { SessionLifecycleState } from '@/types'

export const SESSION_DATA_PROFILES = ['synthetic', 'masked', 'redacted'] as const

export type SessionDataProfile = (typeof SESSION_DATA_PROFILES)[number]

export function normalizeDataProfile(value: string | null | undefined): SessionDataProfile | null {
  if (!value) {
    return null
  }

  const normalized = value.trim().toLowerCase()
  return SESSION_DATA_PROFILES.includes(normalized as SessionDataProfile)
    ? (normalized as SessionDataProfile)
    : null
}

export function isApprovedDataProfile(value: string | null | undefined): value is SessionDataProfile {
  return normalizeDataProfile(value) !== null
}

export function normalizeUsername(email: string, fullName?: string): string {
  const primarySource = (fullName || email.split('@')[0] || 'user').toLowerCase()
  const normalized = primarySource.replace(/[^a-z0-9]/g, '')

  if (normalized.length >= 3) {
    return normalized.slice(0, 32)
  }

  const fallback = email.split('@')[0].toLowerCase().replace(/[^a-z0-9]/g, '') || 'user'
  return fallback.padEnd(3, '0').slice(0, 32)
}

export function formatDate(value: Date | string | number | undefined | null): string {
  if (!value) {
    return 'Not available'
  }

  const date = value instanceof Date ? value : new Date(value)
  if (Number.isNaN(date.getTime())) {
    return 'Not available'
  }

  return new Intl.DateTimeFormat(undefined, {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(date)
}

export function stateTone(state?: SessionLifecycleState | null): string {
  switch (state) {
    case 'ready':
      return 'bg-emerald-100 text-emerald-800 border-emerald-200'
    case 'provisioning':
    case 'requested':
    case 'queued':
      return 'bg-amber-100 text-amber-800 border-amber-200'
    case 'testing':
      return 'bg-sky-100 text-sky-800 border-sky-200'
    case 'teardown_pending':
      return 'bg-orange-100 text-orange-800 border-orange-200'
    case 'destroyed':
    case 'failed':
      return 'bg-rose-100 text-rose-800 border-rose-200'
    default:
      return 'bg-slate-100 text-slate-700 border-slate-200'
  }
}