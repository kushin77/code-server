import crypto from "crypto";
import {
  WorkspaceAuditEvent,
  WorkspaceLaunchMetadata,
  WorkspaceLaunchRequest,
  WorkspaceLaunchPreview,
  WorkspaceLaunchResult,
  WorkspaceRepositoryDescriptor,
  WorkspaceSetDefinition,
  WorkspaceSnapshot,
  WorkspaceTerminalSnapshot,
} from "./types";

const SENSITIVE_KEY_PATTERN = /(token|secret|password|passwd|private|key|credential)/i;

/**
 * In-memory workspace context service for multi-repo launch and restore flows.
 *
 * The service enforces ownership and approval rules for shared workspace sets,
 * blocks cross-repo terminal replay unless explicitly confirmed, and redacts
 * sensitive snapshot fields before restore.
 */
export class WorkspaceContextHubService {
  private readonly workspaceSets = new Map<string, WorkspaceSetDefinition>();
  private readonly auditEvents: WorkspaceAuditEvent[] = [];

  registerWorkspaceSet(
    workspaceSet: Omit<WorkspaceSetDefinition, "createdAt" | "updatedAt" | "approved" | "approvedBy" | "approvedAt"> &
      Partial<Pick<WorkspaceSetDefinition, "approved" | "approvedBy" | "approvedAt" | "createdAt" | "updatedAt">>,
  ): WorkspaceSetDefinition {
    const now = Date.now();
    const nextSet: WorkspaceSetDefinition = {
      ...workspaceSet,
      shared: workspaceSet.shared ?? false,
      allowedPrincipals: workspaceSet.allowedPrincipals ?? [],
      approvalRequired: workspaceSet.approvalRequired ?? workspaceSet.shared,
      approved: workspaceSet.approved ?? !workspaceSet.shared,
      approvedBy: workspaceSet.approvedBy,
      approvedAt: workspaceSet.approvedAt,
      createdAt: workspaceSet.createdAt ?? now,
      updatedAt: workspaceSet.updatedAt ?? now,
    };

    this.workspaceSets.set(nextSet.id, nextSet);
    this.recordAuditEvent({
      eventType: "workspace_set_registered",
      actor: nextSet.owner,
      workspaceSetId: nextSet.id,
      correlationId: `workspace-${nextSet.id}`,
      reason: `registered workspace set ${nextSet.name}`,
      details: {
        shared: nextSet.shared,
        repositoryCount: nextSet.repositories.length,
      },
    });

    return nextSet;
  }

  previewWorkspaceLaunch(request: WorkspaceLaunchRequest, snapshot?: WorkspaceSnapshot): WorkspaceLaunchPreview {
    const decision = this.evaluateLaunchDecision(request, snapshot);

    if (!decision.workspaceSet) {
      return {
        allowed: false,
        reason: decision.reason,
        blockedTerminalReplayCount: 0,
        redactedFields: [],
        requiresConfirmation: false,
      };
    }

    if (decision.reason) {
      return {
        allowed: false,
        reason: decision.reason,
        workspaceSet: decision.workspaceSet,
        previewSnapshot: decision.sanitized?.snapshot,
        restoreMetadata: decision.restoreMetadata,
        blockedTerminalReplayCount: decision.sanitized?.blockedTerminalReplayCount ?? 0,
        redactedFields: decision.sanitized?.redactedFields ?? [],
        requiresConfirmation: decision.sanitized?.requiresConfirmation ?? false,
      };
    }

    if (decision.sanitized?.requiresConfirmation && !request.confirmCrossRepoReplay) {
      return {
        allowed: false,
        reason: "Cross-repo terminal replay requires explicit confirmation",
        workspaceSet: decision.workspaceSet,
        previewSnapshot: decision.sanitized.snapshot,
        restoreMetadata: decision.restoreMetadata,
        blockedTerminalReplayCount: decision.sanitized.blockedTerminalReplayCount,
        redactedFields: decision.sanitized.redactedFields,
        requiresConfirmation: true,
      };
    }

    return {
      allowed: true,
      workspaceSet: decision.workspaceSet,
      previewSnapshot: decision.sanitized?.snapshot ?? snapshot,
      restoreMetadata: decision.restoreMetadata,
      blockedTerminalReplayCount: decision.sanitized?.blockedTerminalReplayCount ?? 0,
      redactedFields: decision.sanitized?.redactedFields ?? [],
      requiresConfirmation: decision.sanitized?.requiresConfirmation ?? false,
    };
  }

