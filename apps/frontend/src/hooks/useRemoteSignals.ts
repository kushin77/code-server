import { useState } from 'react'

interface RemoteSignals {
  health: 'unknown' | 'healthy' | 'degraded' | 'error'
  healthCheckedAt: string | null
  auditCount: number
  auditSummary: string | null
  error: string | null
}

export function useRemoteSignals() {
  const [remoteSignals, setRemoteSignals] = useState<RemoteSignals>({
    health: 'unknown',
    healthCheckedAt: null,
    auditCount: 0,
    auditSummary: null,
    error: null,
  })
  const [isRefreshing, setIsRefreshing] = useState(false)
  const [panelError, setPanelError] = useState<string | null>(null)

  const refreshSignals = async (healthCheck: () => Promise<any>, getAuditLogs: () => Promise<any>) => {
    setIsRefreshing(true)
    setPanelError(null)

    try {
      const [healthResult, auditResult] = await Promise.allSettled([healthCheck(), getAuditLogs()])

      const nextRemoteSignals: RemoteSignals = {
        health: 'unknown',
        healthCheckedAt: new Date().toISOString(),
        auditCount: 0,
        auditSummary: null,
        error: null,
      }

      if (healthResult.status === 'fulfilled') {
        nextRemoteSignals.health = healthResult.value.status === 'ok' ? 'healthy' : 'degraded'
      } else {
        nextRemoteSignals.health = 'error'
        nextRemoteSignals.error =
          healthResult.reason instanceof Error ? healthResult.reason.message : 'Health check failed'
      }

      if (auditResult.status === 'fulfilled') {
        nextRemoteSignals.auditCount = auditResult.value.logs.length
        const latest = auditResult.value.logs[0]
        nextRemoteSignals.auditSummary = latest ? `${latest.eventType}` : 'No recent audit events'
      } else if (!nextRemoteSignals.error) {
        nextRemoteSignals.error =
          auditResult.reason instanceof Error ? auditResult.reason.message : 'Audit fetch failed'
      }

      setRemoteSignals(nextRemoteSignals)
    } catch (error) {
      setRemoteSignals({
        health: 'error',
        healthCheckedAt: new Date().toISOString(),
        auditCount: 0,
        auditSummary: null,
        error: error instanceof Error ? error.message : 'Unable to refresh control-plane signals',
      })
      setPanelError(error instanceof Error ? error.message : 'Unable to refresh control-plane signals')
    } finally {
      setIsRefreshing(false)
    }
  }

  return { remoteSignals, setRemoteSignals, isRefreshing, panelError, setPanelError, refreshSignals }
}
