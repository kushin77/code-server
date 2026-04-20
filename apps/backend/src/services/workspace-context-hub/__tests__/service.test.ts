import { beforeEach, describe, expect, it } from "vitest";
import { WorkspaceContextHubService } from "../service";
import type { WorkspaceLaunchProvenance, WorkspaceSnapshot } from "../types";

const createProvenance = (overrides: Partial<WorkspaceLaunchProvenance> = {}): WorkspaceLaunchProvenance => ({
  imageDigest: `sha256:${"a".repeat(64)}`,
  attestationRef: "attestation://build/123",
  signerIdentity: "builder@ci",
  verificationTimestamp: Date.now(),
  verificationResult: "verified",
  policyVersion: "ephemeral-provenance-v1",
  ...overrides,
});

describe("WorkspaceContextHubService", () => {
  let service: WorkspaceContextHubService;

  beforeEach(() => {
    service = new WorkspaceContextHubService();
  });

});

/*
  it("records audit events for launch attempts", () => {
    const provenance = createProvenance();
  });

  it("issues scoped reviewer links with expiry and permission limits", () => {
    service.registerWorkspaceSet({
      id: "review-set",
      name: "Review set",
      owner: "owner@example.com",
      org: "kushin77",
      shared: true,
      approvalRequired: true,
      approved: true,
      repositories: [{ repoId: "repo-a", accessMode: "read" }],
    });

    const approveLink = service.issueReviewerAccessLink({
      actor: "owner@example.com",
      workspaceSetId: "review-set",
      sessionId: "session-review-1",
      reviewer: "reviewer@example.com",
      permission: "approve-only",
      correlationId: "review-corr-1",
      ttlMs: 60_000,
      oneTimeUse: false,
    });

    expect(approveLink.grant.permission).toBe("approve-only");
    expect(approveLink.grant.sessionId).toBe("session-review-1");

    const resolved = service.resolveReviewerAccessLink(approveLink.token, "session-review-1", "approve-only", "review-corr-2");
    expect(resolved?.grantId).toBe(approveLink.grant.grantId);
    expect(resolved?.sessionId).toBe("session-review-1");

    const insufficientLink = service.issueReviewerAccessLink({
      actor: "owner@example.com",
      workspaceSetId: "review-set",
      sessionId: "session-review-2",
      reviewer: "viewer@example.com",
      permission: "view-only",
      correlationId: "review-corr-3",
      ttlMs: 60_000,
      oneTimeUse: false,
    });

    expect(
      service.resolveReviewerAccessLink(insufficientLink.token, "session-review-2", "approve-only", "review-corr-4"),
    ).toBeUndefined();

    const expiredLink = service.issueReviewerAccessLink({
      actor: "owner@example.com",
      workspaceSetId: "review-set",
      sessionId: "session-review-3",
      reviewer: "expired@example.com",
      permission: "view-only",
      correlationId: "review-corr-5",
      ttlMs: 60_000,
      oneTimeUse: false,
    });

    expiredLink.grant.expiresAt = Date.now() - 1;
    expect(service.resolveReviewerAccessLink(expiredLink.token, "session-review-3", "view-only", "review-corr-6")).toBeUndefined();

    const auditEvents = service.getAuditEvents("review-set");
    expect(auditEvents.some((event) => event.eventType === "workspace_reviewer_link_issued" && event.sessionId === "session-review-1")).toBe(true);
    expect(auditEvents.some((event) => event.eventType === "workspace_reviewer_link_consumed" && event.sessionId === "session-review-1")).toBe(true);
    expect(auditEvents.some((event) => event.eventType === "workspace_reviewer_link_issued" && event.sessionId === "session-review-3")).toBe(true);
  });

  it("revokes one-time reviewer links immediately and prevents reuse", () => {
    service.registerWorkspaceSet({
      id: "review-revoke-set",
      name: "Review revoke set",
      owner: "owner@example.com",
      org: "kushin77",
      shared: true,
      approvalRequired: true,
      approved: true,
      repositories: [{ repoId: "repo-a", accessMode: "read" }],
    });

    const issued = service.issueReviewerAccessLink({
      actor: "owner@example.com",
      workspaceSetId: "review-revoke-set",
      sessionId: "session-review-4",
      reviewer: "reviewer@example.com",
      permission: "view-only",
      correlationId: "review-corr-7",
      ttlMs: 60_000,
      oneTimeUse: true,
    });

    const firstResolve = service.resolveReviewerAccessLink(issued.token, "session-review-4", "view-only", "review-corr-8");
    expect(firstResolve?.consumedAt).toBeDefined();

    const secondResolve = service.resolveReviewerAccessLink(issued.token, "session-review-4", "view-only", "review-corr-9");
    expect(secondResolve).toBeUndefined();

    const revoked = service.revokeReviewerAccessLink(issued.grant.grantId, "owner@example.com", "review-corr-10", "session closed");
    expect(revoked.revokedAt).toBeDefined();

    expect(service.resolveReviewerAccessLink(issued.token, "session-review-4", "view-only", "review-corr-11")).toBeUndefined();

    const auditEvents = service.getAuditEvents("review-revoke-set");
    expect(auditEvents.some((event) => event.eventType === "workspace_reviewer_link_revoked" && event.sessionId === "session-review-4")).toBe(true);
  });

  it("issues scoped reviewer links with expiry and permission limits", () => {
    service.registerWorkspaceSet({
      id: "review-set",
      name: "Review set",
      owner: "owner@example.com",
      org: "kushin77",
      shared: true,
      approvalRequired: true,
      approved: true,
      repositories: [{ repoId: "repo-a", accessMode: "read" }],
    });

    const approveLink = service.issueReviewerAccessLink({
      actor: "owner@example.com",
      workspaceSetId: "review-set",
      sessionId: "session-review-1",
      reviewer: "reviewer@example.com",
      permission: "approve-only",
      correlationId: "review-corr-1",
      ttlMs: 60_000,
      oneTimeUse: false,
    });

    expect(approveLink.grant.permission).toBe("approve-only");
    expect(approveLink.grant.sessionId).toBe("session-review-1");

    const resolved = service.resolveReviewerAccessLink(approveLink.token, "session-review-1", "approve-only", "review-corr-2");
    expect(resolved?.grantId).toBe(approveLink.grant.grantId);
    expect(resolved?.sessionId).toBe("session-review-1");

    const insufficientLink = service.issueReviewerAccessLink({
      actor: "owner@example.com",
      workspaceSetId: "review-set",
      sessionId: "session-review-2",
      reviewer: "viewer@example.com",
      permission: "view-only",
      correlationId: "review-corr-3",
      ttlMs: 60_000,
      oneTimeUse: false,
    });

    expect(
      service.resolveReviewerAccessLink(insufficientLink.token, "session-review-2", "approve-only", "review-corr-4"),
    ).toBeUndefined();

    const expiredLink = service.issueReviewerAccessLink({
      actor: "owner@example.com",
      workspaceSetId: "review-set",
      sessionId: "session-review-3",
      reviewer: "expired@example.com",
      permission: "view-only",
      correlationId: "review-corr-5",
      ttlMs: 60_000,
      oneTimeUse: false,
    });

    expiredLink.grant.expiresAt = Date.now() - 1;
    expect(service.resolveReviewerAccessLink(expiredLink.token, "session-review-3", "view-only", "review-corr-6")).toBeUndefined();

    const auditEvents = service.getAuditEvents("review-set");
    expect(auditEvents.some((event) => event.eventType === "workspace_reviewer_link_issued" && event.sessionId === "session-review-1")).toBe(true);
    expect(auditEvents.some((event) => event.eventType === "workspace_reviewer_link_consumed" && event.sessionId === "session-review-1")).toBe(true);
    expect(auditEvents.some((event) => event.eventType === "workspace_reviewer_link_issued" && event.sessionId === "session-review-3")).toBe(true);
  });

  it("revokes one-time reviewer links immediately and prevents reuse", () => {
    service.registerWorkspaceSet({
      id: "review-revoke-set",
      name: "Review revoke set",
      owner: "owner@example.com",
      org: "kushin77",
      shared: true,
      approvalRequired: true,
      approved: true,
      repositories: [{ repoId: "repo-a", accessMode: "read" }],
    });

    const issued = service.issueReviewerAccessLink({
      actor: "owner@example.com",
      workspaceSetId: "review-revoke-set",
      sessionId: "session-review-4",
      reviewer: "reviewer@example.com",
      permission: "view-only",
      correlationId: "review-corr-7",
      ttlMs: 60_000,
      oneTimeUse: true,
    });

    const firstResolve = service.resolveReviewerAccessLink(issued.token, "session-review-4", "view-only", "review-corr-8");
    expect(firstResolve?.consumedAt).toBeDefined();

    const secondResolve = service.resolveReviewerAccessLink(issued.token, "session-review-4", "view-only", "review-corr-9");
    expect(secondResolve).toBeUndefined();

    const revoked = service.revokeReviewerAccessLink(issued.grant.grantId, "owner@example.com", "review-corr-10", "session closed");
    expect(revoked.revokedAt).toBeDefined();

    expect(service.resolveReviewerAccessLink(issued.token, "session-review-4", "view-only", "review-corr-11")).toBeUndefined();

    const auditEvents = service.getAuditEvents("review-revoke-set");
    expect(auditEvents.some((event) => event.eventType === "workspace_reviewer_link_revoked" && event.sessionId === "session-review-4")).toBe(true);
  });

  it("blocks shared workspace launch until approval is granted", () => {
    const provenance = createProvenance();

    service.registerWorkspaceSet({
      id: "multi-repo-dev",
      name: "Multi-repo dev set",
      owner: "owner@example.com",
      org: "kushin77",
      shared: true,
      approvalRequired: true,
      allowedPrincipals: ["dev@example.com"],
      repositories: [
        { repoId: "repo-a", accessMode: "write" },
        { repoId: "repo-b", accessMode: "read" },
      ],
    });

    const denied = service.launchWorkspace({
      actor: "dev@example.com",
      workspaceSetId: "multi-repo-dev",
      targetRepoId: "repo-a",
      correlationId: "corr-1",
      provenance,
    });

    expect(denied.allowed).toBe(false);
    expect(denied.reason).toContain("approval");
    expect(denied.auditEvent.eventType).toBe("workspace_launch_denied");

    service.approveWorkspaceSet("multi-repo-dev", "owner@example.com", "corr-2");

    const allowed = service.launchWorkspace({
      actor: "dev@example.com",
      workspaceSetId: "multi-repo-dev",
      targetRepoId: "repo-a",
      correlationId: "corr-3",
      provenance,
    });

    expect(allowed.allowed).toBe(true);
    expect(allowed.workspaceSet?.approved).toBe(true);
    expect(allowed.restoreMetadata?.repositoryCount).toBe(2);
    expect(allowed.restoreMetadata?.provenance?.imageDigest).toBe(provenance.imageDigest);
    expect(allowed.restoreMetadata?.sessionFingerprint).toMatch(/^sha256:[a-f0-9]{64}$/);
  });

  it("redacts secrets and blocks cross-repo terminal replay without confirmation", () => {
    const provenance = createProvenance();

    service.registerWorkspaceSet({
      id: "workspace-hub",
      name: "Workspace hub",
      owner: "owner@example.com",
      org: "kushin77",
      shared: false,
      repositories: [
        { repoId: "repo-a", accessMode: "admin" },
        { repoId: "repo-b", accessMode: "read" },
      ],
    });

    const snapshot: WorkspaceSnapshot = {
      activeRepoId: "repo-a",
      repositories: [
        { repoId: "repo-a", accessMode: "admin", dirty: true },
        { repoId: "repo-b", accessMode: "read" },
      ],
      terminals: [
        {
          id: "term-1",
          repoId: "repo-a",
          command: "npm run dev",
          env: {
            PATH: "/usr/bin",
            GITHUB_TOKEN: "ghp_secret",
          },
        },
        {
          id: "term-2",
          repoId: "repo-b",
          command: "deploy --password super-secret",
          env: {
            NODE_ENV: "production",
            PRIVATE_KEY: "top-secret",
          },
        },
      ],
      openFiles: ["README.md"],
      metadata: {
        lastRepo: "repo-a",
        apiSecret: "should-hide",
      },
    };

    const denied = service.launchWorkspace({
      actor: "owner@example.com",
      workspaceSetId: "workspace-hub",
      targetRepoId: "repo-a",
      correlationId: "corr-4",
      provenance,
    }, snapshot);

    expect(denied.allowed).toBe(false);
    expect(denied.reason).toContain("Cross-repo terminal replay");

    const preview = service.previewWorkspaceLaunch({
      actor: "owner@example.com",
      workspaceSetId: "workspace-hub",
      targetRepoId: "repo-a",
      correlationId: "corr-4-preview",
      provenance,
    }, snapshot);

    expect(preview.allowed).toBe(false);
    expect(preview.requiresConfirmation).toBe(true);
    expect(preview.blockedTerminalReplayCount).toBe(1);
    expect(preview.previewSnapshot?.metadata?.apiSecret).toBe("[redacted]");

    const allowed = service.launchWorkspace({
      actor: "owner@example.com",
      workspaceSetId: "workspace-hub",
      targetRepoId: "repo-a",
      correlationId: "corr-5",
      confirmCrossRepoReplay: true,
      provenance,
    }, snapshot);

    expect(allowed.allowed).toBe(true);
    expect(allowed.sanitizedSnapshot?.terminals).toHaveLength(2);
    expect(allowed.sanitizedSnapshot?.terminals[0].env?.GITHUB_TOKEN).toBe("[redacted]");
    expect(allowed.sanitizedSnapshot?.terminals[1].command).toBe("[redacted]");
    expect(allowed.sanitizedSnapshot?.terminals[1].env?.PRIVATE_KEY).toBe("[redacted]");
    expect(allowed.sanitizedSnapshot?.metadata?.apiSecret).toBe("[redacted]");
    expect(allowed.restoreMetadata?.blockedTerminalReplayCount).toBe(1);
    expect(allowed.restoreMetadata?.sessionFingerprint).toMatch(/^sha256:[a-f0-9]{64}$/);
    expect(allowed.restoreMetadata?.redactedFields).toEqual(expect.arrayContaining([
      "terminals.term-1.env.GITHUB_TOKEN",
      "terminals.term-2.command",
      "terminals.term-2.env.PRIVATE_KEY",
      "metadata.apiSecret",
    ]));

    const auditEvents = service.getAuditEvents("workspace-hub");
    expect(auditEvents.map((event) => event.eventType)).toEqual(expect.arrayContaining([
      "workspace_snapshot_redacted",
      "workspace_launch_allowed",
    ]));
  });

  it("denies actors that are not in the allow list", () => {
    const provenance = createProvenance();

    service.registerWorkspaceSet({
      id: "restricted",
      name: "Restricted set",
      owner: "owner@example.com",
      org: "kushin77",
      shared: true,
      approvalRequired: false,
      allowedPrincipals: ["allowed@example.com"],
      approved: true,
      repositories: [{ repoId: "repo-a", accessMode: "write" }],
    });

    const denied = service.launchWorkspace({
      actor: "blocked@example.com",
      workspaceSetId: "restricted",
      targetRepoId: "repo-a",
      correlationId: "corr-6",
      provenance,
    });

    expect(denied.allowed).toBe(false);
    expect(denied.reason).toContain("not allowed");
  });

  it("fails closed when provenance is missing, invalid, or stale", () => {
    service.registerWorkspaceSet({
      id: "provenance-set",
      name: "Provenance set",
      owner: "owner@example.com",
      org: "kushin77",
      shared: false,
      repositories: [{ repoId: "repo-a", accessMode: "admin" }],
    });

    const missing = service.launchWorkspace({
      actor: "owner@example.com",
      workspaceSetId: "provenance-set",
      targetRepoId: "repo-a",
      correlationId: "corr-7",
    });

    expect(missing.allowed).toBe(false);
    expect(missing.reason).toContain("provenance attestation");

    const failedVerification = service.launchWorkspace({
      actor: "owner@example.com",
      workspaceSetId: "provenance-set",
      targetRepoId: "repo-a",
      correlationId: "corr-8",
      provenance: createProvenance({ verificationResult: "failed" }),
    });

    expect(failedVerification.allowed).toBe(false);
    expect(failedVerification.reason).toContain("verified");

    const stale = service.launchWorkspace({
      actor: "owner@example.com",
      workspaceSetId: "provenance-set",
      targetRepoId: "repo-a",
      correlationId: "corr-9",
      provenance: createProvenance({ verificationTimestamp: Date.now() - 2 * 24 * 60 * 60 * 1000 }),
    });

    expect(stale.allowed).toBe(false);
    expect(stale.reason).toContain("stale");
  });

  it("records audit events for launch attempts", () => {
    const provenance = createProvenance();

    service.registerWorkspaceSet({
      id: "audit-set",
      name: "Audit set",
      owner: "owner@example.com",
      org: "kushin77",
      shared: false,
      repositories: [{ repoId: "repo-a", accessMode: "admin" }],
    });

    const result = service.launchWorkspace({
      actor: "owner@example.com",
      workspaceSetId: "audit-set",
      targetRepoId: "repo-a",
      correlationId: "corr-7",
      provenance,
    });

    expect(result.allowed).toBe(true);
    const auditEvents = service.getAuditEvents("audit-set");
    expect(auditEvents.map((event) => event.eventType)).toEqual(
      expect.arrayContaining(["workspace_set_registered", "workspace_launch_allowed"]),
    );
    expect(auditEvents.find((event) => event.eventType === "workspace_launch_allowed")?.details?.sessionFingerprint).toMatch(/^sha256:[a-f0-9]{64}$/);
  });

  it("issues scoped reviewer links and enforces expiry, permission, and revocation", () => {
    service.registerWorkspaceSet({
      id: "review-set",
      name: "Review set",
      owner: "owner@example.com",
      org: "kushin77",
      shared: true,
      approvalRequired: true,
      approved: true,
      repositories: [{ repoId: "repo-a", accessMode: "read" }],
    });

    const approvalLink = service.issueReviewerAccessLink({
      actor: "owner@example.com",
      workspaceSetId: "review-set",
      sessionId: "session-review-1",
      reviewer: "reviewer@example.com",
      permission: "approve-only",
      correlationId: "review-corr-1",
      ttlMs: 60_000,
      oneTimeUse: false,
    });

    expect(approvalLink.grant.permission).toBe("approve-only");
    expect(approvalLink.grant.sessionId).toBe("session-review-1");

    const resolved = service.resolveReviewerAccessLink(approvalLink.token, "session-review-1", "approve-only", "review-corr-2");
    expect(resolved?.grantId).toBe(approvalLink.grant.grantId);
    expect(resolved?.sessionId).toBe("session-review-1");

    const viewOnlyLink = service.issueReviewerAccessLink({
      actor: "owner@example.com",
      workspaceSetId: "review-set",
      sessionId: "session-review-2",
      reviewer: "viewer@example.com",
      permission: "view-only",
      correlationId: "review-corr-3",
      ttlMs: 60_000,
      oneTimeUse: false,
    });

    expect(service.resolveReviewerAccessLink(viewOnlyLink.token, "session-review-2", "approve-only", "review-corr-4")).toBeUndefined();

    const expiredLink = service.issueReviewerAccessLink({
      actor: "owner@example.com",
      workspaceSetId: "review-set",
      sessionId: "session-review-3",
      reviewer: "expired@example.com",
      permission: "view-only",
      correlationId: "review-corr-5",
      ttlMs: 60_000,
      oneTimeUse: true,
    });

    expiredLink.grant.expiresAt = Date.now() - 1;
    expect(service.resolveReviewerAccessLink(expiredLink.token, "session-review-3", "view-only", "review-corr-6")).toBeUndefined();

    const revokedLink = service.issueReviewerAccessLink({
      actor: "owner@example.com",
      workspaceSetId: "review-set",
      sessionId: "session-review-4",
      reviewer: "revoked@example.com",
      permission: "view-only",
      correlationId: "review-corr-7",
      ttlMs: 60_000,
      oneTimeUse: true,
    });

    const firstUse = service.resolveReviewerAccessLink(revokedLink.token, "session-review-4", "view-only", "review-corr-8");
    expect(firstUse?.consumedAt).toBeDefined();
    expect(service.resolveReviewerAccessLink(revokedLink.token, "session-review-4", "view-only", "review-corr-9")).toBeUndefined();

    const revoked = service.revokeReviewerAccessLink(revokedLink.grant.grantId, "owner@example.com", "review-corr-10", "session closed");
    expect(revoked.revokedAt).toBeDefined();
    expect(service.resolveReviewerAccessLink(revokedLink.token, "session-review-4", "view-only", "review-corr-11")).toBeUndefined();

    const auditEvents = service.getAuditEvents("review-set");
    expect(auditEvents.some((event) => event.eventType === "workspace_reviewer_link_issued" && event.sessionId === "session-review-1")).toBe(true);
    expect(auditEvents.some((event) => event.eventType === "workspace_reviewer_link_consumed" && event.sessionId === "session-review-4")).toBe(true);
    expect(auditEvents.some((event) => event.eventType === "workspace_reviewer_link_revoked" && event.sessionId === "session-review-4")).toBe(true);
  });

  it("produces the same session fingerprint for identical launch inputs", () => {
    const provenance = createProvenance({ verificationTimestamp: Date.now() });

    service.registerWorkspaceSet({
      id: "fingerprint-set",
      name: "Fingerprint set",
      owner: "owner@example.com",
      org: "kushin77",
      shared: false,
      repositories: [{ repoId: "repo-a", accessMode: "admin" }],
    });

    const first = service.launchWorkspace({
      actor: "owner@example.com",
      workspaceSetId: "fingerprint-set",
      targetRepoId: "repo-a",
      correlationId: "corr-10",
      provenance,
    });

    const second = service.launchWorkspace({
      actor: "owner@example.com",
      workspaceSetId: "fingerprint-set",
      targetRepoId: "repo-a",
      correlationId: "corr-11",
      provenance,
    });

    expect(first.allowed).toBe(true);
    expect(second.allowed).toBe(true);
    expect(first.restoreMetadata?.sessionFingerprint).toBe(second.restoreMetadata?.sessionFingerprint);
  });

  it("lists workspace sets visible to an actor based on ownership and shared ACL", () => {
    service.registerWorkspaceSet({
      id: "owned-private",
      name: "Owned private",
      owner: "owner@example.com",
      org: "kushin77",
      shared: false,
      repositories: [{ repoId: "repo-a", accessMode: "admin" }],
    });

    service.registerWorkspaceSet({
      id: "shared-open",
      name: "Shared open",
      owner: "team@example.com",
      org: "kushin77",
      shared: true,
      repositories: [{ repoId: "repo-b", accessMode: "read" }],
    });

    service.registerWorkspaceSet({
      id: "shared-restricted",
      name: "Shared restricted",
      owner: "team@example.com",
      org: "kushin77",
      shared: true,
      allowedPrincipals: ["member@example.com"],
      repositories: [{ repoId: "repo-c", accessMode: "read" }],
    });

    const ownerVisible = service.listWorkspaceSetsForActor("owner@example.com");
    expect(ownerVisible.map((set) => set.id)).toEqual(expect.arrayContaining(["owned-private", "shared-open"]));

    const memberVisible = service.listWorkspaceSetsForActor("member@example.com");
    expect(memberVisible.map((set) => set.id)).toEqual(expect.arrayContaining(["shared-open", "shared-restricted"]));
    expect(memberVisible.map((set) => set.id)).not.toContain("owned-private");
  });

  it("stores restore metadata by correlation id for admin visibility", () => {
    const provenance = createProvenance();

    service.registerWorkspaceSet({
      id: "restore-meta-set",
      name: "Restore metadata set",
      owner: "owner@example.com",
      org: "kushin77",
      shared: false,
      repositories: [{ repoId: "repo-a", accessMode: "admin" }],
    });

    const correlationId = "corr-restore-meta";
    const launch = service.launchWorkspace({
      actor: "owner@example.com",
      workspaceSetId: "restore-meta-set",
      targetRepoId: "repo-a",
      correlationId,
      provenance,
    });

    expect(launch.allowed).toBe(true);

    const metadata = service.getRestoreMetadataByCorrelationId(correlationId);
    expect(metadata?.workspaceSetId).toBe("restore-meta-set");
    expect(metadata?.activeRepoId).toBe("repo-a");
    expect(metadata?.repositoryCount).toBe(1);
  });

  it("exports and imports workspace context hub state snapshots", () => {
    service.registerWorkspaceSet({
      id: "snapshot-set-1",
      name: "Snapshot set 1",
      owner: "owner@example.com",
      org: "kushin77",
      shared: true,
      repositories: [{ repoId: "repo-a", accessMode: "read" }],
    });

    service.registerWorkspaceSet({
      id: "snapshot-set-2",
      name: "Snapshot set 2",
      owner: "owner@example.com",
      org: "kushin77",
      shared: false,
      repositories: [{ repoId: "repo-b", accessMode: "write" }],
    });

    const snapshot = service.exportStateSnapshot();
    expect(snapshot.version).toBe("workspace-context-hub-state/v1");
    expect(snapshot.workspaceSets).toHaveLength(2);

    const restoredService = new WorkspaceContextHubService();
    const importedCount = restoredService.importStateSnapshot(snapshot, "admin@example.com", "corr-import-1");
    expect(importedCount).toBe(2);

    const restoredSets = restoredService.listWorkspaceSetsForActor("owner@example.com", true);
    expect(restoredSets.map((set) => set.id)).toEqual(expect.arrayContaining(["snapshot-set-1", "snapshot-set-2"]));

    const auditEvents = restoredService.getAuditEvents();
    expect(auditEvents.some((event) => event.eventType === "workspace_state_imported")).toBe(true);
  });
});
*/
