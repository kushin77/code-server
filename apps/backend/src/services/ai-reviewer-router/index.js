#!/usr/bin/env node
// @file        apps/backend/src/services/ai-reviewer-router/index.ts
// @module      collaboration/ai-reviewer-router
// @description AI-powered code review assignment based on expertise, workload, and timezone
// @owner       collab-3.7
// @status      active
import { EventEmitter } from 'events';
import { getLogger } from '../../lib/logger';
export class AIReviewerRouterService extends EventEmitter {
    constructor(pool, auditService, config = {}) {
        super();
        this.logger = getLogger('AIReviewerRouterService');
        this.initialized = false;
        this.pool = pool;
        this.auditService = auditService;
        this.config = {
            maxReviewersToScore: config.maxReviewersToScore || 10,
            minExpertiseThreshold: config.minExpertiseThreshold || 30,
            workloadWeightPercent: config.workloadWeightPercent || 25,
            expertiseWeightPercent: config.expertiseWeightPercent || 50,
            availabilityWeightPercent: config.availabilityWeightPercent || 25,
        };
    }
    async initialize() {
        if (this.initialized)
            return;
        try {
            await this.createTables();
            this.initialized = true;
            this.logger.info('AI reviewer router database schema initialized');
        }
        catch (error) {
            this.logger.error('Failed to initialize AI reviewer router schema', { error });
            throw error;
        }
    }
    async createTables() {
        const client = await this.pool.connect();
        try {
            await client.query('BEGIN');
            // Reviewer expertise table
            await client.query(`
        CREATE TABLE IF NOT EXISTS reviewer_expertise (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          reviewer_id TEXT NOT NULL,
          file_pattern TEXT NOT NULL,
          expertise_level TEXT NOT NULL CHECK (expertise_level IN ('expert', 'intermediate', 'novice')),
          confidence INTEGER NOT NULL DEFAULT 50,
          last_worked_at TIMESTAMP WITH TIME ZONE,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        )
      `);
            // Reviewer workload table
            await client.query(`
        CREATE TABLE IF NOT EXISTS reviewer_workload (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          reviewer_id TEXT NOT NULL UNIQUE,
          pending_reviews INTEGER DEFAULT 0,
          completed_reviews_last_7days INTEGER DEFAULT 0,
          average_review_time_minutes INTEGER DEFAULT 30,
          updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        )
      `);
            // Reviewer availability table
            await client.query(`
        CREATE TABLE IF NOT EXISTS reviewer_availability (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          reviewer_id TEXT NOT NULL UNIQUE,
          timezone TEXT DEFAULT 'UTC',
          is_online BOOLEAN DEFAULT false,
          last_active_at TIMESTAMP WITH TIME ZONE,
          preferred_work_hours_start INTEGER DEFAULT 9,
          preferred_work_hours_end INTEGER DEFAULT 17,
          updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        )
      `);
            // Review assignments table
            await client.query(`
        CREATE TABLE IF NOT EXISTS review_assignments (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          pull_request_id TEXT NOT NULL,
          reviewer_id TEXT NOT NULL,
          expertise_score DECIMAL(5, 2),
          workload_score DECIMAL(5, 2),
          availability_score DECIMAL(5, 2),
          total_score DECIMAL(5, 2),
          score_explanation JSONB,
          assigned_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          completed_at TIMESTAMP WITH TIME ZONE
        )
      `);
            // Indexes
            await client.query(`
        CREATE INDEX IF NOT EXISTS idx_expertise_reviewer ON reviewer_expertise(reviewer_id);
        CREATE INDEX IF NOT EXISTS idx_expertise_pattern ON reviewer_expertise(file_pattern);
        CREATE INDEX IF NOT EXISTS idx_workload_reviewer ON reviewer_workload(reviewer_id);
        CREATE INDEX IF NOT EXISTS idx_availability_reviewer ON reviewer_availability(reviewer_id);
        CREATE INDEX IF NOT EXISTS idx_assignments_pr ON review_assignments(pull_request_id);
        CREATE INDEX IF NOT EXISTS idx_assignments_reviewer ON review_assignments(reviewer_id);
        CREATE INDEX IF NOT EXISTS idx_assignments_score ON review_assignments(total_score DESC);
      `);
            await client.query('COMMIT');
        }
        catch (error) {
            await client.query('ROLLBACK');
            throw error;
        }
        finally {
            client.release();
        }
    }
    async registerReviewerExpertise(reviewerId, filePattern, expertiseLevel, confidence) {
        if (confidence < 0 || confidence > 100) {
            throw new Error('Confidence must be between 0 and 100');
        }
        const client = await this.pool.connect();
        try {
            const id = require('crypto').randomUUID();
            await client.query(`INSERT INTO reviewer_expertise (id, reviewer_id, file_pattern, expertise_level, confidence, last_worked_at)
         VALUES ($1, $2, $3, $4, $5, NOW())`, [id, reviewerId, filePattern, expertiseLevel, confidence]);
            this.logger.info('Reviewer expertise registered', { reviewerId, filePattern, expertiseLevel });
            this.emit('expertise-registered', { reviewerId, filePattern, expertiseLevel });
            return {
                reviewerId,
                filePattern,
                expertiseLevel,
                confidence,
                lastWorkedAt: new Date(),
            };
        }
        catch (error) {
            this.logger.error('Failed to register reviewer expertise', { error, reviewerId });
            throw error;
        }
        finally {
            client.release();
        }
    }
    async updateReviewerWorkload(reviewerId, pendingReviews, completedReviewsLast7Days, averageReviewTimeMinutes) {
        const client = await this.pool.connect();
        try {
            await client.query(`INSERT INTO reviewer_workload (reviewer_id, pending_reviews, completed_reviews_last_7days, average_review_time_minutes)
         VALUES ($1, $2, $3, $4)
         ON CONFLICT (reviewer_id) DO UPDATE SET
           pending_reviews = $2,
           completed_reviews_last_7days = $3,
           average_review_time_minutes = $4,
           updated_at = NOW()`, [reviewerId, pendingReviews, completedReviewsLast7Days, averageReviewTimeMinutes]);
            this.logger.debug('Reviewer workload updated', { reviewerId, pendingReviews });
            this.emit('workload-updated', { reviewerId, pendingReviews });
            return {
                reviewerId,
                pendingReviews,
                completedReviewsLast7Days,
                averageReviewTimeMinutes,
            };
        }
        catch (error) {
            this.logger.error('Failed to update reviewer workload', { error, reviewerId });
            throw error;
        }
        finally {
            client.release();
        }
    }
    async updateReviewerAvailability(reviewerId, timezone, isOnline, preferredWorkHoursStart, preferredWorkHoursEnd) {
        const client = await this.pool.connect();
        try {
            await client.query(`INSERT INTO reviewer_availability (reviewer_id, timezone, is_online, last_active_at, preferred_work_hours_start, preferred_work_hours_end)
         VALUES ($1, $2, $3, NOW(), $4, $5)
         ON CONFLICT (reviewer_id) DO UPDATE SET
           timezone = $2,
           is_online = $3,
           last_active_at = NOW(),
           preferred_work_hours_start = COALESCE($4, preferred_work_hours_start),
           preferred_work_hours_end = COALESCE($5, preferred_work_hours_end),
           updated_at = NOW()`, [
                reviewerId,
                timezone,
                isOnline,
                preferredWorkHoursStart !== undefined ? preferredWorkHoursStart : null,
                preferredWorkHoursEnd !== undefined ? preferredWorkHoursEnd : null,
            ]);
            this.logger.debug('Reviewer availability updated', { reviewerId, timezone, isOnline });
            this.emit('availability-updated', { reviewerId, timezone, isOnline });
            return {
                reviewerId,
                timezone,
                isOnline,
                lastActiveAt: new Date(),
                preferredWorkHours: { start: preferredWorkHoursStart || 9, end: preferredWorkHoursEnd || 17 },
            };
        }
        catch (error) {
            this.logger.error('Failed to update reviewer availability', { error, reviewerId });
            throw error;
        }
        finally {
            client.release();
        }
    }
}
({
    userId: 'system',
    action: 'allow',
    role: 'system',
    method: 'assignReview',
    path: '/api/reviews/assign',
    reason: 'Assigned review for PR ' + pullRequestId
});
pullRequestId: string,
    changedFiles;
