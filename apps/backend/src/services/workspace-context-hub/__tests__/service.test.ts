import { beforeEach, describe, expect, it } from "vitest";
import { WorkspaceContextHubService } from "../service";
import type { WorkspaceSnapshot } from "../types";

describe("WorkspaceContextHubService", () => {
  let service: WorkspaceContextHubService;

  beforeEach(() => {
    service = new WorkspaceContextHubService();
  });

  it("blocks shared workspace launch until approval is granted", () => {
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
    });

    expect(allowed.allowed).toBe(true);
    expect(allowed.workspaceSet?.approved).toBe(true);
    expect(allowed.restoreMetadata?.repositoryCount).toBe(2);
  });

  it("redacts secrets and blocks cross-repo terminal replay without confirmation", () => {
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
    }, snapshot);

    expect(denied.allowed).toBe(false);
    expect(denied.reason).toContain("Cross-repo terminal replay");

    const preview = service.previewWorkspaceLaunch({
      actor: "owner@example.com",
      workspaceSetId: "workspace-hub",
      targetRepoId: "repo-a",
      correlationId: "corr-4-preview",
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
    }, snapshot);

    expect(allowed.allowed).toBe(true);
    expect(allowed.sanitizedSnapshot?.terminals).toHaveLength(2);
    expect(allowed.sanitizedSnapshot?.terminals[0].env?.GITHUB_TOKEN).toBe("[redacted]");
    expect(allowed.sanitizedSnapshot?.terminals[1].command).toBe("[redacted]");
    expect(allowed.sanitizedSnapshot?.terminals[1].env?.PRIVATE_KEY).toBe("[redacted]");
    expect(allowed.sanitizedSnapshot?.metadata?.apiSecret).toBe("[redacted]");
    expect(allowed.restoreMetadata?.blockedTerminalReplayCount).toBe(1);
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
    });

    expect(denied.allowed).toBe(false);
    expect(denied.reason).toContain("not allowed");
  });

  it("records audit events for launch attempts", () => {
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
    });

    expect(result.allowed).toBe(true);
    const auditEvents = service.getAuditEvents("audit-set");
    expect(auditEvents.map((event) => event.eventType)).toEqual(
      expect.arrayContaining(["workspace_set_registered", "workspace_launch_allowed"]),
    );
  });
});