  approveWorkspaceSet(workspaceSetId: string, approvedBy: string, correlationId: string): WorkspaceSetDefinition {
    const workspaceSet = this.requireWorkspaceSet(workspaceSetId);
    const approvedAt = Date.now();
    const nextSet: WorkspaceSetDefinition = {
      ...workspaceSet,
      approved: true,
      approvedBy,
      approvedAt,
      updatedAt: approvedAt,
    };

    this.workspaceSets.set(workspaceSetId, nextSet);
    this.recordAuditEvent({
      eventType: "workspace_set_approved",
      actor: approvedBy,
      workspaceSetId,
      correlationId,
      reason: `workspace set approved by ${approvedBy}`,
      details: {
        approvedAt,
      },
    });

    return nextSet;
  }

  launchWorkspace(request: WorkspaceLaunchRequest, snapshot?: WorkspaceSnapshot): WorkspaceLaunchResult {
    const decision = this.evaluateLaunchDecision(request, snapshot);
    if (!decision.workspaceSet) {
      return this.denyLaunch(request, decision.reason ?? "Workspace set not found");
    }

    if (decision.reason) {
      return this.denyLaunch(request, decision.reason, decision.workspaceSet, decision.details);
    }

    if (decision.sanitized?.requiresConfirmation && !request.confirmCrossRepoReplay) {
      return this.denyLaunch(
        request,
        "Cross-repo terminal replay requires explicit confirmation",
        decision.workspaceSet,
        {
          blockedTerminalReplayCount: decision.sanitized.blockedTerminalReplayCount,
        },
      );
    }

    const { workspaceSet, sanitized, restoreMetadata, activeRepoId } = decision;

    if ((sanitized?.redactedFields.length ?? 0) > 0 || (sanitized?.blockedTerminalReplayCount ?? 0) > 0) {
      this.recordAuditEvent({
        eventType: "workspace_snapshot_redacted",
        actor: request.actor,
        workspaceSetId: workspaceSet.id,
        targetRepoId: request.targetRepoId,
        correlationId: request.correlationId,
        reason: "workspace snapshot redacted before restore",
        details: {
          blockedTerminalReplayCount: sanitized?.blockedTerminalReplayCount ?? 0,
          redactedFields: sanitized?.redactedFields ?? [],
          requiresConfirmation: sanitized?.requiresConfirmation ?? false,
        },
      });
    }

    const auditEvent = this.recordAuditEvent({
      eventType: "workspace_launch_allowed",
      actor: request.actor,
      workspaceSetId: workspaceSet.id,
      targetRepoId: request.targetRepoId,
      correlationId: request.correlationId,
      reason: "workspace launch authorized",
      details: {
        activeRepoId,
        repositoryCount: workspaceSet.repositories.length,
        blockedTerminalReplayCount: restoreMetadata.blockedTerminalReplayCount,
      },
    });

    return {
      allowed: true,
      workspaceSet,
      sanitizedSnapshot: sanitized?.snapshot ?? snapshot,
      restoreMetadata,
      auditEvent,
    };
  }

  getWorkspaceSet(workspaceSetId: string): WorkspaceSetDefinition | undefined {
    return this.workspaceSets.get(workspaceSetId);
  }

  getAuditEvents(workspaceSetId?: string): WorkspaceAuditEvent[] {
    return workspaceSetId
      ? this.auditEvents.filter((event) => event.workspaceSetId === workspaceSetId)
      : [...this.auditEvents];
  }

