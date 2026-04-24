export const MULTI_REPO_POLICY_SCHEMA_VERSION = 1 as const
const MULTI_REPO_POLICY_VERSION = 'multi-repo-policy-v1' as const

export type MultiRepoPolicySchemaVersion = typeof MULTI_REPO_POLICY_SCHEMA_VERSION

export type MultiRepoPolicyTier = 'admin' | 'developer' | 'reviewer' | 'auditor' | 'read-only'

export type MultiRepoTelemetryLevel = 'off' | 'summary' | 'detailed'

export type MultiRepoPolicyLimits = {
  maxRepos: number
  persistenceDepth: number
  retentionDays: number
  telemetryLevel: MultiRepoTelemetryLevel
}

export type MultiRepoPolicyDefinition = {
  schemaVersion: MultiRepoPolicySchemaVersion
  policyVersion: string
  policyId: string
  tier: MultiRepoPolicyTier
  label: string
  canSwitchWorkspace: boolean
  canUseQuickSwitcher: boolean
  canRestoreSession: boolean
  canPinWorkspace: boolean
  maxRecentWorkspaces: number
  limits: MultiRepoPolicyLimits
  reversible: boolean
}

export type MultiRepoPolicyRuntimeState = {
  recentRepoIds: string[]
  requestedCapabilities?: {
    tabs?: boolean
    switcher?: boolean
    persistence?: boolean
  }
}

export type MultiRepoPolicyIssue = {
  code: string
  message: string
}

export type MultiRepoPolicyConformanceReport = {
  schemaVersion: MultiRepoPolicySchemaVersion
  policyId: string
  compliant: boolean
  issues: MultiRepoPolicyIssue[]
  evaluatedAt: number
}

export type MultiRepoPolicyAuditRecord = {
  auditId: string
  policyId: string
  policyVersion: string
  schemaVersion: MultiRepoPolicySchemaVersion
  compliant: boolean
  issueCount: number
  reversible: boolean
  generatedAt: number
}

type MultiRepoPolicyTemplate = {
  label: string
  canSwitchWorkspace: boolean
  canUseQuickSwitcher: boolean
  canRestoreSession: boolean
  canPinWorkspace: boolean
  maxRecentWorkspaces: number
  limits: MultiRepoPolicyLimits
}

const DEFAULT_POLICY: MultiRepoPolicyTemplate = {
  label: 'Read-only',
  canSwitchWorkspace: false,
  canUseQuickSwitcher: false,
  canRestoreSession: false,
  canPinWorkspace: false,
  maxRecentWorkspaces: 1,
  limits: {
    maxRepos: 1,
    persistenceDepth: 0,
    retentionDays: 0,
    telemetryLevel: 'off',
  },
}

const POLICY_TEMPLATES: Record<MultiRepoPolicyTier, MultiRepoPolicyTemplate> = {
  admin: {
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
  },
  developer: {
    label: 'Developer',
    canSwitchWorkspace: true,
    canUseQuickSwitcher: true,
    canRestoreSession: true,
    canPinWorkspace: false,
    maxRecentWorkspaces: 3,
    limits: {
      maxRepos: 8,
      persistenceDepth: 7,
      retentionDays: 14,
      telemetryLevel: 'summary',
    },
  },
  reviewer: {
    label: 'Reviewer',
    canSwitchWorkspace: true,
    canUseQuickSwitcher: true,
    canRestoreSession: false,
    canPinWorkspace: false,
    maxRecentWorkspaces: 2,
    limits: {
      maxRepos: 4,
      persistenceDepth: 3,
      retentionDays: 7,
      telemetryLevel: 'summary',
    },
  },
  auditor: {
    label: 'Auditor',
    canSwitchWorkspace: false,
    canUseQuickSwitcher: false,
    canRestoreSession: false,
    canPinWorkspace: false,
    maxRecentWorkspaces: 1,
    limits: {
      maxRepos: 1,
      persistenceDepth: 0,
      retentionDays: 0,
      telemetryLevel: 'off',
    },
  },
  'read-only': DEFAULT_POLICY,
}

function normalizeRoleIds(roleIds: string[]): Set<string> {
  return new Set(roleIds.map((roleId) => roleId.trim().toLowerCase()).filter(Boolean))
}

function selectPolicyTier(roleIds: string[]): MultiRepoPolicyTier {
  const normalizedRoles = normalizeRoleIds(roleIds)

  if (normalizedRoles.has('admin')) {
    return 'admin'
  }

  if (normalizedRoles.has('developer')) {
    return 'developer'
  }

  if (normalizedRoles.has('reviewer')) {
    return 'reviewer'
  }

  if (normalizedRoles.has('auditor')) {
    return 'auditor'
  }

  return 'read-only'
}

function buildPolicyDefinition(tier: MultiRepoPolicyTier): MultiRepoPolicyDefinition {
  const template = POLICY_TEMPLATES[tier]

  return {
    schemaVersion: MULTI_REPO_POLICY_SCHEMA_VERSION,
    policyVersion: MULTI_REPO_POLICY_VERSION,
    policyId: `${MULTI_REPO_POLICY_VERSION}:${tier}`,
    tier,
    label: template.label,
    canSwitchWorkspace: template.canSwitchWorkspace,
    canUseQuickSwitcher: template.canUseQuickSwitcher,
    canRestoreSession: template.canRestoreSession,
    canPinWorkspace: template.canPinWorkspace,
    maxRecentWorkspaces: template.maxRecentWorkspaces,
    limits: template.limits,
    reversible: true,
  }
}

