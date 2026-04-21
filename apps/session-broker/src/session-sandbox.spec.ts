import { describe, expect, it } from 'vitest'
import {
  normalizeSessionSandboxRuntime,
  resolveSessionSandboxDecision,
} from './session-sandbox.js'

describe('session sandbox policy', () => {
  it('normalizes gVisor runtime aliases to runsc', () => {
    expect(normalizeSessionSandboxRuntime('gvisor')).toBe('runsc')
    expect(normalizeSessionSandboxRuntime(' runsc ')).toBe('runsc')
  })

  it('treats default and runc as the standard runtime', () => {
    expect(normalizeSessionSandboxRuntime('')).toBeUndefined()
    expect(normalizeSessionSandboxRuntime('default')).toBeUndefined()
    expect(normalizeSessionSandboxRuntime('runc')).toBeUndefined()
  })

  it('fails closed when sandboxing is required but not configured', () => {
    expect(() => resolveSessionSandboxDecision('', true)).toThrow(/SESSION_SANDBOX_REQUIRED/i)
  })

  it('returns a gVisor decision when sandbox runtime is set', () => {
    expect(resolveSessionSandboxDecision('gvisor')).toEqual({
      enabled: true,
      mode: 'gvisor',
      runtime: 'runsc',
      required: false,
    })
  })
})