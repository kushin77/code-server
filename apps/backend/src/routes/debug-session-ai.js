#!/usr/bin/env node
// @file        apps/backend/src/routes/debug-session-ai.ts
// @module      routes/collaboration
// @description REST API endpoints for debug session AI service
import { Router } from 'express';
import service from '../services/debugging/debug-session-ai-service';
import { getLogger } from '../lib/logger';
const logger = getLogger('DebugSessionAIRoutes');
const router = Router();
/**
 * Helper function to serialize session with Maps converted to arrays
 */
const serializeSession = (session) => {
    return {
        ...session,
        breakpoints: Array.from((session.breakpoints || new Map()).entries()).map(([id, bp]) => ({
            id,
            ...bp,
        })),
    };
};
/**
 * Middleware to validate debug session ID
 */
const validateSessionId = (req, res, next) => {
    const sessionId = req.params.sessionId || req.body.sessionId;
    if (!sessionId || typeof sessionId !== 'string') {
        return res.status(400).json({ success: false, error: 'sessionId is required' });
    }
    next();
};
/**
 * POST /api/debug/sessions
 * Start a new debug session
 */
router.post('/sessions', (req, res) => {
    try {
        const { userId, workspaceId, sessionId, type } = req.body;
        if (!userId || !workspaceId || !sessionId || !type) {
            return res.status(400).json({
                success: false,
                error: 'userId, workspaceId, sessionId, and type are required',
            });
        }
        const session = service.startSession(userId, workspaceId, sessionId, type);
        res.status(201).json({
            success: true,
            data: serializeSession(session),
        });
    }
    catch (error) {
        logger.error('Failed to start debug session', error);
        res.status(500).json({
            success: false,
            error: 'Failed to start debug session',
        });
    }
});
/**
 * GET /api/debug/sessions/:sessionId
 * Get a debug session
 */
router.get('/sessions/:sessionId', (req, res) => {
    try {
        const { sessionId } = req.params;
        const session = service.getSession(sessionId);
        if (!session) {
            return res.status(404).json({
                success: false,
                error: 'Debug session not found',
            });
        }
        res.status(200).json({
            success: true,
            data: serializeSession(session),
        });
    }
    catch (error) {
        logger.error('Failed to get debug session', error);
        res.status(500).json({
            success: false,
            error: 'Failed to get debug session',
        });
    }
});
/**
 * PATCH /api/debug/sessions/:sessionId/state
 * Update debug session state
 */
router.patch('/sessions/:sessionId/state', (req, res) => {
    try {
        const { sessionId } = req.params;
        const { state } = req.body;
        if (!state || !['running', 'paused', 'stopped'].includes(state)) {
            return res.status(400).json({
                success: false,
                error: 'state must be one of: running, paused, stopped',
            });
        }
        const session = service.updateSessionState(sessionId, state);
        if (!session) {
            return res.status(404).json({
                success: false,
                error: 'Debug session not found',
            });
        }
        res.status(200).json({
            success: true,
            data: serializeSession(session),
        });
    }
    catch (error) {
        logger.error('Failed to update session state', error);
        res.status(500).json({
            success: false,
            error: 'Failed to update session state',
        });
    }
});
/**
 * POST /api/debug/sessions/:sessionId/breakpoints
 * Set a breakpoint in a session
 */
router.post('/sessions/:sessionId/breakpoints', (req, res) => {
    try {
        const { sessionId } = req.params;
        const { id, file, line, verified } = req.body;
        if (!id || !file || typeof line !== 'number') {
            return res.status(400).json({
                success: false,
                error: 'id, file, and line are required',
            });
        }
        const session = service.setBreakpoint(sessionId, {
            id,
            file,
            line,
            verified: verified ?? false,
        });
        if (!session) {
            return res.status(404).json({
                success: false,
                error: 'Debug session not found',
            });
        }
        res.status(201).json({
            success: true,
            data: serializeSession(session),
        });
    }
    catch (error) {
        logger.error('Failed to set breakpoint', error);
        res.status(500).json({
            success: false,
            error: 'Failed to set breakpoint',
        });
    }
});
/**
 * DELETE /api/debug/sessions/:sessionId/breakpoints/:breakpointId
 * Remove a breakpoint from a session
 */
router.delete('/sessions/:sessionId/breakpoints/:breakpointId', (req, res) => {
    try {
        const { sessionId, breakpointId } = req.params;
        const session = service.removeBreakpoint(sessionId, breakpointId);
        if (!session) {
            return res.status(404).json({
                success: false,
                error: 'Debug session not found',
            });
        }
        res.status(200).json({
            success: true,
            data: serializeSession(session),
        });
    }
    catch (error) {
        logger.error('Failed to remove breakpoint', error);
        res.status(500).json({
            success: false,
            error: 'Failed to remove breakpoint',
        });
    }
});
/**
 * POST /api/debug/sessions/:sessionId/variables
 * Capture variables at a breakpoint
 */
