#!/usr/bin/env node
// @file        apps/backend/src/routes/ai-reviewer-router.ts
// @module      collaboration/ai-reviewer-router
// @description AI reviewer router REST API endpoints
// @owner       collab-3.7
// @status      active
import { Router } from 'express';
import { getLogger } from '../lib/logger';
const logger = getLogger('AIReviewerRouterRoutes');
export function initializeAIReviewerRouterRoutes(service) {
    const router = Router();
    // Register reviewer expertise
    router.post('/api/reviewers/:reviewerId/expertise', async (req, res) => {
        try {
            const { reviewerId } = req.params;
            const { filePattern, expertiseLevel, confidence } = req.body;
            if (!filePattern || !expertiseLevel || confidence === undefined) {
                return res.status(400).json({ error: 'Missing filePattern, expertiseLevel, or confidence' });
            }
            const expertise = await service.registerReviewerExpertise(reviewerId, filePattern, expertiseLevel, confidence);
            logger.info('Reviewer expertise registered via API', { reviewerId, filePattern });
            res.status(201).json(expertise);
        }
        catch (error) {
            logger.error('Failed to register reviewer expertise', { error });
            res.status(500).json({ error: 'Failed to register reviewer expertise' });
        }
    });
    // Update reviewer workload
    router.post('/api/reviewers/:reviewerId/workload', async (req, res) => {
        try {
            const { reviewerId } = req.params;
            const { pendingReviews, completedReviewsLast7Days, averageReviewTimeMinutes } = req.body;
            if (pendingReviews === undefined || completedReviewsLast7Days === undefined || averageReviewTimeMinutes === undefined) {
                return res.status(400).json({ error: 'Missing required workload fields' });
            }
            const workload = await service.updateReviewerWorkload(reviewerId, pendingReviews, completedReviewsLast7Days, averageReviewTimeMinutes);
            logger.info('Reviewer workload updated via API', { reviewerId, pendingReviews });
            res.json(workload);
        }
        catch (error) {
            logger.error('Failed to update reviewer workload', { error });
            res.status(500).json({ error: 'Failed to update reviewer workload' });
        }
    });
    // Update reviewer availability
    router.post('/api/reviewers/:reviewerId/availability', async (req, res) => {
        try {
            const { reviewerId } = req.params;
            const { timezone, isOnline, preferredWorkHoursStart, preferredWorkHoursEnd } = req.body;
            if (!timezone || isOnline === undefined) {
                return res.status(400).json({ error: 'Missing timezone or isOnline' });
            }
            const availability = await service.updateReviewerAvailability(reviewerId, timezone, isOnline, preferredWorkHoursStart, preferredWorkHoursEnd);
            logger.info('Reviewer availability updated via API', { reviewerId, isOnline });
            res.json(availability);
        }
        catch (error) {
            logger.error('Failed to update reviewer availability', { error });
            res.status(500).json({ error: 'Failed to update reviewer availability' });
        }
    });
    // Assign review
    router.post('/api/reviews/assign', async (req, res) => {
        try {
            const { pullRequestId, changedFiles, teamId } = req.body;
            if (!pullRequestId || !changedFiles || !Array.isArray(changedFiles) || !teamId) {
                return res.status(400).json({ error: 'Missing pullRequestId, changedFiles, or teamId' });
            }
            const assignment = await service.assignReview(pullRequestId, changedFiles, teamId);
            logger.info('Review assigned via API', { prId: pullRequestId, reviewerId: assignment.reviewerId });
            res.status(201).json(assignment);
        }
        catch (error) {
            logger.error('Failed to assign review', { error });
            res.status(500).json({ error: 'Failed to assign review' });
        }
    });
    // Score reviewers
    router.post('/api/reviews/score', async (req, res) => {
        try {
            const { changedFiles, teamId } = req.body;
            if (!changedFiles || !Array.isArray(changedFiles) || !teamId) {
                return res.status(400).json({ error: 'Missing changedFiles or teamId' });
            }
            const scores = await service.scoreReviewers(changedFiles, teamId);
            logger.info('Reviewers scored via API', { count: scores.length });
            res.json(scores);
        }
        catch (error) {
            logger.error('Failed to score reviewers', { error });
            res.status(500).json({ error: 'Failed to score reviewers' });
        }
    });
    // Complete review
    router.post('/api/reviews/:assignmentId/complete', async (req, res) => {
        try {
            const { assignmentId } = req.params;
            await service.completeReview(assignmentId);
            logger.info('Review completed via API', { assignmentId });
            res.json({ success: true });
        }
        catch (error) {
            logger.error('Failed to complete review', { error });
            res.status(500).json({ error: 'Failed to complete review' });
        }
    });
    // Get assignment
    router.get('/api/reviews/:assignmentId', async (req, res) => {
        try {
            const { assignmentId } = req.params;
            const assignment = await service.getAssignment(assignmentId);
            if (!assignment) {
                return res.status(404).json({ error: 'Assignment not found' });
            }
            logger.debug('Assignment retrieved', { assignmentId });
            res.json(assignment);
        }
        catch (error) {
            logger.error('Failed to get assignment', { error });
            res.status(500).json({ error: 'Failed to get assignment' });
        }
    });
    return router;
}
export { AIReviewerRouterService } from '../services/ai-reviewer-router';
//# sourceMappingURL=ai-reviewer-router.js.map