/**
 * Types for multi-repo workspace context management.
 */

export type WorkspaceAccessMode = "read" | "write" | "admin";

export interface WorkspaceRepositoryDescriptor {
  repoId: string;
  branch?: string;
  accessMode: WorkspaceAccessMode;
  lastActiveAt?: number;
  dirty?: boolean;
}

export interface WorkspaceSetDefinition {
  id: string;
  name: string;
  owner: string;
  org: string;
  repositories: WorkspaceRepositoryDescriptor[];
  shared: boolean;
  allowedPrincipals?: string[];
  approvalRequired?: boolean;
  approved?: boolean;
  approvedBy?: string;
  approvedAt?: number;
  createdAt: number;
  updatedAt: number;
}

export interface WorkspaceTerminalSnapshot {
  id: string;
  repoId: string;
  command?: string;
  cwd?: string;
  env?: Record<string, string>;
}

export interface WorkspaceSnapshot {
  activeRepoId: string;
  repositories: WorkspaceRepositoryDescriptor[];
  terminals: WorkspaceTerminalSnapshot[];
  openFiles: string[];
  metadata?: Record<string, unknown>;
}

export interface WorkspaceLaunchRequest {
  actor: string;
  workspaceSetId: string;
  targetRepoId?: string;
  correlationId: string;
  confirmCrossRepoReplay?: boolean;
}

export interface WorkspaceLaunchMetadata {
  workspaceSetId: string;
  owner: string;
  activeRepoId: string;
  repositoryCount: number;
  terminalCount: number;
  blockedTerminalReplayCount: number;
  redactedFields: string[];
  requiresConfirmation: boolean;
  generatedAt: number;
}

export interface WorkspaceLaunchPreview {
  allowed: boolean;
  reason?: string;
  workspaceSet?: WorkspaceSetDefinition;
  previewSnapshot?: WorkspaceSnapshot;
  restoreMetadata?: WorkspaceLaunchMetadata;
  blockedTerminalReplayCount: number;
  redactedFields: string[];
  requiresConfirmation: boolean;
}

export interface WorkspaceAuditEvent {
  eventId: string;
  eventType:
    | "workspace_set_registered"
    | "workspace_set_approved"
    | "workspace_launch_allowed"
    | "workspace_launch_denied"
    | "workspace_snapshot_redacted";
  actor: string;
  workspaceSetId: string;
  targetRepoId?: string;
  correlationId: string;
  timestamp: number;
  reason?: string;
  details?: Record<string, unknown>;
}

export interface WorkspaceLaunchResult {
  allowed: boolean;
  reason?: string;
  workspaceSet?: WorkspaceSetDefinition;
  sanitizedSnapshot?: WorkspaceSnapshot;
  restoreMetadata?: WorkspaceLaunchMetadata;
  auditEvent: WorkspaceAuditEvent;
}
