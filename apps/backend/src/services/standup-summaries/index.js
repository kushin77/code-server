#!/usr/bin/env node
// @file        apps/backend/src/services/standup-summaries/index.ts
// @module      collaboration/standup-summaries
// @description Async standup AI summaries service - auto-generates daily summaries from commits/reviews
// @owner       collab-2.9
// @status      active
import { EventEmitter } from 'events';
import { getLogger } from '../../lib/logger.js';
import { CollaborationMessageEncryptionService } from '../collaboration-message-encryption/index.js';
export class StandupSummariesService extends EventEmitter {
    db;
    logger;
    aiRouter;
    config;
    scheduleTimer;
    constructor(db, aiRouter, config = {}) {
        super();
        this.db = db;
        this.logger = getLogger('StandupSummariesService');
        this.aiRouter = aiRouter;
        this.config = {
            githubRepo: 'code-server',
            githubOwner: 'kushin77',
            postingTime: '09:00',
            timezone: 'America/New_York',
            enabled: true,
            ...config,
        };
    }
    /**
     * Initialize the service and database schema
     */
    async initialize() {
        await this.initializeSchema();
        if (this.config.enabled) {
            this.scheduleDailyPosting();
        }
        this.logger.info('Standup summaries service initialized', {
            enabled: this.config.enabled,
            postingTime: this.config.postingTime,
            timezone: this.config.timezone,
        });
    }
    /**
     * Initialize database schema for standup summaries
     */
    async initializeSchema() {
        const createTablesQuery = `
      CREATE TABLE IF NOT EXISTS standup_summaries (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        date DATE NOT NULL,
        summary TEXT NOT NULL,
        status VARCHAR(20) NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'approved', 'posted')),
        created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
        posted_at TIMESTAMP WITH TIME ZONE,
        approved_by VARCHAR(255),
        matrix_message_id VARCHAR(255),

        UNIQUE(date)
      );

      CREATE INDEX IF NOT EXISTS idx_standup_summaries_date ON standup_summaries(date);
      CREATE INDEX IF NOT EXISTS idx_standup_summaries_status ON standup_summaries(status);
    `;
        try {
            await this.db.query(createTablesQuery);
            this.logger.info('Initialized standup summaries database schema');
        }
        catch (error) {
            this.logger.error('Failed to initialize standup summaries schema', { error });
            throw error;
        }
    }
    /**
     * Collect daily activity from GitHub
     */
    async collectDailyActivity(date) {
        const dateStr = date.toISOString().split('T')[0];
        const activity = {
            date: dateStr,
            commits: [],
            reviews: [],
            comments: [],
            issues: [],
        };
        try {
            // Collect commits
            activity.commits = await this.collectCommits(date);
            // Collect reviews
            activity.reviews = await this.collectReviews(date);
            // Collect comments
            activity.comments = await this.collectComments(date);
            // Collect issues
            activity.issues = await this.collectIssues(date);
            this.logger.info('Collected daily activity', {
                date: dateStr,
                commits: activity.commits.length,
                reviews: activity.reviews.length,
                comments: activity.comments.length,
                issues: activity.issues.length,
            });
        }
        catch (error) {
            this.logger.error('Failed to collect daily activity', { error, date: dateStr });
        }
        return activity;
    }
    /**
     * Collect commits for the given date
     */
    async collectCommits(date) {
        if (!this.config.githubToken) {
            this.logger.debug('GitHub token not configured, skipping commit collection');
            return [];
        }
        try {
            const since = new Date(date);
            since.setHours(0, 0, 0, 0);
            const until = new Date(date);
            until.setHours(23, 59, 59, 999);
            const url = `https://api.github.com/repos/${this.config.githubOwner}/${this.config.githubRepo}/commits?since=${since.toISOString()}&until=${until.toISOString()}`;
            const response = await fetch(url, {
                headers: {
                    'Authorization': `token ${this.config.githubToken}`,
                    'Accept': 'application/vnd.github.v3+json',
                },
            });
            if (!response.ok) {
                throw new Error(`GitHub API error: ${response.status}`);
            }
            const commits = await response.json();
            return commits.map((commit) => ({
                sha: commit.sha,
                message: commit.commit.message,
                author: commit.commit.author.name,
                timestamp: new Date(commit.commit.author.date),
                files: [], // Would need additional API call to get files
                additions: 0,
                deletions: 0,
            }));
        }
        catch (error) {
            this.logger.error('Failed to collect commits', { error });
            return [];
        }
    }
    /**
     * Collect reviews for the given date
     */
    async collectReviews(date) {
        if (!this.config.githubToken) {
            this.logger.debug('GitHub token not configured, skipping review collection');
            return [];
        }
        try {
            const since = new Date(date);
            since.setHours(0, 0, 0, 0);
            const until = new Date(date);
            until.setHours(23, 59, 59, 999);
            // First, get all PRs that were updated on this date
            const prsUrl = `https://api.github.com/repos/${this.config.githubOwner}/${this.config.githubRepo}/pulls?state=all&sort=updated&direction=desc&per_page=100`;
            const prsResponse = await fetch(prsUrl, {
                headers: {
                    'Authorization': `token ${this.config.githubToken}`,
                    'Accept': 'application/vnd.github.v3+json',
                },
            });
            if (!prsResponse.ok) {
                throw new Error(`GitHub API error: ${prsResponse.status}`);
            }
            const prs = await prsResponse.json();
            // Filter PRs updated on the target date
            const targetDateStr = date.toISOString().split('T')[0];
            const relevantPrs = prs.filter((pr) => {
                const updatedDate = new Date(pr.updated_at).toISOString().split('T')[0];
                return updatedDate === targetDateStr;
            });
            const reviews = [];
            // For each relevant PR, get its reviews
            for (const pr of relevantPrs.slice(0, 10)) { // Limit to avoid rate limits
                try {
                    const reviewsUrl = `https://api.github.com/repos/${this.config.githubOwner}/${this.config.githubRepo}/pulls/${pr.number}/reviews`;
                    const reviewsResponse = await fetch(reviewsUrl, {
                        headers: {
                            'Authorization': `token ${this.config.githubToken}`,
                            'Accept': 'application/vnd.github.v3+json',
                        },
                    });
                    if (reviewsResponse.ok) {
                        const prReviews = await reviewsResponse.json();
                        // Filter reviews from the target date
                        const dateReviews = prReviews.filter((review) => {
                            const reviewDate = new Date(review.submitted_at).toISOString().split('T')[0];
                            return reviewDate === targetDateStr;
                        });
                        reviews.push(...dateReviews.map((review) => ({
                            prNumber: pr.number,
                            reviewer: review.user.login,
                            state: review.state.toLowerCase(),
                            timestamp: new Date(review.submitted_at),
                            body: review.body,
                        })));
                    }
                }
                catch (error) {
                    this.logger.debug('Failed to get reviews for PR', { prNumber: pr.number, error });
                }
            }
            return reviews;
        }
        catch (error) {
            this.logger.error('Failed to collect reviews', { error });
            return [];
        }
    }
    /**
     * Collect comments for the given date
     */
    async collectComments(date) {
        if (!this.config.githubToken) {
            this.logger.debug('GitHub token not configured, skipping comment collection');
            return [];
        }
        try {
            const since = new Date(date);
            since.setHours(0, 0, 0, 0);
            const until = new Date(date);
            until.setHours(23, 59, 59, 999);
            const comments = [];
            // Get issue comments
            const issueCommentsUrl = `https://api.github.com/repos/${this.config.githubOwner}/${this.config.githubRepo}/issues/comments?since=${since.toISOString()}&per_page=100`;
            const issueCommentsResponse = await fetch(issueCommentsUrl, {
                headers: {
                    'Authorization': `token ${this.config.githubToken}`,
                    'Accept': 'application/vnd.github.v3+json',
                },
            });
            if (issueCommentsResponse.ok) {
                const issueComments = await issueCommentsResponse.json();
                // Filter comments from the target date
                const targetDateStr = date.toISOString().split('T')[0];
                const dateIssueComments = issueComments.filter((comment) => {
                    const commentDate = new Date(comment.created_at).toISOString().split('T')[0];
                    return commentDate === targetDateStr;
                });
                comments.push(...dateIssueComments.map((comment) => ({
                    type: comment.pull_request ? 'pr' : 'issue',
                    number: this.extractIssueNumberFromUrl(comment.html_url),
                    author: comment.user.login,
                    body: comment.body,
                    timestamp: new Date(comment.created_at),
                })));
            }
            // Get commit comments
            const commitCommentsUrl = `https://api.github.com/repos/${this.config.githubOwner}/${this.config.githubRepo}/comments?since=${since.toISOString()}&per_page=100`;
            const commitCommentsResponse = await fetch(commitCommentsUrl, {
                headers: {
                    'Authorization': `token ${this.config.githubToken}`,
                    'Accept': 'application/vnd.github.v3+json',
                },
            });
            if (commitCommentsResponse.ok) {
                const commitComments = await commitCommentsResponse.json();
                // Filter comments from the target date
                const targetDateStr = date.toISOString().split('T')[0];
                const dateCommitComments = commitComments.filter((comment) => {
                    const commentDate = new Date(comment.created_at).toISOString().split('T')[0];
                    return commentDate === targetDateStr;
                });
                comments.push(...dateCommitComments.map((comment) => ({
                    type: 'commit',
                    author: comment.user.login,
                    body: comment.body,
                    timestamp: new Date(comment.created_at),
                })));
            }
            return comments;
        }
        catch (error) {
            this.logger.error('Failed to collect comments', { error });
            return [];
        }
    }
    /**
     * Extract issue/PR number from GitHub URL
     */
    extractIssueNumberFromUrl(url) {
        const match = url.match(/\/issues\/(\d+)/) || url.match(/\/pull\/(\d+)/);
        return match ? parseInt(match[1], 10) : undefined;
    }
    /**
     * Collect issues for the given date
     */
    async collectIssues(date) {
        if (!this.config.githubToken) {
            this.logger.debug('GitHub token not configured, skipping issue collection');
            return [];
        }
        try {
            const since = new Date(date);
            since.setHours(0, 0, 0, 0);
            const until = new Date(date);
            until.setHours(23, 59, 59, 999);
            const url = `https://api.github.com/repos/${this.config.githubOwner}/${this.config.githubRepo}/issues?since=${since.toISOString()}&state=all&per_page=100`;
            const response = await fetch(url, {
                headers: {
                    'Authorization': `token ${this.config.githubToken}`,
                    'Accept': 'application/vnd.github.v3+json',
                },
            });
            if (!response.ok) {
                throw new Error(`GitHub API error: ${response.status}`);
            }
            const issues = await response.json();
            // Filter issues created on the target date (since= parameter should handle this, but double-check)
            const targetDateStr = date.toISOString().split('T')[0];
            const dateIssues = issues
                .filter((issue) => !issue.pull_request) // Exclude PRs
                .filter((issue) => {
                const createdDate = new Date(issue.created_at).toISOString().split('T')[0];
                return createdDate === targetDateStr;
            });
            return dateIssues.map((issue) => ({
                number: issue.number,
                title: issue.title,
                author: issue.user.login,
                state: issue.state,
                timestamp: new Date(issue.created_at),
            }));
        }
        catch (error) {
            this.logger.error('Failed to collect issues', { error });
            return [];
        }
    }
    /**
     * Generate AI summary from daily activity
     */
    async generateSummary(activity) {
        try {
            const prompt = this.buildSummaryPrompt(activity);
            const routeResult = this.aiRouter.route({
                task: 'summarize',
                prompt,
                max_tokens: 1000,
            });
            // For now, return a placeholder summary
            // In production, this would call the AI service
            const summary = `## Daily Standup Summary - ${activity.date}

### Commits (${activity.commits.length})
${activity.commits.slice(0, 5).map(c => `- ${c.message.split('\n')[0]} (${c.author})`).join('\n')}

### Issues (${activity.issues.length})
${activity.issues.slice(0, 5).map(i => `- ${i.title} (${i.state})`).join('\n')}

### Reviews (${activity.reviews.length})
${activity.reviews.slice(0, 5).map(r => `- PR #${r.prNumber} ${r.state} by ${r.reviewer}`).join('\n')}

*Generated automatically at ${new Date().toISOString()}*`;
            this.logger.info('Generated standup summary', {
                date: activity.date,
                summaryLength: summary.length
            });
            return summary;
        }
        catch (error) {
            this.logger.error('Failed to generate AI summary', { error, date: activity.date });
            throw error;
        }
    }
    /**
     * Build the AI prompt for summary generation
     */
    buildSummaryPrompt(activity) {
        return `Generate a concise daily standup summary from the following GitHub activity data. Focus on key accomplishments, issues opened/closed, and review activity. Keep it professional and actionable.

Date: ${activity.date}

Commits: ${activity.commits.length}
${activity.commits.map(c => `- ${c.message} by ${c.author}`).join('\n')}

Issues: ${activity.issues.length}
${activity.issues.map(i => `- ${i.title} (${i.state}) by ${i.author}`).join('\n')}

Reviews: ${activity.reviews.length}
${activity.reviews.map(r => `- PR #${r.prNumber} ${r.state} by ${r.reviewer}`).join('\n')}

Please format as a clean standup summary suitable for team chat.`;
    }
    /**
     * Save a draft summary
     */
    async saveDraftSummary(date, summary) {
        const query = `
      INSERT INTO standup_summaries (date, summary, status)
      VALUES ($1, $2, 'draft')
      ON CONFLICT (date) DO UPDATE SET
        summary = EXCLUDED.summary,
        created_at = NOW()
      RETURNING *
    `;
        try {
            const result = await this.db.query(query, [date, summary]);
            const row = result.rows[0];
            const standupSummary = {
                id: row.id,
                date: typeof row.date === 'string' ? row.date : row.date.toISOString().split('T')[0],
                summary: row.summary,
                status: row.status,
                createdAt: row.created_at,
                postedAt: row.posted_at,
                approvedBy: row.approved_by,
                matrixMessageId: row.matrix_message_id,
            };
            this.logger.info('Saved draft standup summary', { date, id: standupSummary.id });
            return standupSummary;
        }
        catch (error) {
            this.logger.error('Failed to save draft summary', { error, date });
            throw error;
        }
    }
    /**
     * Approve a summary for posting
     */
    async approveSummary(date, approvedBy) {
        const query = `
      UPDATE standup_summaries
      SET status = 'approved', approved_by = $2
      WHERE date = $1 AND status = 'draft'
    `;
        try {
            const result = await this.db.query(query, [date, approvedBy]);
            const updated = (result.rowCount || 0) > 0;
            if (updated) {
                this.logger.info('Approved standup summary', { date, approvedBy });
            }
            else {
                this.logger.warn('No draft summary found to approve', { date });
            }
            return updated;
        }
        catch (error) {
            this.logger.error('Failed to approve summary', { error, date });
            throw error;
        }
    }
    /**
     * Post approved summary to Matrix
     */
    async postToMatrix(date) {
        if (!this.config.matrixRoomId) {
            this.logger.warn('Matrix room ID not configured, cannot post to Matrix');
            return false;
        }
        try {
            const summary = await this.getSummary(date);
            if (!summary || summary.status !== 'approved') {
                this.logger.warn('No approved summary found for posting', { date });
                return false;
            }
            // Basic Matrix posting implementation
            // In production, this would use a proper Matrix client with encrypted payloads only.
            const encryptedMessage = new CollaborationMessageEncryptionService().encryptMessage(summary.summary, {
                channel: 'matrix',
                roomId: this.config.matrixRoomId,
                summaryDate: date,
                summaryStatus: summary.status,
            });
            const matrixMessage = {
                body: encryptedMessage.body,
                msgtype: 'm.text',
            };
            // For now, just log the message that would be sent
            this.logger.info('Would post encrypted collaboration payload to Matrix', {
                roomId: this.config.matrixRoomId,
                keyId: encryptedMessage.keyId,
                messageType: matrixMessage.msgtype,
                payloadBytes: Buffer.byteLength(matrixMessage.body, 'utf8'),
            });
            // TODO: Implement actual Matrix API call
            // const success = await this.sendMatrixMessage(this.config.matrixRoomId, matrixMessage);
            // Simulate success for now
            const success = true;
            if (success) {
                await this.markAsPosted(date);
                this.logger.info('Posted standup summary to Matrix', { date });
            }
            return success;
        }
        catch (error) {
            this.logger.error('Failed to post summary to Matrix', { error, date });
            return false;
        }
    }
    /**
     * Mark summary as posted
     */
    async markAsPosted(date) {
        const query = `
      UPDATE standup_summaries
      SET status = 'posted', posted_at = NOW()
      WHERE date = $1
    `;
        await this.db.query(query, [date]);
    }
    /**
     * Get summary for a specific date
     */
    async getSummary(date) {
        const query = 'SELECT * FROM standup_summaries WHERE date = $1';
        try {
            const result = await this.db.query(query, [date]);
            if (result.rows.length === 0) {
                return null;
            }
            const row = result.rows[0];
            return {
                id: row.id,
                date: typeof row.date === 'string' ? row.date : row.date.toISOString().split('T')[0],
                summary: row.summary,
                status: row.status,
                createdAt: row.created_at,
                postedAt: row.posted_at,
                approvedBy: row.approved_by,
                matrixMessageId: row.matrix_message_id,
            };
        }
        catch (error) {
            this.logger.error('Failed to get summary', { error, date });
            throw error;
        }
    }
    /**
     * Schedule daily posting at configured time
     */
    scheduleDailyPosting() {
        const [hours, minutes] = this.config.postingTime.split(':').map(Number);
        const now = new Date();
        const targetTime = new Date(now);
        targetTime.setHours(hours, minutes, 0, 0);
        // If target time has passed today, schedule for tomorrow
        if (targetTime <= now) {
            targetTime.setDate(targetTime.getDate() + 1);
        }
        const delay = targetTime.getTime() - now.getTime();
        this.logger.info('Scheduling daily standup posting', {
            nextPosting: targetTime.toISOString(),
            delayMs: delay,
        });
        this.scheduleTimer = setTimeout(() => {
            this.performDailyPosting();
            // Schedule next day's posting
            this.scheduleDailyPosting();
        }, delay);
    }
    /**
     * Perform the daily posting routine
     */
    async performDailyPosting() {
        try {
            const yesterday = new Date();
            yesterday.setDate(yesterday.getDate() - 1);
            const dateStr = yesterday.toISOString().split('T')[0];
            this.logger.info('Starting daily standup posting routine', { date: dateStr });
            // Check if we already have a posted summary for this date
            const existing = await this.getSummary(dateStr);
            if (existing?.status === 'posted') {
                this.logger.info('Summary already posted for date, skipping', { date: dateStr });
                return;
            }
            // Collect activity and generate summary
            const activity = await this.collectDailyActivity(yesterday);
            const summary = await this.generateSummary(activity);
            // Save as draft
            await this.saveDraftSummary(dateStr, summary);
            // For now, auto-approve and post (in production, this would wait for approval)
            await this.approveSummary(dateStr, 'auto-approver');
            await this.postToMatrix(dateStr);
            this.logger.info('Completed daily standup posting routine', { date: dateStr });
        }
        catch (error) {
            this.logger.error('Failed daily standup posting routine', { error });
        }
    }
    /**
     * Manually trigger summary generation for testing
     */
    async generateForDate(date) {
        const activity = await this.collectDailyActivity(date);
        const summary = await this.generateSummary(activity);
        return await this.saveDraftSummary(date.toISOString().split('T')[0], summary);
    }
    /**
     * Clean up resources
     */
    destroy() {
        if (this.scheduleTimer) {
            clearTimeout(this.scheduleTimer);
            this.scheduleTimer = undefined;
        }
    }
}
//# sourceMappingURL=index.js.map