import { describe, expect, it } from 'vitest'
import {
  APPROVED_SESSION_DATA_PROFILES,
  DEFAULT_SESSION_DATA_PROFILE,
  isApprovedSessionDataProfile,
  normalizeSessionDataProfile,
} from './session-data-profile.js'

describe('session data profile helpers', () => {
  it('normalizes and validates approved data profiles', () => {
    expect(APPROVED_SESSION_DATA_PROFILES).toEqual(['synthetic', 'masked', 'redacted'])
    expect(DEFAULT_SESSION_DATA_PROFILE).toBe('synthetic')
    expect(normalizeSessionDataProfile(' SYNTHETIC ')).toBe('synthetic')
    expect(normalizeSessionDataProfile('masked')).toBe('masked')
    expect(normalizeSessionDataProfile('raw')).toBeNull()
    expect(isApprovedSessionDataProfile('redacted')).toBe(true)
    expect(isApprovedSessionDataProfile('production')).toBe(false)
  })
})
