#!/usr/bin/env node
/**
 * @file        apps/backend/src/services/session/session-hibernation-service.ts
 * @module      session/hibernation
 * @description Session hibernation service for idle workspace checkpointing and restoration
 *
 */
import { EventEmitter } from "events";
import { getLogger } from "../../lib/logger";
const logger = getLogger("session-hibernation");
/**
 * Hibernation state enumeration
 */
export var HibernationState;
(function (HibernationState) {
    HibernationState["ACTIVE"] = "active";
    HibernationState["IDLE"] = "idle";
    HibernationState["HIBERNATING"] = "hibernating";
    HibernationState["HIBERNATED"] = "hibernated";
    HibernationState["WAKING"] = "waking";
})(HibernationState || (HibernationState = {}));
/**
 * SessionHibernationService manages workspace hibernation and restoration
 */
export class SessionHibernationService extends EventEmitter {
    constructor() {
        super();
        this.sessionStates = new Map();
        this.lastActivityTimes = new Map();
        this.checkpoints = new Map();
        this.metrics = new Map();
        this.monitoringInterval = null;
        this.hibernationTimers = new Map();
        this.idleConfig = {
            idleThresholdMs: 5 * 60 * 1000, // 5 minutes
            checkIntervalMs: 30 * 1000, // 30 seconds
            hibernationDelayMs: 10 * 1000, // 10 seconds after idle detected
            enableAutoHibernation: true,
        };
    }
    /**
     * Get or create singleton instance
     */
    static getInstance() {
        if (!SessionHibernationService.instance) {
            SessionHibernationService.instance = new SessionHibernationService();
        }
        return SessionHibernationService.instance;
    }
    /**
     * Register a session for hibernation monitoring
     */
    registerSession(sessionId, userId, workspaceId) {
        this.sessionStates.set(sessionId, HibernationState.ACTIVE);
        this.lastActivityTimes.set(sessionId, Date.now());
        const metrics = {
            sessionId,
            state: HibernationState.ACTIVE,
            lastActivityTime: Date.now(),
            ramSaved: 0,
            idleDurationMs: 0,
            checkpointSize: 0,
        };
        this.metrics.set(sessionId, metrics);
        this.emit("sessionRegistered", { sessionId, userId, workspaceId });
        logger.info(`Session registered for hibernation`, { sessionId, userId });
        return metrics;
    }
    /**
     * Record activity on a session (resets idle timer)
     */
    recordActivity(sessionId) {
        const currentState = this.sessionStates.get(sessionId);
        if (currentState === HibernationState.HIBERNATED) {
            // Session is hibernated, don't just record activity - wake it
            return;
        }
        this.lastActivityTimes.set(sessionId, Date.now());
        const currentMetrics = this.metrics.get(sessionId);
        if (currentMetrics) {
            currentMetrics.lastActivityTime = Date.now();
            currentMetrics.state = HibernationState.ACTIVE;
        }
        // Clear any pending hibernation timer
        const timer = this.hibernationTimers.get(sessionId);
        if (timer) {
            clearTimeout(timer);
            this.hibernationTimers.delete(sessionId);
        }
        if (currentState === HibernationState.IDLE) {
            this.sessionStates.set(sessionId, HibernationState.ACTIVE);
            this.emit("sessionActivityResumed", { sessionId });
        }
    }
    /**
     * Create checkpoint for session (simulate CRIU checkpoint)
     */
    createCheckpoint(sessionId, workspaceState) {
        const enforcement = this.metrics.get(sessionId);
        if (!enforcement) {
            throw new Error(`Session not registered: ${sessionId}`);
        }
        const checkpoint = {
            id: `hib-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
            sessionId,
            userId: "", // Should be passed from caller
            workspaceId: "", // Should be passed from caller
            timestamp: Date.now(),
            files: workspaceState.files || new Map(),
            terminals: workspaceState.terminals || [],
            debugState: workspaceState.debugState || {
                breakpoints: [],
                watches: [],
                stack: [],
                variables: {},
            },
            editorState: workspaceState.editorState || {
                activeFile: "",
                scrollPosition: {},
                selections: {},
                folds: {},
            },
            settings: workspaceState.settings || {},
            ramUsageBefore: workspaceState.ramUsage || 0,
        };
        this.checkpoints.set(checkpoint.id, checkpoint);
        const metrics = this.metrics.get(sessionId);
        if (metrics) {
            metrics.checkpointId = checkpoint.id;
            metrics.checkpointSize = this.estimateCheckpointSize(checkpoint);
            metrics.ramSaved = Math.floor(checkpoint.ramUsageBefore * 0.8); // 80% RAM saved
        }
        this.emit("checkpointCreated", { sessionId, checkpointId: checkpoint.id });
        logger.info(`Checkpoint created for session ${sessionId}`, {
            checkpointId: checkpoint.id,
            ramSaved: metrics?.ramSaved,
        });
        return checkpoint;
    }
    /**
     * Hibernate a session (move to HIBERNATED state)
     */
    hibernate(sessionId) {
        const state = this.sessionStates.get(sessionId);
        if (!state) {
            throw new Error(`Session not registered: ${sessionId}`);
        }
        this.sessionStates.set(sessionId, HibernationState.HIBERNATING);
        const metrics = this.metrics.get(sessionId);
        if (!metrics) {
            throw new Error(`Metrics not found for session: ${sessionId}`);
        }
        metrics.state = HibernationState.HIBERNATING;
        // Simulate hibernation delay (checkpoint is created and workspace is suspended)
        setTimeout(() => {
            this.sessionStates.set(sessionId, HibernationState.HIBERNATED);
            const updatedMetrics = this.metrics.get(sessionId);
            if (updatedMetrics) {
                updatedMetrics.state = HibernationState.HIBERNATED;
                updatedMetrics.hibernatedAt = Date.now();
            }
            this.emit("sessionHibernated", { sessionId });
            logger.info(`Session hibernated`, {
                sessionId,
                checkpointId: metrics.checkpointId,
            });
        }, 100);
        this.emit("hibernationStarted", { sessionId });
        return metrics;
    }
    /**
     * Wake a hibernated session (< 5 seconds)
     */
    wake(sessionId) {
        const state = this.sessionStates.get(sessionId);
        if (state !== HibernationState.HIBERNATED) {
            throw new Error(`Session is not hibernated: ${sessionId}`);
        }
        this.sessionStates.set(sessionId, HibernationState.WAKING);
        const metrics = this.metrics.get(sessionId);
        if (!metrics) {
            throw new Error(`Metrics not found for session: ${sessionId}`);
        }
        const wakeStartTime = Date.now();
        metrics.state = HibernationState.WAKING;
        // Simulate wake process (restore checkpoint) - target < 5 seconds
        const wakeTimeMs = Math.random() * 3000 + 500; // 500ms - 3.5s
        setTimeout(() => {
            this.sessionStates.set(sessionId, HibernationState.ACTIVE);
            const updatedMetrics = this.metrics.get(sessionId);
            if (updatedMetrics) {
                updatedMetrics.state = HibernationState.ACTIVE;
                updatedMetrics.wakedAt = Date.now();
                updatedMetrics.wakeTimeMs = wakeTimeMs;
            }
            this.lastActivityTimes.set(sessionId, Date.now());
            this.emit("sessionWoken", { sessionId, wakeTimeMs });
            logger.info(`Session woken`, { sessionId, wakeTimeMs: `${wakeTimeMs}ms` });
        }, wakeTimeMs);
        this.emit("wakeStarted", { sessionId });
        return metrics;
    }
    /**
     * Check if session is idle
     */
    isSessionIdle(sessionId) {
        const lastActivity = this.lastActivityTimes.get(sessionId);
        if (!lastActivity) {
            return false;
        }
        const idleDuration = Date.now() - lastActivity;
        return idleDuration >= this.idleConfig.idleThresholdMs;
    }
    /**
     * Get idle duration for session
     */
    getIdleDuration(sessionId) {
        const lastActivity = this.lastActivityTimes.get(sessionId);
        if (!lastActivity) {
            return 0;
        }
        return Date.now() - lastActivity;
    }
    /**
     * Get session state
     */
    getSessionState(sessionId) {
        return this.sessionStates.get(sessionId);
    }
    /**
     * Get hibernation metrics for session
     */
    getMetrics(sessionId) {
        return this.metrics.get(sessionId);
    }
    /**
     * Get checkpoint for session
     */
    getCheckpoint(checkpointId) {
        return this.checkpoints.get(checkpointId);
    }
    /**
     * Restore checkpoint to workspace
     */
    restoreCheckpoint(sessionId, checkpointId) {
        const checkpoint = this.checkpoints.get(checkpointId);
        if (!checkpoint) {
            throw new Error(`Checkpoint not found: ${checkpointId}`);
        }
        if (checkpoint.sessionId !== sessionId) {
            throw new Error(`Checkpoint does not belong to session: ${sessionId}`);
        }
        this.emit("checkpointRestored", { sessionId, checkpointId });
        logger.info(`Checkpoint restored for session ${sessionId}`, {
            checkpointId,
        });
        return checkpoint;
    }
    /**
     * Delete checkpoint (cleanup)
     */
    deleteCheckpoint(checkpointId) {
        const removed = this.checkpoints.delete(checkpointId);
        if (removed) {
            this.emit("checkpointDeleted", { checkpointId });
            logger.info(`Checkpoint deleted`, { checkpointId });
        }
        return removed;
    }
    /**
     * Update idle configuration
     */
    updateIdleConfig(config) {
        this.idleConfig = { ...this.idleConfig, ...config };
        logger.info("Idle configuration updated", this.idleConfig);
        return this.idleConfig;
    }
    /**
     * Get idle configuration
     */
    getIdleConfig() {
        return { ...this.idleConfig };
    }
    /**
     * Start monitoring for idle sessions
     */
    startMonitoring() {
        if (this.monitoringInterval) {
            return;
        }
        this.monitoringInterval = setInterval(() => {
            const sessions = Array.from(this.sessionStates.entries());
            sessions.forEach(([sessionId, state]) => {
                if (state === HibernationState.ACTIVE && this.isSessionIdle(sessionId)) {
                    const idleDuration = this.getIdleDuration(sessionId);
                    // Transition to IDLE
                    this.sessionStates.set(sessionId, HibernationState.IDLE);
                    const metrics = this.metrics.get(sessionId);
                    if (metrics) {
                        metrics.state = HibernationState.IDLE;
                        metrics.idleDurationMs = idleDuration;
                    }
                    this.emit("sessionIdleDetected", { sessionId, idleDuration });
                    // Schedule hibernation
                    if (this.idleConfig.enableAutoHibernation) {
                        const timer = setTimeout(() => {
                            this.hibernate(sessionId);
                        }, this.idleConfig.hibernationDelayMs);
                        this.hibernationTimers.set(sessionId, timer);
                    }
                }
            });
        }, this.idleConfig.checkIntervalMs);
        logger.info(`Hibernation monitoring started`);
    }
    /**
     * Stop monitoring
     */
    stopMonitoring() {
        if (this.monitoringInterval) {
            clearInterval(this.monitoringInterval);
            this.monitoringInterval = null;
            logger.info("Hibernation monitoring stopped");
        }
    }
    /**
     * Get all active sessions
     */
    getAllSessions() {
        const sessions = [];
        this.sessionStates.forEach((state, sessionId) => {
            sessions.push({ sessionId, state });
        });
        return sessions;
    }
    /**
     * Get statistics
     */
    getStatistics() {
        const metricsArray = Array.from(this.metrics.values());
        const activeSessions = Array.from(this.sessionStates.values()).filter((s) => s === HibernationState.ACTIVE).length;
        const idleSessions = Array.from(this.sessionStates.values()).filter((s) => s === HibernationState.IDLE).length;
        const hibernatedSessions = Array.from(this.sessionStates.values()).filter((s) => s === HibernationState.HIBERNATED).length;
        const totalRamSaved = metricsArray.reduce((sum, m) => sum + m.ramSaved, 0);
        const wakeTimes = metricsArray
            .filter((m) => m.wakeTimeMs !== undefined)
            .map((m) => m.wakeTimeMs || 0);
        const averageWakeTime = wakeTimes.length > 0
            ? wakeTimes.reduce((a, b) => a + b) / wakeTimes.length
            : 0;
        return {
            totalSessions: this.sessionStates.size,
            activeSessions,
            idleSessions,
            hibernatedSessions,
            totalRamSaved,
            averageWakeTime,
        };
    }
    /**
     * Estimate checkpoint size in bytes
     */
    estimateCheckpointSize(checkpoint) {
        let size = 0;
        // Estimate files size
        if (checkpoint.files) {
            checkpoint.files.forEach((content) => {
                size += content.length;
            });
        }
        // Estimate terminals size
        if (checkpoint.terminals) {
            checkpoint.terminals.forEach((terminal) => {
                size += terminal.history.join("").length;
            });
        }
        // Estimate debug state size
        size += JSON.stringify(checkpoint.debugState).length;
        size += JSON.stringify(checkpoint.editorState).length;
        size += JSON.stringify(checkpoint.settings).length;
        return size;
    }
    /**
     * Reset service for testing
     */
    reset() {
        this.stopMonitoring();
        this.sessionStates.clear();
        this.lastActivityTimes.clear();
        this.checkpoints.clear();
        this.metrics.clear();
        this.hibernationTimers.forEach((timer) => clearTimeout(timer));
        this.hibernationTimers.clear();
        this.removeAllListeners();
        logger.debug("Session hibernation service reset");
    }
}
SessionHibernationService.instance = null;
export default SessionHibernationService.getInstance();
//# sourceMappingURL=session-hibernation-service.js.map