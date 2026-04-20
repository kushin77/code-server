/**
 * Types for multi-repo workspace context management.
 */

export type WorkspaceAccessMode = "read" | "write" | "admin";

export type WorkspaceReviewerPermission = "view-only" | "approve-only";

export type WorkspaceProvenanceVerificationResult = "verified" | "failed";

export interface WorkspaceLaunchProvenance {
  imageDigest: string;
  attestationRef: string;
  signerIdentity: string;
  verificationTimestamp: number;
  verificationResult: WorkspaceProvenanceVerificationResult;
  policyVersion: string;
}

export interface WorkspaceReviewerAccessGrant {
  grantId: string;
  workspaceSetId: string;
  sessionId: string;
  reviewer: string;
  permission: WorkspaceReviewerPermission;
  issuedBy: string;
  issuedAt: number;
  expiresAt: number;
  oneTimeUse: boolean;
  tokenHash: string;
  revokedAt?: number;
  consumedAt?: number;
  revokedReason?: string;
}

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
  provenance?: WorkspaceLaunchProvenance;
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
  sessionFingerprint?: string;
  provenance?: WorkspaceLaunchProvenance;
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
    | "workspace_state_imported"
    | "workspace_launch_allowed"
    | "workspace_launch_denied"
    | "workspace_snapshot_redacted"
    | "workspace_reviewer_link_issued"
    | "workspace_reviewer_link_consumed"
    | "workspace_reviewer_link_revoked"
    | "workspace_reviewer_link_denied";
  actor: string;
  workspaceSetId: string;
  sessionId?: string;
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

export interface WorkspaceContextHubStateSnapshot {
  version: "workspace-context-hub-state/v1";
  exportedAt: number;
  workspaceSets: WorkspaceSetDefinition[];
}
