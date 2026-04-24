import React, { useCallback, useEffect, useMemo, useState } from 'react'
import { rbacAPI } from '@/api/rbac-client'
import { useAuthStore } from '@/store'

interface CostTotals {
  cpuHours: number
  memoryGbHours: number
  storageGbDays: number
  gpuHours: number
}

interface CostQuotaReport extends CostTotals {
  quotaId: string
  userId?: string
  workspaceId?: string
  windowStart: number
  windowEnd: number
  sampleCount: number
  estimated: boolean
}

interface MonthlyCostReport {
  userId?: string
  workspaceId?: string
  windowStart: number
  windowEnd: number
  totals: CostTotals
  quotas: CostQuotaReport[]
}

interface BudgetAlert {
  alertId: string
  scope: 'quota' | 'user' | 'workspace'
  scopeId: string
  quotaId?: string
  userId?: string
  workspaceId?: string
  metric: keyof CostTotals
  threshold: number
  actual: number
  severity: 'warning' | 'critical'
  message: string
  triggeredAt: number
  acknowledgedAt?: number
  acknowledgedBy?: string
}

type ControlCategory = 'security' | 'compliance' | 'operations' | 'release'
type ControlId =
  | 'sessionApprovalRequired'
  | 'emergencyLockdown'
  | 'publicSessionPublishing'
  | 'driftDetectionEnforced'
  | 'auditExportEnabled'
type ApprovalStatus = 'pending' | 'approved' | 'rejected'

interface PolicyControl {
  id: ControlId
  label: string
  description: string
  category: ControlCategory
  value: boolean
  critical: boolean
  owner: string
  lastChangedAt: string | null
  lastChangedBy: string | null

}

interface PolicyApprovalRequest {
  id: string
  controlId: ControlId
  requestedValue: boolean
  requestedBy: string
  approver: string
  reason: string
  status: ApprovalStatus
  requestedAt: string
  decidedAt?: string
}

interface PolicyAuditEntry {
  id: string
  action: 'bootstrap' | 'update' | 'request-approval' | 'approve' | 'reject' | 'sync'
  controlId?: ControlId
  actor: string
  diff: string
  timestamp: string
  status: 'info' | 'warn' | 'critical' | 'success'
}

interface ControlPlaneSnapshot {
  controls: PolicyControl[]
  approvals: PolicyApprovalRequest[]
  auditTrail: PolicyAuditEntry[]
  lastSyncedAt: string | null
}

interface RemoteSignals {
  health: 'unknown' | 'healthy' | 'degraded' | 'error'
  healthCheckedAt: string | null
  auditCount: number
  auditSummary: string | null
  error: string | null
}

interface RemoteAuditLog {
  eventType?: string
  userId?: string
  targetId?: string
  timestamp?: Date | string
  changes?: Record<string, unknown>
}

const STORAGE_KEY = 'portal-control-plane:v1'
const DEFAULT_APPROVER = 'security-lead@kushnir.cloud'
const APPROVER_OPTIONS = [
  'security-lead@kushnir.cloud',
  'platform-lead@kushnir.cloud',
  'sre-oncall@kushnir.cloud',
  'cto@kushnir.cloud',
]

const TIMESTAMP_FORMAT = new Intl.DateTimeFormat(undefined, {
  dateStyle: 'medium',
  timeStyle: 'short',
})

const MONTH_LABEL_FORMAT = new Intl.DateTimeFormat(undefined, {
  month: 'long',
  year: 'numeric',
})

const NUMBER_FORMAT = new Intl.NumberFormat(undefined, {
  maximumFractionDigits: 2,
})

const CATEGORY_STYLES: Record<
  ControlCategory,
  { label: string; chip: string; border: string; accent: string }
> = {
  security: {
    label: 'Security',
    chip: 'bg-rose-500/15 text-rose-100 ring-1 ring-rose-400/30',
    border: 'border-rose-400/20',
    accent: 'from-rose-500/15 to-rose-500/5',
  },
  compliance: {
    label: 'Compliance',
    chip: 'bg-amber-500/15 text-amber-100 ring-1 ring-amber-400/30',
    border: 'border-amber-400/20',
    accent: 'from-amber-500/15 to-amber-500/5',
  },
  operations: {
    label: 'Operations',
    chip: 'bg-sky-500/15 text-sky-100 ring-1 ring-sky-400/30',
    border: 'border-sky-400/20',
    accent: 'from-sky-500/15 to-sky-500/5',
  },
  release: {
    label: 'Release',
    chip: 'bg-emerald-500/15 text-emerald-100 ring-1 ring-emerald-400/30',
    border: 'border-emerald-400/20',
    accent: 'from-emerald-500/15 to-emerald-500/5',
  },
}

function nowIso(): string {
  return new Date().toISOString()
}

function formatTimestamp(timestamp: string): string {
  return TIMESTAMP_FORMAT.format(new Date(timestamp))
}

