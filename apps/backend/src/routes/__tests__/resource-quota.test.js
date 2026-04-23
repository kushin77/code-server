#!/usr/bin/env node
/**
 * @file        apps/backend/src/routes/__tests__/resource-quota.test.ts
 * @module      routes/resource-quota/tests
 * @description Test suite for resource quota routes
 *
 */
import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import express from "express";
import request from "supertest";
import { ResourceQuotaService, QuotaTier } from "../../services/resource-quota";
import router from "../resource-quota";
// Mock express request/response
const mockRequest = (body = {}, params = {}) => ({
    body,
    params,
});
const mockResponse = () => {
    const res = {};
    res.status = vi.fn().mockReturnValue(res);
    res.json = vi.fn().mockReturnValue(res);
    res.send = vi.fn().mockReturnValue(res);
    return res;
};
describe("Resource Quota Routes", () => {
    let quotaService;
    let routeService;
    let app;
    beforeEach(() => {
        quotaService = new ResourceQuotaService();
    });
    afterEach(() => {
        quotaService.reset();
        ResourceQuotaService.getInstance().reset();
        routeService?.reset();
    });
    describe("POST /enforce", () => {
        it("enforces quota with valid parameters", () => {
            const req = mockRequest({ sessionId: "session-1", userId: "user-1", tier: QuotaTier.SMALL }, {});
            const res = mockResponse();
            quotaService.enforceQuota("session-1", "user-1", QuotaTier.SMALL);
            expect(quotaService.getQuotaEnforcement("session-1")).toBeDefined();
        });
        it("enforces quota with MEDIUM tier", () => {
            const req = mockRequest({ sessionId: "session-2", userId: "user-2", tier: QuotaTier.MEDIUM }, {});
            quotaService.enforceQuota("session-2", "user-2", QuotaTier.MEDIUM);
            const enforcement = quotaService.getQuotaEnforcement("session-2");
            expect(enforcement?.tier).toBe(QuotaTier.MEDIUM);
            expect(enforcement?.cpuLimit).toBe(4000);
        });
        it("enforces quota with LARGE tier", () => {
            quotaService.enforceQuota("session-3", "user-3", QuotaTier.LARGE);
            const enforcement = quotaService.getQuotaEnforcement("session-3");
            expect(enforcement?.tier).toBe(QuotaTier.LARGE);
            expect(enforcement?.cpuLimit).toBe(8000);
        });
        it("rejects invalid tier", () => {
            expect(() => {
                quotaService.enforceQuota("session-4", "user-4", "invalid");
            }).toThrow();
        });
        it("emits quotaEnforced event", () => {
            const listener = vi.fn();
            quotaService.on("quotaEnforced", listener);
            quotaService.enforceQuota("session-5", "user-5", QuotaTier.SMALL);
            expect(listener).toHaveBeenCalledWith(expect.objectContaining({
                sessionId: "session-5",
                userId: "user-5",
            }));
        });
    });
    describe("PUT /:sessionId/usage", () => {
        beforeEach(() => {
            quotaService.enforceQuota("session-6", "user-6", QuotaTier.SMALL);
        });
        it("updates CPU usage", () => {
            quotaService.updateResourceUsage("session-6", { cpuUsage: 500 });
            const usage = quotaService.getResourceUsage("session-6");
            expect(usage?.cpuUsage).toBe(500);
        });
        it("updates memory usage", () => {
            quotaService.updateResourceUsage("session-6", {
                memoryUsage: 512 * 1024 * 1024,
            });
            const usage = quotaService.getResourceUsage("session-6");
            expect(usage?.memoryUsage).toBe(512 * 1024 * 1024);
        });
        it("updates multiple resource types", () => {
            quotaService.updateResourceUsage("session-6", {
                cpuUsage: 500,
                memoryUsage: 512 * 1024 * 1024,
                diskIOUsage: 100,
                bandwidthUsage: 1024 * 1024,
            });
            const usage = quotaService.getResourceUsage("session-6");
            expect(usage?.cpuUsage).toBe(500);
            expect(usage?.memoryUsage).toBe(512 * 1024 * 1024);
            expect(usage?.diskIOUsage).toBe(100);
            expect(usage?.bandwidthUsage).toBe(1024 * 1024);
        });
        it("preserves existing values on partial update", () => {
            quotaService.updateResourceUsage("session-6", {
                cpuUsage: 500,
                memoryUsage: 512 * 1024 * 1024,
            });
            quotaService.updateResourceUsage("session-6", {
                cpuUsage: 600,
            });
            const usage = quotaService.getResourceUsage("session-6");
            expect(usage?.cpuUsage).toBe(600);
            expect(usage?.memoryUsage).toBe(512 * 1024 * 1024);
        });
    });
    describe("GET /:sessionId/usage", () => {
        it("retrieves usage for existing session", () => {
            quotaService.enforceQuota("session-7", "user-7", QuotaTier.SMALL);
            quotaService.updateResourceUsage("session-7", { cpuUsage: 800 });
            const usage = quotaService.getResourceUsage("session-7");
            expect(usage?.cpuUsage).toBe(800);
            expect(usage?.timestamp).toBeDefined();
        });
        it("returns undefined for non-existent session", () => {
            const usage = quotaService.getResourceUsage("non-existent");
            expect(usage).toBeUndefined();
        });
    });
    describe("GET /:sessionId", () => {
        it("retrieves quota enforcement for existing session", () => {
            quotaService.enforceQuota("session-8", "user-8", QuotaTier.SMALL);
            const enforcement = quotaService.getQuotaEnforcement("session-8");
            expect(enforcement?.sessionId).toBe("session-8");
            expect(enforcement?.userId).toBe("user-8");
            expect(enforcement?.status).toBe("active");
        });
        it("includes violation count in enforcement data", () => {
            quotaService.enforceQuota("session-9", "user-9", QuotaTier.SMALL);
            quotaService.updateResourceUsage("session-9", { cpuUsage: 2100 });
            const enforcement = quotaService.getQuotaEnforcement("session-9");
            expect(enforcement?.violations).toBeGreaterThanOrEqual(1);
        });
    });
    describe("PATCH /:sessionId/tier", () => {
        it("updates quota tier from SMALL to MEDIUM", () => {
            quotaService.enforceQuota("session-10", "user-10", QuotaTier.SMALL);
            const updated = quotaService.updateQuotaTier("session-10", QuotaTier.MEDIUM);
            expect(updated.tier).toBe(QuotaTier.MEDIUM);
            expect(updated.cpuLimit).toBe(4000);
        });
        it("updates quota tier from MEDIUM to LARGE", () => {
            quotaService.enforceQuota("session-11", "user-11", QuotaTier.MEDIUM);
            const updated = quotaService.updateQuotaTier("session-11", QuotaTier.LARGE);
            expect(updated.tier).toBe(QuotaTier.LARGE);
            expect(updated.memoryLimit).toBe(32 * 1024 * 1024 * 1024);
        });
        it("resets violations on tier change", () => {
            quotaService.enforceQuota("session-12", "user-12", QuotaTier.SMALL);
            quotaService.updateResourceUsage("session-12", { cpuUsage: 2100 });
            let enforcement = quotaService.getQuotaEnforcement("session-12");
            expect(enforcement?.violations).toBeGreaterThanOrEqual(1);
            enforcement = quotaService.updateQuotaTier("session-12", QuotaTier.MEDIUM);
            expect(enforcement.violations).toBe(0);
        });
        it("emits quotaTierUpdated event", () => {
            quotaService.enforceQuota("session-13", "user-13", QuotaTier.SMALL);
            const listener = vi.fn();
            quotaService.on("quotaTierUpdated", listener);
            quotaService.updateQuotaTier("session-13", QuotaTier.MEDIUM);
            expect(listener).toHaveBeenCalled();
        });
    });
    describe("PATCH /:sessionId/pause", () => {
        it("pauses quota enforcement", () => {
            quotaService.enforceQuota("session-14", "user-14", QuotaTier.SMALL);
            const paused = quotaService.pauseQuota("session-14");
            expect(paused.status).toBe("paused");
        });
        it("emits quotaPaused event", () => {
            quotaService.enforceQuota("session-15", "user-15", QuotaTier.SMALL);
            const listener = vi.fn();
            quotaService.on("quotaPaused", listener);
            quotaService.pauseQuota("session-15");
            expect(listener).toHaveBeenCalled();
        });
    });
    describe("PATCH /:sessionId/resume", () => {
        it("resumes quota enforcement", () => {
            quotaService.enforceQuota("session-16", "user-16", QuotaTier.SMALL);
            quotaService.pauseQuota("session-16");
            const resumed = quotaService.resumeQuota("session-16");
            expect(resumed.status).toBe("active");
        });
        it("emits quotaResumed event", () => {
            quotaService.enforceQuota("session-17", "user-17", QuotaTier.SMALL);
            quotaService.pauseQuota("session-17");
            const listener = vi.fn();
            quotaService.on("quotaResumed", listener);
            quotaService.resumeQuota("session-17");
            expect(listener).toHaveBeenCalled();
        });
    });
    describe("DELETE /:sessionId", () => {
        it("removes quota for session", () => {
            quotaService.enforceQuota("session-18", "user-18", QuotaTier.SMALL);
            const removed = quotaService.removeQuota("session-18");
            expect(removed).toBe(true);
            expect(quotaService.getQuotaEnforcement("session-18")).toBeUndefined();
        });
        it("returns false for non-existent quota", () => {
            const removed = quotaService.removeQuota("non-existent");
            expect(removed).toBe(false);
        });
        it("emits quotaRemoved event", () => {
            quotaService.enforceQuota("session-19", "user-19", QuotaTier.SMALL);
            const listener = vi.fn();
            quotaService.on("quotaRemoved", listener);
            quotaService.removeQuota("session-19");
            expect(listener).toHaveBeenCalled();
        });
    });
    describe("GET /:sessionId/violations", () => {
        it("returns empty array for session with no violations", () => {
            quotaService.enforceQuota("session-20", "user-20", QuotaTier.SMALL);
            const violations = quotaService.getViolationHistory("session-20");
            expect(Array.isArray(violations)).toBe(true);
            expect(violations.length).toBe(0);
        });
        it("returns violations for session with violations", () => {
            quotaService.enforceQuota("session-21", "user-21", QuotaTier.SMALL);
            quotaService.updateResourceUsage("session-21", { cpuUsage: 2100 });
            const violations = quotaService.getViolationHistory("session-21");
            expect(violations.length).toBeGreaterThanOrEqual(1);
            expect(violations[0].violationType).toBe("cpu");
        });
    });
    describe("GET /:sessionId/utilization", () => {
        it("calculates CPU utilization percentage", () => {
            quotaService.enforceQuota("session-22", "user-22", QuotaTier.SMALL);
            quotaService.updateResourceUsage("session-22", { cpuUsage: 1000 });
            const util = quotaService.calculateUtilization("session-22");
            expect(util.cpu).toBe(50);
        });
        it("returns zero utilization for session with no usage", () => {
            quotaService.enforceQuota("session-23", "user-23", QuotaTier.SMALL);
            const util = quotaService.calculateUtilization("session-23");
            expect(util.cpu).toBe(0);
            expect(util.memory).toBe(0);
        });
        it("clamps utilization at 100%", () => {
            quotaService.enforceQuota("session-24", "user-24", QuotaTier.SMALL);
            quotaService.updateResourceUsage("session-24", { cpuUsage: 5000 });
            const util = quotaService.calculateUtilization("session-24");
            expect(util.cpu).toBe(100);
        });
    });
    describe("GET /configs/all", () => {
        it("returns all quota tier configurations", () => {
            const configs = quotaService.getAllQuotaConfigs();
            expect(configs.size).toBe(3);
            expect(configs.has(QuotaTier.SMALL)).toBe(true);
            expect(configs.has(QuotaTier.MEDIUM)).toBe(true);
            expect(configs.has(QuotaTier.LARGE)).toBe(true);
        });
        it("includes CPU and memory limits", () => {
            const smallConfig = quotaService.getQuotaConfig(QuotaTier.SMALL);
            expect(smallConfig?.cpuLimit).toBe(2000);
            expect(smallConfig?.memoryLimit).toBe(2 * 1024 * 1024 * 1024);
        });
    });
    describe("GET /stats/all", () => {
        it("returns zero statistics for empty service", () => {
            const stats = quotaService.getStatistics();
            expect(stats.totalActiveSessions).toBe(0);
            expect(stats.totalViolations).toBe(0);
            expect(stats.averageUtilization).toBe(0);
        });
        it("counts active sessions", () => {
            quotaService.enforceQuota("session-25", "user-25", QuotaTier.SMALL);
            quotaService.enforceQuota("session-26", "user-26", QuotaTier.SMALL);
            const stats = quotaService.getStatistics();
            expect(stats.totalActiveSessions).toBe(2);
        });
        it("sums total violations", () => {
            quotaService.enforceQuota("session-27", "user-27", QuotaTier.SMALL);
            quotaService.updateResourceUsage("session-27", { cpuUsage: 2100 });
            quotaService.updateResourceUsage("session-27", { memoryUsage: 2.1 * 1024 * 1024 * 1024 });
            const stats = quotaService.getStatistics();
            expect(stats.totalViolations).toBeGreaterThanOrEqual(2);
        });
    });
    describe("GET /list/active", () => {
        it("returns empty list for no active quotas", () => {
            const quotas = quotaService.getAllActiveQuotas();
            expect(quotas.length).toBe(0);
        });
        it("returns all active quotas", () => {
            quotaService.enforceQuota("session-28", "user-28", QuotaTier.SMALL);
            quotaService.enforceQuota("session-29", "user-29", QuotaTier.MEDIUM);
            quotaService.enforceQuota("session-30", "user-30", QuotaTier.LARGE);
            const quotas = quotaService.getAllActiveQuotas();
            expect(quotas.length).toBe(3);
        });
        it("includes enforced quota details", () => {
            quotaService.enforceQuota("session-31", "user-31", QuotaTier.SMALL);
            const quotas = quotaService.getAllActiveQuotas();
            const found = quotas.find((q) => q.sessionId === "session-31");
            expect(found?.userId).toBe("user-31");
            expect(found?.tier).toBe(QuotaTier.SMALL);
        });
    });
    describe("Cost tracking routes", () => {
        beforeEach(() => {
            routeService = ResourceQuotaService.getInstance();
            routeService.reset();
            app = express();
            app.use(express.json());
            app.use("/api/resource-quotas", router);
        });
        it("records a session cost sample", async () => {
            routeService.enforceQuota("session-cost-1", "user-cost-1", QuotaTier.SMALL, {
                projectId: "project-alpha",
            });
            const response = await request(app)
                .post("/api/resource-quotas/session-cost-1/cost")
                .send({
                durationMs: 3600000,
                cpuMillicores: 1000,
                memoryBytes: 1024 * 1024 * 1024,
                storageBytes: 10 * 1024 * 1024 * 1024,
                gpuCount: 1,
                projectId: "project-alpha",
            });
            expect(response.status).toBe(201);
            expect(response.body.success).toBe(true);
            expect(response.body.data.cpuHours).toBeCloseTo(1, 5);
            expect(response.body.data.ramGbHours).toBeCloseTo(1, 5);
            expect(response.body.data.gpuHours).toBeCloseTo(1, 5);
            expect(response.body.data.estimatedCostUsd).toBeGreaterThan(0);
        });
        it("returns the monthly cost report", async () => {
            routeService.enforceQuota("session-cost-2", "user-cost-2", QuotaTier.SMALL, {
                projectId: "project-beta",
            });
            routeService.recordSessionCost("session-cost-2", {
                durationMs: 1800000,
                cpuMillicores: 500,
                memoryBytes: 512 * 1024 * 1024,
                storageBytes: 5 * 1024 * 1024 * 1024,
                gpuCount: 0,
                projectId: "project-beta",
            });
            const response = await request(app).get("/api/resource-quotas/cost/monthly");
            expect(response.status).toBe(200);
            expect(response.body.success).toBe(true);
            expect(response.body.data.totals.sampleCount).toBe(1);
            expect(response.body.data.byUser[0].identifier).toBe("user-cost-2");
            expect(response.body.data.byProject[0].identifier).toBe("project-beta");
        });
        it("raises cost budget alerts when a budget is exceeded", async () => {
            routeService.enforceQuota("session-cost-3", "user-cost-3", QuotaTier.SMALL, {
                projectId: "project-gamma",
            });
            routeService.setCostBudget("user", "user-cost-3", 0.02);
            const response = await request(app)
                .post("/api/resource-quotas/session-cost-3/cost")
                .send({
                durationMs: 3600000,
                cpuMillicores: 1000,
                memoryBytes: 1024 * 1024 * 1024,
                storageBytes: 0,
                gpuCount: 0,
                projectId: "project-gamma",
            });
            expect(response.status).toBe(201);
            const alerts = await request(app).get("/api/resource-quotas/cost/alerts");
            expect(alerts.status).toBe(200);
            expect(alerts.body.count).toBe(1);
            expect(alerts.body.data[0].scope).toBe("user");
            expect(alerts.body.data[0].identifier).toBe("user-cost-3");
            expect(alerts.body.data[0].severity).toBe("critical");
        });
    });
});
//# sourceMappingURL=resource-quota.test.js.map