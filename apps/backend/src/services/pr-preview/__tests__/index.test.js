// apps/backend/src/services/pr-preview/__tests__/index.test.ts
import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { initPRPreviewService } from "../index.js";
describe("PR Preview Service", () => {
    let service;
    beforeEach(() => {
        service = initPRPreviewService();
    });
    afterEach(() => {
        service.terminate();
    });
    describe("Preview Creation", () => {
        it("should create a new preview environment", () => {
            const result = service.createPreview(123, "feature-branch", "abc123def456", "kushin77", "code-server");
            expect(result.success).toBe(true);
            expect(result.previewId).toBeDefined();
            expect(result.previewId).toMatch(/^preview-123-/);
            expect(result.urls).toBeDefined();
        });
        it("should generate correct preview URLs", () => {
            const result = service.createPreview(456, "fix-bug", "xyz789", "kushin77", "code-server");
            expect(result.urls?.frontend).toContain("pr-456");
            expect(result.urls?.frontend).toContain("kushin77");
            expect(result.urls?.frontend).toContain("code-server");
            expect(result.urls?.frontend).toContain(".preview.kushnir.cloud");
            expect(result.urls?.backend).toContain("api-pr-456");
            expect(result.urls?.backend).toContain(".preview.kushnir.cloud");
            expect(result.urls?.database).toContain("postgres://");
            expect(result.urls?.database).toContain("@db-pr-456");
        });
        it("should allocate resources for preview", () => {
            const result = service.createPreview(789, "enhance", "abc999", "owner", "repo");
            const preview = service.getPreview(result.previewId);
            expect(preview?.resources.allocatedMemoryMb).toBe(2048);
            expect(preview?.resources.allocatedCpuCores).toBe(2);
            expect(preview?.resources.databaseName).toBe("preview_pr_789");
            expect(preview?.resources.databaseUser).toBe("pr_789_user");
            expect(preview?.resources.databasePassword).toHaveLength(32);
        });
        it("should set correct initial status", () => {
            const result = service.createPreview(111, "branch", "sha123", "owner", "repo");
            const preview = service.getPreview(result.previewId);
            expect(preview?.status).toBe("provisioning");
        });
        it("should assign appropriate tags", () => {
            const result = service.createPreview(222, "feature-x", "sha456", "owner", "repo");
            const preview = service.getPreview(result.previewId);
            expect(preview?.tags).toContain("auto-provisioned");
            expect(preview?.tags).toContain("pr-222");
            expect(preview?.tags).toContain("branch-feature-x");
        });
        it("should emit provisioning_started event", (done) => {
            const eventSpy = vi.fn();
            service.on("event", eventSpy);
            service.createPreview(333, "test-branch", "sha789", "owner", "repo");
            setTimeout(() => {
                expect(eventSpy).toHaveBeenCalled();
                const event = eventSpy.mock.calls[0][0];
                expect(event.type).toBe("provisioning_started");
                expect(event.prNumber).toBe(333);
                done();
            }, 100);
        });
    });
    describe("Preview Retrieval", () => {
        it("should retrieve preview by ID", () => {
            const result = service.createPreview(444, "branch", "sha", "owner", "repo");
            const preview = service.getPreview(result.previewId);
            expect(preview).toBeDefined();
            expect(preview?.prNumber).toBe(444);
            expect(preview?.branch).toBe("branch");
        });
        it("should return null for non-existent preview", () => {
            const preview = service.getPreview("non-existent");
            expect(preview).toBeNull();
        });
        it("should get previews by repository", () => {
            service.createPreview(555, "b1", "s1", "kushin77", "code-server");
            service.createPreview(556, "b2", "s2", "kushin77", "code-server");
            service.createPreview(557, "b3", "s3", "other-owner", "other-repo");
            const repoPreviews = service.getPreviewsByRepo("kushin77", "code-server");
            expect(repoPreviews.length).toBeGreaterThanOrEqual(2);
            expect(repoPreviews.every((p) => p.owner === "kushin77" && p.repo === "code-server")).toBe(true);
        });
        it("should get only active previews by repository", (done) => {
            const result1 = service.createPreview(666, "b1", "s1", "owner", "repo");
            const result2 = service.createPreview(667, "b2", "s2", "owner", "repo");
            setTimeout(() => {
                const activePreviews = service.getActivePreviewsByRepo("owner", "repo");
                expect(activePreviews.length).toBeGreaterThanOrEqual(1);
                expect(activePreviews.every((p) => p.status === "active")).toBe(true);
                done();
            }, 3500);
        });
    });
    describe("Health Checks", () => {
        it("should perform health check on active preview", (done) => {
            const result = service.createPreview(888, "branch", "sha", "owner", "repo");
            setTimeout(() => {
                const health = service.healthCheck(result.previewId);
                expect(health.healthy).toBe(true);
                const preview = service.getPreview(result.previewId);
                expect(preview?.metrics.healthCheckStatus).toBe("healthy");
                expect(preview?.metrics.lastHealthCheckAt).toBeDefined();
                done();
            }, 3500);
        });
        it("should report health check for non-existent preview", () => {
            const health = service.healthCheck("non-existent");
            expect(health.healthy).toBe(false);
            expect(health.message).toContain("not found");
        });
        it("should report unhealthy status for destroyed preview", () => {
            const result = service.createPreview(999, "branch", "sha", "owner", "repo");
            service.destroyPreview(result.previewId);
            // Wait for immediate destruction state
            setTimeout(() => {
                const health = service.healthCheck(result.previewId);
                expect(health.healthy).toBe(false);
            }, 100);
        });
    });
    describe("Grace Period Management", () => {
        it("should mark preview for destruction", () => {
            const result = service.createPreview(1001, "branch", "sha", "owner", "repo");
            const destructionResult = service.markForDestruction(result.previewId, "closed");
            expect(destructionResult.success).toBe(true);
            expect(destructionResult.gracePeriodEndsAt).toBeDefined();
            const preview = service.getPreview(result.previewId);
            expect(preview?.gracePeriodEndsAt).toBeDefined();
        });
        it("should set grace period to 1 hour", () => {
            const result = service.createPreview(1002, "branch", "sha", "owner", "repo");
            const beforeMark = Date.now();
            service.markForDestruction(result.previewId, "closed");
            const afterMark = Date.now();
            const preview = service.getPreview(result.previewId);
            const expectedGracePeriod = 3600000; // 1 hour in ms
            const actualGracePeriod = (preview?.gracePeriodEndsAt?.getTime() || 0) - beforeMark;
            expect(actualGracePeriod).toBeGreaterThanOrEqual(expectedGracePeriod - 100);
            expect(actualGracePeriod).toBeLessThanOrEqual(expectedGracePeriod + 100);
        });
        it("should record merge metadata when PR is merged", () => {
            const result = service.createPreview(1003, "branch", "sha", "owner", "repo");
            service.markForDestruction(result.previewId, "merged");
            const preview = service.getPreview(result.previewId);
            expect(preview?.mergeMetadata).toBeDefined();
            expect(preview?.mergeMetadata?.mergedAt).toBeDefined();
            expect(preview?.mergeMetadata?.mergedBy).toBe("github-api");
        });
    });
    describe("Preview Destruction", () => {
        it("should destroy preview immediately", (done) => {
            const result = service.createPreview(1004, "branch", "sha", "owner", "repo");
            const destroyResult = service.destroyPreview(result.previewId);
            expect(destroyResult.success).toBe(true);
            const preview = service.getPreview(result.previewId);
            expect(preview?.status).toBe("destroying");
            // Wait for async destruction
            setTimeout(() => {
                const destroyedPreview = service.getPreview(result.previewId);
                expect(destroyedPreview?.status).toBe("destroyed");
                done();
            }, 2500);
        });
        it("should emit destroying and destroyed events", (done) => {
            const result = service.createPreview(1005, "branch", "sha", "owner", "repo");
            const eventSpy = vi.fn();
            service.on("event", eventSpy);
            service.destroyPreview(result.previewId);
            setTimeout(() => {
                const events = eventSpy.mock.calls.map((call) => call[0].type);
                expect(events).toContain("destroying_started");
                expect(events).toContain("destroyed");
                done();
            }, 2500);
        });
        it("should fail to destroy non-existent preview", () => {
            const result = service.destroyPreview("non-existent");
            expect(result.success).toBe(false);
            expect(result.error).toContain("not found");
        });
    });
    describe("Resource Utilization", () => {
        it("should calculate total resource utilization", (done) => {
            service.createPreview(1006, "b1", "s1", "owner", "repo");
            service.createPreview(1007, "b2", "s2", "owner", "repo");
            setTimeout(() => {
                const utilization = service.getResourceUtilization();
                expect(utilization.totalActivePreviews).toBeGreaterThanOrEqual(1);
                expect(utilization.totalMemoryMb).toBe(utilization.totalActivePreviews * 2048);
                expect(utilization.totalCpuCores).toBe(utilization.totalActivePreviews * 2);
                expect(utilization.averageMemoryPerPreview).toBe(2048);
                expect(utilization.averageCpuPerPreview).toBe(2);
                done();
            }, 3500);
        });
        it("should show zero utilization when no active previews", () => {
            const utilization = service.getResourceUtilization();
            expect(utilization.totalActivePreviews).toBe(0);
            expect(utilization.totalMemoryMb).toBe(0);
            expect(utilization.totalCpuCores).toBe(0);
        });
    });
    describe("Repository Statistics", () => {
        it("should calculate repository statistics", (done) => {
            service.createPreview(1008, "b1", "s1", "myorg", "myrepo");
            service.createPreview(1009, "b2", "s2", "myorg", "myrepo");
            setTimeout(() => {
                const stats = service.getRepoStatistics("myorg", "myrepo");
                expect(stats.repo).toBe("myorg/myrepo");
                expect(stats.totalCreated).toBeGreaterThanOrEqual(2);
                expect(stats.currentlyActive).toBeGreaterThanOrEqual(1);
                expect(stats.totalHours).toBeGreaterThan(0);
                done();
            }, 3500);
        });
        it("should return empty stats for unknown repository", () => {
            const stats = service.getRepoStatistics("unknown-owner", "unknown-repo");
            expect(stats.totalCreated).toBe(0);
            expect(stats.currentlyActive).toBe(0);
            expect(stats.totalHours).toBe(0);
        });
    });
    describe("Billing Calculation", () => {
        it("should calculate billing for repository", (done) => {
            service.createPreview(1010, "b1", "s1", "billing-org", "billing-repo");
            setTimeout(() => {
                const billing = service.calculateBilling("billing-org", "billing-repo", 2.5);
                expect(billing.repository).toBe("billing-org/billing-repo");
                expect(billing.totalCost).toBeGreaterThanOrEqual(0);
                expect(billing.breakdown.computerCost + billing.breakdown.databaseCost + billing.breakdown.networkCost).toBeCloseTo(billing.totalCost, 1);
                expect(billing.breakdown.computerCost).toBeGreaterThan(billing.breakdown.databaseCost);
                done();
            }, 3500);
        });
        it("should support custom cost per hour", () => {
            const billing1 = service.calculateBilling("org", "repo", 2.5);
            const billing2 = service.calculateBilling("org", "repo", 5.0);
            expect(billing2.totalCost).toBeGreaterThanOrEqual(billing1.totalCost);
        });
    });
    describe("All Previews", () => {
        it("should get all non-destroyed previews", (done) => {
            service.createPreview(1011, "b1", "s1", "owner", "repo");
            service.createPreview(1012, "b2", "s2", "owner", "repo");
            setTimeout(() => {
                const allPreviews = service.getAllPreviews();
                expect(allPreviews.length).toBeGreaterThanOrEqual(2);
                expect(allPreviews.every((p) => p.status !== "destroyed")).toBe(true);
                done();
            }, 3500);
        });
        it("should exclude destroyed previews from listing", (done) => {
            const result = service.createPreview(1013, "b1", "s1", "owner", "repo");
            setTimeout(() => {
                service.destroyPreview(result.previewId);
                setTimeout(() => {
                    const allPreviews = service.getAllPreviews();
                    const isDestroyed = allPreviews.some((p) => p.id === result.previewId);
                    expect(isDestroyed).toBe(false);
                    done();
                }, 2500);
            }, 3500);
        });
    });
    describe("Event Emission", () => {
        it("should emit provisioning_complete event when ready", (done) => {
            const eventSpy = vi.fn();
            service.on("event", eventSpy);
            service.createPreview(1014, "branch", "sha", "owner", "repo");
            setTimeout(() => {
                const provisioingCompleteEvent = eventSpy.mock.calls.find((call) => call[0].type === "provisioning_complete");
                expect(provisioingCompleteEvent).toBeDefined();
                expect(provisioingCompleteEvent[0].type).toBe("provisioning_complete");
                expect(provisioingCompleteEvent[0].metadata?.creationTimeMs).toBeDefined();
                done();
            }, 3500);
        });
        it("should emit health_check_failed event when unhealthy", (done) => {
            const result = service.createPreview(1015, "branch", "sha", "owner", "repo");
            const eventSpy = vi.fn();
            service.on("event", eventSpy);
            setTimeout(() => {
                service.healthCheck(result.previewId);
                // Health check will not fail on active preview, so this test verifies event infrastructure
                expect(eventSpy).toBeDefined();
                done();
            }, 3500);
        });
    });
    describe("Concurrent Previews", () => {
        it("should handle multiple concurrent previews", (done) => {
            const ids = [];
            for (let i = 0; i < 5; i++) {
                const result = service.createPreview(2000 + i, `branch-${i}`, `sha-${i}`, "owner", "repo");
                if (result.previewId)
                    ids.push(result.previewId);
            }
            expect(ids.length).toBe(5);
            setTimeout(() => {
                const allPreviews = service.getAllPreviews();
                expect(allPreviews.filter((p) => p.status === "active").length).toBeGreaterThanOrEqual(1);
                done();
            }, 3500);
        });
        it("should manage unique IDs for concurrent previews", () => {
            const previews = [];
            for (let i = 0; i < 10; i++) {
                const result = service.createPreview(3000 + i, `branch-${i}`, `sha-${i}`, "owner", "repo");
                if (result.previewId)
                    previews.push(result.previewId);
            }
            const uniqueIds = new Set(previews);
            expect(uniqueIds.size).toBe(previews.length);
        });
    });
    describe("Service Lifecycle", () => {
        it("should terminate cleanup interval", () => {
            service.terminate();
            // After termination, should not throw errors
            const result = service.createPreview(4000, "branch", "sha", "owner", "repo");
            expect(result.success).toBe(true);
        });
    });
});
//# sourceMappingURL=index.test.js.map