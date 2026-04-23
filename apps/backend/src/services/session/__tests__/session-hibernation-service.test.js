#!/usr/bin/env node
/**
 * @file        apps/backend/src/services/session/__tests__/session-hibernation-service.test.ts
 * @module      session/hibernation/tests
 * @description Test suite for SessionHibernationService
 *
 */
import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { SessionHibernationService, HibernationState } from "../session-hibernation-service";
describe("SessionHibernationService", () => {
    let service;
    beforeEach(() => {
        service = new SessionHibernationService();
    });
    afterEach(() => {
        service.reset();
    });
    describe("Singleton Instance", () => {
        it("returns same instance on multiple calls", () => {
            const instance1 = SessionHibernationService.getInstance();
            const instance2 = SessionHibernationService.getInstance();
            expect(instance1).toBe(instance2);
        });
        it("instance extends EventEmitter", () => {
            expect(typeof service.on).toBe("function");
            expect(typeof service.emit).toBe("function");
        });
    });
    describe("Session Registration", () => {
        it("registers session with ACTIVE state", () => {
            const metrics = service.registerSession("session-1", "user-1", "workspace-1");
            expect(metrics.sessionId).toBe("session-1");
            expect(metrics.state).toBe(HibernationState.ACTIVE);
        });
        it("records initial activity time", () => {
            service.registerSession("session-2", "user-2", "workspace-2");
            const idleDuration = service.getIdleDuration("session-2");
            expect(idleDuration).toBeGreaterThanOrEqual(0);
            expect(idleDuration).toBeLessThan(100);
        });
        it("emits sessionRegistered event", () => {
            const listener = vi.fn();
            service.on("sessionRegistered", listener);
            service.registerSession("session-3", "user-3", "workspace-3");
            expect(listener).toHaveBeenCalledWith(expect.objectContaining({
                sessionId: "session-3",
                userId: "user-3",
            }));
        });
        it("initializes metrics for session", () => {
            service.registerSession("session-4", "user-4", "workspace-4");
            const metrics = service.getMetrics("session-4");
            expect(metrics).toBeDefined();
            expect(metrics?.ramSaved).toBe(0);
            expect(metrics?.checkpointSize).toBe(0);
        });
    });
    describe("Activity Recording", () => {
        beforeEach(() => {
            service.registerSession("session-5", "user-5", "workspace-5");
        });
        it("updates last activity time", () => {
            const before = service.getIdleDuration("session-5");
            // Wait a bit then record activity
            return new Promise((resolve) => {
                setTimeout(() => {
                    service.recordActivity("session-5");
                    const after = service.getIdleDuration("session-5");
                    expect(after).toBeLessThan(before + 100);
                    resolve(undefined);
                }, 50);
            });
        });
        it("resets session to ACTIVE state from IDLE", () => {
            service.recordActivity("session-5");
            const state = service.getSessionState("session-5");
            expect(state).toBe(HibernationState.ACTIVE);
        });
        it("emits sessionActivityResumed event when resuming from IDLE", () => {
            const listener = vi.fn();
            service.on("sessionActivityResumed", listener);
            // Manually set to IDLE for testing
            service["sessionStates"].set("session-5", HibernationState.IDLE);
            service.recordActivity("session-5");
            expect(listener).toHaveBeenCalled();
        });
    });
    describe("Idle Detection", () => {
        beforeEach(() => {
            service.registerSession("session-6", "user-6", "workspace-6");
        });
        it("returns false for non-idle session", () => {
            const isIdle = service.isSessionIdle("session-6");
            expect(isIdle).toBe(false);
        });
        it("detects idle after threshold", () => {
            // Set custom idle threshold to 100ms for testing
            service.updateIdleConfig({ idleThresholdMs: 100 });
            // Wait for idle threshold
            return new Promise((resolve) => {
                setTimeout(() => {
                    const isIdle = service.isSessionIdle("session-6");
                    expect(isIdle).toBe(true);
                    resolve(undefined);
                }, 150);
            });
        });
        it("calculates idle duration correctly", () => {
            const idleDuration = service.getIdleDuration("session-6");
            expect(idleDuration).toBeGreaterThanOrEqual(0);
            expect(idleDuration).toBeLessThan(100);
        });
        it("returns 0 for unregistered session", () => {
            const idleDuration = service.getIdleDuration("unknown");
            expect(idleDuration).toBe(0);
        });
    });
    describe("Checkpoint Creation", () => {
        beforeEach(() => {
            service.registerSession("session-7", "user-7", "workspace-7");
        });
        it("creates checkpoint with workspace state", () => {
            const checkpoint = service.createCheckpoint("session-7", {
                files: new Map([["file.ts", "console.log('test')"]]),
                terminals: [{ id: "term-1", name: "bash", history: [], cwd: "/home" }],
                debugState: { breakpoints: [], watches: [], stack: [], variables: {} },
                editorState: { activeFile: "file.ts", scrollPosition: {}, selections: {}, folds: {} },
                settings: {},
                ramUsage: 1024 * 1024 * 100, // 100MB
            });
            expect(checkpoint.id).toBeDefined();
            expect(checkpoint.sessionId).toBe("session-7");
            expect(checkpoint.files.size).toBe(1);
        });
        it("calculates 80% RAM saved", () => {
            const ramUsage = 1024 * 1024 * 100; // 100MB
            service.createCheckpoint("session-7", {
                files: new Map(),
                terminals: [],
                debugState: { breakpoints: [], watches: [], stack: [], variables: {} },
                editorState: { activeFile: "", scrollPosition: {}, selections: {}, folds: {} },
                settings: {},
                ramUsage,
            });
            const metrics = service.getMetrics("session-7");
            expect(metrics?.ramSaved).toBe(Math.floor(ramUsage * 0.8));
        });
        it("emits checkpointCreated event", () => {
            const listener = vi.fn();
            service.on("checkpointCreated", listener);
            service.createCheckpoint("session-7", {
                files: new Map(),
                terminals: [],
                debugState: { breakpoints: [], watches: [], stack: [], variables: {} },
                editorState: { activeFile: "", scrollPosition: {}, selections: {}, folds: {} },
                settings: {},
                ramUsage: 0,
            });
            expect(listener).toHaveBeenCalled();
        });
        it("preserves terminal history", () => {
            const terminalHistory = ["ls", "cd /home", "pwd"];
            const checkpoint = service.createCheckpoint("session-7", {
                files: new Map(),
                terminals: [
                    { id: "term-1", name: "bash", history: terminalHistory, cwd: "/home" },
                ],
                debugState: { breakpoints: [], watches: [], stack: [], variables: {} },
                editorState: { activeFile: "", scrollPosition: {}, selections: {}, folds: {} },
                settings: {},
                ramUsage: 0,
            });
            expect(checkpoint.terminals[0].history).toEqual(terminalHistory);
        });
        it("preserves debug state", () => {
            const debugState = {
                breakpoints: [{ file: "app.ts", line: 42 }],
                watches: ["myVar"],
                stack: [],
                variables: { myVar: 123 },
            };
            const checkpoint = service.createCheckpoint("session-7", {
                files: new Map(),
                terminals: [],
                debugState,
                editorState: { activeFile: "", scrollPosition: {}, selections: {}, folds: {} },
                settings: {},
                ramUsage: 0,
            });
            expect(checkpoint.debugState).toEqual(debugState);
        });
    });
    describe("Hibernation", () => {
        beforeEach(() => {
            service.registerSession("session-8", "user-8", "workspace-8");
        });
        it("transitions session to HIBERNATING state", () => {
            service.hibernate("session-8");
            const state = service.getSessionState("session-8");
            expect(state).toBe(HibernationState.HIBERNATING);
        });
        it("emits hibernationStarted event", () => {
            const listener = vi.fn();
            service.on("hibernationStarted", listener);
            service.hibernate("session-8");
            expect(listener).toHaveBeenCalled();
        });
        it("transitions to HIBERNATED after delay", () => {
            return new Promise((resolve) => {
                service.hibernate("session-8");
                setTimeout(() => {
                    const state = service.getSessionState("session-8");
                    expect(state).toBe(HibernationState.HIBERNATED);
                    resolve(undefined);
                }, 200);
            });
        });
        it("throws error for unregistered session", () => {
            expect(() => {
                service.hibernate("unknown");
            }).toThrow();
        });
    });
    describe("Wake from Hibernation", () => {
        beforeEach(() => {
            service.registerSession("session-9", "user-9", "workspace-9");
        });
        it("transitions to WAKING state", () => {
            // First hibernate the session
            service["sessionStates"].set("session-9", HibernationState.HIBERNATED);
            service.wake("session-9");
            const state = service.getSessionState("session-9");
            expect(state).toBe(HibernationState.WAKING);
        });
        it("completes wake in less than 5 seconds", () => {
            service["sessionStates"].set("session-9", HibernationState.HIBERNATED);
            return new Promise((resolve) => {
                service.wake("session-9");
                setTimeout(() => {
                    const metrics = service.getMetrics("session-9");
                    expect(metrics?.wakeTimeMs).toBeLessThan(5000);
                    resolve(undefined);
                }, 3500);
            });
        });
        it("emits wakeStarted and sessionWoken events", () => {
            service["sessionStates"].set("session-9", HibernationState.HIBERNATED);
            const startListener = vi.fn();
            const wokeListener = vi.fn();
            service.on("wakeStarted", startListener);
            service.on("sessionWoken", wokeListener);
            service.wake("session-9");
            expect(startListener).toHaveBeenCalled();
            return new Promise((resolve) => {
                setTimeout(() => {
                    expect(wokeListener).toHaveBeenCalled();
                    resolve(undefined);
                }, 3500);
            });
        });
        it("throws error if session not hibernated", () => {
            expect(() => {
                service.wake("session-9");
            }).toThrow("not hibernated");
        });
    });
    describe("Checkpoint Management", () => {
        beforeEach(() => {
            service.registerSession("session-10", "user-10", "workspace-10");
        });
        it("retrieves checkpoint by ID", () => {
            const created = service.createCheckpoint("session-10", {
                files: new Map(),
                terminals: [],
                debugState: { breakpoints: [], watches: [], stack: [], variables: {} },
                editorState: { activeFile: "", scrollPosition: {}, selections: {}, folds: {} },
                settings: {},
                ramUsage: 0,
            });
            const retrieved = service.getCheckpoint(created.id);
            expect(retrieved?.id).toBe(created.id);
        });
        it("restores checkpoint", () => {
            const checkpoint = service.createCheckpoint("session-10", {
                files: new Map([["test.ts", "code"]]),
                terminals: [],
                debugState: { breakpoints: [], watches: [], stack: [], variables: {} },
                editorState: { activeFile: "", scrollPosition: {}, selections: {}, folds: {} },
                settings: {},
                ramUsage: 0,
            });
            const restored = service.restoreCheckpoint("session-10", checkpoint.id);
            expect(restored.files.size).toBe(1);
        });
        it("emits checkpointRestored event", () => {
            const listener = vi.fn();
            service.on("checkpointRestored", listener);
            const checkpoint = service.createCheckpoint("session-10", {
                files: new Map(),
                terminals: [],
                debugState: { breakpoints: [], watches: [], stack: [], variables: {} },
                editorState: { activeFile: "", scrollPosition: {}, selections: {}, folds: {} },
                settings: {},
                ramUsage: 0,
            });
            service.restoreCheckpoint("session-10", checkpoint.id);
            expect(listener).toHaveBeenCalled();
        });
        it("deletes checkpoint", () => {
            const checkpoint = service.createCheckpoint("session-10", {
                files: new Map(),
                terminals: [],
                debugState: { breakpoints: [], watches: [], stack: [], variables: {} },
                editorState: { activeFile: "", scrollPosition: {}, selections: {}, folds: {} },
                settings: {},
                ramUsage: 0,
            });
            const deleted = service.deleteCheckpoint(checkpoint.id);
            expect(deleted).toBe(true);
            const retrieved = service.getCheckpoint(checkpoint.id);
            expect(retrieved).toBeUndefined();
        });
        it("emits checkpointDeleted event", () => {
            const listener = vi.fn();
            service.on("checkpointDeleted", listener);
            const checkpoint = service.createCheckpoint("session-10", {
                files: new Map(),
                terminals: [],
                debugState: { breakpoints: [], watches: [], stack: [], variables: {} },
                editorState: { activeFile: "", scrollPosition: {}, selections: {}, folds: {} },
                settings: {},
                ramUsage: 0,
            });
            service.deleteCheckpoint(checkpoint.id);
            expect(listener).toHaveBeenCalled();
        });
    });
    describe("Configuration", () => {
        it("returns default idle configuration", () => {
            const config = service.getIdleConfig();
            expect(config.idleThresholdMs).toBe(5 * 60 * 1000);
            expect(config.checkIntervalMs).toBe(30 * 1000);
            expect(config.enableAutoHibernation).toBe(true);
        });
        it("updates idle configuration", () => {
            service.updateIdleConfig({ idleThresholdMs: 1000 });
            const config = service.getIdleConfig();
            expect(config.idleThresholdMs).toBe(1000);
        });
        it("preserves unmodified config values", () => {
            service.updateIdleConfig({ idleThresholdMs: 2000 });
            const config = service.getIdleConfig();
            expect(config.checkIntervalMs).toBe(30 * 1000); // unchanged
        });
    });
    describe("Session State", () => {
        it("returns undefined for unregistered session", () => {
            const state = service.getSessionState("unknown");
            expect(state).toBeUndefined();
        });
        it("returns ACTIVE for newly registered session", () => {
            service.registerSession("session-11", "user-11", "workspace-11");
            const state = service.getSessionState("session-11");
            expect(state).toBe(HibernationState.ACTIVE);
        });
    });
    describe("Statistics", () => {
        it("returns zero statistics for empty service", () => {
            const stats = service.getStatistics();
            expect(stats.totalSessions).toBe(0);
            expect(stats.activeSessions).toBe(0);
            expect(stats.totalRamSaved).toBe(0);
        });
        it("counts sessions by state", () => {
            service.registerSession("session-12", "user-12", "workspace-12");
            service.registerSession("session-13", "user-13", "workspace-13");
            const stats = service.getStatistics();
            expect(stats.totalSessions).toBe(2);
            expect(stats.activeSessions).toBe(2);
        });
        it("sums total RAM saved", () => {
            service.registerSession("session-14", "user-14", "workspace-14");
            service.createCheckpoint("session-14", {
                files: new Map(),
                terminals: [],
                debugState: { breakpoints: [], watches: [], stack: [], variables: {} },
                editorState: { activeFile: "", scrollPosition: {}, selections: {}, folds: {} },
                settings: {},
                ramUsage: 1024 * 1024 * 100, // 100MB
            });
            const stats = service.getStatistics();
            expect(stats.totalRamSaved).toBeGreaterThan(0);
        });
        it("calculates average wake time", () => {
            service.registerSession("session-15", "user-15", "workspace-15");
            const metrics = service.getMetrics("session-15");
            if (metrics) {
                metrics.wakeTimeMs = 1500;
            }
            const stats = service.getStatistics();
            expect(stats.averageWakeTime).toBeGreaterThan(0);
        });
    });
    describe("Session Listing", () => {
        it("returns empty list for no sessions", () => {
            const sessions = service.getAllSessions();
            expect(sessions.length).toBe(0);
        });
        it("lists all registered sessions with state", () => {
            service.registerSession("session-16", "user-16", "workspace-16");
            service.registerSession("session-17", "user-17", "workspace-17");
            const sessions = service.getAllSessions();
            expect(sessions.length).toBe(2);
            expect(sessions[0].state).toBe(HibernationState.ACTIVE);
        });
    });
    describe("Monitoring", () => {
        it("starts monitoring interval", () => {
            service.startMonitoring();
            expect(service["monitoringInterval"]).toBeDefined();
        });
        it("stops monitoring interval", () => {
            service.startMonitoring();
            service.stopMonitoring();
            expect(service["monitoringInterval"]).toBeNull();
        });
        it("does not start multiple monitoring intervals", () => {
            service.startMonitoring();
            const first = service["monitoringInterval"];
            service.startMonitoring();
            const second = service["monitoringInterval"];
            expect(first).toBe(second);
            service.stopMonitoring();
        });
    });
});
//# sourceMappingURL=session-hibernation-service.test.js.map