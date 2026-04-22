// @file        apps/backend/src/routes/standup-summaries.ts
// @module      routes/standup-summaries
// @description Express routes for standup summaries API
//              Endpoints: get summaries, approve summary, generate for date
//
import { Router } from 'express';
import { StandupSummariesService } from '../services/standup-summaries';
import { logger } from '../lib/logger';
const router = Router();
// Global service instance - in production this would be injected
let standupService = null;
/**
 * Initialize the standup summaries service
 * This would typically be done in the main application initialization
 */
export function initializeStandupRoutes(db, aiRouter, config) {
    standupService = new StandupSummariesService(db, aiRouter, config);
    standupService.initialize();
}
/**
 * Middleware to ensure service is initialized
 */
const requireService = (req, res, next) => {
    if (!standupService) {
        return res.status(503).json({
            error: 'Standup summaries service not initialized',
        });
    }
    next();
};
/**
 * GET /api/standup-summaries/:date
 * Get standup summary for a specific date
 */
router.get('/:date', requireService, async (req, res) => {
    try {
        const { date } = req.params;
        // Validate date format (YYYY-MM-DD)
        if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
            return res.status(400).json({
                error: 'Invalid date format. Use YYYY-MM-DD',
            });
        }
        const summary = await standupService.getSummary(date);
        if (!summary) {
            return res.status(404).json({
                error: 'No summary found for date',
                date,
            });
        }
        res.json({
            success: true,
            summary,
        });
    }
    catch (error) {
        logger.error('Failed to get standup summary', { error, date: req.params.date });
        res.status(500).json({
            error: 'Failed to get standup summary',
        });
    }
});
/**
 * POST /api/standup-summaries/:date/approve
 * Approve a draft summary for posting
 */
router.post('/:date/approve', requireService, async (req, res) => {
    try {
        const { date } = req.params;
        const { approvedBy } = req.body;
        if (!approvedBy) {
            return res.status(400).json({
                error: 'approvedBy is required',
            });
        }
        const approved = await standupService.approveSummary(date, approvedBy);
        if (!approved) {
            return res.status(404).json({
                error: 'No draft summary found to approve',
                date,
            });
        }
        res.json({
            success: true,
            message: 'Summary approved for posting',
            date,
        });
    }
    catch (error) {
        logger.error('Failed to approve standup summary', { error, date: req.params.date });
        res.status(500).json({
            error: 'Failed to approve standup summary',
        });
    }
});
/**
 * POST /api/standup-summaries/:date/generate
 * Manually generate summary for a specific date (for testing/admin)
 */
router.post('/:date/generate', requireService, async (req, res) => {
    try {
        const { date } = req.params;
        // Validate date format
        if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
            return res.status(400).json({
                error: 'Invalid date format. Use YYYY-MM-DD',
            });
        }
        const dateObj = new Date(date + 'T00:00:00Z');
        const summary = await standupService.generateForDate(dateObj);
        res.json({
            success: true,
            message: 'Summary generated successfully',
            summary,
        });
    }
    catch (error) {
        logger.error('Failed to generate standup summary', { error, date: req.params.date });
        res.status(500).json({
            error: 'Failed to generate standup summary',
        });
    }
});
/**
 * POST /api/standup-summaries/:date/post
 * Manually post an approved summary to Matrix (for testing/admin)
 */
router.post('/:date/post', requireService, async (req, res) => {
    try {
        const { date } = req.params;
        const posted = await standupService.postToMatrix(date);
        if (!posted) {
            return res.status(400).json({
                error: 'Failed to post summary to Matrix',
                date,
            });
        }
        res.json({
            success: true,
            message: 'Summary posted to Matrix successfully',
            date,
        });
    }
    catch (error) {
        logger.error('Failed to post standup summary', { error, date: req.params.date });
        res.status(500).json({
            error: 'Failed to post standup summary',
        });
    }
});
/**
 * GET /api/standup-summaries
 * Get list of recent summaries
 */
router.get('/', requireService, async (req, res) => {
    try {
        const { limit = 10, status } = req.query;
        // This would require a more complex query to get multiple summaries
        // For now, return a placeholder
        res.json({
            success: true,
            summaries: [],
            message: 'Recent summaries endpoint - implementation pending',
        });
    }
    catch (error) {
        logger.error('Failed to get standup summaries list', { error });
        res.status(500).json({
            error: 'Failed to get standup summaries list',
        });
    }
});
export default router;
//# sourceMappingURL=standup-summaries.js.map