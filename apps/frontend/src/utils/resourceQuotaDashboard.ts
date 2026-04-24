export interface ResourceCostTotals {
  cpuHours: number
  memoryGbHours: number
  storageGbDays: number
  gpuHours: number
}

export type ResourceCostMetric = keyof ResourceCostTotals

export interface MonthlyCostQuotaLike extends Partial<ResourceCostTotals> {
  quotaId?: string
  userId?: string
  workspaceId?: string
  projectId?: string
  identifier?: string
  scope?: 'quota' | 'user' | 'workspace' | 'project'
  sampleCount?: number
  estimated?: boolean
  totals?: Partial<ResourceCostTotals>
}

export interface MonthlyCostReportLike {
  windowStart?: number | string | null
  windowEnd?: number | string | null
  totals?: Partial<ResourceCostTotals> | null
  quotas?: MonthlyCostQuotaLike[]
  byUser?: MonthlyCostQuotaLike[]
  byWorkspace?: MonthlyCostQuotaLike[]
  byProject?: MonthlyCostQuotaLike[]
}

export interface BudgetAlertLike {
  alertId?: string
  scope?: 'quota' | 'user' | 'workspace' | 'project'
  scopeId?: string
  quotaId?: string
  userId?: string
  workspaceId?: string
  projectId?: string
  identifier?: string
  metric?: ResourceCostMetric
  threshold?: number
  actual?: number
  severity?: 'warning' | 'critical'
  message?: string
  triggeredAt?: number | string
  acknowledgedAt?: number | string | null
  acknowledgedBy?: string | null
}

export interface ResourceCostRollup {
  identifier: string
  scope: 'user' | 'workspace'
  sampleCount: number
  estimated: boolean
  totals: ResourceCostTotals
}

export interface ResourceBudgetAlert {
  alertId: string
  scope: 'quota' | 'user' | 'workspace' | 'project'
  identifier: string
  metric: ResourceCostMetric
  threshold: number
  actual: number
  severity: 'warning' | 'critical'
  message: string
  triggeredAt: string
  acknowledgedAt: string | null
  acknowledgedBy: string | null
  quotaId: string | null
  userId: string | null
  workspaceId: string | null
  projectId: string | null
}

export interface ResourceCostDashboardSnapshot {
  windowStart: string | null
  windowEnd: string | null
  totals: ResourceCostTotals
  userRollups: ResourceCostRollup[]
  workspaceRollups: ResourceCostRollup[]
  alerts: ResourceBudgetAlert[]
}

const API_ROOT = '/api/resource-quotas'

const ZERO_TOTALS: ResourceCostTotals = {
  cpuHours: 0,
  memoryGbHours: 0,
  storageGbDays: 0,
  gpuHours: 0,
}

const METRIC_LABELS: Record<ResourceCostMetric, string> = {
  cpuHours: 'CPU-h',
  memoryGbHours: 'RAM-GB-h',
  storageGbDays: 'Storage-GB-d',
  gpuHours: 'GPU-h',
}

export function formatCostMetricLabel(metric: ResourceCostMetric): string {
  return METRIC_LABELS[metric]
}

export async function loadResourceCostDashboard(fetchImpl: typeof fetch = fetch): Promise<{
  snapshot: ResourceCostDashboardSnapshot
  errors: string[]
}> {
  const [monthlyResult, alertsResult] = await Promise.allSettled([
    fetchMonthlyCostReport(fetchImpl),
    fetchBudgetAlerts(fetchImpl),
  ])

  const errors: string[] = []

  if (monthlyResult.status === 'rejected') {
    errors.push(monthlyResult.reason instanceof Error ? monthlyResult.reason.message : 'Failed to load monthly cost report')
  }

  if (alertsResult.status === 'rejected') {
    errors.push(alertsResult.reason instanceof Error ? alertsResult.reason.message : 'Failed to load budget alerts')
  }

  return {
    snapshot: summarizeMonthlyCostReport(
      monthlyResult.status === 'fulfilled' ? monthlyResult.value : null,
      alertsResult.status === 'fulfilled' ? alertsResult.value : [],
    ),
    errors,
  }
}

export async function fetchMonthlyCostReport(fetchImpl: typeof fetch = fetch): Promise<MonthlyCostReportLike | null> {
  return fetchApiData<MonthlyCostReportLike>(fetchImpl, `${API_ROOT}/cost/monthly`)
}

export async function fetchBudgetAlerts(fetchImpl: typeof fetch = fetch): Promise<BudgetAlertLike[]> {
  return fetchApiData<BudgetAlertLike[]>(fetchImpl, `${API_ROOT}/cost/alerts`)
}

export function summarizeMonthlyCostReport(
  report: MonthlyCostReportLike | null,
  alerts: BudgetAlertLike[] = [],
): ResourceCostDashboardSnapshot {
  const quotas = Array.isArray(report?.quotas) ? report.quotas : []

  return {
    windowStart: toIsoTimestamp(report?.windowStart ?? null),
    windowEnd: toIsoTimestamp(report?.windowEnd ?? null),
    totals: normalizeTotals(report?.totals),
    userRollups: normalizeRollups(report?.byUser, quotas, 'user'),
    workspaceRollups: normalizeRollups(report?.byWorkspace ?? report?.byProject, quotas, 'workspace'),
    alerts: normalizeBudgetAlerts(alerts),
  }
}

