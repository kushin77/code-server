import { useState } from 'react';
export function useApprovalWorkflow(initialSnapshot) {
    const [snapshot, setSnapshot] = useState(initialSnapshot);
    const updateApprover = (requestId, approver) => {
        setSnapshot((current) => ({
            ...current,
            approvals: current.approvals.map((request) => {
                if (request.id !== requestId) {
                    return request;
                }
                return {
                    ...request,
                    approver,
                };
            }),
        }));
    };
    const approveRequest = (requestId, actor) => {
        const request = snapshot.approvals.find((item) => item.id === requestId);
        const control = request ? snapshot.controls.find((item) => item.id === request.controlId) : undefined;
        if (!request || !control) {
            return false;
        }
        setSnapshot((current) => ({
            ...current,
            controls: current.controls.map((item) => {
                if (item.id !== request.controlId) {
                    return item;
                }
                return {
                    ...item,
                    value: request.requestedValue,
                    lastChangedAt: new Date().toISOString(),
                    lastChangedBy: request.approver,
                };
            }),
            approvals: current.approvals.map((item) => {
                if (item.id !== requestId) {
                    return item;
                }
                return {
                    ...item,
                    status: 'approved',
                    decidedAt: new Date().toISOString(),
                };
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
        }));
        return true;
    };
    const rejectRequest = (requestId, actor) => {
        const request = snapshot.approvals.find((item) => item.id === requestId);
        if (!request) {
            return false;
        }
        const control = snapshot.controls.find((item) => item.id === request.controlId);
        setSnapshot((current) => ({
            ...current,
            approvals: current.approvals.map((item) => {
                if (item.id !== requestId) {
                    return item;
                }
                return {
                    ...item,
                    status: 'rejected',
                    decidedAt: new Date().toISOString(),
                };
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
        }));
        return true;
    };
    return { snapshot, setSnapshot, updateApprover, approveRequest, rejectRequest };
}
//# sourceMappingURL=useApprovalWorkflow.js.map