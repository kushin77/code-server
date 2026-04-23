/**
 * @file        apps/backend/src/services/crdt-operations/integration-example.ts
 * @module      collaboration/crdt
 * @description Example Express app integration for CRDT operations service
 */
import express from 'express';
import { CRDTOperationsService } from './index';
/**
 * Set up CRDT operations routes on an Express router
 */
export function initializeCRDTRoutes(router, crdt) {
    /**
     * Initialize a new document for editing
     * POST /api/crdt/documents
     */
    router.post('/documents', (req, res) => {
        try {
            const { documentId, initialContent } = req.body;
            if (!documentId) {
                return res.status(400).json({ error: 'documentId required' });
            }
            const state = crdt.initializeDocument(documentId, initialContent || '');
            res.status(201).json(state);
        }
        catch (err) {
            const error = err instanceof Error ? err.message : 'Unknown error';
            res.status(500).json({ error });
        }
    });
    /**
     * Get current document state
     * GET /api/crdt/documents/:documentId
     */
    router.get('/documents/:documentId', (req, res) => {
        try {
            const { documentId } = req.params;
            const state = crdt.getDocumentState(documentId);
            if (!state) {
                return res.status(404).json({ error: 'Document not found' });
            }
            res.json(state);
        }
        catch (err) {
            const error = err instanceof Error ? err.message : 'Unknown error';
            res.status(500).json({ error });
        }
    });
    /**
     * Apply insert operation
     * POST /api/crdt/documents/:documentId/insert
     */
    router.post('/documents/:documentId/insert', (req, res) => {
        try {
            const { documentId } = req.params;
            const { clientId, position, content } = req.body;
            if (!clientId || position === undefined || !content) {
                return res.status(400).json({ error: 'clientId, position, and content required' });
            }
            const result = crdt.applyInsertOperation(documentId, clientId, position, content);
            res.status(200).json(result);
        }
        catch (err) {
            const error = err instanceof Error ? err.message : 'Unknown error';
            res.status(400).json({ error });
        }
    });
    /**
     * Apply delete operation
     * POST /api/crdt/documents/:documentId/delete
     */
    router.post('/documents/:documentId/delete', (req, res) => {
        try {
            const { documentId } = req.params;
            const { clientId, position, length } = req.body;
            if (!clientId || position === undefined || length === undefined) {
                return res.status(400).json({ error: 'clientId, position, and length required' });
            }
            const result = crdt.applyDeleteOperation(documentId, clientId, position, length);
            res.status(200).json(result);
        }
        catch (err) {
            const error = err instanceof Error ? err.message : 'Unknown error';
            res.status(400).json({ error });
        }
    });
    /**
     * Get operation history
     * GET /api/crdt/documents/:documentId/history
     */
    router.get('/documents/:documentId/history', (req, res) => {
        try {
            const { documentId } = req.params;
            const history = crdt.getOperationHistory(documentId);
            res.json({ operations: history });
        }
        catch (err) {
            const error = err instanceof Error ? err.message : 'Unknown error';
            res.status(500).json({ error });
        }
    });
    /**
     * Get operations since version (for sync)
     * GET /api/crdt/documents/:documentId/sync?since=0
     */
    router.get('/documents/:documentId/sync', (req, res) => {
        try {
            const { documentId } = req.params;
            const since = parseInt(req.query.since, 10) || 0;
            const operations = crdt.getOperationsSince(documentId, since);
            res.json({ operations });
        }
        catch (err) {
            const error = err instanceof Error ? err.message : 'Unknown error';
            res.status(500).json({ error });
        }
    });
    /**
     * List all documents
     * GET /api/crdt/documents
     */
    router.get('/documents', (req, res) => {
        try {
            const documents = crdt.listDocuments();
            res.json({ documents });
        }
        catch (err) {
            const error = err instanceof Error ? err.message : 'Unknown error';
            res.status(500).json({ error });
        }
    });
    return router;
}
/**
 * Set up CRDT integration in an Express app
 */
export function setupCRDTIntegration(app) {
    const crdt = new CRDTOperationsService();
    // Mount routes under /api/crdt
    const router = express.Router();
    initializeCRDTRoutes(router, crdt);
    app.use('/api/crdt', router);
    // Log initialization
    console.log('[CRDTIntegration] CRDT operations service initialized');
    return crdt;
}
/**
 * Create an example Express app with CRDT support
 */
export async function createCRDTExampleApp() {
    const app = express();
    // Middleware
    app.use(express.json());
    // Setup CRDT
    setupCRDTIntegration(app);
    // Health check
    app.get('/health', (req, res) => {
        res.json({ status: 'ok', service: 'crdt-example' });
    });
    return app;
}
//# sourceMappingURL=integration-example.js.map