import { describe, expect, it } from 'vitest'
import {
  buildSessionDeletionRecord,
  finalizeDeletionRecord,
  holdDeletionRecord,
  isDeletionHoldActive,
  isDeletionQuarantineExpired,
  releaseDeletionHold,
} from './session-deletion.js'

describe('session deletion quarantine helpers', () => {
  const baseResources = {
    containerId: 'container-123',
    containerName: 'session-user-123',
    storageRoot: '/var/lib/code-server-sessions/session-123',
    quarantineRoot: '/var/lib/code-server-sessions/quarantine/session-123',
    workspacePath: '/var/lib/code-server-sessions/session-123/workspace',
    profilePath: '/var/lib/code-server-sessions/session-123/profile',
    sessionRecordPresent: true,
  }

  it('builds a quarantined deletion record with a future ttl', () => {
    const record = buildSessionDeletionRecord({
      sessionId: 'session-123',
      actor: 'system',
      reason: 'termination requested',
      correlationId: 'corr-1',
      quarantineHours: 24,
      resourcesBefore: baseResources,
      resourcesRemoved: ['container:container-123', baseResources.storageRoot],
      resourcesRemaining: [baseResources.quarantineRoot],
    })

    expect(record).toMatchObject({
      sessionId: 'session-123',
      status: 'quarantined',
      hold: false,
      quarantineRoot: baseResources.quarantineRoot,
      resourcesRemaining: [baseResources.quarantineRoot],
      residualResourceZero: false,
    })
    expect(new Date(record.quarantineUntil).getTime()).toBeGreaterThan(Date.now())
    expect(record.checksum).toMatch(/^sha256:[a-f0-9]{64}$/i)
  })

  it('tracks hold and release decisions with updated checksums', () => {
    const record = buildSessionDeletionRecord({
      sessionId: 'session-123',
      actor: 'system',
      reason: 'termination requested',
      correlationId: 'corr-1',
      quarantineHours: 24,
      resourcesBefore: baseResources,
      resourcesRemoved: ['container:container-123', baseResources.storageRoot],
      resourcesRemaining: [baseResources.quarantineRoot],
    })

    const held = holdDeletionRecord(record, {
      actor: 'alice',
      reason: 'forensic review',
      correlationId: 'corr-2',
    })

    expect(isDeletionHoldActive(held)).toBe(true)
    expect(held.holdReason).toBe('forensic review')
    expect(held.holdAppliedBy).toBe('alice')
    expect(held.checksum).not.toBe(record.checksum)

    const released = releaseDeletionHold(held, {
      actor: 'alice',
      reason: 'review complete',
      correlationId: 'corr-3',
    })

    expect(isDeletionHoldActive(released)).toBe(false)
    expect(released.holdReason).toContain('review complete')
    expect(released.checksum).not.toBe(held.checksum)
  })

  it('finalizes a quarantined record into a zero-residual purge', () => {
    const record = buildSessionDeletionRecord({
      sessionId: 'session-123',
      actor: 'system',
      reason: 'termination requested',
      correlationId: 'corr-1',
      quarantineHours: 24,
      resourcesBefore: baseResources,
      resourcesRemoved: ['container:container-123', baseResources.storageRoot],
      resourcesRemaining: [baseResources.quarantineRoot],
    })

    const finalized = finalizeDeletionRecord(record, {
      actor: 'system',
      reason: 'quarantine expired',
      correlationId: 'corr-4',
    }, [baseResources.quarantineRoot])

    expect(finalized.status).toBe('completed')
    expect(finalized.residualResourceZero).toBe(true)
    expect(finalized.resourcesRemaining).toEqual([])
    expect(finalized.purgedAt).toBeDefined()
    expect(finalized.overrideAppliedBy).toBe('system')
    expect(finalized.checksum).not.toBe(record.checksum)
  })

  it('detects quarantine expiry from the ttl deadline', () => {
    const expired = buildSessionDeletionRecord({
      sessionId: 'session-123',
      actor: 'system',
      reason: 'termination requested',
      correlationId: 'corr-1',
      quarantineHours: 0.001,
      resourcesBefore: baseResources,
      resourcesRemoved: ['container:container-123', baseResources.storageRoot],
      resourcesRemaining: [baseResources.quarantineRoot],
    })

    expect(isDeletionQuarantineExpired(expired, Date.now() + 10_000)).toBe(true)
  })
})