export function resolveMultiRepoPolicy(roleIds: string[]): MultiRepoPolicyDefinition {
  return buildPolicyDefinition(selectPolicyTier(roleIds))
}

export function assessMultiRepoPolicyConformance(
  policy: MultiRepoPolicyDefinition,
  runtimeState: MultiRepoPolicyRuntimeState
): MultiRepoPolicyConformanceReport {
  const issues: MultiRepoPolicyIssue[] = []

  if (runtimeState.recentRepoIds.length > policy.maxRecentWorkspaces) {
    issues.push({
      code: 'recent-workspace-cap-exceeded',
      message: `recent workspace history exceeds policy cap (${runtimeState.recentRepoIds.length}/${policy.maxRecentWorkspaces})`,
    })
  }

  if (runtimeState.requestedCapabilities?.tabs && !policy.canSwitchWorkspace) {
    issues.push({
      code: 'tabs-disallowed',
      message: 'workspace tabs are enabled by the client but denied by policy',
    })
  }

  if (runtimeState.requestedCapabilities?.switcher && !policy.canUseQuickSwitcher) {
    issues.push({
      code: 'switcher-disallowed',
      message: 'quick switcher is enabled by the client but denied by policy',
    })
  }

  if (runtimeState.requestedCapabilities?.persistence && !policy.canRestoreSession) {
    issues.push({
      code: 'persistence-disallowed',
      message: 'session persistence is enabled by the client but denied by policy',
    })
  }

  return {
    schemaVersion: policy.schemaVersion,
    policyId: policy.policyId,
    compliant: issues.length === 0,
    issues,
    evaluatedAt: Date.now(),
  }
}

export function serializeMultiRepoPolicy(policy: MultiRepoPolicyDefinition): string {
  return JSON.stringify(policy)
}

export function deserializeMultiRepoPolicy(rawPolicy: string): MultiRepoPolicyDefinition | null {
  try {
    const parsedValue = JSON.parse(rawPolicy) as Partial<MultiRepoPolicyDefinition>
    if (
      !parsedValue ||
      parsedValue.schemaVersion !== MULTI_REPO_POLICY_SCHEMA_VERSION ||
      typeof parsedValue.policyId !== 'string'
    ) {
      return null
    }

    return {
      schemaVersion: MULTI_REPO_POLICY_SCHEMA_VERSION,
      policyVersion: typeof parsedValue.policyVersion === 'string' ? parsedValue.policyVersion : MULTI_REPO_POLICY_VERSION,
      policyId: parsedValue.policyId,
      tier: (parsedValue.tier as MultiRepoPolicyTier) ?? 'read-only',
      label: typeof parsedValue.label === 'string' ? parsedValue.label : DEFAULT_POLICY.label,
      canSwitchWorkspace: Boolean(parsedValue.canSwitchWorkspace),
      canUseQuickSwitcher: Boolean(parsedValue.canUseQuickSwitcher),
      canRestoreSession: Boolean(parsedValue.canRestoreSession),
      canPinWorkspace: Boolean(parsedValue.canPinWorkspace),
      maxRecentWorkspaces: Number.isFinite(parsedValue.maxRecentWorkspaces)
        ? Number(parsedValue.maxRecentWorkspaces)
        : DEFAULT_POLICY.maxRecentWorkspaces,
      limits: {
        maxRepos: Number.isFinite(parsedValue.limits?.maxRepos) ? Number(parsedValue.limits!.maxRepos) : DEFAULT_POLICY.limits.maxRepos,
        persistenceDepth: Number.isFinite(parsedValue.limits?.persistenceDepth)
          ? Number(parsedValue.limits!.persistenceDepth)
          : DEFAULT_POLICY.limits.persistenceDepth,
        retentionDays: Number.isFinite(parsedValue.limits?.retentionDays)
          ? Number(parsedValue.limits!.retentionDays)
          : DEFAULT_POLICY.limits.retentionDays,
        telemetryLevel:
          parsedValue.limits?.telemetryLevel === 'summary' || parsedValue.limits?.telemetryLevel === 'detailed'
            ? parsedValue.limits.telemetryLevel
            : DEFAULT_POLICY.limits.telemetryLevel,
      },
      reversible: parsedValue.reversible !== false,
    }
  } catch {
    return null
  }
}

export function buildMultiRepoPolicyAuditRecord(
  policy: MultiRepoPolicyDefinition,
  report: MultiRepoPolicyConformanceReport
): MultiRepoPolicyAuditRecord {
  return {
    auditId: `${policy.policyId}:${report.evaluatedAt}`,
    policyId: policy.policyId,
    policyVersion: policy.policyVersion,
    schemaVersion: policy.schemaVersion,
    compliant: report.compliant,
    issueCount: report.issues.length,
    reversible: policy.reversible,
    generatedAt: report.evaluatedAt,
  }
}