#!/usr/bin/env node
/**
 * @file        apps/backend/src/routes/session-hibernation.ts
 * @module      routes/session-hibernation
 * @description HTTP routes for session hibernation management
 *
 */
import { Router } from "express";
import { getLogger } from "../lib/logger";
import SessionHibernationService from "../services/session/session-hibernation-service";
const logger = getLogger("session-hibernation-routes");
const router = Router();
const hibernationService = SessionHibernationService.getInstance();
/**
 * POST /session-hibernation/register
 * Register a session for hibernation monitoring
 */
router.post("/register", (req, res) => {
    try {
        const { sessionId, userId, workspaceId } = req.body;
        if (!sessionId || !userId || !workspaceId) {
            return res.status(400).json({
                error: "Missing required fields: sessionId, userId, workspaceId",
            });
        }
        const metrics = hibernationService.registerSession(sessionId, userId, workspaceId);
        res.status(201).json({
            success: true,
            data: metrics,
        });
    }
    catch (error) {
        logger.error("Error registering session", { error });
        res.status(500).json({
            error: "Failed to register session",
            details: error instanceof Error ? error.message : "Unknown error",
        });
    }
});
/**
 * POST /session-hibernation/:sessionId/activity
 * Record activity on a session
 */
router.post("/:sessionId/activity", (req, res) => {
    try {
        const { sessionId } = req.params;
        hibernationService.recordActivity(sessionId);
        res.status(200).json({
            success: true,
            message: "Activity recorded",
        });
    }
    catch (error) {
        logger.error("Error recording activity", { error });
        res.status(500).json({
            error: "Failed to record activity",
            details: error instanceof Error ? error.message : "Unknown error",
        });
    }
});
/**
 * POST /session-hibernation/:sessionId/checkpoint
 * Create a checkpoint for a session
 */
router.post("/:sessionId/checkpoint", (req, res) => {
    try {
        const { sessionId } = req.params;
        const { files, terminals, debugState, editorState, settings, ramUsage } = req.body;
        const checkpoint = hibernationService.createCheckpoint(sessionId, {
            files: new Map(files || []),
            terminals: terminals || [],
            debugState: debugState || { breakpoints: [], watches: [], stack: [], variables: {} },
            editorState: editorState || {
                activeFile: "",
                scrollPosition: {},
                selections: {},
                folds: {},
            },
            settings: settings || {},
            ramUsage: ramUsage || 0,
        });
        res.status(201).json({
            success: true,
            data: checkpoint,
        });
    }
    catch (error) {
        logger.error("Error creating checkpoint", { error });
        res.status(500).json({
            error: "Failed to create checkpoint",
            details: error instanceof Error ? error.message : "Unknown error",
        });
    }
});
/**
 * POST /session-hibernation/:sessionId/hibernate
 * Hibernate a session
 */
router.post("/:sessionId/hibernate", (req, res) => {
    try {
        const { sessionId } = req.params;
        const metrics = hibernationService.hibernate(sessionId);
        res.status(200).json({
            success: true,
            data: metrics,
            message: "Hibernation started, will complete shortly",
        });
    }
    catch (error) {
        logger.error("Error hibernating session", { error });
        res.status(500).json({
            error: "Failed to hibernate session",
            details: error instanceof Error ? error.message : "Unknown error",
        });
    }
});
/**
 * POST /session-hibernation/:sessionId/wake
 * Wake a hibernated session (< 5 seconds)
 */
router.post("/:sessionId/wake", (req, res) => {
    try {
        const { sessionId } = req.params;
        const metrics = hibernationService.wake(sessionId);
        res.status(200).json({
            success: true,
            data: metrics,
            message: "Wake process started, session will be available shortly",
        });
    }
    catch (error) {
        logger.error("Error waking session", { error });
        res.status(400).json({
            error: "Failed to wake session",
            details: error instanceof Error ? error.message : "Unknown error",
        });
    }
});
/**
 * GET /session-hibernation/:sessionId/state
 * Get hibernation state of a session
 */
router.get("/:sessionId/state", (req, res) => {
    try {
        const { sessionId } = req.params;
        const state = hibernationService.getSessionState(sessionId);
        const metrics = hibernationService.getMetrics(sessionId);
        if (!state) {
            return res.status(404).json({
                error: "Session not registered for hibernation",
            });
        }
        res.status(200).json({
            success: true,
            data: {
                sessionId,
                state,
                metrics,
            },
        });
    }
    catch (error) {
        logger.error("Error retrieving session state", { error });
        res.status(500).json({
            error: "Failed to retrieve session state",
            details: error instanceof Error ? error.message : "Unknown error",
        });
    }
});
/**
 * GET /session-hibernation/:sessionId/metrics
 * Get hibernation metrics for a session
 */
router.get("/:sessionId/metrics", (req, res) => {
    try {
        const { sessionId } = req.params;
        const metrics = hibernationService.getMetrics(sessionId);
        if (!metrics) {
            return res.status(404).json({
                error: "Metrics not found for session",
            });
        }
        res.status(200).json({
            success: true,
            data: metrics,
        });
    }
    catch (error) {
        logger.error("Error retrieving metrics", { error });
        res.status(500).json({
            error: "Failed to retrieve metrics",
            details: error instanceof Error ? error.message : "Unknown error",
        });
    }
});
/**
 * GET /session-hibernation/:sessionId/checkpoint/:checkpointId
 * Get checkpoint details
 */
