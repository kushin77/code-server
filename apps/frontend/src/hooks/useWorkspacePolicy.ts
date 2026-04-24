import { useState } from 'react'

interface PolicyControl {
  id: string
  label: string
  value: boolean
  critical: boolean
  lastChangedAt: string | null
  lastChangedBy: string | null
}

type ControlId = string

type ControlPlaneSnapshot = any

export function useWorkspacePolicy(initialSnapshot: ControlPlaneSnapshot) {
  const [snapshot, setSnapshot] = useState<ControlPlaneSnapshot>(initialSnapshot)

  const updateControl = (controlId: ControlId, nextValue: boolean, actor: string) => {
    setSnapshot((current: ControlPlaneSnapshot) => {
      const control = current.controls.find((item: PolicyControl) => item.id === controlId)
      if (!control) {
        return current
      }

      const nextControls = current.controls.map((item: PolicyControl) => {
        if (item.id !== controlId) {
          return item
        }

        return {
          ...item,
          value: nextValue,
          lastChangedAt: new Date().toISOString(),
          lastChangedBy: actor,
        }
      })

      return {
        ...current,
        controls: nextControls,
        auditTrail: [
          {
            id: `audit-${Date.now()}`,
            action: 'update',
            actor,
            controlId,
            diff: `${control.label}: ${control.value ? 'enabled' : 'disabled'} -> ${nextValue ? 'enabled' : 'disabled'}`,
            status: nextValue ? 'success' : 'warn',
            timestamp: new Date().toISOString(),
          },
          ...current.auditTrail,
        ],
      }
    })
  }

  const requestApproval = (
    controlId: ControlId,
    nextValue: boolean,
    actor: string,
    reason: string,
    onSuccess?: () => void
  ) => {
    const control = snapshot.controls.find((item: PolicyControl) => item.id === controlId)
    if (!control) {
      return false
    }

    if (!reason?.trim()) {
      return false
    }

    const requestId = `approval-${Date.now()}-${controlId}`

    setSnapshot((current: ControlPlaneSnapshot) => ({
      ...current,
      approvals: [
        {
          id: requestId,
          controlId,
          requestedValue: nextValue,
          requestedBy: actor,
          approver: 'security-lead@kushnir.cloud',
          reason,
          status: 'pending',
          requestedAt: new Date().toISOString(),
        },
        ...current.approvals,
      ],
      auditTrail: [
        {
          id: `audit-${Date.now()}`,
          action: 'request-approval',
          actor,
          controlId,
          diff: `${control.label}: requested ${nextValue ? 'enable' : 'disable'} with reason "${reason}"`,
          status: 'warn',
          timestamp: new Date().toISOString(),
        },
        ...current.auditTrail,
      ],
    }))

    onSuccess?.()
    return true
  }

  return { snapshot, setSnapshot, updateControl, requestApproval }
}
