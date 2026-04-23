#!/usr/bin/env node
/**
 * @file        apps/backend/src/routes/__tests__/session-hibernation.test.ts
 * @module      routes/session-hibernation/tests
 * @description Test suite for session hibernation routes
 *
 */
import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { SessionHibernationService, HibernationState } from "../../services/session/session-hibernation-service";
describe("Session Hibernation Routes", () => {
    let service;
    beforeEach(() => {
        service = new SessionHibernationService();
    });
    afterEach(() => {
        service.reset();
    });
    describe("POST /register", () => {
        it("registers session for hibernation monitoring", () => {
            const metrics = service.registerSession("session-1", "user-1", "workspace-1");
            expect(metrics.sessionId).toBe("session-1");
            expect(metrics.state).toBe(HibernationState.ACTIVE);
        });
        it("initializes metrics on registration", () => {
            service.registerSession("session-2", "user-2", "workspace-2");
            const metrics = service.getMetrics("session-2");
            expect(metrics?.ramSaved).toBe(0);
            expect(metrics?.idleDurationMs).toBe(0);
        });
    });
    describe("POST /:sessionId/activity", () => {
        beforeEach(() => {
            service.registerSession("session-3", "user-3", "workspace-3");
        });
        it("records activity on a session", () => {
            service.recordActivity("session-3");
            const state = service.getSessionState("session-3");
            expect(state).toBe(HibernationState.ACTIVE);
        });
        it("resets idle timer on activity", () => {
            const before = service.getIdleDuration("session-3");
            service.recordActivity("session-3");
            const after = service.getIdleDuration("session-3");
            expect(after).toBeLessThanOrEqual(before + 10);
        });
    });
    describe("POST /:sessionId/checkpoint", () => {
        beforeEach(() => {
            service.registerSession("session-4", "user-4", "workspace-4");
        });
        it("creates checkpoint with workspace state", () => {
            const checkpoint = service.createCheckpoint("session-4", {
                files: new Map([["file.ts", "code"]]),
                terminals: [{ id: "t1", name: "bash", history: ["ls"], cwd: "/home" }],
                debugState: { breakpoints: [], watches: [], stack: [], variables: {} },
                editorState: {
                    activeFile: "file.ts",
                    scrollPosition: {},
                    selections: {},
                    folds: {},
                },
                settings: {},
                ramUsage: 1024 * 1024 * 100,
            });
            expect(checkpoint.id).toBeDefined();
            expect(checkpoint.files.size).toBe(1);
        });
        it("saves 80% RAM in checkpoint", () => {
            const ramUsage = 1024 * 1024 * 100;
            service.createCheckpoint("session-4", {
                files: new Map(),
                terminals: [],
                debugState: { breakpoints: [], watches: [], stack: [], variables: {} },
                editorState: {
                    activeFile: "",
                    scrollPosition: {},
                    selections: {},
                    folds: {},
                },
                settings: {},
                ramUsage,
            });
            const metrics = service.getMetrics("session-4");
            expect(metrics?.ramSaved).toBe(Math.floor(ramUsage * 0.8));
        });
    });
    describe("POST /:sessionId/hibernate", () => {
        beforeEach(() => {
            service.registerSession("session-5", "user-5", "workspace-5");
        });
        it("transitions session to HIBERNATING state", () => {
            service.hibernate("session-5");
            const state = service.getSessionState("session-5");
            expect(state).toBe(HibernationState.HIBERNATING);
        });
        it("emits hibernationStarted event", () => {
            const listener = vi.fn();
            service.on("hibernationStarted", listener);
            service.hibernate("session-5");
            expect(listener).toHaveBeenCalled();
        });
        it("transitions to HIBERNATED after delay", () => {
            return new Promise((resolve) => {
                service.hibernate("session-5");
                setTimeout(() => {
                    const state = service.getSessionState("session-5");
                    expect(state).toBe(HibernationState.HIBERNATED);
                    resolve(undefined);
                }, 200);
            });
        });
    });
    describe("POST /:sessionId/wake", () => {
        beforeEach(() => {
            service.registerSession("session-6", "user-6", "workspace-6");
            service["sessionStates"].set("session-6", HibernationState.HIBERNATED);
        });
        it("transitions session to WAKING state", () => {
            service.wake("session-6");
            const state = service.getSessionState("session-6");
            expect(state).toBe(HibernationState.WAKING);
        });
        it("completes wake in less than 5 seconds", () => {
            return new Promise((resolve) => {
                service.wake("session-6");
                setTimeout(() => {
                    const metrics = service.getMetrics("session-6");
                    expect(metrics?.wakeTimeMs).toBeLessThan(5000);
                    resolve(undefined);
                }, 3500);
            });
        });
        it("emits sessionWoken event", () => {
            return new Promise((resolve) => {
                const listener = vi.fn();
                service.on("sessionWoken", listener);
                service.wake("session-6");
                setTimeout(() => {
                    expect(listener).toHaveBeenCalled();
                    resolve(undefined);
                }, 3500);
            });
        });
    });
    describe("GET /:sessionId/state", () => {
        it("retrieves session hibernation state", () => {
            service.registerSession("session-7", "user-7", "workspace-7");
            const state = service.getSessionState("session-7");
            expect(state).toBe(HibernationState.ACTIVE);
        });
        it("returns undefined for unregistered session", () => {
            const state = service.getSessionState("unknown");
            expect(state).toBeUndefined();
        });
    });
    describe("GET /:sessionId/metrics", () => {
        it("retrieves hibernation metrics", () => {
            service.registerSession("session-8", "user-8", "workspace-8");
            const metrics = service.getMetrics("session-8");
            expect(metrics?.sessionId).toBe("session-8");
            expect(metrics?.state).toBe(HibernationState.ACTIVE);
        });
        it("includes RAM saved in metrics", () => {
            service.registerSession("session-9", "user-9", "workspace-9");
            service.createCheckpoint("session-9", {
                files: new Map(),
                terminals: [],
                debugState: { breakpoints: [], watches: [], stack: [], variables: {} },
                editorState: {
                    activeFile: "",
                    scrollPosition: {},
                    selections: {},
                    folds: {},
                },
                settings: {},
                ramUsage: 1024 * 1024 * 100,
            });
            const metrics = service.getMetrics("session-9");
            expect(metrics?.ramSaved).toBeGreaterThan(0);
        });
    });
    describe("GET /:sessionId/checkpoint/:checkpointId", () => {
        beforeEach(() => {
            service.registerSession("session-10", "user-10", "workspace-10");
        });
        it("retrieves checkpoint details", () => {
            const created = service.createCheckpoint("session-10", {
                files: new Map([["test.ts", "code"]]),
                terminals: [],
                debugState: { breakpoints: [], watches: [], stack: [], variables: {} },
                editorState: {
                    activeFile: "",
                    scrollPosition: {},
                    selections: {},
                    folds: {},
                },
                settings: {},
                ramUsage: 0,
            });
            const retrieved = service.getCheckpoint(created.id);
            expect(retrieved?.files.size).toBe(1);
        });
        it("returns undefined for non-existent checkpoint", () => {
            const checkpoint = service.getCheckpoint("unknown");
            expect(checkpoint).toBeUndefined();
        });
    });
    describe("POST /:sessionId/checkpoint/:checkpointId/restore", () => {
        beforeEach(() => {
            service.registerSession("session-11", "user-11", "workspace-11");
        });
        it("restores checkpoint successfully", () => {
            const checkpoint = service.createCheckpoint("session-11", {
                files: new Map([["app.ts", "console.log('restored')"]]),
                terminals: [],
                debugState: { breakpoints: [], watches: [], stack: [], variables: {} },
                editorState: {
                    activeFile: "",
                    scrollPosition: {},
                    selections: {},
                    folds: {},
                },
                settings: {},
                ramUsage: 0,
            });
            const restored = service.restoreCheckpoint("session-11", checkpoint.id);
            expect(restored.files.get("app.ts")).toContain("restored");
        });
        it("emits checkpointRestored event", () => {
            const listener = vi.fn();
            service.on("checkpointRestored", listener);
            const checkpoint = service.createCheckpoint("session-11", {
                files: new Map(),
                terminals: [],
                debugState: { breakpoints: [], watches: [], stack: [], variables: {} },
                editorState: {
                    activeFile: "",
                    scrollPosition: {},
                    selections: {},
                    folds: {},
                },
                settings: {},
                ramUsage: 0,
            });
            service.restoreCheckpoint("session-11", checkpoint.id);
            expect(listener).toHaveBeenCalled();
        });
    });
    describe("DELETE /:sessionId/checkpoint/:checkpointId", () => {
        beforeEach(() => {
            service.registerSession("session-12", "user-12", "workspace-12");
        });
        it("deletes checkpoint", () => {
            const checkpoint = service.createCheckpoint("session-12", {
                files: new Map(),
                terminals: [],
                debugState: { breakpoints: [], watches: [], stack: [], variables: {} },
                editorState: {
                    activeFile: "",
                    scrollPosition: {},
                    selections: {},
                    folds: {},
                },
                settings: {},
                ramUsage: 0,
            });
            const deleted = service.deleteCheckpoint(checkpoint.id);
            expect(deleted).toBe(true);
        });
        it("returns false for non-existent checkpoint", () => {
            const deleted = service.deleteCheckpoint("unknown");
            expect(deleted).toBe(false);
        });
    });
    describe("GET /:sessionId/idle-duration", () => {
        it("calculates idle duration for session", () => {
            service.registerSession("session-13", "user-13", "workspace-13");
            const idleDuration = service.getIdleDuration("session-13");
            expect(idleDuration).toBeGreaterThanOrEqual(0);
            expect(idleDuration).toBeLessThan(100);
        });
        it("detects idle state", () => {
            service.registerSession("session-14", "user-14", "workspace-14");
            service.updateIdleConfig({ idleThresholdMs: 100 });
            return new Promise((resolve) => {
                setTimeout(() => {
                    const isIdle = service.isSessionIdle("session-14");
                    expect(isIdle).toBe(true);
                    resolve(undefined);
                }, 150);
            });
        });
    });
    describe("GET /config/idle", () => {
        it("returns idle configuration", () => {
            const config = service.getIdleConfig();
            expect(config.idleThresholdMs).toBe(5 * 60 * 1000);
            expect(config.enableAutoHibernation).toBe(true);
        });
        it("includes all config parameters", () => {
            const config = service.getIdleConfig();
            expect(config.checkIntervalMs).toBeDefined();
            expect(config.hibernationDelayMs).toBeDefined();
        });
    });
    describe("PATCH /config/idle", () => {
        it("updates idle configuration", () => {
            service.updateIdleConfig({ idleThresholdMs: 2000 });
            const config = service.getIdleConfig();
            expect(config.idleThresholdMs).toBe(2000);
        });
        it("preserves unmodified config values", () => {
            const originalCheck = service.getIdleConfig().checkIntervalMs;
            service.updateIdleConfig({ idleThresholdMs: 3000 });
            const config = service.getIdleConfig();
            expect(config.checkIntervalMs).toBe(originalCheck);
        });
    });
    describe("GET /stats", () => {
        it("returns empty statistics for no sessions", () => {
            const stats = service.getStatistics();
            expect(stats.totalSessions).toBe(0);
            expect(stats.activeSessions).toBe(0);
        });
        it("counts active sessions", () => {
            service.registerSession("session-15", "user-15", "workspace-15");
            service.registerSession("session-16", "user-16", "workspace-16");
            const stats = service.getStatistics();
            expect(stats.totalSessions).toBe(2);
            expect(stats.activeSessions).toBe(2);
        });
        it("sums total RAM saved", () => {
            service.registerSession("session-17", "user-17", "workspace-17");
            service.createCheckpoint("session-17", {
                files: new Map(),
                terminals: [],
                debugState: { breakpoints: [], watches: [], stack: [], variables: {} },
                editorState: {
                    activeFile: "",
                    scrollPosition: {},
                    selections: {},
                    folds: {},
                },
                settings: {},
                ramUsage: 1024 * 1024 * 100,
            });
            const stats = service.getStatistics();
            expect(stats.totalRamSaved).toBeGreaterThan(0);
        });
    });
    describe("GET /sessions/list", () => {
        it("lists all registered sessions", () => {
            service.registerSession("session-18", "user-18", "workspace-18");
            service.registerSession("session-19", "user-19", "workspace-19");
            const sessions = service.getAllSessions();
            expect(sessions.length).toBe(2);
        });
        it("includes hibernation state for each session", () => {
            service.registerSession("session-20", "user-20", "workspace-20");
            const sessions = service.getAllSessions();
            expect(sessions[0].state).toBe(HibernationState.ACTIVE);
        });
    });
    describe("POST /monitoring/start", () => {
        it("starts hibernation monitoring", () => {
            service.startMonitoring();
            expect(service["monitoringInterval"]).toBeDefined();
        });
        it("does not start multiple intervals", () => {
            service.startMonitoring();
            const first = service["monitoringInterval"];
            service.startMonitoring();
            const second = service["monitoringInterval"];
            expect(first).toBe(second);
            service.stopMonitoring();
        });
    });
    describe("POST /monitoring/stop", () => {
        it("stops hibernation monitoring", () => {
            service.startMonitoring();
            service.stopMonitoring();
            expect(service["monitoringInterval"]).toBeNull();
        });
    });
});
//# sourceMappingURL=session-hibernation.test.js.map