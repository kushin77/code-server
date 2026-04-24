import { useEffect, useState } from 'react'

interface ControlPlaneSnapshot {
  controls: any[]
  approvals: any[]
  auditTrail: any[]
  lastSyncedAt: string | null
}

const STORAGE_KEY = 'portal-control-plane:v1'

export function useWorkspaceStorage(initialSnapshot: ControlPlaneSnapshot) {
  const [snapshot, setSnapshot] = useState<ControlPlaneSnapshot>(initialSnapshot)

  // Persist to localStorage whenever snapshot changes
  useEffect(() => {
    if (typeof window === 'undefined') {
      return
    }
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(snapshot))
  }, [snapshot])

  return { snapshot, setSnapshot }
}
