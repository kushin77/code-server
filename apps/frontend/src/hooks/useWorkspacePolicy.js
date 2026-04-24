import { useState } from 'react';
export function useWorkspacePolicy(initialSnapshot) {
    const [snapshot, setSnapshot] = useState(initialSnapshot);
    const updateControl = (controlId, nextValue, actor) => {
        setSnapshot((current) => {
            const control = current.controls.find((item) => item.id === controlId);
            if (!control) {
                return current;
            }
            const nextControls = current.controls.map((item) => {
                if (item.id !== controlId) {
                    return item;
                }
                return {
                    ...item,
                    value: nextValue,
                    lastChangedAt: new Date().toISOString(),
                    lastChangedBy: actor,
                };
            });
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
            };
        });
    };
    const requestApproval = (controlId, nextValue, actor, reason, onSuccess) => {
        const control = snapshot.controls.find((item) => item.id === controlId);
        if (!control) {
            return false;
        }
        if (!reason?.trim()) {
            return false;
        }
        const requestId = `approval-${Date.now()}-${controlId}`;
        setSnapshot((current) => ({
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
        }));
        onSuccess?.();
        return true;
    };
    return { snapshot, setSnapshot, updateControl, requestApproval };
}
//# sourceMappingURL=useWorkspacePolicy.js.map