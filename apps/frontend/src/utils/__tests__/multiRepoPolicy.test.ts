import { describe, expect, it } from 'vitest'

import {
  assessMultiRepoPolicyConformance,
  buildMultiRepoPolicyAuditRecord,
  deserializeMultiRepoPolicy,
  resolveMultiRepoPolicy,
  serializeMultiRepoPolicy,
} from '../multiRepoPolicy'

describe('multiRepoPolicy', () => {
  it('resolves versioned admin policy limits', () => {
    const policy = resolveMultiRepoPolicy(['admin'])

    expect(policy).toEqual({
      schemaVersion: 1,
      policyVersion: 'multi-repo-policy-v1',
      policyId: 'multi-repo-policy-v1:admin',
      tier: 'admin',
      label: 'Admin',
      canSwitchWorkspace: true,
      canUseQuickSwitcher: true,
      canRestoreSession: true,
      canPinWorkspace: true,
      maxRecentWorkspaces: 3,
      limits: {
        maxRepos: 12,
        persistenceDepth: 7,
        retentionDays: 30,
        telemetryLevel: 'detailed',
      },
      reversible: true,
    })
  })

  it('serializes and restores a policy definition', () => {
    const policy = resolveMultiRepoPolicy(['developer'])
    const restored = deserializeMultiRepoPolicy(serializeMultiRepoPolicy(policy))

    expect(restored).toEqual(policy)
  })

  it('detects conformance drift when recent history exceeds the tier cap', () => {
    const policy = resolveMultiRepoPolicy(['reviewer'])
    const report = assessMultiRepoPolicyConformance(policy, {
      recentRepoIds: ['repo-a', 'repo-b', 'repo-c'],
    })

    expect(report.compliant).toBe(false)
    expect(report.issues).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ code: 'recent-workspace-cap-exceeded' }),
      ])
    )
  })

  it('builds an auditable policy record', () => {
    const policy = resolveMultiRepoPolicy(['auditor'])
    const report = assessMultiRepoPolicyConformance(policy, { recentRepoIds: [] })
    const auditRecord = buildMultiRepoPolicyAuditRecord(policy, report)

    expect(auditRecord).toMatchObject({
      policyId: policy.policyId,
      policyVersion: policy.policyVersion,
      schemaVersion: 1,
      reversible: true,
    })
  })
})