  private evaluateLaunchDecision(request: WorkspaceLaunchRequest, snapshot?: WorkspaceSnapshot): {
    workspaceSet?: WorkspaceSetDefinition;
    reason?: string;
    details?: Record<string, unknown>;
    sanitized?: {
      snapshot: WorkspaceSnapshot;
      redactedFields: string[];
      blockedTerminalReplayCount: number;
      requiresConfirmation: boolean;
    };
    restoreMetadata: WorkspaceLaunchMetadata;
    activeRepoId: string;
  } {
    const workspaceSet = this.workspaceSets.get(request.workspaceSetId);
    if (!workspaceSet) {
      return {
        reason: "Workspace set not found",
        restoreMetadata: {
          workspaceSetId: request.workspaceSetId,
          owner: "",
          activeRepoId: request.targetRepoId || snapshot?.activeRepoId || "",
          repositoryCount: 0,
          terminalCount: snapshot?.terminals.length ?? 0,
          blockedTerminalReplayCount: 0,
          redactedFields: [],
          requiresConfirmation: false,
          generatedAt: Date.now(),
        },
        activeRepoId: request.targetRepoId || snapshot?.activeRepoId || "",
      };
    }

    const authorizationError = this.validateLaunchAuthorization(workspaceSet, request);
    const sanitized = snapshot ? this.sanitizeSnapshot(workspaceSet, snapshot, request) : undefined;
    const activeRepoId = request.targetRepoId || snapshot?.activeRepoId || workspaceSet.repositories[0]?.repoId || "";
    const restoreMetadata: WorkspaceLaunchMetadata = {
      workspaceSetId: workspaceSet.id,
      owner: workspaceSet.owner,
      activeRepoId,
      repositoryCount: workspaceSet.repositories.length,
      terminalCount: sanitized?.snapshot.terminals.length ?? snapshot?.terminals.length ?? 0,
      blockedTerminalReplayCount: sanitized?.blockedTerminalReplayCount ?? 0,
      redactedFields: sanitized?.redactedFields ?? [],
      requiresConfirmation: sanitized?.requiresConfirmation ?? false,
      generatedAt: Date.now(),
    };

    return {
      workspaceSet,
      reason: authorizationError,
      sanitized,
      restoreMetadata,
      activeRepoId,
    };
  }

  private validateLaunchAuthorization(workspaceSet: WorkspaceSetDefinition, request: WorkspaceLaunchRequest): string | undefined {
    const targetRepoId = request.targetRepoId;
    if (targetRepoId && !workspaceSet.repositories.some((repo) => repo.repoId === targetRepoId)) {
      return `Repository ${targetRepoId} is not part of workspace set ${workspaceSet.id}`;
    }

    if (workspaceSet.shared) {
      if (workspaceSet.approvalRequired && !workspaceSet.approved && request.actor !== workspaceSet.owner) {
        return "Workspace set requires approval before launch";
      }

      const allowedPrincipals = new Set(workspaceSet.allowedPrincipals ?? []);
      if (request.actor !== workspaceSet.owner && allowedPrincipals.size > 0 && !allowedPrincipals.has(request.actor)) {
        return `Actor ${request.actor} is not allowed to launch shared workspace set ${workspaceSet.id}`;
      }
    }

    return undefined;
  }

  private sanitizeSnapshot(
    workspaceSet: WorkspaceSetDefinition,
    snapshot: WorkspaceSnapshot,
    request: WorkspaceLaunchRequest,
  ): { snapshot: WorkspaceSnapshot; redactedFields: string[]; blockedTerminalReplayCount: number; requiresConfirmation: boolean } {
    const targetRepoId = request.targetRepoId || snapshot.activeRepoId;
    const redactedFields: string[] = [];
    let blockedTerminalReplayCount = 0;
    let requiresConfirmation = false;

    const terminals: WorkspaceTerminalSnapshot[] = [];
    for (const terminal of snapshot.terminals) {
      const sameRepo = terminal.repoId === targetRepoId;
      if (!sameRepo) {
        blockedTerminalReplayCount += 1;
        requiresConfirmation = true;
        if (!request.confirmCrossRepoReplay) {
          continue;
        }
      }

      const redactedEnv = this.redactSecretValues(terminal.env, `terminals.${terminal.id}.env`, redactedFields);
      const redactedCommand = this.redactCommand(terminal.command, terminal.id, redactedFields);
      terminals.push({
        ...terminal,
        command: redactedCommand,
        env: redactedEnv,
      });
    }

    const metadata = this.redactMetadata(snapshot.metadata, redactedFields);

    return {
      snapshot: {
        ...snapshot,
        terminals,
        metadata,
      },
      redactedFields,
      blockedTerminalReplayCount,
      requiresConfirmation,
    };
  }

