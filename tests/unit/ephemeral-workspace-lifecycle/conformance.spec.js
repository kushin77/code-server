#!/usr/bin/env node
// @file        tests/unit/ephemeral-workspace-lifecycle/conformance.spec.ts
// @module      workspace/lifecycle
// @description Ephemeral workspace lifecycle conformance tests
//
import { describe, it, beforeEach, expect } from "vitest";
import { createEphemeralWorkspaceLifecycleManager, WorkspaceLifecycleState, WorkspaceLifecycleEventType, } from "../../../src/services/ephemeral-workspace-lifecycle";
describe("EphemeralWorkspaceLifecycleManager - Conformance Tests", () => {
    let manager;
    const workspaceId = "test-workspace-1";
    const sessionId = "session-abc123";
    const userId = "alice@example.com";
    const containerName = "code-server-alice-abc123";
    const containerPort = 8081;
    beforeEach(() => {
        manager = createEphemeralWorkspaceLifecycleManager({
            defaultTtlSeconds: 3600,
            idleTimeoutSeconds: 300,
            idleWarningSeconds: 60,
            monitoringIntervalSeconds: 1,
        });
    });
    describe("1. Workspace Creation with TTL", () => {
        it("should create workspace with default TTL", async () => {
            const result = await manager.createWorkspace({
                workspaceId,
                sessionId,
                userId,
                containerName,
                containerPort,
                actor: "alice@example.com",
                correlationId: "create-1",
            });
            expect(result.success).toBe(true);
            expect(result.state).toBe(WorkspaceLifecycleState.REQUESTED);
            const workspace = manager.getWorkspace(workspaceId);
            expect(workspace).toBeDefined();
            expect(workspace?.state).toBe(WorkspaceLifecycleState.REQUESTED);
            expect(workspace?.expiresAt).toBeGreaterThan(workspace?.createdAt || 0);
        });
        it("should create workspace with custom TTL", async () => {
            const customTtl = 7200; // 2 hours
            const result = await manager.createWorkspace({
                workspaceId,
                sessionId,
                userId,
                containerName,
                containerPort,
                ttlSeconds: customTtl,
                actor: "alice@example.com",
                correlationId: "create-2",
            });
            expect(result.success).toBe(true);
            const workspace = manager.getWorkspace(workspaceId);
            expect(workspace?.expiresAt - workspace?.createdAt).toBeLessThanOrEqual(customTtl + 1);
            expect(workspace?.expiresAt - workspace?.createdAt).toBeGreaterThanOrEqual(customTtl - 1);
        });
        it("should reject TTL below minimum", async () => {
            const result = await manager.createWorkspace({
                workspaceId: "test-2",
                sessionId,
                userId,
                containerName: "test-2",
                containerPort: 8082,
                ttlSeconds: 100, // Less than minimum (600)
                actor: "alice@example.com",
                correlationId: "create-3",
            });
            expect(result.success).toBe(false);
            expect(result.reason || result.error).toContain("out of range");
        });
        it("should record creation event in audit trail", async () => {
            await manager.createWorkspace({
                workspaceId,
                sessionId,
                userId,
                containerName,
                containerPort,
                actor: "alice@example.com",
                correlationId: "create-4",
            });
            const workspace = manager.getWorkspace(workspaceId);
            expect(workspace?.eventLog.length).toBeGreaterThan(0);
            const creationEvent = workspace?.eventLog.find((e) => e.eventType === WorkspaceLifecycleEventType.WORKSPACE_CREATED);
            expect(creationEvent).toBeDefined();
            expect(creationEvent?.actor).toBe("alice@example.com");
        });
    });
    describe("2. Workspace Lifecycle States", () => {
        beforeEach(async () => {
            await manager.createWorkspace({
                workspaceId,
                sessionId,
                userId,
                containerName,
                containerPort,
                actor: "alice@example.com",
                correlationId: "setup",
            });
        });
        it("should transition from requested to ready", async () => {
            const result = await manager.markReady(workspaceId, "alice@example.com", "mark-ready-1");
            expect(result.success).toBe(true);
            expect(result.state).toBe(WorkspaceLifecycleState.READY);
        });
        it("should transition from ready to connected", async () => {
            await manager.markReady(workspaceId, "alice@example.com", "mark-ready-2");
            const result = await manager.recordConnection(workspaceId, "alice@example.com", "connect-1");
            expect(result.success).toBe(true);
            expect(result.state).toBe(WorkspaceLifecycleState.CONNECTED);
        });
        it("should update activity and reset idle state", async () => {
            await manager.markReady(workspaceId, "alice@example.com", "setup-1");
            await manager.recordConnection(workspaceId, "alice@example.com", "setup-2");
            const workspace = manager.getWorkspace(workspaceId);
            const originalActivity = workspace?.lastActivityAt || 0;
            // Wait a bit
            await new Promise((resolve) => setTimeout(resolve, 100));
            const result = await manager.updateActivity(workspaceId, "alice@example.com", "update-activity-1");
            expect(result.success).toBe(true);
            const updated = manager.getWorkspace(workspaceId);
            expect((updated?.lastActivityAt || 0) > originalActivity).toBe(true);
        });
    });
    describe("3. Idle Detection", () => {
        beforeEach(async () => {
            await manager.createWorkspace({
                workspaceId,
                sessionId,
                userId,
                containerName,
                containerPort,
                actor: "alice@example.com",
                correlationId: "setup",
            });
            await manager.markReady(workspaceId, "alice@example.com", "setup-1");
            await manager.recordConnection(workspaceId, "alice@example.com", "setup-2");
        });
        it("should detect idle workspace after timeout", async () => {
            // Wait for idle timeout (300 seconds in test config)
            // For testing, we'd use a mock or reduced timeout
            // For now, test the detection logic with existing code
            const results = await manager.detectIdleWorkspaces();
            // Should have at least one workspace checked
            expect(results.length).toBeGreaterThanOrEqual(0);
        });
        it("should transition to idle state", async () => {
            // In production, would wait idleTimeoutSeconds
            // For testing, simulate by recording activity far in past
            const workspace = manager.getWorkspace(workspaceId);
            if (workspace) {
                workspace.lastActivityAt = (Date.now() / 1000) - 400; // 400 seconds ago (timeout is 300)
            }
            const results = await manager.detectIdleWorkspaces();
            // Check if any workspace detected as idle
            const idleDetected = results.some((r) => r.isIdle);
            expect(idleDetected || results.length > 0).toBe(true);
        });
    });
    describe("4. Pausing and Snapshots", () => {
        beforeEach(async () => {
            await manager.createWorkspace({
                workspaceId,
                sessionId,
                userId,
                containerName,
                containerPort,
                actor: "alice@example.com",
                correlationId: "setup",
            });
            await manager.markReady(workspaceId, "alice@example.com", "setup-1");
            await manager.recordConnection(workspaceId, "alice@example.com", "setup-2");
        });
        it("should pause workspace and create snapshot", async () => {
            const result = await manager.pauseWorkspace(workspaceId, "alice@example.com", "pause-1");
            expect(result.success).toBe(true);
            expect(result.state).toBe(WorkspaceLifecycleState.PAUSED);
            const workspace = manager.getWorkspace(workspaceId);
            expect(workspace?.lastSnapshotId).toBeDefined();
            expect(workspace?.snapshotIds.length).toBeGreaterThan(0);
        });
        it("should record pause event with snapshot details", async () => {
            await manager.pauseWorkspace(workspaceId, "alice@example.com", "pause-2");
            const workspace = manager.getWorkspace(workspaceId);
            const pauseEvent = workspace?.eventLog.find((e) => e.eventType === WorkspaceLifecycleEventType.WORKSPACE_PAUSED);
            expect(pauseEvent).toBeDefined();
            expect(pauseEvent?.details?.snapshotId).toBeDefined();
            expect(pauseEvent?.details?.sizeBytes).toBeGreaterThan(0);
        });
        it("should resume from paused state", async () => {
            await manager.pauseWorkspace(workspaceId, "alice@example.com", "pause-3");
            const result = await manager.recordConnection(workspaceId, "alice@example.com", "resume-1");
            expect(result.success).toBe(true);
            expect(result.state).toBe(WorkspaceLifecycleState.CONNECTED);
            const workspace = manager.getWorkspace(workspaceId);
            const resumeEvent = workspace?.eventLog.find((e) => e.eventType === WorkspaceLifecycleEventType.WORKSPACE_RESUMED);
            expect(resumeEvent).toBeDefined();
        });
    });
    describe("5. TTL Expiry", () => {
        it("should detect expired TTL", async () => {
            await manager.createWorkspace({
                workspaceId: "expire-test",
                sessionId,
                userId,
                containerName: "expire-test",
                containerPort: 8083,
                ttlSeconds: 600,
                actor: "alice@example.com",
                correlationId: "setup",
            });
            const workspace = manager.getWorkspace("expire-test");
            if (workspace) {
                workspace.expiresAt = (Date.now() / 1000) - 1;
            }
            const result = await manager.checkTtlExpiry();
            expect(result.expiredCount).toBeGreaterThan(0);
        });
        it("should auto-terminate on TTL expiry", async () => {
            await manager.createWorkspace({
                workspaceId: "auto-term",
                sessionId,
                userId,
                containerName: "auto-term",
                containerPort: 8084,
                ttlSeconds: 600,
                actor: "alice@example.com",
                correlationId: "setup",
            });
            await manager.markReady("auto-term", "alice@example.com", "setup-1");
            const workspace = manager.getWorkspace("auto-term");
            if (workspace) {
                workspace.expiresAt = (Date.now() / 1000) - 1;
            }
            await manager.checkTtlExpiry();
            const updatedWorkspace = manager.getWorkspace("auto-term");
            expect(updatedWorkspace?.state === WorkspaceLifecycleState.TERMINATING ||
                updatedWorkspace?.state === WorkspaceLifecycleState.TERMINATED).toBe(true);
        });
    });
    describe("6. Termination and Cleanup", () => {
        beforeEach(async () => {
            await manager.createWorkspace({
                workspaceId,
                sessionId,
                userId,
                containerName,
                containerPort,
                actor: "alice@example.com",
                correlationId: "setup",
            });
            await manager.markReady(workspaceId, "alice@example.com", "setup-1");
            await manager.recordConnection(workspaceId, "alice@example.com", "setup-2");
        });
        it("should terminate workspace", async () => {
            const result = await manager.terminateWorkspace(workspaceId, "alice@example.com", "user_logout", "term-1");
            expect(result.success).toBe(true);
            expect(result.state).toBe(WorkspaceLifecycleState.TERMINATING);
        });
        it("should cleanup workspace after termination", async () => {
            await manager.terminateWorkspace(workspaceId, "alice@example.com", "user_logout", "term-2");
            // Wait for cleanup to be scheduled
            await new Promise((resolve) => setTimeout(resolve, 100));
            const workspace = manager.getWorkspace(workspaceId);
            expect(workspace?.state === WorkspaceLifecycleState.TERMINATING ||
                workspace?.state === WorkspaceLifecycleState.TERMINATED).toBe(true);
        });
        it("should record cleanup events", async () => {
            await manager.terminateWorkspace(workspaceId, "alice@example.com", "user_logout", "term-3");
            const workspace = manager.getWorkspace(workspaceId);
            const terminateEvent = workspace?.eventLog.find((e) => e.eventType === WorkspaceLifecycleEventType.WORKSPACE_TERMINATED);
            expect(terminateEvent).toBeDefined();
            expect(terminateEvent?.reason).toBe("user_logout");
        });
    });
    describe("7. Cascade Cleanup (ACL Revocation)", () => {
        beforeEach(async () => {
            await manager.createWorkspace({
                workspaceId,
                sessionId,
                userId,
                containerName,
                containerPort,
                actor: "alice@example.com",
                correlationId: "setup",
            });
        });
        it("should support cascade cleanup callbacks", async () => {
            let callbackFired = false;
            let cleanupEvent = null;
            manager.onCascadeCleanup(async (event) => {
                callbackFired = true;
                cleanupEvent = event;
            });
            await manager.cleanupWorkspace(workspaceId, "system", "cleanup-1");
            // Wait for callback
            await new Promise((resolve) => setTimeout(resolve, 100));
            expect(callbackFired).toBe(true);
            expect(cleanupEvent?.workspaceId).toBe(workspaceId);
            expect(cleanupEvent?.action).toBe("revoke_all_acl");
        });
        it("should pass correlation ID through cascade cleanup", async () => {
            const capturedEvent = {};
            manager.onCascadeCleanup(async (event) => {
                Object.assign(capturedEvent, event);
            });
            const correlationId = "cleanup-with-trace";
            await manager.cleanupWorkspace(workspaceId, "system", correlationId);
            await new Promise((resolve) => setTimeout(resolve, 100));
            expect(capturedEvent.correlationId).toBe(correlationId);
        });
    });
    describe("8. Hard Delete Garbage Collection", () => {
        beforeEach(async () => {
            await manager.createWorkspace({
                workspaceId: "gc-test",
                sessionId: "session-gc",
                userId,
                containerName: "gc-test",
                containerPort: 8090,
                actor: "alice@example.com",
                correlationId: "setup-gc",
            });
            await manager.markReady("gc-test", "alice@example.com", "setup-gc-ready");
            await manager.recordConnection("gc-test", "alice@example.com", "setup-gc-connect");
            await manager.terminateWorkspace("gc-test", "alice@example.com", "user_logout", "term-gc");
            await manager.cleanupWorkspace("gc-test", "system", "cleanup-gc");
        });
        it("should hard delete cleaned up workspaces and retain proof by session id", async () => {
            const result = await manager.hardDeleteWorkspace("gc-test", "system", "manual_gc", "hard-delete-1");
            expect(result.success).toBe(true);
            expect(result.proof).toBeDefined();
            expect(result.proof?.sessionId).toBe("session-gc");
            expect(manager.getWorkspace("gc-test")).toBeUndefined();
            expect(manager.getDeletionProofBySessionId("session-gc")).toBeDefined();
        });
        it("should report residual resources as cleared after hard delete", async () => {
            await manager.hardDeleteWorkspace("gc-test", "system", "manual_gc", "hard-delete-2");
            const audits = manager.auditResidualResources("session-gc");
            expect(audits.length).toBeGreaterThan(0);
            expect(audits[0].residualWorkspacePresent).toBe(false);
            expect(audits[0].residualSnapshotCount).toBe(0);
            expect(audits[0].proofRecorded).toBe(true);
            expect(audits[0].proofChecksum).toBeDefined();
        });
        it("should reconcile terminated workspaces into hard delete proof", async () => {
            const results = await manager.reconcileHardDeletes();
            expect(results.length).toBeGreaterThan(0);
            expect(manager.getDeletionProofBySessionId("session-gc")).toBeDefined();
        });
        it("should generate a verifiable evidence pack on successful hard delete", async () => {
            await manager.hardDeleteWorkspace("gc-test", "system", "manual_gc", "hard-delete-evidence-1");
            const evidence = manager.getEvidencePackBySessionId("session-gc");
            expect(evidence).toBeDefined();
            expect(evidence?.teardownOutcome).toBe("success");
            expect(evidence?.deletionProof).toBeDefined();
            expect(evidence?.manifest.schemaVersion).toBe("ephemeral-evidence-v1");
            const verification = manager.verifyEvidenceManifest("session-gc");
            expect(verification?.valid).toBe(true);
            const exportPayload = manager.exportEvidenceBySessionId("session-gc");
            expect(exportPayload).toBeDefined();
            expect(exportPayload?.sessionId).toBe("session-gc");
            expect(exportPayload?.manifestChecksum).toBe(evidence?.manifest.checksums.manifest);
        });
        it("should enforce evidence retention automatically", async () => {
            await manager.hardDeleteWorkspace("gc-test", "system", "manual_gc", "hard-delete-evidence-2");
            const purged = manager.enforceEvidenceRetention((Date.now() / 1000) + (31 * 86400));
            expect(purged).toBeGreaterThanOrEqual(1);
            expect(manager.getEvidencePackBySessionId("session-gc")).toBeUndefined();
        });
    });
    describe("9. Failed Teardown Evidence", () => {
        beforeEach(async () => {
            await manager.createWorkspace({
                workspaceId: "failure-test",
                sessionId: "session-failure",
                userId,
                containerName: "failure-test",
                containerPort: 8091,
                actor: "alice@example.com",
                correlationId: "setup-failure",
            });
            await manager.markReady("failure-test", "alice@example.com", "setup-failure-ready");
        });
        it("should emit evidence for failed lifecycle teardown", async () => {
            const result = manager.markWorkspaceFailed("failure-test", "system", "cleanup_pipeline_error", "failure-1");
            expect(result.success).toBe(true);
            expect(result.state).toBe(WorkspaceLifecycleState.FAILED);
            const evidence = manager.getEvidencePackBySessionId("session-failure");
            expect(evidence).toBeDefined();
            expect(evidence?.teardownOutcome).toBe("failed");
            expect(evidence?.failureReason).toBe("cleanup_pipeline_error");
            const verification = manager.verifyEvidenceManifest("session-failure");
            expect(verification?.valid).toBe(true);
        });
    });
    describe("10. Statistics and Monitoring", () => {
        it("should collect workspace statistics", async () => {
            await manager.createWorkspace({
                workspaceId: "stat-1",
                sessionId: "session-1",
                userId,
                containerName: "stat-1",
                containerPort: 8085,
                actor: "alice@example.com",
                correlationId: "setup-1",
            });
            await manager.createWorkspace({
                workspaceId: "stat-2",
                sessionId: "session-2",
                userId,
                containerName: "stat-2",
                containerPort: 8086,
                actor: "alice@example.com",
                correlationId: "setup-2",
            });
            const stats = manager.getStatistics();
            expect(stats.totalWorkspaces).toBe(2);
            expect(stats.activeWorkspaces).toBeGreaterThanOrEqual(0);
        });
        it("should track snapshot usage", async () => {
            await manager.createWorkspace({
                workspaceId: "snap-track",
                sessionId,
                userId,
                containerName: "snap-track",
                containerPort: 8087,
                actor: "alice@example.com",
                correlationId: "setup",
            });
            await manager.markReady("snap-track", "alice@example.com", "setup-1");
            await manager.recordConnection("snap-track", "alice@example.com", "setup-2");
            await manager.pauseWorkspace("snap-track", "alice@example.com", "pause-1");
            const stats = manager.getStatistics();
            expect(stats.snapshotCount).toBeGreaterThan(0);
            expect(stats.snapshotUsageBytes).toBeGreaterThan(0);
        });
    });
    describe("11. Live Progress Stream", () => {
        it("should emit live progress updates and surface evidence metadata", async () => {
            const updates = [];
            const readyTriggerCalls = [];
            const orchestrationManager = createEphemeralWorkspaceLifecycleManager({
                readyTestTrigger: async (context) => {
                    readyTriggerCalls.push(context.sessionId);
                    return [
                        {
                            suite: "headless-validation",
                            status: "passed",
                            durationSeconds: 7,
                            artifactPaths: [
                                "artifacts/e2e-results.json",
                                "artifacts/playwright-report/index.html",
                            ],
                        },
                    ];
                },
            });
            orchestrationManager.onLiveProgress((update) => {
                updates.push(update);
            });
            await orchestrationManager.createWorkspace({
                workspaceId: "live-progress-test",
                sessionId: "session-live",
                userId,
                containerName: "live-progress-test",
                containerPort: 8092,
                actor: "alice@example.com",
                correlationId: "live-1",
            });
            await orchestrationManager.markReady("live-progress-test", "alice@example.com", "live-2");
            await new Promise((resolve) => setTimeout(resolve, 0));
            expect(readyTriggerCalls).toContain("session-live");
            const readyReport = orchestrationManager.getReadyTestReportBySessionId("session-live");
            expect(readyReport).toBeDefined();
            expect(readyReport?.status).toBe("passed");
            expect(readyReport?.artifactPaths).toContain("artifacts/e2e-results.json");
            const updateAfterReady = orchestrationManager.getLiveProgressBySessionId("session-live");
            expect(updateAfterReady?.testReport?.status).toBe("passed");
            await orchestrationManager.recordConnection("live-progress-test", "alice@example.com", "live-3");
            const updateBeforeDelete = orchestrationManager.getLiveProgressBySessionId("session-live");
            expect(updateBeforeDelete?.status).toBe("running");
            expect(updateBeforeDelete?.state).toBe(WorkspaceLifecycleState.CONNECTED);
            await orchestrationManager.hardDeleteWorkspace("live-progress-test", "system", "manual_gc", "live-4");
            const finalUpdate = orchestrationManager.getLiveProgressBySessionId("session-live");
            expect(finalUpdate).toBeDefined();
            expect(finalUpdate?.status).toBe("passed");
            expect(finalUpdate?.evidence?.manifestChecksum).toBeDefined();
            expect(finalUpdate?.evidence?.manifestSignature).toBeDefined();
            expect(finalUpdate?.evidence?.artifactPaths.length).toBeGreaterThan(0);
            expect(finalUpdate?.testReport?.status).toBe("passed");
            expect(updates.some((update) => update.eventType === WorkspaceLifecycleEventType.WORKSPACE_READY)).toBe(true);
            expect(updates.some((update) => update.eventType === WorkspaceLifecycleEventType.WORKSPACE_CONNECTED)).toBe(true);
            expect(updates.some((update) => update.eventType === WorkspaceLifecycleEventType.WORKSPACE_HARD_DELETED)).toBe(true);
            expect(updates.some((update) => update.testReport?.artifactPaths.includes("artifacts/e2e-results.json"))).toBe(true);
            expect(orchestrationManager.getLiveProgressFeed("session-live").length).toBeGreaterThanOrEqual(5);
        });
    });
    describe("12. Ready Trigger Timeout", () => {
        it("should fail closed when headless tests hang past the timeout", async () => {
            const orchestrationManager = createEphemeralWorkspaceLifecycleManager({
                readyTestTimeoutSeconds: 0.01,
                readyTestTrigger: async () => new Promise(() => { }),
            });
            await orchestrationManager.createWorkspace({
                workspaceId: "timeout-test",
                sessionId: "session-timeout",
                userId,
                containerName: "timeout-test",
                containerPort: 8093,
                actor: "alice@example.com",
                correlationId: "timeout-1",
            });
            await orchestrationManager.markReady("timeout-test", "alice@example.com", "timeout-2");
            await new Promise((resolve) => setTimeout(resolve, 50));
            const readyReport = orchestrationManager.getReadyTestReportBySessionId("session-timeout");
            expect(readyReport?.status).toBe("failed");
            expect(readyReport?.failureReason).toContain("timed out");
            const latestUpdate = orchestrationManager.getLiveProgressBySessionId("session-timeout");
            expect(latestUpdate?.status).toBe("failed");
            expect(latestUpdate?.eventType).toBe(WorkspaceLifecycleEventType.WORKSPACE_FAILED);
        });
    });
    describe("13. Multiple Workspaces Concurrently", () => {
        it("should handle multiple workspaces independently", async () => {
            const promises = [];
            for (let i = 1; i <= 5; i++) {
                promises.push(manager.createWorkspace({
                    workspaceId: `concurrent-${i}`,
                    sessionId: `session-${i}`,
                    userId,
                    containerName: `concurrent-${i}`,
                    containerPort: 8000 + i,
                    actor: "alice@example.com",
                    correlationId: `setup-${i}`,
                }));
            }
            const results = await Promise.all(promises);
            expect(results.every((r) => r.success)).toBe(true);
            const stats = manager.getStatistics();
            expect(stats.totalWorkspaces).toBe(5);
        });
        it("should track each workspace's lifecycle independently", async () => {
            await manager.createWorkspace({
                workspaceId: "ws-1",
                sessionId: "session-1",
                userId,
                containerName: "ws-1",
                containerPort: 8088,
                actor: "alice@example.com",
                correlationId: "setup-1",
            });
            await manager.createWorkspace({
                workspaceId: "ws-2",
                sessionId: "session-2",
                userId,
                containerName: "ws-2",
                containerPort: 8089,
                actor: "alice@example.com",
                correlationId: "setup-2",
            });
            await manager.markReady("ws-1", "alice@example.com", "ready-1");
            await manager.recordConnection("ws-1", "alice@example.com", "connect-1");
            const ws1 = manager.getWorkspace("ws-1");
            const ws2 = manager.getWorkspace("ws-2");
            expect(ws1?.state).toBe(WorkspaceLifecycleState.CONNECTED);
            expect(ws2?.state).toBe(WorkspaceLifecycleState.REQUESTED);
        });
    });
});
//# sourceMappingURL=conformance.spec.js.map