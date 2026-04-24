import { useState } from 'react'

type ControlId = string

interface PolicyApprovalRequest {
  id: string
  controlId: ControlId
  requestedValue: boolean
  requestedBy: string
  approver: string
  reason: string
  status: 'pending' | 'approved' | 'rejected'
  requestedAt: string
  decidedAt?: string
}

type ControlPlaneSnapshot = any

export function useApprovalWorkflow(initialSnapshot: ControlPlaneSnapshot) {
  const [snapshot, setSnapshot] = useState<ControlPlaneSnapshot>(initialSnapshot)

  const updateApprover = (requestId: string, approver: string) => {
    setSnapshot((current: ControlPlaneSnapshot) => ({
      ...current,
      approvals: current.approvals.map((request: PolicyApprovalRequest) => {
        if (request.id !== requestId) {
          return request
        }

        return {
          ...request,
          approver,
        }
      }),
    }))
  }

  const approveRequest = (requestId: string, actor: string) => {
    const request = snapshot.approvals.find((item: PolicyApprovalRequest) => item.id === requestId)
    const control = request ? snapshot.controls.find((item: any) => item.id === request.controlId) : undefined

    if (!request || !control) {
      return false
    }

    setSnapshot((current: ControlPlaneSnapshot) => ({
      ...current,
      controls: current.controls.map((item: any) => {
        if (item.id !== request.controlId) {
          return item
        }

        return {
          ...item,
          value: request.requestedValue,
          lastChangedAt: new Date().toISOString(),
          lastChangedBy: request.approver,
        }
      }),
      approvals: current.approvals.map((item: PolicyApprovalRequest) => {
        if (item.id !== requestId) {
          return item
        }

        return {
          ...item,
          status: 'approved',
          decidedAt: new Date().toISOString(),
        }
      }),
      auditTrail: [
        {
          id: `audit-${Date.now()}`,
          action: 'approve',
          actor,
          controlId: request.controlId,
          diff: `${control.label}: approved by ${request.approver}; ${control.value ? 'enabled' : 'disabled'} -> ${request.requestedValue ? 'enabled' : 'disabled'}`,
          status: 'success',
          timestamp: new Date().toISOString(),
        },
        ...current.auditTrail,
      ],
    }))

    return true
  }

  const rejectRequest = (requestId: string, actor: string) => {
    const request = snapshot.approvals.find((item: PolicyApprovalRequest) => item.id === requestId)
    if (!request) {
      return false
    }

    const control = snapshot.controls.find((item: any) => item.id === request.controlId)

    setSnapshot((current: ControlPlaneSnapshot) => ({
      ...current,
      approvals: current.approvals.map((item: PolicyApprovalRequest) => {
        if (item.id !== requestId) {
          return item
        }

        return {
          ...item,
          status: 'rejected',
          decidedAt: new Date().toISOString(),
        }
      }),
      auditTrail: [
        {
          id: `audit-${Date.now()}`,
          action: 'reject',
          actor,
          controlId: request.controlId,
          diff: `${control?.label ?? request.controlId}: request rejected by ${actor}`,
          status: 'critical',
          timestamp: new Date().toISOString(),
        },
        ...current.auditTrail,
      ],
    }))

    return true
  }

  return { snapshot, setSnapshot, updateApprover, approveRequest, rejectRequest }
}