router.post('/sessions/:sessionId/variables', (req, res) => {
    try {
        const { sessionId } = req.params;
        const { breakpointId, variables } = req.body;
        if (!breakpointId || !Array.isArray(variables)) {
            return res.status(400).json({
                success: false,
                error: 'breakpointId and variables array are required',
            });
        }
        const session = service.captureVariables(sessionId, breakpointId, variables);
        if (!session) {
            return res.status(404).json({
                success: false,
                error: 'Debug session or breakpoint not found',
            });
        }
        res.status(201).json({
            success: true,
            data: serializeSession(session),
        });
    }
    catch (error) {
        logger.error('Failed to capture variables', error);
        res.status(500).json({
            success: false,
            error: 'Failed to capture variables',
        });
    }
});
/**
 * POST /api/debug/sessions/:sessionId/stack-frames
 * Capture stack frames
 */
router.post('/sessions/:sessionId/stack-frames', (req, res) => {
    try {
        const { sessionId } = req.params;
        const { stackFrames } = req.body;
        if (!Array.isArray(stackFrames)) {
            return res.status(400).json({
                success: false,
                error: 'stackFrames array is required',
            });
        }
        const session = service.captureStackFrames(sessionId, stackFrames);
        if (!session) {
            return res.status(404).json({
                success: false,
                error: 'Debug session not found',
            });
        }
        res.status(201).json({
            success: true,
            data: serializeSession(session),
        });
    }
    catch (error) {
        logger.error('Failed to capture stack frames', error);
        res.status(500).json({
            success: false,
            error: 'Failed to capture stack frames',
        });
    }
});
/**
 * POST /api/debug/sessions/:sessionId/analyze
 * Analyze root cause of a debugging issue
 */
router.post('/sessions/:sessionId/analyze', (req, res) => {
    try {
        const { sessionId } = req.params;
        const analysis = service.analyzeRootCause(sessionId);
        if (!analysis) {
            return res.status(404).json({
                success: false,
                error: 'Debug session or breakpoint not found',
            });
        }
        res.status(200).json({
            success: true,
            data: analysis,
        });
    }
    catch (error) {
        logger.error('Failed to analyze root cause', error);
        res.status(500).json({
            success: false,
            error: 'Failed to analyze root cause',
        });
    }
});
/**
 * POST /api/debug/sessions/:sessionId/fix-suggestions
 * Generate fix suggestions for a debugging session
 */
router.post('/sessions/:sessionId/fix-suggestions', (req, res) => {
    try {
        const { sessionId } = req.params;
        const suggestions = service.generateFixSuggestions(sessionId);
        res.status(200).json({
            success: true,
            data: suggestions,
        });
    }
    catch (error) {
        logger.error('Failed to generate fix suggestions', error);
        res.status(500).json({
            success: false,
            error: 'Failed to generate fix suggestions',
        });
    }
});
/**
 * GET /api/debug/sessions/:sessionId/docs
 * Get relevant documentation for a debug session
 */
router.get('/sessions/:sessionId/docs', (req, res) => {
    try {
        const { sessionId } = req.params;
        const docs = service.getRelevantDocs(sessionId);
        res.status(200).json({
            success: true,
            data: docs,
        });
    }
    catch (error) {
        logger.error('Failed to get relevant docs', error);
        res.status(500).json({
            success: false,
            error: 'Failed to get relevant docs',
        });
    }
});
/**
 * GET /api/debug/stats
 * Get debug session statistics
 */
router.get('/stats', (req, res) => {
    try {
        const stats = service.getStatistics();
        res.status(200).json({
            success: true,
            data: stats,
        });
    }
    catch (error) {
        logger.error('Failed to get statistics', error);
        res.status(500).json({
            success: false,
            error: 'Failed to get statistics',
        });
    }
});
/**
 * DELETE /api/debug/sessions/:sessionId
 * Stop and remove a debug session
 */
router.delete('/sessions/:sessionId', (req, res) => {
    try {
        const { sessionId } = req.params;
        const session = service.stopSession(sessionId);
        if (!session) {
            return res.status(404).json({
                success: false,
                error: 'Debug session not found',
            });
        }
        res.status(200).json({
            success: true,
            data: serializeSession(session),
        });
    }
    catch (error) {
        logger.error('Failed to delete debug session', error);
        res.status(500).json({
            success: false,
            error: 'Failed to delete debug session',
        });
    }
});
export default router;
//# sourceMappingURL=debug-session-ai.js.map