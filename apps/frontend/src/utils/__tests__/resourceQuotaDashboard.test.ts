import { describe, expect, it, vi } from 'vitest'

import { formatCostMetricLabel, loadResourceCostDashboard } from '../resourceQuotaDashboard'

describe('resourceQuotaDashboard', () => {
  it('loads and normalizes the monthly cost dashboard payloads', async () => {
    const fetchMock = vi.fn(async (url: string) => {
      if (url.endsWith('/cost/monthly')) {
        return {
          ok: true,
          json: async () => ({
            data: {
              windowStart: 1_735_689_600_000,
              windowEnd: 1_735_776_000_000,
              totals: {
                cpuHours: 10,
                memoryGbHours: 20,
                storageGbDays: 30,
                gpuHours: 4,
              },
              quotas: [
                {
                  quotaId: 'quota-a',
                  userId: 'alice',
                  workspaceId: 'workspace-alpha',
                  cpuHours: 2,
                  memoryGbHours: 4,
                  storageGbDays: 6,
                  gpuHours: 1,
                  sampleCount: 2,
                  estimated: false,
                },
                {
                  quotaId: 'quota-b',
                  userId: 'alice',
                  workspaceId: 'workspace-beta',
                  cpuHours: 1,
                  memoryGbHours: 2,
                  storageGbDays: 3,
                  gpuHours: 0,
                  sampleCount: 1,
                  estimated: true,
                },
              ],
            },
          }),
        } as Response
      }

      if (url.endsWith('/cost/alerts')) {
        return {
          ok: true,
          json: async () => ({
            data: [
              {
                alertId: 'alert-a',
                scope: 'user',
                scopeId: 'alice',
                metric: 'cpuHours',
                threshold: 8,
                actual: 10,
                severity: 'critical',
                message: 'User budget exceeded',
                triggeredAt: 1_735_776_000_000,
                acknowledgedAt: 1_735_862_400_000,
                acknowledgedBy: 'ops@kushnir.cloud',
              },
            ],
          }),
        } as Response
      }

      throw new Error(`Unexpected URL: ${url}`)
    })

    const result = await loadResourceCostDashboard(fetchMock as unknown as typeof fetch)

    expect(fetchMock).toHaveBeenCalledTimes(2)
    expect(fetchMock).toHaveBeenNthCalledWith(1, '/api/resource-quotas/cost/monthly')
    expect(fetchMock).toHaveBeenNthCalledWith(2, '/api/resource-quotas/cost/alerts')
    expect(result.errors).toEqual([])
    expect(result.snapshot.userRollups[0].identifier).toBe('alice')
    expect(result.snapshot.userRollups[0].totals.cpuHours).toBe(3)
    expect(result.snapshot.workspaceRollups[0].identifier).toBe('workspace-alpha')
    expect(result.snapshot.alerts[0].acknowledgedBy).toBe('ops@kushnir.cloud')
    expect(result.snapshot.alerts[0].acknowledgedAt).toBe('2025-01-03T00:00:00.000Z')
    expect(formatCostMetricLabel('storageGbDays')).toBe('Storage-GB-d')
  })
})