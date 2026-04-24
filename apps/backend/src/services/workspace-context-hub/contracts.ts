import type {
  WorkspaceLaunchRequest,
  WorkspaceLaunchResult,
  WorkspaceReviewerPermission,
  WorkspaceSetDefinition,
} from "./types.js";

export const WORKSPACE_CONTEXT_HUB_CONTRACT_VERSION = "workspace-context-hub/v1";

export type PortalWorkspaceSetSummary = {
  id: string;
  name: string;
  owner: string;
  org: string;
  shared: boolean;
  approvalRequired: boolean;
  approved: boolean;
  approvedBy?: string;
  approvedAt?: number;
  repositoryCount: number;
  updatedAt: number;
};

export type PortalWorkspaceLaunchRequestPayload = {
  actor: string;
  workspaceSetId: string;
  correlationId: string;
  targetRepoId?: string;
  confirmCrossRepoReplay?: boolean;
};

export type PortalWorkspaceLaunchResponsePayload = {
  contractVersion: string;
  allowed: boolean;
  reason?: string;
  workspaceSetId?: string;
  activeRepoId?: string;
  restoreMetadata?: {
    repositoryCount: number;
    terminalCount: number;
    blockedTerminalReplayCount: number;
    redactedFields: string[];
    requiresConfirmation: boolean;
    sessionFingerprint?: string;
    generatedAt: number;
  };
  audit: {
    eventId: string;
    eventType: string;
    correlationId: string;
    timestamp: number;
  };
};

export type PortalReviewerLinkRequestPayload = {
  actor: string;
  workspaceSetId: string;
  sessionId: string;
  reviewer: string;
  permission: WorkspaceReviewerPermission;
  correlationId: string;
  ttlMs?: number;
  oneTimeUse?: boolean;
};

type ValidationResult<T> = {
  valid: boolean;
  value?: T;
  errors: string[];
};

function isNonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

export function validatePortalWorkspaceLaunchRequest(
  payload: unknown,
): ValidationResult<PortalWorkspaceLaunchRequestPayload> {
  const errors: string[] = [];
  const input = (payload ?? {}) as Record<string, unknown>;

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
      actor: input.actor as string,
      workspaceSetId: input.workspaceSetId as string,
      correlationId: input.correlationId as string,
      targetRepoId: input.targetRepoId as string | undefined,
      confirmCrossRepoReplay: input.confirmCrossRepoReplay as boolean | undefined,
    },
    errors,
  };
}

export function toWorkspaceLaunchRequest(payload: PortalWorkspaceLaunchRequestPayload): WorkspaceLaunchRequest {
  return {
    actor: payload.actor,
    workspaceSetId: payload.workspaceSetId,
    correlationId: payload.correlationId,
    targetRepoId: payload.targetRepoId,
    confirmCrossRepoReplay: payload.confirmCrossRepoReplay,
  };
}

export function toPortalWorkspaceLaunchResponse(
  result: WorkspaceLaunchResult,
): PortalWorkspaceLaunchResponsePayload {
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

export function toPortalWorkspaceSetSummary(workspaceSet: WorkspaceSetDefinition): PortalWorkspaceSetSummary {
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