function createControlAuditEntry(parameters: {
  action: PolicyAuditEntry['action']
  actor: string
  diff: string
  status: PolicyAuditEntry['status']
  controlId?: ControlId
}): PolicyAuditEntry {
  return {
    id: `audit-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
    action: parameters.action,
    controlId: parameters.controlId,
    actor: parameters.actor,
    diff: parameters.diff,
    timestamp: nowIso(),
    status: parameters.status,
  }
}

function seedControls(): PolicyControl[] {
  const baseline = nowIso()

  return [
    {
      id: 'sessionApprovalRequired',
      label: 'Session approval gate',
      description: 'Require approval before session URLs are published to the live portal.',
      category: 'security',
      value: true,
      critical: true,
      owner: 'session-broker',
      lastChangedAt: baseline,
      lastChangedBy: 'system',
    },
    {
      id: 'emergencyLockdown',
      label: 'Emergency lockdown mode',
      description: 'Freeze non-essential changes and force the control plane into a read-only posture.',
      category: 'security',
      value: false,
      critical: true,
      owner: 'incident-response',
      lastChangedAt: baseline,
      lastChangedBy: 'system',
    },
    {
      id: 'publicSessionPublishing',
      label: 'Public session publishing',
      description: 'Expose live session links only when the approval gate is clear.',
      category: 'operations',
      value: false,
      critical: true,
      owner: 'portal-ops',
      lastChangedAt: baseline,
      lastChangedBy: 'system',
    },
    {
      id: 'driftDetectionEnforced',
      label: 'Drift detection enforced',
      description: 'Block deploys when governance or compliance drift is detected.',
      category: 'compliance',
      value: true,
      critical: false,
      owner: 'platform-governance',
      lastChangedAt: baseline,
      lastChangedBy: 'system',
    },
    {
      id: 'auditExportEnabled',
      label: 'Audit export access',
      description: 'Allow compliance export and incident evidence download for approved reviewers.',
      category: 'release',
      value: true,
      critical: false,
      owner: 'security-ops',
      lastChangedAt: baseline,
      lastChangedBy: 'system',
    },
  ]
}

function seedSnapshot(): ControlPlaneSnapshot {
  const bootstrapTime = nowIso()

  return {
    controls: seedControls(),
    approvals: [],
    auditTrail: [
      createControlAuditEntry({
        action: 'bootstrap',
        actor: 'system',
        diff: 'Initialized portal control plane with baseline security and compliance controls.',
        status: 'info',
      }),
      {
        id: `audit-${Date.now()}-policy`,
        action: 'sync',
        actor: 'system',
        diff: 'Baseline policy posture loaded from local portal cache.',
        timestamp: bootstrapTime,
        status: 'success',
      },
    ],
    lastSyncedAt: bootstrapTime,
  }
}

function isSnapshotLike(value: unknown): value is ControlPlaneSnapshot {
  if (!value || typeof value !== 'object') {
    return false
  }

  const snapshot = value as Partial<ControlPlaneSnapshot>
  return Array.isArray(snapshot.controls) && Array.isArray(snapshot.approvals) && Array.isArray(snapshot.auditTrail)
}

function readSnapshot(): ControlPlaneSnapshot {
  if (typeof window === 'undefined') {
    return seedSnapshot()
  }

  try {
    const raw = window.localStorage.getItem(STORAGE_KEY)
    if (!raw) {
      return seedSnapshot()
    }

    const parsed = JSON.parse(raw) as unknown
    if (!isSnapshotLike(parsed)) {
      return seedSnapshot()
    }

    return {
      controls: parsed.controls,
      approvals: parsed.approvals,
      auditTrail: parsed.auditTrail,
      lastSyncedAt: parsed.lastSyncedAt ?? null,
    }
  } catch {
    return seedSnapshot()
  }
}

function describeRemoteAuditLog(log: RemoteAuditLog): string {
  const pieces = [log.eventType ?? 'audit_event']

  if (log.userId) {
    pieces.push(`actor=${log.userId}`)
  }

  if (log.targetId) {
    pieces.push(`target=${log.targetId}`)
  }

  return pieces.join(' · ')
}

function formatCostValue(value: number): string {
  return NUMBER_FORMAT.format(value)
}

function formatCostMetricLabel(metric: keyof CostTotals): string {
  switch (metric) {
    case 'cpuHours':
      return 'CPU-h'
    case 'memoryGbHours':
      return 'RAM GB-h'
    case 'storageGbDays':
      return 'Storage GB-d'
    case 'gpuHours':
      return 'GPU-h'
    default:
      return metric
  }
}

function formatCostScopeLabel(report: CostQuotaReport): string {
  if (report.userId && report.workspaceId) {
    return `${report.userId} · ${report.workspaceId}`
  }

  return report.userId ?? report.workspaceId ?? report.quotaId
}

function sumCostTotals(report: CostTotals): number {
  return report.cpuHours + report.memoryGbHours + report.storageGbDays + report.gpuHours
}

// --- Sub-components ---

const RestrictedAccessPanel: React.FC<{ userRoles: string[] }> = ({ userRoles }) => (
  <div className="min-h-screen bg-slate-950 text-slate-100">
    <div className="mx-auto flex min-h-screen max-w-3xl items-center px-4 py-16 sm:px-6 lg:px-8">
      <div className="w-full rounded-3xl border border-white/10 bg-white/5 p-8 shadow-2xl backdrop-blur">
        <p className="text-xs font-semibold uppercase tracking-[0.35em] text-rose-200">Restricted access</p>
        <h1 className="mt-4 text-3xl font-semibold text-white">Control plane access is limited to admins</h1>
        <p className="mt-3 max-w-2xl text-sm leading-6 text-slate-300">
          The portal control plane contains security, compliance, and emergency lockdown controls.
          Your current role set does not grant view or edit access to this surface.
        </p>
        <div className="mt-6 rounded-2xl border border-white/10 bg-slate-900/70 p-4 text-sm text-slate-300">
          <p className="font-medium text-slate-100">Current roles</p>
          <p className="mt-2">{userRoles.join(', ') || 'none detected'}</p>
        </div>
        <div className="mt-6 flex flex-wrap gap-3 text-sm text-slate-300">
          <span className="rounded-full border border-white/10 bg-white/5 px-3 py-1">Audit logging</span>
          <span className="rounded-full border border-white/10 bg-white/5 px-3 py-1">Approval workflow</span>
          <span className="rounded-full border border-white/10 bg-white/5 px-3 py-1">Emergency lockdown</span>
        </div>
      </div>
    </div>
  </div>
)

interface ComplianceScoreHeaderProps {
  complianceScore: number
  postureLabel: string
  remoteSignals: RemoteSignals
  isRefreshing: boolean
  onRefresh: () => void
  panelError: string | null
  pendingApprovalsCount: number
  lockdownArmed: boolean
  criticalControlsCount: number
  lastSyncedAt: string | null
}

const ComplianceScoreHeader: React.FC<ComplianceScoreHeaderProps> = ({
  complianceScore,
  postureLabel,
  remoteSignals,
  isRefreshing,
  onRefresh,
  panelError,
  pendingApprovalsCount,
  lockdownArmed,
  criticalControlsCount,
  lastSyncedAt,
}) => (
  <>
    <header className="rounded-[2rem] border border-white/10 bg-white/5 p-6 shadow-2xl backdrop-blur">
      <div className="flex flex-col gap-6 lg:flex-row lg:items-start lg:justify-between">
        <div className="space-y-4">
          <div className="flex flex-wrap items-center gap-2 text-xs font-semibold uppercase tracking-[0.35em] text-sky-200">
            <span className="rounded-full border border-sky-400/30 bg-sky-500/10 px-3 py-1">Portal control plane</span>
            <span className="rounded-full border border-white/10 bg-white/5 px-3 py-1">Admin UX hardening</span>
          </div>
          <div>
            <h1 className="text-3xl font-semibold tracking-tight text-white sm:text-4xl">
              Compliance and security controls in one panel
            </h1>
            <p className="mt-3 max-w-3xl text-sm leading-6 text-slate-300 sm:text-base">
              Centralized control over approval gates, emergency lockdown, policy drift enforcement, and audit exports.
              Every change is tracked locally with actor, timestamp, and diff, while live health and audit signals are
              refreshed from the backend.
            </p>
          </div>
        </div>

        <div className="grid gap-3 sm:grid-cols-2 xl:w-[28rem]">
          <div className="rounded-2xl border border-emerald-400/20 bg-emerald-500/10 p-4">
            <p className="text-xs font-semibold uppercase tracking-[0.28em] text-emerald-100">Compliance score</p>
            <p className="mt-3 text-4xl font-semibold text-white">{complianceScore}</p>
            <p className="mt-2 text-sm text-emerald-50/80">{postureLabel} posture for the current control set.</p>
          </div>
          <div className="rounded-2xl border border-white/10 bg-slate-900/70 p-4">
            <p className="text-xs font-semibold uppercase tracking-[0.28em] text-slate-300">Live signal</p>
            <p className="mt-3 text-lg font-semibold text-white">
              {remoteSignals.health === 'healthy'
                ? 'Health OK'
                : remoteSignals.health === 'degraded'
                  ? 'Health degraded'
                  : remoteSignals.health === 'error'
                    ? 'Health error'
                    : 'Waiting for refresh'}
            </p>
            <p className="mt-2 text-sm text-slate-300">
              {remoteSignals.auditSummary ?? 'Latest audit sample will appear after refresh.'}
            </p>
            <button
              type="button"
              onClick={onRefresh}
              className="mt-4 inline-flex items-center rounded-full border border-white/10 bg-white/5 px-4 py-2 text-sm font-medium text-white transition hover:bg-white/10 disabled:cursor-not-allowed disabled:opacity-60"
              disabled={isRefreshing}
            >
              {isRefreshing ? 'Refreshing...' : 'Refresh live signals'}
            </button>
          </div>
        </div>
      </div>
    </header>

    {panelError ? (
      <div className="mt-6 rounded-2xl border border-rose-400/30 bg-rose-500/10 p-4 text-sm text-rose-100">
        {panelError}
      </div>
    ) : null}

    <div className="mt-6 grid gap-4 md:grid-cols-2 xl:grid-cols-4">
      <div className="rounded-2xl border border-white/10 bg-white/5 p-4">
        <p className="text-xs font-semibold uppercase tracking-[0.24em] text-slate-400">Approval queue</p>
        <p className="mt-2 text-3xl font-semibold text-white">{pendingApprovalsCount}</p>
        <p className="mt-1 text-sm text-slate-300">Critical requests awaiting sign-off.</p>
      </div>
      <div className="rounded-2xl border border-white/10 bg-white/5 p-4">
        <p className="text-xs font-semibold uppercase tracking-[0.24em] text-slate-400">Lockdown mode</p>
        <p className="mt-2 text-3xl font-semibold text-white">{lockdownArmed ? 'Armed' : 'Clear'}</p>
        <p className="mt-1 text-sm text-slate-300">Emergency operations status.</p>
      </div>
      <div className="rounded-2xl border border-white/10 bg-white/5 p-4">
        <p className="text-xs font-semibold uppercase tracking-[0.24em] text-slate-400">Audit feed</p>
        <p className="mt-2 text-3xl font-semibold text-white">{remoteSignals.auditCount}</p>
        <p className="mt-1 text-sm text-slate-300">Latest records observed from the backend.</p>
      </div>
      <div className="rounded-2xl border border-white/10 bg-white/5 p-4">
        <p className="text-xs font-semibold uppercase tracking-[0.24em] text-slate-400">Last sync</p>
        <p className="mt-2 text-lg font-semibold text-white">
          {lastSyncedAt ? formatTimestamp(lastSyncedAt) : 'Not synced'}
        </p>
        <p className="mt-1 text-sm text-slate-300">Control plane snapshot persistence.</p>
      </div>
    </div>

    <div className="mt-4 rounded-2xl border border-white/10 bg-slate-900/50 px-4 py-3 text-sm text-slate-300">
      <span className="font-medium text-white">{criticalControlsCount} high-risk controls</span>
      {' '}require approval before apply.
    </div>
  </>
)

interface PolicyControlsGridProps {
  controls: PolicyControl[]
  pendingApprovals: PolicyApprovalRequest[]
  draftReasons: Record<ControlId, string>
  onDraftReasonChange: (id: ControlId, value: string) => void
  onControlToggle: (control: PolicyControl) => void
}

const PolicyControlsGrid: React.FC<PolicyControlsGridProps> = ({
  controls,
  pendingApprovals,
  draftReasons,
  onDraftReasonChange,
  onControlToggle,
}) => (
  <div className="rounded-[2rem] border border-white/10 bg-white/5 p-6 shadow-2xl backdrop-blur">
    <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
      <div>
        <p className="text-xs font-semibold uppercase tracking-[0.28em] text-slate-400">Policy controls</p>
        <h2 className="mt-2 text-2xl font-semibold text-white">Operational toggles and critical gates</h2>
        <p className="mt-2 max-w-2xl text-sm leading-6 text-slate-300">
          Critical controls require a request, approval selection, and final apply step. Non-critical controls
          can be changed immediately and are still written to the local audit trail.
        </p>
      </div>
    </div>

    <div className="mt-6 grid gap-4 lg:grid-cols-2">
      {controls.map((control) => {
        const style = CATEGORY_STYLES[control.category]
        const pendingRequest = pendingApprovals.find((request) => request.controlId === control.id)
        const nextValue = !control.value

        return (
          <article
            key={control.id}
            className={`rounded-3xl border ${style.border} bg-gradient-to-br ${style.accent} p-5`}
          >
            <div className="flex flex-col gap-4">
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <div className="flex flex-wrap items-center gap-2">
                    <p className="text-lg font-semibold text-white">{control.label}</p>
                    <span className={`rounded-full px-3 py-1 text-[11px] font-semibold uppercase tracking-[0.28em] ${style.chip}`}>
                      {style.label}
                    </span>
                    {control.critical ? (
                      <span className="rounded-full border border-rose-400/30 bg-rose-500/15 px-3 py-1 text-[11px] font-semibold uppercase tracking-[0.28em] text-rose-100">
                        Critical
                      </span>
                    ) : null}
                  </div>
                  <p className="mt-2 max-w-xl text-sm leading-6 text-slate-200/90">{control.description}</p>
                </div>
                <div className="rounded-2xl border border-white/10 bg-slate-950/50 px-4 py-3 text-right">
                  <p className="text-xs font-semibold uppercase tracking-[0.24em] text-slate-400">State</p>
                  <p className={`mt-2 text-2xl font-semibold ${control.value ? 'text-emerald-300' : 'text-slate-200'}`}>
                    {control.value ? 'Enabled' : 'Disabled'}
                  </p>
                </div>
              </div>

              <div className="grid gap-3 sm:grid-cols-2 text-sm text-slate-200/80">
                <div className="rounded-2xl border border-white/10 bg-slate-950/40 p-4">
                  <p className="text-xs font-semibold uppercase tracking-[0.24em] text-slate-400">Owner</p>
                  <p className="mt-2 font-medium text-white">{control.owner}</p>
                  <p className="mt-1 text-xs text-slate-400">
                    {control.lastChangedBy ? `Updated by ${control.lastChangedBy}` : 'Not yet updated'}
                  </p>
                </div>
                <div className="rounded-2xl border border-white/10 bg-slate-950/40 p-4">
                  <p className="text-xs font-semibold uppercase tracking-[0.24em] text-slate-400">Last change</p>
                  <p className="mt-2 font-medium text-white">
                    {control.lastChangedAt ? formatTimestamp(control.lastChangedAt) : 'No change recorded'}
                  </p>
                  <p className="mt-1 text-xs text-slate-400">
                    {control.critical ? 'Approval required for the next change.' : 'Immediate change is allowed.'}
                  </p>
                </div>
              </div>

              {control.critical ? (
                <div className="space-y-3 rounded-2xl border border-white/10 bg-slate-950/50 p-4">
                  <label className="block text-xs font-semibold uppercase tracking-[0.24em] text-slate-400">
                    Approval reason
                  </label>
                  <textarea
                    value={draftReasons[control.id] ?? ''}
                    onChange={(event) => {
                      onDraftReasonChange(control.id, event.target.value)
                    }}
                    rows={3}
                    placeholder={`Why should ${control.label.toLowerCase()} change?`}
                    className="w-full rounded-2xl border border-white/10 bg-slate-900/80 px-4 py-3 text-sm text-white outline-none transition placeholder:text-slate-500 focus:border-sky-400/60"
                  />
                  {pendingRequest ? (
                    <div className="rounded-2xl border border-amber-400/30 bg-amber-500/10 p-4 text-sm text-amber-50">
                      <p className="font-semibold">Approval pending</p>
                      <p className="mt-1">
                        Requested by {pendingRequest.requestedBy} at {formatTimestamp(pendingRequest.requestedAt)}
                      </p>
                      <p className="mt-1">Reason: {pendingRequest.reason}</p>
                    </div>
                  ) : null}
                  <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
                    <button
                      type="button"
                      onClick={() => { onControlToggle(control) }}
                      className="inline-flex items-center justify-center rounded-full bg-white px-4 py-2 text-sm font-semibold text-slate-950 transition hover:bg-slate-200"
                    >
                      Request {nextValue ? 'enable' : 'disable'}
                    </button>
                    <p className="text-xs text-slate-400">
                      Pending requests become auditable change records before the control is applied.
                    </p>
                  </div>
                </div>
              ) : (
                <div className="flex flex-col gap-3 rounded-2xl border border-white/10 bg-slate-950/50 p-4 sm:flex-row sm:items-center sm:justify-between">
                  <div>
                    <p className="text-sm font-medium text-white">Immediate change</p>
                    <p className="text-xs text-slate-400">
                      This control can be changed directly. The edit is still written to the audit trail.
                    </p>
                  </div>
                  <button
                    type="button"
                    onClick={() => { onControlToggle(control) }}
                    className={`inline-flex items-center justify-center rounded-full px-4 py-2 text-sm font-semibold transition ${
                      control.value
                        ? 'bg-slate-200 text-slate-950 hover:bg-white'
                        : 'bg-emerald-400 text-slate-950 hover:bg-emerald-300'
                    }`}
                  >
                    Toggle to {nextValue ? 'enabled' : 'disabled'}
                  </button>
                </div>
              )}
            </div>
          </article>
        )
      })}
    </div>
  </div>
)

interface ApprovalWorkflowPanelProps {
  pendingApprovals: PolicyApprovalRequest[]
  controls: PolicyControl[]
  onUpdateApprover: (requestId: string, approver: string) => void
  onApprove: (requestId: string) => void
  onReject: (requestId: string) => void
}

const ApprovalWorkflowPanel: React.FC<ApprovalWorkflowPanelProps> = ({
  pendingApprovals,
  controls,
  onUpdateApprover,
  onApprove,
  onReject,
}) => (
  <div className="rounded-[2rem] border border-white/10 bg-white/5 p-6 shadow-2xl backdrop-blur">
    <p className="text-xs font-semibold uppercase tracking-[0.28em] text-slate-400">Approval workflow</p>
    <h2 className="mt-2 text-2xl font-semibold text-white">Pending critical changes</h2>
    <p className="mt-2 text-sm leading-6 text-slate-300">
      Only approved requests can mutate critical controls. This queue records the requested value, the chosen
      approver, and the reason submitted by the operator.
    </p>

    <div className="mt-6 space-y-4">
      {pendingApprovals.length === 0 ? (
        <div className="rounded-2xl border border-white/10 bg-slate-950/50 p-4 text-sm text-slate-300">
          No pending critical changes.
        </div>
      ) : null}

      {pendingApprovals.map((request) => {
        const control = controls.find((item) => item.id === request.controlId)

        return (
          <div key={request.id} className="rounded-2xl border border-white/10 bg-slate-950/60 p-4">
            <div className="flex items-start justify-between gap-3">
              <div>
                <p className="font-semibold text-white">{control?.label ?? request.controlId}</p>
                <p className="mt-1 text-xs text-slate-400">Requested at {formatTimestamp(request.requestedAt)}</p>
              </div>
              <span className="rounded-full border border-amber-400/30 bg-amber-500/10 px-3 py-1 text-[11px] font-semibold uppercase tracking-[0.24em] text-amber-100">
                Pending
              </span>
            </div>

            <p className="mt-3 text-sm text-slate-300">Reason: {request.reason}</p>
            <p className="mt-2 text-sm text-slate-300">
              Requested value: <span className="font-semibold text-white">{request.requestedValue ? 'Enabled' : 'Disabled'}</span>
            </p>

            <label className="mt-4 block text-xs font-semibold uppercase tracking-[0.24em] text-slate-400">
              Approver
            </label>
            <select
              value={request.approver}
              onChange={(event) => { onUpdateApprover(request.id, event.target.value) }}
              className="mt-2 w-full rounded-2xl border border-white/10 bg-slate-900/80 px-4 py-3 text-sm text-white outline-none transition focus:border-sky-400/60"
            >
              {APPROVER_OPTIONS.map((approver) => (
                <option key={approver} value={approver}>{approver}</option>
              ))}
            </select>

            <div className="mt-4 flex flex-col gap-3 sm:flex-row">
              <button
                type="button"
                onClick={() => { onApprove(request.id) }}
                className="inline-flex flex-1 items-center justify-center rounded-full bg-emerald-400 px-4 py-2 text-sm font-semibold text-slate-950 transition hover:bg-emerald-300"
              >
                Approve and apply
              </button>
              <button
                type="button"
                onClick={() => { onReject(request.id) }}
                className="inline-flex flex-1 items-center justify-center rounded-full border border-white/10 bg-white/5 px-4 py-2 text-sm font-semibold text-white transition hover:bg-white/10"
              >
                Reject
              </button>
            </div>
          </div>
        )
      })}
    </div>
  </div>
)

interface AuditTrailPanelProps {
  auditTrail: PolicyAuditEntry[]
  latestAuditEntry: PolicyAuditEntry | undefined
}

const AuditTrailPanel: React.FC<AuditTrailPanelProps> = ({ auditTrail, latestAuditEntry }) => (
  <div className="rounded-[2rem] border border-white/10 bg-white/5 p-6 shadow-2xl backdrop-blur">
    <p className="text-xs font-semibold uppercase tracking-[0.28em] text-slate-400">Local audit trail</p>
    <h2 className="mt-2 text-2xl font-semibold text-white">Change history</h2>
    <p className="mt-2 text-sm leading-6 text-slate-300">
      The control plane keeps a durable browser-side record of who changed what, when they changed it, and why.
    </p>

    <div className="mt-6 space-y-3">
      {auditTrail.slice(0, 8).map((entry) => (
        <div key={entry.id} className="rounded-2xl border border-white/10 bg-slate-950/60 p-4">
          <div className="flex items-start justify-between gap-3">
            <div>
              <p className="text-sm font-semibold text-white">{entry.diff}</p>
              <p className="mt-1 text-xs text-slate-400">
                {entry.actor} · {formatTimestamp(entry.timestamp)}
              </p>
            </div>
            <span
              className={`rounded-full px-3 py-1 text-[11px] font-semibold uppercase tracking-[0.24em] ${
                entry.status === 'success'
                  ? 'bg-emerald-500/15 text-emerald-100'
                  : entry.status === 'warn'
                    ? 'bg-amber-500/15 text-amber-100'
                    : entry.status === 'critical'
                      ? 'bg-rose-500/15 text-rose-100'
                      : 'bg-slate-500/15 text-slate-100'
              }`}
            >
              {entry.action}
            </span>
          </div>
        </div>
      ))}
    </div>

    {latestAuditEntry ? (
      <div className="mt-6 rounded-2xl border border-white/10 bg-slate-900/70 p-4 text-sm text-slate-300">
        <p className="font-semibold text-white">Latest event</p>
        <p className="mt-1">{latestAuditEntry.diff}</p>
      </div>
    ) : null}
  </div>
)

const RemoteSignalsPanel: React.FC<{ remoteSignals: RemoteSignals }> = ({ remoteSignals }) => (
  <div className="rounded-[2rem] border border-white/10 bg-white/5 p-6 shadow-2xl backdrop-blur">
    <p className="text-xs font-semibold uppercase tracking-[0.28em] text-slate-400">Remote status</p>
    <h2 className="mt-2 text-2xl font-semibold text-white">Backend signals</h2>
    <div className="mt-6 space-y-3 text-sm text-slate-300">
      <div className="rounded-2xl border border-white/10 bg-slate-950/60 p-4">
        <p className="text-xs font-semibold uppercase tracking-[0.24em] text-slate-400">Health</p>
        <p className="mt-2 text-base font-semibold text-white">{remoteSignals.health}</p>
        <p className="mt-1">{remoteSignals.healthCheckedAt ? formatTimestamp(remoteSignals.healthCheckedAt) : 'Not checked'}</p>
      </div>
      <div className="rounded-2xl border border-white/10 bg-slate-950/60 p-4">
        <p className="text-xs font-semibold uppercase tracking-[0.24em] text-slate-400">Audit sample</p>
        <p className="mt-2 text-base font-semibold text-white">{remoteSignals.auditSummary ?? 'Unavailable'}</p>
        <p className="mt-1">{remoteSignals.error ?? 'Backend signals received successfully.'}</p>
      </div>
    </div>
  </div>
)

interface CostInsightsPanelProps {
  monthlyReport: MonthlyCostReport | null
  budgetAlerts: BudgetAlert[]
  isLoading: boolean
  error: string | null
  lastLoadedAt: string | null
  onRefresh: () => void
}

const CostInsightsPanel: React.FC<CostInsightsPanelProps> = ({
  monthlyReport,
  budgetAlerts,
  isLoading,
  error,
  lastLoadedAt,
  onRefresh,
}) => {
  const rankedQuotas = useMemo(
    () =>
      [...(monthlyReport?.quotas ?? [])].sort((left, right) => sumCostTotals(right) - sumCostTotals(left)),
    [monthlyReport],
  )
  const acknowledgedCount = budgetAlerts.filter((alert) => Boolean(alert.acknowledgedAt)).length
  const activeAlerts = budgetAlerts.filter((alert) => !alert.acknowledgedAt)
  const criticalAlerts = budgetAlerts.filter((alert) => alert.severity === 'critical')

  return (
    <div className="rounded-[2rem] border border-white/10 bg-white/5 p-6 shadow-2xl backdrop-blur">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.28em] text-slate-400">Session cost dashboard</p>
          <h2 className="mt-2 text-2xl font-semibold text-white">Monthly cost report and budget alerts</h2>
          <p className="mt-2 max-w-2xl text-sm leading-6 text-slate-300">
            This panel surfaces the backend resource-quota cost rollups, active alerts, and acknowledgement
            state so operators do not need to query the backend directly.
          </p>
        </div>
        <button
          type="button"
          onClick={onRefresh}
          className="inline-flex items-center justify-center rounded-full border border-white/10 bg-white/5 px-4 py-2 text-sm font-medium text-white transition hover:bg-white/10 disabled:cursor-not-allowed disabled:opacity-60"
          disabled={isLoading}
        >
          {isLoading ? 'Refreshing...' : 'Refresh cost data'}
        </button>
      </div>

      {error ? (
        <div className="mt-4 rounded-2xl border border-rose-400/30 bg-rose-500/10 p-4 text-sm text-rose-100">
          {error}
        </div>
      ) : null}

      <div className="mt-6 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <div className="rounded-2xl border border-white/10 bg-slate-950/60 p-4">
          <p className="text-xs font-semibold uppercase tracking-[0.24em] text-slate-400">CPU-h</p>
          <p className="mt-2 text-3xl font-semibold text-white">{formatCostValue(monthlyReport?.totals.cpuHours ?? 0)}</p>
          <p className="mt-1 text-sm text-slate-300">Compute consumed in the selected month.</p>
        </div>
        <div className="rounded-2xl border border-white/10 bg-slate-950/60 p-4">
          <p className="text-xs font-semibold uppercase tracking-[0.24em] text-slate-400">RAM GB-h</p>
          <p className="mt-2 text-3xl font-semibold text-white">{formatCostValue(monthlyReport?.totals.memoryGbHours ?? 0)}</p>
          <p className="mt-1 text-sm text-slate-300">Memory-time across all tracked sessions.</p>
        </div>
        <div className="rounded-2xl border border-white/10 bg-slate-950/60 p-4">
          <p className="text-xs font-semibold uppercase tracking-[0.24em] text-slate-400">Storage GB-d</p>
          <p className="mt-2 text-3xl font-semibold text-white">{formatCostValue(monthlyReport?.totals.storageGbDays ?? 0)}</p>
          <p className="mt-1 text-sm text-slate-300">Persistent storage exposure over time.</p>
        </div>
        <div className="rounded-2xl border border-white/10 bg-slate-950/60 p-4">
          <p className="text-xs font-semibold uppercase tracking-[0.24em] text-slate-400">GPU-h</p>
          <p className="mt-2 text-3xl font-semibold text-white">{formatCostValue(monthlyReport?.totals.gpuHours ?? 0)}</p>
          <p className="mt-1 text-sm text-slate-300">Accelerator time in the current period.</p>
        </div>
      </div>

      <div className="mt-4 grid gap-4 md:grid-cols-3">
        <div className="rounded-2xl border border-white/10 bg-slate-950/50 p-4">
          <p className="text-xs font-semibold uppercase tracking-[0.24em] text-slate-400">Window</p>
          <p className="mt-2 text-lg font-semibold text-white">
            {monthlyReport ? MONTH_LABEL_FORMAT.format(new Date(monthlyReport.windowStart)) : 'Current month'}
          </p>
          <p className="mt-1 text-sm text-slate-300">Report window starts at {monthlyReport ? formatTimestamp(new Date(monthlyReport.windowStart).toISOString()) : 'current month start'}.</p>
        </div>
        <div className="rounded-2xl border border-white/10 bg-slate-950/50 p-4">
          <p className="text-xs font-semibold uppercase tracking-[0.24em] text-slate-400">Alerts</p>
          <p className="mt-2 text-lg font-semibold text-white">{activeAlerts.length} active</p>
          <p className="mt-1 text-sm text-slate-300">{criticalAlerts.length} critical, {acknowledgedCount} acknowledged.</p>
        </div>
        <div className="rounded-2xl border border-white/10 bg-slate-950/50 p-4">
          <p className="text-xs font-semibold uppercase tracking-[0.24em] text-slate-400">Last loaded</p>
          <p className="mt-2 text-lg font-semibold text-white">{lastLoadedAt ? formatTimestamp(lastLoadedAt) : 'Not loaded yet'}</p>
          <p className="mt-1 text-sm text-slate-300">Latest fetch from the resource-quota endpoints.</p>
        </div>
      </div>

      <div className="mt-6 grid gap-6 xl:grid-cols-[1.4fr_1fr]">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.28em] text-slate-400">Quota rollups</p>
          <div className="mt-3 space-y-3">
            {rankedQuotas.length === 0 ? (
              <div className="rounded-2xl border border-white/10 bg-slate-950/50 p-4 text-sm text-slate-300">
                No monthly cost samples have been recorded yet.
              </div>
            ) : null}

            {rankedQuotas.slice(0, 5).map((quota) => (
              <div key={quota.quotaId} className="rounded-2xl border border-white/10 bg-slate-950/60 p-4">
                <div className="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
                  <div>
                    <p className="font-semibold text-white">{formatCostScopeLabel(quota)}</p>
                    <p className="mt-1 text-xs text-slate-400">
                      {quota.quotaId} · {quota.sampleCount} samples · {quota.estimated ? 'estimated' : 'exact'}
                    </p>
                  </div>
                  <div className="rounded-full border border-sky-400/20 bg-sky-500/10 px-3 py-1 text-xs font-semibold uppercase tracking-[0.24em] text-sky-100">
                    {formatCostValue(sumCostTotals(quota))} total units
                  </div>
                </div>

                <div className="mt-4 grid gap-2 sm:grid-cols-2 xl:grid-cols-4">
                  {(['cpuHours', 'memoryGbHours', 'storageGbDays', 'gpuHours'] as const).map((metric) => (
                    <div key={metric} className="rounded-2xl border border-white/10 bg-slate-900/70 p-3">
                      <p className="text-[11px] font-semibold uppercase tracking-[0.24em] text-slate-400">
                        {formatCostMetricLabel(metric)}
                      </p>
                      <p className="mt-2 text-lg font-semibold text-white">{formatCostValue(quota[metric])}</p>
                    </div>
                  ))}
                </div>
              </div>
            ))}
          </div>
        </div>

        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.28em] text-slate-400">Budget alerts</p>
          <div className="mt-3 space-y-3">
            {budgetAlerts.length === 0 ? (
              <div className="rounded-2xl border border-white/10 bg-slate-950/50 p-4 text-sm text-slate-300">
                No budget alerts are currently active.
              </div>
            ) : null}

            {budgetAlerts.map((alert) => (
              <div key={alert.alertId} className="rounded-2xl border border-white/10 bg-slate-950/60 p-4">
                <div className="flex items-start justify-between gap-3">
                  <div>
                    <p className="font-semibold text-white">{alert.message}</p>
                    <p className="mt-1 text-xs text-slate-400">
                      {alert.scope} · {alert.scopeId} · {formatTimestamp(new Date(alert.triggeredAt).toISOString())}
                    </p>
                  </div>
                  <span
                    className={`rounded-full px-3 py-1 text-[11px] font-semibold uppercase tracking-[0.24em] ${
                      alert.severity === 'critical'
                        ? 'bg-rose-500/15 text-rose-100'
                        : 'bg-amber-500/15 text-amber-100'
                    }`}
                  >
                    {alert.severity}
                  </span>
                </div>

                <div className="mt-3 grid gap-2 sm:grid-cols-2">
                  <div className="rounded-2xl border border-white/10 bg-slate-900/70 p-3 text-sm text-slate-300">
                    <p className="text-[11px] font-semibold uppercase tracking-[0.24em] text-slate-400">Metric</p>
                    <p className="mt-1 font-medium text-white">{formatCostMetricLabel(alert.metric)}</p>
                    <p className="mt-1">Threshold {formatCostValue(alert.threshold)} · Actual {formatCostValue(alert.actual)}</p>
                  </div>
                  <div className="rounded-2xl border border-white/10 bg-slate-900/70 p-3 text-sm text-slate-300">
                    <p className="text-[11px] font-semibold uppercase tracking-[0.24em] text-slate-400">Acknowledgement</p>
                    <p className="mt-1 font-medium text-white">
                      {alert.acknowledgedAt ? 'Acknowledged' : 'Open'}
                    </p>
                    <p className="mt-1">
                      {alert.acknowledgedBy ? `By ${alert.acknowledgedBy}` : 'Awaiting review'}
                    </p>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  )
}

export const AdminControlsPage: React.FC = () => {
  const { user } = useAuthStore()
  const isAuthorized = user?.roles.some((role) => role.roleId === 'admin') ?? false

  if (!isAuthorized) {
    return <RestrictedAccessPanel userRoles={user?.roles.map((role) => role.roleId) ?? []} />
  }

  // Delegate to main orchestrator component
  return <AdminControlsPageOrchestratorComponent userEmail={user?.email ?? 'unknown'} />
}

// Orchestrator component - CC < 15 (main logic delegated to helpers and sub-components)
const AdminControlsPageOrchestratorComponent: React.FC<{ userEmail: string }> = ({ userEmail }) => {
  const initialSnapshot = useMemo(() => readSnapshot(), [])
  const { snapshot: storageSnapshot, setSnapshot: setStorageSnapshot } = useWorkspaceStorageManager(initialSnapshot)

  const { remoteSignals, isRefreshing, panelError, setPanelError, refreshSignals } = useRemoteSignalsManager()
  const { monthlyReport, budgetAlerts, isLoading: isCostLoading, error: costError, lastLoadedAt, refreshCostInsights } = useCostInsightsManager()
  const [draftReasons, setDraftReasons] = useState<Record<ControlId, string>>({
    sessionApprovalRequired: '',
    emergencyLockdown: '',
    publicSessionPublishing: '',
    driftDetectionEnforced: '',
    auditExportEnabled: '',
  })

  // Load initial signals
  useEffect(() => {
    void refreshSignals(() => rbacAPI.healthCheck(), () => rbacAPI.getAuditLogs({ limit: 5 }))
  }, [refreshSignals])

  // Calculate derived state
  const pendingApprovals = useMemo(
    () => storageSnapshot.approvals.filter((request: any) => request.status === 'pending'),
    [storageSnapshot.approvals],
  )

  const complianceScore = useComplianceScore(storageSnapshot, pendingApprovals, remoteSignals)
  const postureLabel = usePostureLabel(complianceScore, pendingApprovals, remoteSignals)
  const criticalControls = useMemo(
    () => storageSnapshot.controls.filter((control: any) => control.critical),
    [storageSnapshot.controls],
  )
  const lockdownArmed = storageSnapshot.controls.find((control: any) => control.id === 'emergencyLockdown')?.value ?? false
  const latestAuditEntry = storageSnapshot.auditTrail[0]

  // Handlers - delegated to utility functions (CC < 10 each)
  const handleControlToggle = (control: PolicyControl) => {
    setPanelError(null)
    toggleControl(control, storageSnapshot, setStorageSnapshot, draftReasons, setDraftReasons, userEmail, setPanelError)
  }

  const handleApproverUpdate = (requestId: string, approver: string) => {
    updateApproverInSnapshot(requestId, approver, setStorageSnapshot)
  }

  const handleApproveRequest = (requestId: string) => {
    approveRequestInSnapshot(requestId, userEmail, storageSnapshot, setStorageSnapshot)
  }

  const handleRejectRequest = (requestId: string) => {
    rejectRequestInSnapshot(requestId, userEmail, storageSnapshot, setStorageSnapshot)
  }

  return (
    <div className="relative min-h-screen overflow-hidden bg-slate-950 text-slate-100">
      <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_top_right,_rgba(14,165,233,0.22),_transparent_38%),radial-gradient(circle_at_bottom_left,_rgba(244,63,94,0.14),_transparent_32%),linear-gradient(180deg,_rgba(15,23,42,0.98),_rgba(2,6,23,1))]" />
      <div className="relative mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
        <ComplianceScoreHeader
          complianceScore={complianceScore}
          postureLabel={postureLabel}
          remoteSignals={remoteSignals}
          isRefreshing={isRefreshing}
          onRefresh={() => { void refreshSignals(() => rbacAPI.healthCheck(), () => rbacAPI.getAuditLogs({ limit: 5 })) }}
          panelError={panelError}
          pendingApprovalsCount={pendingApprovals.length}
          lockdownArmed={lockdownArmed}
          criticalControlsCount={criticalControls.length}
          lastSyncedAt={storageSnapshot.lastSyncedAt}
        />

        <div className="mt-6 grid gap-6 xl:grid-cols-[1.45fr_1fr]">
          <section className="space-y-6">
            <PolicyControlsGrid
              controls={storageSnapshot.controls}
              pendingApprovals={pendingApprovals}
              draftReasons={draftReasons}
              onDraftReasonChange={(id, value) => { setDraftReasons((current) => ({ ...current, [id]: value })) }}
              onControlToggle={handleControlToggle}
            />
          </section>

          <aside className="space-y-6">
            <CostInsightsPanel
              monthlyReport={monthlyReport}
              budgetAlerts={budgetAlerts}
              isLoading={isCostLoading}
              error={costError}
              lastLoadedAt={lastLoadedAt}
              onRefresh={() => { void refreshCostInsights() }}
            />
            <ApprovalWorkflowPanel
              pendingApprovals={pendingApprovals}
              controls={storageSnapshot.controls}
              onUpdateApprover={handleApproverUpdate}
              onApprove={handleApproveRequest}
              onReject={handleRejectRequest}
            />
            <AuditTrailPanel
              auditTrail={storageSnapshot.auditTrail}
              latestAuditEntry={latestAuditEntry}
            />
            <RemoteSignalsPanel remoteSignals={remoteSignals} />
          </aside>
        </div>
      </div>
    </div>
  )
}

// Helper hooks - each < 15 CC
function useWorkspaceStorageManager(initialSnapshot: ControlPlaneSnapshot) {
  const [snapshot, setSnapshot] = useState<ControlPlaneSnapshot>(initialSnapshot)

  useEffect(() => {
    if (typeof window === 'undefined') {
      return
    }
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(snapshot))
  }, [snapshot])

  return { snapshot, setSnapshot }
}

function useRemoteSignalsManager() {
  const [remoteSignals, setRemoteSignals] = useState<RemoteSignals>({
    health: 'unknown',
    healthCheckedAt: null,
    auditCount: 0,
    auditSummary: null,
    error: null,
  })
  const [isRefreshing, setIsRefreshing] = useState(false)
  const [panelError, setPanelError] = useState<string | null>(null)

  const refreshSignals = useCallback(
    async (healthCheck: () => Promise<any>, getAuditLogs: () => Promise<any>) => {
      setIsRefreshing(true)
      setPanelError(null)

      try {
        const [healthResult, auditResult] = await Promise.allSettled([healthCheck(), getAuditLogs()])

        const nextRemoteSignals: RemoteSignals = {
          health: 'unknown',
          healthCheckedAt: nowIso(),
          auditCount: 0,
          auditSummary: null,
          error: null,
        }

        if (healthResult.status === 'fulfilled') {
          nextRemoteSignals.health = healthResult.value.status === 'ok' ? 'healthy' : 'degraded'
        } else {
          nextRemoteSignals.health = 'error'
          nextRemoteSignals.error = healthResult.reason instanceof Error ? healthResult.reason.message : 'Health check failed'
        }

        if (auditResult.status === 'fulfilled') {
          nextRemoteSignals.auditCount = auditResult.value.logs.length
          const latest = auditResult.value.logs[0]
          nextRemoteSignals.auditSummary = latest ? describeRemoteAuditLog(latest as RemoteAuditLog) : 'No recent audit events'
        } else if (!nextRemoteSignals.error) {
          nextRemoteSignals.error = auditResult.reason instanceof Error ? auditResult.reason.message : 'Audit fetch failed'
        }

        setRemoteSignals(nextRemoteSignals)
      } catch (error) {
        setRemoteSignals({
          health: 'error',
          healthCheckedAt: nowIso(),
          auditCount: 0,
          auditSummary: null,
          error: error instanceof Error ? error.message : 'Unable to refresh control-plane signals',
        })
        setPanelError(error instanceof Error ? error.message : 'Unable to refresh control-plane signals')
      } finally {
        setIsRefreshing(false)
      }
    },
    [],
  )

  return { remoteSignals, isRefreshing, panelError, setPanelError, refreshSignals }
}

function useCostInsightsManager() {
  const [monthlyReport, setMonthlyReport] = useState<MonthlyCostReport | null>(null)
  const [budgetAlerts, setBudgetAlerts] = useState<BudgetAlert[]>([])
  const [isLoading, setIsLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [lastLoadedAt, setLastLoadedAt] = useState<string | null>(null)

  const refreshCostInsights = useCallback(async () => {
    setIsLoading(true)
    setError(null)

    try {
      const [monthlyResponse, alertsResponse] = await Promise.all([
        fetch('/api/resource-quotas/cost/monthly', { credentials: 'include' }),
        fetch('/api/resource-quotas/cost/alerts', { credentials: 'include' }),
      ])

      if (!monthlyResponse.ok) {
        throw new Error(`Monthly cost report request failed (${monthlyResponse.status})`)
      }

      if (!alertsResponse.ok) {
        throw new Error(`Budget alerts request failed (${alertsResponse.status})`)
      }

      const monthlyPayload = (await monthlyResponse.json()) as { success?: boolean; data?: MonthlyCostReport }
      const alertsPayload = (await alertsResponse.json()) as { success?: boolean; data?: BudgetAlert[] }

      setMonthlyReport(monthlyPayload.data ?? null)
      setBudgetAlerts(alertsPayload.data ?? [])
      setLastLoadedAt(nowIso())
    } catch (fetchError) {
      setMonthlyReport(null)
      setBudgetAlerts([])
      setError(fetchError instanceof Error ? fetchError.message : 'Unable to load cost insights')
    } finally {
      setIsLoading(false)
    }
  }, [])

  useEffect(() => {
    void refreshCostInsights()
  }, [refreshCostInsights])

  return { monthlyReport, budgetAlerts, isLoading, error, lastLoadedAt, refreshCostInsights }
}

function useComplianceScore(snapshot: ControlPlaneSnapshot, pendingApprovals: any[], remoteSignals: RemoteSignals) {
  return useMemo(() => {
    const pendingPenalty = pendingApprovals.length * 12
    const lockdownPenalty = snapshot.controls.find((control) => control.id === 'emergencyLockdown')?.value ? 18 : 0
    const auditBonus = remoteSignals.health === 'healthy' ? 5 : 0
    const driftBonus = snapshot.controls.every((control) => control.value || !control.critical) ? 4 : 0

    return Math.max(0, Math.min(100, 88 + auditBonus + driftBonus - pendingPenalty - lockdownPenalty))
  }, [pendingApprovals.length, remoteSignals.health, snapshot.controls])
}

function usePostureLabel(complianceScore: number, pendingApprovals: any[], remoteSignals: RemoteSignals) {
  return useMemo(() => {
    if (complianceScore >= 90 && pendingApprovals.length === 0 && remoteSignals.health === 'healthy') {
      return 'Ready'
    }

    if (complianceScore >= 70) {
      return 'Review'
    }

    return 'Blocked'
  }, [complianceScore, pendingApprovals.length, remoteSignals.health])
}

// Handler utilities - each < 10 CC
function toggleControl(
  control: PolicyControl,
  snapshot: ControlPlaneSnapshot,
  setSnapshot: (snap: ControlPlaneSnapshot) => void,
  draftReasons: Record<ControlId, string>,
  setDraftReasons: (reasons: Record<ControlId, string>) => void,
  userEmail: string,
  setPanelError: (error: string | null) => void,
) {
  if (control.critical) {
    const reason = draftReasons[control.id]?.trim()
    if (!reason) {
      setPanelError('Critical control changes require a reason before submission.')
      return
    }

    requestCriticalApproval(control, snapshot, setSnapshot, draftReasons, setDraftReasons, userEmail)
  } else {
    updateControlDirect(control.id, !control.value, snapshot, setSnapshot, userEmail)
  }
}

function requestCriticalApproval(
  control: PolicyControl,
  snapshot: ControlPlaneSnapshot,
  setSnapshot: (snap: ControlPlaneSnapshot) => void,
  draftReasons: Record<ControlId, string>,
  setDraftReasons: (reasons: Record<ControlId, string>) => void,
  userEmail: string,
) {
  const reason = draftReasons[control.id]?.trim() ?? ''
  const nextValue = !control.value

  setSnapshot({
    ...snapshot,
    approvals: [
      {
        id: `approval-${Date.now()}-${control.id}`,
        controlId: control.id,
        requestedValue: nextValue,
        requestedBy: userEmail,
        approver: DEFAULT_APPROVER,
        reason,
        status: 'pending',
        requestedAt: nowIso(),
      },
      ...snapshot.approvals,
    ],
    auditTrail: [
      createControlAuditEntry({
        action: 'request-approval',
        actor: userEmail,
        controlId: control.id,
        diff: `${control.label}: requested ${nextValue ? 'enable' : 'disable'} with reason "${reason}"`,
        status: 'warn',
      }),
      ...snapshot.auditTrail,
    ],
  })

  setDraftReasons((current) => ({
    ...current,
    [control.id]: '',
  }))
}

function updateControlDirect(
  controlId: ControlId,
  nextValue: boolean,
  snapshot: ControlPlaneSnapshot,
  setSnapshot: (snap: ControlPlaneSnapshot) => void,
  userEmail: string,
) {
  const control = snapshot.controls.find((item) => item.id === controlId)
  if (!control) {
    return
  }

  setSnapshot({
    ...snapshot,
    controls: snapshot.controls.map((item) =>
      item.id === controlId
        ? {
            ...item,
            value: nextValue,
            lastChangedAt: nowIso(),
            lastChangedBy: userEmail,
          }
        : item,
    ),
    auditTrail: [
      createControlAuditEntry({
        action: 'update',
        actor: userEmail,
        controlId,
        diff: `${control.label}: ${control.value ? 'enabled' : 'disabled'} -> ${nextValue ? 'enabled' : 'disabled'}`,
        status: nextValue ? 'success' : 'warn',
      }),
      ...snapshot.auditTrail,
    ],
  })
}

function updateApproverInSnapshot(
  requestId: string,
  approver: string,
  setSnapshot: (snap: ControlPlaneSnapshot) => void,
) {
  setSnapshot((current: ControlPlaneSnapshot) => ({
    ...current,
    approvals: current.approvals.map((request: any) =>
      request.id === requestId ? { ...request, approver } : request,
    ),
  }))
}

function approveRequestInSnapshot(
  requestId: string,
  userEmail: string,
  snapshot: ControlPlaneSnapshot,
  setSnapshot: (snap: ControlPlaneSnapshot) => void,
) {
  const request = snapshot.approvals.find((item: any) => item.id === requestId)
  const control = request ? snapshot.controls.find((item) => item.id === request.controlId) : undefined

  if (!request || !control) {
    return
  }

  setSnapshot({
    ...snapshot,
    controls: snapshot.controls.map((item) =>
      item.id === request.controlId
        ? {
            ...item,
            value: request.requestedValue,
            lastChangedAt: nowIso(),
            lastChangedBy: request.approver,
          }
        : item,
    ),
    approvals: snapshot.approvals.map((item: any) =>
      item.id === requestId ? { ...item, status: 'approved', decidedAt: nowIso() } : item,
    ),
    auditTrail: [
      createControlAuditEntry({
        action: 'approve',
        actor: userEmail,
        controlId: request.controlId,
        diff: `${control.label}: approved by ${request.approver}; ${control.value ? 'enabled' : 'disabled'} -> ${request.requestedValue ? 'enabled' : 'disabled'}`,
        status: 'success',
      }),
      ...snapshot.auditTrail,
    ],
  })
}

function rejectRequestInSnapshot(
  requestId: string,
  userEmail: string,
  snapshot: ControlPlaneSnapshot,
  setSnapshot: (snap: ControlPlaneSnapshot) => void,
) {
  const request = snapshot.approvals.find((item: any) => item.id === requestId)
  if (!request) {
    return
  }

  const control = snapshot.controls.find((item) => item.id === request.controlId)

  setSnapshot({
    ...snapshot,
    approvals: snapshot.approvals.map((item: any) =>
      item.id === requestId ? { ...item, status: 'rejected', decidedAt: nowIso() } : item,
    ),
    auditTrail: [
      createControlAuditEntry({
        action: 'reject',
        actor: userEmail,
        controlId: request.controlId,
        diff: `${control?.label ?? request.controlId}: request rejected by ${userEmail}`,
        status: 'critical',
      }),
      ...snapshot.auditTrail,
    ],
  })
}