router.get("/:sessionId/checkpoint/:checkpointId", (req, res) => {
    try {
        const { sessionId, checkpointId } = req.params;
        const checkpoint = hibernationService.getCheckpoint(checkpointId);
        if (!checkpoint) {
            return res.status(404).json({
                error: "Checkpoint not found",
            });
        }
        if (checkpoint.sessionId !== sessionId) {
            return res.status(403).json({
                error: "Checkpoint does not belong to this session",
            });
        }
        res.status(200).json({
            success: true,
            data: checkpoint,
        });
    }
    catch (error) {
        logger.error("Error retrieving checkpoint", { error });
        res.status(500).json({
            error: "Failed to retrieve checkpoint",
            details: error instanceof Error ? error.message : "Unknown error",
        });
    }
});
/**
 * POST /session-hibernation/:sessionId/checkpoint/:checkpointId/restore
 * Restore a checkpoint
 */
router.post("/:sessionId/checkpoint/:checkpointId/restore", (req, res) => {
    try {
        const { sessionId, checkpointId } = req.params;
        const checkpoint = hibernationService.restoreCheckpoint(sessionId, checkpointId);
        res.status(200).json({
            success: true,
            data: checkpoint,
            message: "Checkpoint restored successfully",
        });
    }
    catch (error) {
        logger.error("Error restoring checkpoint", { error });
        res.status(400).json({
            error: "Failed to restore checkpoint",
            details: error instanceof Error ? error.message : "Unknown error",
        });
    }
});
/**
 * DELETE /session-hibernation/:sessionId/checkpoint/:checkpointId
 * Delete a checkpoint
 */
router.delete("/:sessionId/checkpoint/:checkpointId", (req, res) => {
    try {
        const { checkpointId } = req.params;
        const deleted = hibernationService.deleteCheckpoint(checkpointId);
        if (!deleted) {
            return res.status(404).json({
                error: "Checkpoint not found",
            });
        }
        res.status(204).send();
    }
    catch (error) {
        logger.error("Error deleting checkpoint", { error });
        res.status(500).json({
            error: "Failed to delete checkpoint",
            details: error instanceof Error ? error.message : "Unknown error",
        });
    }
});
/**
 * GET /session-hibernation/:sessionId/idle-duration
 * Get idle duration for a session
 */
router.get("/:sessionId/idle-duration", (req, res) => {
    try {
        const { sessionId } = req.params;
        const idleDuration = hibernationService.getIdleDuration(sessionId);
        res.status(200).json({
            success: true,
            data: {
                sessionId,
                idleDurationMs: idleDuration,
                isIdle: hibernationService.isSessionIdle(sessionId),
            },
        });
    }
    catch (error) {
        logger.error("Error calculating idle duration", { error });
        res.status(500).json({
            error: "Failed to calculate idle duration",
            details: error instanceof Error ? error.message : "Unknown error",
        });
    }
});
/**
 * GET /session-hibernation/config/idle
 * Get idle configuration
 */
router.get("/config/idle", (req, res) => {
    try {
        const config = hibernationService.getIdleConfig();
        res.status(200).json({
            success: true,
            data: config,
        });
    }
    catch (error) {
        logger.error("Error retrieving idle config", { error });
        res.status(500).json({
            error: "Failed to retrieve idle config",
            details: error instanceof Error ? error.message : "Unknown error",
        });
    }
});
/**
 * PATCH /session-hibernation/config/idle
 * Update idle configuration
 */
router.patch("/config/idle", (req, res) => {
    try {
        const config = hibernationService.updateIdleConfig(req.body);
        res.status(200).json({
            success: true,
            data: config,
        });
    }
    catch (error) {
        logger.error("Error updating idle config", { error });
        res.status(500).json({
            error: "Failed to update idle config",
            details: error instanceof Error ? error.message : "Unknown error",
        });
    }
});
/**
 * GET /session-hibernation/stats
 * Get hibernation statistics
 */
router.get("/stats", (req, res) => {
    try {
        const stats = hibernationService.getStatistics();
        res.status(200).json({
            success: true,
            data: stats,
        });
    }
    catch (error) {
        logger.error("Error retrieving statistics", { error });
        res.status(500).json({
            error: "Failed to retrieve statistics",
            details: error instanceof Error ? error.message : "Unknown error",
        });
    }
});
/**
 * GET /session-hibernation/sessions/list
 * List all sessions with hibernation state
 */
router.get("/sessions/list", (req, res) => {
    try {
        const sessions = hibernationService.getAllSessions();
        res.status(200).json({
            success: true,
            data: sessions,
            count: sessions.length,
        });
    }
    catch (error) {
        logger.error("Error listing sessions", { error });
        res.status(500).json({
            error: "Failed to list sessions",
            details: error instanceof Error ? error.message : "Unknown error",
        });
    }
});
/**
 * POST /session-hibernation/monitoring/start
 * Start background monitoring
 */
router.post("/monitoring/start", (req, res) => {
    try {
        hibernationService.startMonitoring();
        res.status(200).json({
            success: true,
            message: "Hibernation monitoring started",
        });
    }
    catch (error) {
        logger.error("Error starting monitoring", { error });
        res.status(500).json({
            error: "Failed to start monitoring",
            details: error instanceof Error ? error.message : "Unknown error",
        });
    }
});
/**
 * POST /session-hibernation/monitoring/stop
 * Stop background monitoring
 */
router.post("/monitoring/stop", (req, res) => {
    try {
        hibernationService.stopMonitoring();
        res.status(200).json({
            success: true,
            message: "Hibernation monitoring stopped",
        });
    }
    catch (error) {
        logger.error("Error stopping monitoring", { error });
        res.status(500).json({
            error: "Failed to stop monitoring",
            details: error instanceof Error ? error.message : "Unknown error",
        });
    }
});
export const initializeSessionHibernationRoutes = (app) => {
    app.use("/api/session-hibernation", router);
    logger.info("Session hibernation routes initialized");
};
export default router;
//# sourceMappingURL=session-hibernation.js.map