  private redactMetadata(metadata: Record<string, unknown> | undefined, redactedFields: string[]): Record<string, unknown> | undefined {
    if (!metadata) {
      return metadata;
    }

    const nextMetadata: Record<string, unknown> = {};
    for (const [key, value] of Object.entries(metadata)) {
      if (SENSITIVE_KEY_PATTERN.test(key)) {
        redactedFields.push(`metadata.${key}`);
        nextMetadata[key] = "[redacted]";
        continue;
      }

      nextMetadata[key] = value;
    }

    return nextMetadata;
  }

  private redactSecretValues(
    env: Record<string, string> | undefined,
    prefix: string,
    redactedFields: string[],
  ): Record<string, string> | undefined {
    if (!env) {
      return env;
    }

    const nextEnv: Record<string, string> = {};
    for (const [key, value] of Object.entries(env)) {
      if (SENSITIVE_KEY_PATTERN.test(key)) {
        redactedFields.push(`${prefix}.${key}`);
        nextEnv[key] = "[redacted]";
        continue;
      }

      nextEnv[key] = value;
    }

    return nextEnv;
  }

  private redactCommand(command: string | undefined, terminalId: string, redactedFields: string[]): string | undefined {
    if (!command) {
      return command;
    }

    const looksSensitive = /(--token|--password|secret=|password=|token=|ssh -i)/i.test(command);
    if (!looksSensitive) {
      return command;
    }

    redactedFields.push(`terminals.${terminalId}.command`);
    return "[redacted]";
  }

  private denyLaunch(
    request: WorkspaceLaunchRequest,
    reason: string,
    workspaceSet?: WorkspaceSetDefinition,
    details?: Record<string, unknown>,
  ): WorkspaceLaunchResult {
    const auditEvent = this.recordAuditEvent({
      eventType: "workspace_launch_denied",
      actor: request.actor,
      workspaceSetId: request.workspaceSetId,
      targetRepoId: request.targetRepoId,
      correlationId: request.correlationId,
      reason,
      details,
    });

    return {
      allowed: false,
      reason,
      workspaceSet,
      auditEvent,
    };
  }

  private requireWorkspaceSet(workspaceSetId: string): WorkspaceSetDefinition {
    const workspaceSet = this.workspaceSets.get(workspaceSetId);
    if (!workspaceSet) {
      throw new Error(`Workspace set not found: ${workspaceSetId}`);
    }

    return workspaceSet;
  }

  private recordAuditEvent(event: Omit<WorkspaceAuditEvent, "eventId" | "timestamp">): WorkspaceAuditEvent {
    const auditEvent: WorkspaceAuditEvent = {
      ...event,
      eventId: crypto.randomUUID(),
      timestamp: Date.now(),
    };

    this.auditEvents.push(auditEvent);
    return auditEvent;
  }
}

export function createWorkspaceContextHubService(): WorkspaceContextHubService {
  return new WorkspaceContextHubService();
}

export type { WorkspaceAccessMode, WorkspaceAuditEvent, WorkspaceLaunchMetadata, WorkspaceLaunchRequest, WorkspaceLaunchResult, WorkspaceRepositoryDescriptor, WorkspaceSetDefinition, WorkspaceSnapshot, WorkspaceTerminalSnapshot } from "./types";
