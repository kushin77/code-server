#!/usr/bin/env node
// @file        apps/backend/src/routes/issue-linking.ts
// @module      collaboration/issue-linking
// @description REST API routes for issue linking service
// @owner       collab-9.2
// @status      active
import { Router } from 'express';
import { IssueLinkingService } from '../services/issue-linking';
import { getLogger } from '../lib/logger';
const logger = getLogger('IssueLinkingRoutes');
export function initializeIssueLinkingRoutes(pool, auditService, config) {
    const router = Router();
    const issueLinkingService = new IssueLinkingService(pool, auditService, config);
    issueLinkingService.initialize().catch(error => {
        logger.error('Failed to initialize issue linking service', { error });
    });
    // GET /api/issues/search - Search for tickets
    router.get('/search', async (req, res) => {
        try {
            const { q, provider } = req.query;
            if (!q) {
                return res.status(400).json({ error: 'Missing required parameter: q' });
            }
            const results = await issueLinkingService.searchTickets(q, provider);
            res.json({
                success: true,
                query: q,
                results,
            });
        }
        catch (error) {
            logger.error('Failed to search tickets', { error, query: req.query });
            res.status(500).json({ error: 'Failed to search tickets' });
        }
    });
    // POST /api/issues/link - Link a ticket to GitHub issue
    router.post('/link', async (req, res) => {
        try {
            const { ticketId, githubIssueNumber, provider } = req.body;
            if (!ticketId || !githubIssueNumber || !provider) {
                return res.status(400).json({ error: 'Missing required fields: ticketId, githubIssueNumber, provider' });
            }
            await issueLinkingService.linkIssue(ticketId, githubIssueNumber, provider);
            res.json({
                success: true,
                message: 'Issue linked successfully',
            });
        }
        catch (error) {
            logger.error('Failed to link issue', { error, body: req.body });
            res.status(500).json({ error: 'Failed to link issue' });
        }
    });
    // GET /api/issues/context/:ticketKey - Get issue context
    router.get('/context/:ticketKey', async (req, res) => {
        try {
            const { ticketKey } = req.params;
            const context = await issueLinkingService.getIssueContext(ticketKey);
            if (!context) {
                return res.status(404).json({ error: 'Context not found' });
            }
            res.json({
                success: true,
                context,
            });
        }
        catch (error) {
            logger.error('Failed to get issue context', { error, ticketKey: req.params.ticketKey });
            res.status(500).json({ error: 'Failed to get context' });
        }
    });
    // POST /api/issues/context - Save issue context
    router.post('/context', async (req, res) => {
        try {
            const context = req.body;
            if (!context.ticketKey) {
                return res.status(400).json({ error: 'Missing required field: ticketKey' });
            }
            await issueLinkingService.saveIssueContext(context);
            res.json({
                success: true,
                message: 'Context saved',
            });
        }
        catch (error) {
            logger.error('Failed to save context', { error, body: req.body });
            res.status(500).json({ error: 'Failed to save context' });
        }
    });
    // POST /api/issues/branch-name - Generate branch name
    router.post('/branch-name', async (req, res) => {
        try {
            const { ticketKey, title, prefix, maxLength } = req.body;
            if (!ticketKey || !title) {
                return res.status(400).json({ error: 'Missing required fields: ticketKey, title' });
            }
            const branchName = issueLinkingService.generateBranchName({
                ticketKey,
                title,
                prefix,
                maxLength,
            });
            res.json({
                success: true,
                branchName,
            });
        }
        catch (error) {
            logger.error('Failed to generate branch name', { error, body: req.body });
            res.status(500).json({ error: 'Failed to generate branch name' });
        }
    });
    // POST /api/issues/branch-name-save - Save generated branch name
    router.post('/branch-name-save', async (req, res) => {
        try {
            const { ticketKey, suggestedName, actualName, createdBy } = req.body;
            if (!ticketKey || !suggestedName) {
                return res.status(400).json({ error: 'Missing required fields: ticketKey, suggestedName' });
            }
            await issueLinkingService.saveBranchName(ticketKey, suggestedName, actualName, createdBy);
            res.json({
                success: true,
                message: 'Branch name saved',
            });
        }
        catch (error) {
            logger.error('Failed to save branch name', { error, body: req.body });
            res.status(500).json({ error: 'Failed to save branch name' });
        }
    });
    // GET /api/issues/branch-names/:ticketKey - Get branch naming history
    router.get('/branch-names/:ticketKey', async (req, res) => {
        try {
            const { ticketKey } = req.params;
            const names = await issueLinkingService.getBranchNames(ticketKey);
            res.json({
                success: true,
                ticketKey,
                names,
            });
        }
        catch (error) {
            logger.error('Failed to get branch names', { error, ticketKey: req.params.ticketKey });
            res.status(500).json({ error: 'Failed to get branch names' });
        }
    });
    // GET /api/issues/context-copilot/:ticketKey - Get formatted context for Copilot
    router.get('/context-copilot/:ticketKey', async (req, res) => {
        try {
            const { ticketKey } = req.params;
            const context = await issueLinkingService.getIssueContext(ticketKey);
            if (!context) {
                return res.status(404).json({ error: 'Context not found' });
            }
            const formatted = issueLinkingService.formatContextForCopilot(context);
            res.json({
                success: true,
                ticketKey,
                context: formatted,
            });
        }
        catch (error) {
            logger.error('Failed to format context for Copilot', { error, ticketKey: req.params.ticketKey });
            res.status(500).json({ error: 'Failed to format context' });
        }
    });
    return router;
}
export { IssueLinkingService } from '../services/issue-linking';
//# sourceMappingURL=issue-linking.js.map