export const WORKSPACE_CONTEXT_HUB_CONTRACT_VERSION = "workspace-context-hub/v1";
function isNonEmptyString(value) {
    return typeof value === "string" && value.trim().length > 0;
}
export function validatePortalWorkspaceLaunchRequest(payload) {
    const errors = [];
    const input = (payload ?? {});
    if (!isNonEmptyString(input.actor)) {
        errors.push("actor is required");
    }
    if (!isNonEmptyString(input.workspaceSetId)) {
        errors.push("workspaceSetId is required");
    }
    if (!isNonEmptyString(input.correlationId)) {
        errors.push("correlationId is required");
    }
    if (input.targetRepoId !== undefined && !isNonEmptyString(input.targetRepoId)) {
        errors.push("targetRepoId must be a non-empty string when provided");
    }
    if (input.confirmCrossRepoReplay !== undefined && typeof input.confirmCrossRepoReplay !== "boolean") {
        errors.push("confirmCrossRepoReplay must be boolean when provided");
    }
    if (errors.length > 0) {
        return { valid: false, errors };
    }
    return {
        valid: true,
        value: {
            actor: input.actor,
            workspaceSetId: input.workspaceSetId,
            correlationId: input.correlationId,
            targetRepoId: input.targetRepoId,
            confirmCrossRepoReplay: input.confirmCrossRepoReplay,
        },
        errors,
    };
}
export function toWorkspaceLaunchRequest(payload) {
    return {
        actor: payload.actor,
        workspaceSetId: payload.workspaceSetId,
        correlationId: payload.correlationId,
        targetRepoId: payload.targetRepoId,
        confirmCrossRepoReplay: payload.confirmCrossRepoReplay,
    };
}
export function toPortalWorkspaceLaunchResponse(result) {
    return {
        contractVersion: WORKSPACE_CONTEXT_HUB_CONTRACT_VERSION,
        allowed: result.allowed,
        reason: result.reason,
        workspaceSetId: result.workspaceSet?.id,
        activeRepoId: result.restoreMetadata?.activeRepoId,
        restoreMetadata: result.restoreMetadata
            ? {
                repositoryCount: result.restoreMetadata.repositoryCount,
                terminalCount: result.restoreMetadata.terminalCount,
                blockedTerminalReplayCount: result.restoreMetadata.blockedTerminalReplayCount,
                redactedFields: result.restoreMetadata.redactedFields,
                requiresConfirmation: result.restoreMetadata.requiresConfirmation,
                sessionFingerprint: result.restoreMetadata.sessionFingerprint,
                generatedAt: result.restoreMetadata.generatedAt,
            }
            : undefined,
        audit: {
            eventId: result.auditEvent.eventId,
            eventType: result.auditEvent.eventType,
            correlationId: result.auditEvent.correlationId,
            timestamp: result.auditEvent.timestamp,
        },
    };
}
export function toPortalWorkspaceSetSummary(workspaceSet) {
    return {
        id: workspaceSet.id,
        name: workspaceSet.name,
        owner: workspaceSet.owner,
        org: workspaceSet.org,
        shared: workspaceSet.shared,
        approvalRequired: workspaceSet.approvalRequired ?? workspaceSet.shared,
        approved: workspaceSet.approved ?? !workspaceSet.shared,
        approvedBy: workspaceSet.approvedBy,
        approvedAt: workspaceSet.approvedAt,
        repositoryCount: workspaceSet.repositories.length,
        updatedAt: workspaceSet.updatedAt,
    };
}
//# sourceMappingURL=contracts.js.map