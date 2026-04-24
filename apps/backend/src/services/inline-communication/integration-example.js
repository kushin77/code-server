/**
 * @file        apps/backend/src/services/inline-communication/integration-example.ts
 * @module      collaboration/inline-communication
 * @description Express integration for inline communication REST API
 * @owner       Collaboration Team
 * @status      Production - April 23, 2026
 */
import { Router } from 'express';
import InlineCommunicationService from './index';
/**
 * Initialize inline communication routes
 */
export function initializeInlineCommunicationRoutes(service) {
    const router = Router();
    /**
     * POST /threads
     * Create a new comment thread at a code location
     */
    router.post('/threads', (req, res) => {
        const { codeLocation, sessionId, authorId, authorName, comment } = req.body;
        // Validation
        if (!codeLocation || !sessionId || !authorId || !authorName || !comment) {
            return res.status(400).json({
                error: 'Missing required fields: codeLocation, sessionId, authorId, authorName, comment',
            });
        }
        if (!codeLocation.filePath || typeof codeLocation.startLine !== 'number') {
            return res.status(400).json({ error: 'Invalid codeLocation' });
        }
        try {
            const thread = service.createThread(codeLocation, sessionId, authorId, authorName, comment);
            res.status(201).json(thread);
        }
        catch (error) {
            res.status(500).json({ error: error.message });
        }
    });
    /**
     * GET /threads/:threadId
     * Get a specific thread by ID
     */
    router.get('/threads/:threadId', (req, res) => {
        const { threadId } = req.params;
        const thread = service.getThread(threadId);
        if (!thread) {
            return res.status(404).json({ error: 'Thread not found' });
        }
        res.json(thread);
    });
    /**
     * POST /threads/:threadId/comments
     * Add a comment to a thread
     */
    router.post('/threads/:threadId/comments', (req, res) => {
        const { threadId } = req.params;
        const { authorId, authorName, content } = req.body;
        // Validation
        if (!authorId || !authorName || !content) {
            return res.status(400).json({ error: 'Missing required fields: authorId, authorName, content' });
        }
        const comment = service.addComment(threadId, authorId, authorName, content);
        if (!comment) {
            return res.status(404).json({ error: 'Thread not found' });
        }
        res.status(201).json(comment);
    });
    /**
     * PUT /threads/:threadId/comments/:commentId
     * Edit a comment
     */
    router.put('/threads/:threadId/comments/:commentId', (req, res) => {
        const { threadId, commentId } = req.params;
        const { content } = req.body;
        if (!content) {
            return res.status(400).json({ error: 'Missing required field: content' });
        }
        const updated = service.updateComment(threadId, commentId, content);
        if (!updated) {
            return res.status(404).json({ error: 'Thread or comment not found' });
        }
        res.json(updated);
    });
    /**
     * POST /threads/:threadId/resolve
     * Resolve a thread
     */
    router.post('/threads/:threadId/resolve', (req, res) => {
        const { threadId } = req.params;
        const { resolvedBy } = req.body;
        if (!resolvedBy) {
            return res.status(400).json({ error: 'Missing required field: resolvedBy' });
        }
        const resolved = service.resolveThread(threadId, resolvedBy);
        if (!resolved) {
            return res.status(404).json({ error: 'Thread not found' });
        }
        res.json(resolved);
    });
    /**
     * POST /threads/:threadId/unresolve
     * Unresolve (reopen) a thread
     */
    router.post('/threads/:threadId/unresolve', (req, res) => {
        const { threadId } = req.params;
        const unresolved = service.unresolveThread(threadId);
        if (!unresolved) {
            return res.status(404).json({ error: 'Thread not found' });
        }
        res.json(unresolved);
    });
    /**
     * GET /threads/file/:filePath
     * Get all threads in a file
     */
    router.get('/threads/file/:filePath', (req, res) => {
        const { filePath } = req.params;
        const threads = service.getThreadsInFile(decodeURIComponent(filePath));
        res.json(threads);
    });
    /**
     * GET /threads/location
     * Get threads at a specific code location
     */
    router.get('/threads/location', (req, res) => {
        const { filePath, startLine, endLine, functionName } = req.query;
        // Validation
        if (!filePath || typeof startLine !== 'string' || typeof endLine !== 'string') {
            return res.status(400).json({
                error: 'Missing required query params: filePath, startLine, endLine',
            });
        }
        const location = {
            filePath: decodeURIComponent(filePath),
            startLine: parseInt(startLine),
            endLine: parseInt(endLine),
            functionName: functionName ? decodeURIComponent(functionName) : undefined,
        };
        const threads = service.getThreadsForLocation(location);
        res.json(threads);
    });
    /**
     * GET /threads
     * Get all threads
     */
    router.get('/threads', (req, res) => {
        const threads = service.getAllThreads();
        res.json(threads);
    });
    /**
     * GET /statistics
     * Get thread statistics
     */
    router.get('/statistics', (req, res) => {
        const stats = service.getThreadStatistics();
        res.json(stats);
    });
    /**
     * GET /users/:userId/statistics
     * Get user-specific statistics
     */
    router.get('/users/:userId/statistics', (req, res) => {
        const { userId } = req.params;
        const stats = service.getUserStatistics(userId);
        res.json(stats);
    });
    /**
     * GET /search
     * Search threads by content
     */
    router.get('/search', (req, res) => {
        const { query } = req.query;
        if (!query || typeof query !== 'string') {
            return res.status(400).json({ error: 'Missing required query param: query' });
        }
        const results = service.searchThreads(query);
        res.json(results);
    });
    /**
     * POST /refactor
     * Handle code refactor - relocate threads
     */
    router.post('/refactor', (req, res) => {
        const { oldLocation, newLocation } = req.body;
        if (!oldLocation || !newLocation) {
            return res.status(400).json({ error: 'Missing required fields: oldLocation, newLocation' });
        }
        const count = service.handleCodeRefactor(oldLocation, newLocation);
        res.json({ updatedThreadCount: count });
    });
    /**
     * POST /export
     * Export all threads
     */
    router.post('/export', (req, res) => {
        const threads = service.exportThreads();
        res.json(threads);
    });
    /**
     * POST /import
     * Import threads
     */
    router.post('/import', (req, res) => {
        const { threads } = req.body;
        if (!Array.isArray(threads)) {
            return res.status(400).json({ error: 'Invalid threads data' });
        }
        const count = service.importThreads(threads);
        res.json({ importedThreadCount: count });
    });
    return router;
}
/**
 * Setup Express app integration
 */
export function setupInlineCommunicationIntegration(app) {
    const service = InlineCommunicationService.getInstance();
    const router = initializeInlineCommunicationRoutes(service);
    app.use('/api/inline-communication', router);
}
/**
 * Create example Express app for testing
 */
export function createInlineCommunicationExampleApp() {
    const express = require('express');
    const app = express();
    app.use(express.json());
    const service = InlineCommunicationService.getInstance();
    const router = initializeInlineCommunicationRoutes(service);
    app.use('/api/inline-communication', router);
    // Health check
    app.get('/health', (req, res) => {
        res.json({ status: 'ok', service: 'inline-communication' });
    });
    return app;
}
export { InlineCommunicationService };
//# sourceMappingURL=integration-example.js.map