string[],
    teamId;
string;
Promise < ReviewAssignment > {
    const: client = await this.pool.connect(),
    try: {
        // Score all reviewers
        const: scores = await this.scoreReviewers(changedFiles, teamId),
        if(scores) { }, : .length === 0
    }
};
{
    throw new Error(`No suitable reviewers found for PR ${pullRequestId}`);
}
// Get best reviewer
const bestReviewer = scores[0];
// Create assignment
const assignmentId = require('crypto').randomUUID();
await client.query(`INSERT INTO review_assignments (id, pull_request_id, reviewer_id, expertise_score, workload_score, availability_score, total_score, score_explanation)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`, [
    assignmentId,
    pullRequestId,
    bestReviewer.reviewerId,
    bestReviewer.expertiseScore,
    bestReviewer.workloadScore,
    bestReviewer.availabilityScore,
    bestReviewer.totalScore,
    JSON.stringify({ reasoning: bestReviewer.reasoning }),
]);
// Increment pending reviews count
await client.query(`UPDATE reviewer_workload SET pending_reviews = pending_reviews + 1 WHERE reviewer_id = $1`, [bestReviewer.reviewerId]);
this.logger.info('Review assigned', { prId: pullRequestId, reviewerId: bestReviewer.reviewerId, score: bestReviewer.totalScore });
this.emit('review-assigned', {
    prId: pullRequestId,
    reviewerId: bestReviewer.reviewerId,
    score: bestReviewer.totalScore,
});
return {
    id: assignmentId,
    pullRequestId,
    reviewerId: bestReviewer.reviewerId,
    assignedAt: new Date(),
    scoreExplanation: {
        expertiseScore: bestReviewer.expertiseScore,
        workloadScore: bestReviewer.workloadScore,
        availabilityScore: bestReviewer.availabilityScore,
        totalScore: bestReviewer.totalScore,
        reasoning: bestReviewer.reasoning,
    },
};
try { }
catch (error) {
    this.logger.error('Failed to assign review', { error, prId: pullRequestId });
    throw error;
}
finally {
    client.release();
}
async;
scoreReviewers(changedFiles, string[], teamId, string);
Promise < ReviewerScore[] > {
    const: client = await this.pool.connect(),
    try: {
        // Get all reviewers with their data
        const: result = await client.query(`SELECT DISTINCT re.reviewer_id FROM reviewer_expertise re
         WHERE re.confidence >= $1
         LIMIT $2`, [this.config.minExpertiseThreshold, this.config.maxReviewersToScore]),
        const: reviewerIds = result.rows.map(row => row.reviewer_id),
        if(reviewerIds) { }, : .length === 0
    }
};
{
    return [];
}
const scores = [];
for (const reviewerId of reviewerIds) {
    // Get expertise score
    const expertiseResult = await client.query(`SELECT AVG(confidence) as avg_confidence FROM reviewer_expertise
           WHERE reviewer_id = $1`, [reviewerId]);
    const expertiseScore = parseFloat(expertiseResult.rows[0].avg_confidence) || 0;
    // Get workload score (inverse - lower pending = higher score)
    const workloadResult = await client.query(`SELECT pending_reviews, completed_reviews_last_7days FROM reviewer_workload
           WHERE reviewer_id = $1`, [reviewerId]);
    const pendingReviews = workloadResult.rows[0]?.pending_reviews || 0;
    const completedLast7 = workloadResult.rows[0]?.completed_reviews_last_7days || 1;
    const workloadScore = Math.max(0, 100 - (pendingReviews * 10)); // Penalize high workload
    // Get availability score
    const availabilityResult = await client.query(`SELECT is_online, timezone FROM reviewer_availability
           WHERE reviewer_id = $1`, [reviewerId]);
    const isOnline = availabilityResult.rows[0]?.is_online || false;
    const availabilityScore = isOnline ? 100 : 50;
    // Calculate weighted total
    const totalScore = (expertiseScore * this.config.expertiseWeightPercent +
        workloadScore * this.config.workloadWeightPercent +
        availabilityScore * this.config.availabilityWeightPercent) /
        100;
    const reasoning = `Expertise: ${expertiseScore.toFixed(0)}%, Workload: ${workloadScore.toFixed(0)}% (${pendingReviews} pending), Availability: ${availabilityScore.toFixed(0)}% (${isOnline ? 'online' : 'offline'})`;
    scores.push({
        reviewerId,
        name: reviewerId,
        expertiseScore,
        workloadScore,
        availabilityScore,
        totalScore,
        reasoning,
    });
}
// Sort by total score descending
scores.sort((a, b) => b.totalScore - a.totalScore);
this.logger.debug('Reviewers scored', { count: scores.length, topScore: scores[0]?.totalScore });
this.emit('reviewers-scored', { count: scores.length, topScore: scores[0]?.totalScore });
return scores;
try { }
catch (error) {
    this.logger.error('Failed to score reviewers', { error });
    throw error;
}
finally {
    client.release();
}
async;
completeReview(assignmentId, string);
Promise < void  > {
    const: client = await this.pool.connect(),
    try: {
        // Get assignment to find reviewer
        const: result = await client.query(`SELECT reviewer_id FROM review_assignments WHERE id = $1`, [assignmentId]),
        if(result) { }, : .rows.length === 0
    }
};
{
    throw new Error(`Assignment ${assignmentId} not found`);
}
const reviewerId = result.rows[0].reviewer_id;
// Mark as completed
await client.query(`UPDATE review_assignments SET completed_at = NOW() WHERE id = $1`, [assignmentId]);
// Decrement pending reviews
await client.query(`UPDATE reviewer_workload SET pending_reviews = GREATEST(0, pending_reviews - 1) WHERE reviewer_id = $1`, [reviewerId]);
this.logger.info('Review completed', { assignmentId, reviewerId });
this.emit('review-completed', { assignmentId, reviewerId });
try { }
catch (error) {
    this.logger.error('Failed to complete review', { error, assignmentId });
    throw error;
}
finally {
    client.release();
}
async;
getAssignment(assignmentId, string);
Promise < ReviewAssignment | null > {
    const: client = await this.pool.connect(),
    try: {
        const: result = await client.query(`SELECT * FROM review_assignments WHERE id = $1`, [assignmentId]),
        if(result) { }, : .rows.length === 0
    }
};
{
    return null;
}
const row = result.rows[0];
return {
    id: row.id,
    pullRequestId: row.pull_request_id,
    reviewerId: row.reviewer_id,
    assignedAt: new Date(row.assigned_at),
    scoreExplanation: {
        expertiseScore: parseFloat(row.expertise_score),
        workloadScore: parseFloat(row.workload_score),
        availabilityScore: parseFloat(row.availability_score),
        totalScore: parseFloat(row.total_score),
        reasoning: row.score_explanation?.reasoning || '',
    },
};
try { }
catch (error) {
    this.logger.error('Failed to get assignment', { error, assignmentId });
    throw error;
}
finally {
    client.release();
}
//# sourceMappingURL=index.js.map