export function normalizeBudgetAlerts(alerts: BudgetAlertLike[]): ResourceBudgetAlert[] {
  return [...alerts]
    .map((alert) => ({
      alertId: alert.alertId ?? alert.identifier ?? 'alert-unknown',
      scope: alert.scope ?? 'quota',
      identifier: alert.identifier ?? alert.scopeId ?? alert.userId ?? alert.workspaceId ?? alert.projectId ?? alert.quotaId ?? 'unknown',
      metric: alert.metric ?? 'cpuHours',
      threshold: Number(alert.threshold ?? 0),
      actual: Number(alert.actual ?? 0),
      severity: alert.severity ?? 'warning',
      message: alert.message ?? 'Budget threshold exceeded',
      triggeredAt: toIsoTimestamp(alert.triggeredAt) ?? new Date().toISOString(),
      acknowledgedAt: toIsoTimestamp(alert.acknowledgedAt),
      acknowledgedBy: alert.acknowledgedBy ?? null,
      quotaId: alert.quotaId ?? null,
      userId: alert.userId ?? null,
      workspaceId: alert.workspaceId ?? null,
      projectId: alert.projectId ?? null,
    }))
    .sort((left, right) => {
      if (left.severity !== right.severity) {
        return left.severity === 'critical' ? -1 : 1
      }

      return right.triggeredAt.localeCompare(left.triggeredAt)
    })
}

function fetchApiData<T>(fetchImpl: typeof fetch, url: string): Promise<T> {
  return fetchImpl(url).then(async (response) => {
    if (!response.ok) {
      throw new Error(`Request failed with status ${response.status} for ${url}`)
    }

    const payload = (await response.json()) as { data?: unknown; error?: unknown; details?: unknown }
    if (!payload || typeof payload !== 'object' || !('data' in payload)) {
      throw new Error(`Unexpected response payload from ${url}`)
    }

    return payload.data as T
  })
}

function normalizeRollups(
  directRollups: MonthlyCostQuotaLike[] | undefined,
  quotas: MonthlyCostQuotaLike[],
  scope: 'user' | 'workspace',
): ResourceCostRollup[] {
  if (Array.isArray(directRollups) && directRollups.length > 0) {
    return directRollups.map((rollup) => normalizeDirectRollup(rollup, scope)).sort(compareRollups)
  }

  const grouped = new Map<string, MonthlyCostQuotaLike[]>()

  for (const quota of quotas) {
    const identifier = getRollupIdentifier(quota, scope)
    const bucket = grouped.get(identifier) ?? []
    bucket.push(quota)
    grouped.set(identifier, bucket)
  }

  return [...grouped.entries()]
    .map<ResourceCostRollup>(([identifier, items]) => ({
      identifier,
      scope,
      sampleCount: items.reduce((count, item) => count + Number(item.sampleCount ?? 0), 0),
      estimated: items.some((item) => Boolean(item.estimated)),
      totals: items.reduce<ResourceCostTotals>(
        (runningTotals, item) => mergeTotals(runningTotals, extractTotals(item)),
        { ...ZERO_TOTALS },
      ),
    }))
    .sort(compareRollups)
}

function normalizeDirectRollup(rollup: MonthlyCostQuotaLike, scope: 'user' | 'workspace'): ResourceCostRollup {
  return {
    identifier: rollup.identifier ?? getRollupIdentifier(rollup, scope),
    scope,
    sampleCount: Number(rollup.sampleCount ?? 0),
    estimated: Boolean(rollup.estimated),
    totals: extractTotals(rollup),
  }
}

function extractTotals(source: MonthlyCostQuotaLike | Partial<ResourceCostTotals> | null | undefined): ResourceCostTotals {
  if (!source) {
    return { ...ZERO_TOTALS }
  }

  const nestedTotals = 'totals' in source ? (source.totals as Partial<ResourceCostTotals> | undefined) : undefined
  const resolvedSource = nestedTotals ?? source

  return normalizeTotals(resolvedSource)
}

function normalizeTotals(totals: Partial<ResourceCostTotals> | null | undefined): ResourceCostTotals {
  return {
    cpuHours: Number(totals?.cpuHours ?? 0),
    memoryGbHours: Number(totals?.memoryGbHours ?? 0),
    storageGbDays: Number(totals?.storageGbDays ?? 0),
    gpuHours: Number(totals?.gpuHours ?? 0),
  }
}

function mergeTotals(left: ResourceCostTotals, right: ResourceCostTotals): ResourceCostTotals {
  return {
    cpuHours: left.cpuHours + right.cpuHours,
    memoryGbHours: left.memoryGbHours + right.memoryGbHours,
    storageGbDays: left.storageGbDays + right.storageGbDays,
    gpuHours: left.gpuHours + right.gpuHours,
  }
}

function compareRollups(left: ResourceCostRollup, right: ResourceCostRollup): number {
  const leftScore = rollupScore(left)
  const rightScore = rollupScore(right)

  if (leftScore !== rightScore) {
    return rightScore - leftScore
  }

  return left.identifier.localeCompare(right.identifier)
}

function rollupScore(rollup: ResourceCostRollup): number {
  return rollup.totals.cpuHours + rollup.totals.memoryGbHours + rollup.totals.storageGbDays + rollup.totals.gpuHours
}

function getRollupIdentifier(item: MonthlyCostQuotaLike, scope: 'user' | 'workspace'): string {
  if (scope === 'user') {
    return item.userId ?? item.identifier ?? item.projectId ?? item.workspaceId ?? item.quotaId ?? 'unassigned-user'
  }

  return item.workspaceId ?? item.projectId ?? item.identifier ?? item.userId ?? item.quotaId ?? 'unassigned-workspace'
}

function toIsoTimestamp(value: number | string | null | undefined): string | null {
  if (value === null || value === undefined) {
    return null
  }

  if (typeof value === 'string') {
    return value
  }

  return new Date(value).toISOString()
}