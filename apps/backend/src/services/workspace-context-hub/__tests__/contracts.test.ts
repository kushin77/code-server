import { describe, expect, it } from "vitest";

import {
  WORKSPACE_CONTEXT_HUB_CONTRACT_VERSION,
  toPortalWorkspaceLaunchResponse,
  toPortalWorkspaceSetSummary,
  toWorkspaceLaunchRequest,
  validatePortalWorkspaceLaunchRequest,
} from "../contracts";
import { WorkspaceContextHubService } from "../service";

describe("workspace-context-hub contracts", () => {
  it("validates portal launch payloads", () => {
    const invalid = validatePortalWorkspaceLaunchRequest({ actor: "", workspaceSetId: "set-1" });
    expect(invalid.valid).toBe(false);
    expect(invalid.errors).toContain("actor is required");
    expect(invalid.errors).toContain("correlationId is required");

    const valid = validatePortalWorkspaceLaunchRequest({
      actor: "dev@example.com",
      workspaceSetId: "set-1",
      correlationId: "corr-1",
      confirmCrossRepoReplay: false,
    });
    expect(valid.valid).toBe(true);
    expect(valid.errors).toHaveLength(0);
  });

  it("maps validated launch payloads into internal launch requests", () => {
    const payload = {
      actor: "dev@example.com",
      workspaceSetId: "set-1",
      correlationId: "corr-2",
      targetRepoId: "repo-a",
      confirmCrossRepoReplay: true,
    };

    expect(toWorkspaceLaunchRequest(payload)).toEqual(payload);
  });

  it("returns contract-versioned launch responses for portal consumers", () => {
    const service = new WorkspaceContextHubService();
    const provenanceTimestamp = Date.now();

    service.registerWorkspaceSet({
      id: "set-portal",
      name: "Portal set",
      owner: "owner@example.com",
      org: "kushin77",
      shared: false,
      repositories: [{ repoId: "repo-a", accessMode: "write" }],
    });

    const result = service.launchWorkspace({
      actor: "owner@example.com",
      workspaceSetId: "set-portal",
      targetRepoId: "repo-a",
      correlationId: "corr-3",
      provenance: {
        imageDigest: `sha256:${"b".repeat(64)}`,
        attestationRef: "attestation://build/contracts-1",
        signerIdentity: "builder@ci",
        verificationTimestamp: provenanceTimestamp,
        verificationResult: "verified",
        policyVersion: "ephemeral-provenance-v1",
      },
    });

    const response = toPortalWorkspaceLaunchResponse(result);
    expect(response.contractVersion).toBe(WORKSPACE_CONTEXT_HUB_CONTRACT_VERSION);
    expect(response.allowed).toBe(true);
    expect(response.workspaceSetId).toBe("set-portal");
    expect(response.audit.correlationId).toBe("corr-3");
  });

  it("builds concise workspace-set summaries for Backstage and Appsmith", () => {
    const service = new WorkspaceContextHubService();
    const workspaceSet = service.registerWorkspaceSet({
      id: "set-shared",
      name: "Shared set",
      owner: "owner@example.com",
      org: "kushin77",
      shared: true,
      approvalRequired: true,
      repositories: [
        { repoId: "repo-a", accessMode: "write" },
        { repoId: "repo-b", accessMode: "read" },
      ],
    });

    const summary = toPortalWorkspaceSetSummary(workspaceSet);
    expect(summary.repositoryCount).toBe(2);
    expect(summary.approvalRequired).toBe(true);
    expect(summary.approved).toBe(false);
  });
});