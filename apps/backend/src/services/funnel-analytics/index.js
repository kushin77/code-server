#!/usr/bin/env node
/**
 * @file        apps/backend/src/services/funnel-analytics/index.ts
 * @module      services/analytics
 * @description Onboarding funnel analytics with conversion tracking
 */
import { EventEmitter } from 'events';
import { getLogger } from '../../lib/logger';
export class FunnelAnalyticsService extends EventEmitter {
    constructor(pool) {
        super();
        this.logger = getLogger('FunnelAnalyticsService');
        this.pool = pool;
    }
    async initialize() {
        this.logger.info('Initializing FunnelAnalyticsService');
        await this.createTables();
    }
    async createTables() {
        const client = await this.pool.connect();
        try {
            // Create funnel_events table
            await client.query(`
        CREATE TABLE IF NOT EXISTS funnel_events (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id UUID NOT NULL,
          event_type VARCHAR(255) NOT NULL,
          event_name VARCHAR(255) NOT NULL,
          occurred_at TIMESTAMP NOT NULL,
          metadata JSONB,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      `);
            // Create user_funnel_journeys table
            await client.query(`
        CREATE TABLE IF NOT EXISTS user_funnel_journeys (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id UUID NOT NULL,
          funnel_name VARCHAR(255) NOT NULL,
          current_step VARCHAR(255) NOT NULL,
          completed_steps TEXT[] DEFAULT ARRAY[]::TEXT[],
          started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          last_updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          UNIQUE(user_id, funnel_name)
        )
      `);
            // Create funnel_conversion_tracking table
            await client.query(`
        CREATE TABLE IF NOT EXISTS funnel_conversion_tracking (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          funnel_name VARCHAR(255) NOT NULL,
          step_number INTEGER NOT NULL,
          step_name VARCHAR(255) NOT NULL,
          total_users INTEGER DEFAULT 0,
          completed_count INTEGER DEFAULT 0,
          recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          UNIQUE(funnel_name, step_number)
        )
      `);
            // Create indexes
            await client.query(`CREATE INDEX IF NOT EXISTS idx_funnel_events_user_id ON funnel_events(user_id)`);
            await client.query(`CREATE INDEX IF NOT EXISTS idx_funnel_events_event_type ON funnel_events(event_type, occurred_at DESC)`);
            await client.query(`CREATE INDEX IF NOT EXISTS idx_user_funnel_journeys_user_id ON user_funnel_journeys(user_id)`);
            await client.query(`CREATE INDEX IF NOT EXISTS idx_user_funnel_journeys_funnel ON user_funnel_journeys(funnel_name)`);
            await client.query(`CREATE INDEX IF NOT EXISTS idx_funnel_conversion_tracking ON funnel_conversion_tracking(funnel_name, step_number)`);
            this.logger.info('Funnel analytics tables created successfully');
        }
        finally {
            client.release();
        }
    }
    async recordFunnelEvent(userId, eventType, eventName, metadata) {
        const client = await this.pool.connect();
        try {
            const occurredAt = new Date();
            await client.query(`INSERT INTO funnel_events (user_id, event_type, event_name, occurred_at, metadata)
         VALUES ($1, $2, $3, $4, $5)`, [userId, eventType, eventName, occurredAt, JSON.stringify(metadata || {})]);
            // Update user journey
            await this.updateUserJourney(client, userId, eventType);
            this.emit('funnel-event-recorded', { userId, eventType, eventName });
        }
        finally {
            client.release();
        }
    }
    async updateUserJourney(client, userId, eventType) {
        const funnelName = 'onboarding';
        const steps = ['invite', 'link_click', 'account_create', 'session_join', 'first_edit', 'seven_day_streak'];
        const stepIndex = steps.indexOf(eventType);
        if (stepIndex === -1)
            return;
        // Get or create journey
        const journeyResult = await client.query(`SELECT completed_steps, current_step FROM user_funnel_journeys
       WHERE user_id = $1 AND funnel_name = $2`, [userId, funnelName]);
        let completedSteps = [];
        if (journeyResult.rows.length > 0) {
            completedSteps = this.normalizeCompletedSteps(journeyResult.rows[0].completed_steps);
        }
        // Add event to completed steps if not already there
        if (!completedSteps.includes(eventType)) {
            completedSteps.push(eventType);
        }
        // Determine next step
        let nextStep = eventType;
        for (let i = stepIndex + 1; i < steps.length; i++) {
            if (!completedSteps.includes(steps[i])) {
                nextStep = steps[i];
                break;
            }
        }
        if (stepIndex === steps.length - 1) {
            nextStep = 'completed';
        }
        // Update or insert journey
        await client.query(`INSERT INTO user_funnel_journeys (user_id, funnel_name, current_step, completed_steps, last_updated_at)
       VALUES ($1, $2, $3, $4, CURRENT_TIMESTAMP)
       ON CONFLICT (user_id, funnel_name) DO UPDATE SET
       current_step = $3, completed_steps = $4, last_updated_at = CURRENT_TIMESTAMP`, [userId, funnelName, nextStep, completedSteps]);
        // Update conversion tracking
        await client.query(`INSERT INTO funnel_conversion_tracking (funnel_name, step_number, step_name, completed_count)
       VALUES ($1, $2, $3, 1)
       ON CONFLICT (funnel_name, step_number) DO UPDATE SET
       completed_count = funnel_conversion_tracking.completed_count + 1`, [funnelName, stepIndex, eventType]);
    }
    async getUserJourney(userId, funnelName = 'onboarding') {
        const client = await this.pool.connect();
        try {
            const result = await client.query(`SELECT user_id, current_step, completed_steps FROM user_funnel_journeys
         WHERE user_id = $1 AND funnel_name = $2`, [userId, funnelName]);
            if (result.rows.length === 0) {
                return null;
            }
            const row = result.rows[0];
            // Get timestamps for each step
            const eventResult = await client.query(`SELECT event_type, occurred_at FROM funnel_events
         WHERE user_id = $1
         ORDER BY occurred_at ASC`, [userId]);
            const events = {};
            eventResult.rows.forEach(event => {
                events[event.event_type] = new Date(event.occurred_at);
            });
            return {
                userId,
                inviteTime: events['invite'],
                linkClickTime: events['link_click'],
                accountCreateTime: events['account_create'],
                sessionJoinTime: events['session_join'],
                firstEditTime: events['first_edit'],
                sevenDayStreakTime: events['seven_day_streak'],
                currentStep: row.current_step,
                completedSteps: this.normalizeCompletedSteps(row.completed_steps)
            };
        }
        finally {
            client.release();
        }
    }
    normalizeCompletedSteps(value) {
        if (Array.isArray(value)) {
            return value.map(step => String(step));
        }
        if (typeof value === 'string' && value.length > 0) {
            try {
                const parsed = JSON.parse(value);
                if (Array.isArray(parsed)) {
                    return parsed.map(step => String(step));
                }
            }
            catch {
                return value
                    .split(',')
                    .map(step => step.trim())
                    .filter(Boolean);
            }
        }
        return [];
    }
    async getFunnelMetrics(funnelName = 'onboarding') {
        const client = await this.pool.connect();
        try {
            // Get total users
            const totalUsersResult = await client.query(`SELECT COUNT(DISTINCT user_id) as count FROM funnel_events
         WHERE event_type IN ('invite', 'link_click', 'account_create', 'session_join', 'first_edit', 'seven_day_streak')`);
            const totalUsers = totalUsersResult.rows[0].count;
            // Get conversion metrics for each step
            const stepsResult = await client.query(`SELECT step_number, step_name, completed_count FROM funnel_conversion_tracking
         WHERE funnel_name = $1
         ORDER BY step_number ASC`, [funnelName]);
            const steps = ['invite', 'link_click', 'account_create', 'session_join', 'first_edit', 'seven_day_streak'];
            const funnel = [];
            let previousCount = totalUsers;
            stepsResult.rows.forEach((row, index) => {
                const count = row.completed_count;
                const conversionRate = previousCount > 0 ? (count / previousCount) * 100 : 0;
                funnel.push({
                    stepId: `step_${index}`,
                    stepName: row.step_name,
                    count,
                    conversionRate
                });
                previousCount = count;
            });
            // Calculate overall metrics
            const finalConversions = stepsResult.rows.length > 0 ? stepsResult.rows[stepsResult.rows.length - 1].completed_count : 0;
            const overallConversionRate = totalUsers > 0 ? (finalConversions / totalUsers) * 100 : 0;
            const dropoffRate = 100 - overallConversionRate;
            return {
                funnel,
                totalUsers,
                totalConversions: finalConversions,
                overallConversionRate,
                dropoffRate
            };
        }
        finally {
            client.release();
        }
    }
    async getConversionRateByStep(funnelName, stepNumber) {
        const client = await this.pool.connect();
        try {
            const result = await client.query(`SELECT completed_count FROM funnel_conversion_tracking
         WHERE funnel_name = $1 AND step_number = $2`, [funnelName, stepNumber]);
            if (result.rows.length === 0)
                return 0;
            const completedCount = result.rows[0].completed_count;
            // Get previous step count for conversion rate
            const prevResult = await client.query(`SELECT completed_count FROM funnel_conversion_tracking
         WHERE funnel_name = $1 AND step_number = $2`, [funnelName, stepNumber - 1]);
            const prevCount = prevResult.rows.length > 0 ? prevResult.rows[0].completed_count : completedCount;
            return prevCount > 0 ? (completedCount / prevCount) * 100 : 100;
        }
        finally {
            client.release();
        }
    }
    async trackConversionBySegment(userId, segmentName) {
        const client = await this.pool.connect();
        try {
            const journey = await this.getUserJourney(userId);
            if (journey) {
                this.emit('conversion-tracked', {
                    userId,
                    segment: segmentName,
                    completionRate: journey.completedSteps.length / 6
                });
            }
        }
        finally {
            client.release();
        }
    }
    async getDropoffRate(funnelName, fromStep, toStep) {
        const client = await this.pool.connect();
        try {
            const fromResult = await client.query(`SELECT completed_count FROM funnel_conversion_tracking
         WHERE funnel_name = $1 AND step_number = $2`, [funnelName, fromStep]);
            const toResult = await client.query(`SELECT completed_count FROM funnel_conversion_tracking
         WHERE funnel_name = $1 AND step_number = $2`, [funnelName, toStep]);
            if (fromResult.rows.length === 0)
                return 0;
            const fromCount = fromResult.rows[0].completed_count;
            const toCount = toResult.rows.length > 0 ? toResult.rows[0].completed_count : 0;
            return fromCount > 0 ? ((fromCount - toCount) / fromCount) * 100 : 0;
        }
        finally {
            client.release();
        }
    }
    async cleanupOldFunnelData(daysOld = 90) {
        const client = await this.pool.connect();
        try {
            const cutoffDate = new Date();
            cutoffDate.setDate(cutoffDate.getDate() - daysOld);
            const result = await client.query(`DELETE FROM funnel_events
         WHERE created_at < $1`, [cutoffDate]);
            this.emit('funnel-data-cleaned', { count: result.rowCount, daysOld });
            return result.rowCount || 0;
        }
        finally {
            client.release();
        }
    }
}
export async function initializeFunnelAnalyticsRoutes(service) {
    const { Router } = require('express');
    const router = Router();
    const logger = getLogger('FunnelAnalyticsRoutes');
    router.post('/api/funnel/events', async (req, res) => {
        try {
            const { userId, eventType, eventName, metadata } = req.body;
            await service.recordFunnelEvent(userId, eventType, eventName, metadata);
            res.json({ success: true });
        }
        catch (error) {
            logger.error('Failed to record funnel event', error);
            res.status(500).json({ error: 'Failed to record funnel event' });
        }
    });
    router.get('/api/funnel/journey/:userId', async (req, res) => {
        try {
            const { userId } = req.params;
            const funnelName = req.query.funnel || 'onboarding';
            const journey = await service.getUserJourney(userId, funnelName);
            if (!journey) {
                return res.status(404).json({ error: 'Journey not found' });
            }
            res.json(journey);
        }
        catch (error) {
            logger.error('Failed to get user journey', error);
            res.status(500).json({ error: 'Failed to get user journey' });
        }
    });
    router.get('/api/funnel/metrics', async (req, res) => {
        try {
            const funnelName = req.query.funnel || 'onboarding';
            const metrics = await service.getFunnelMetrics(funnelName);
            res.json(metrics);
        }
        catch (error) {
            logger.error('Failed to get funnel metrics', error);
            res.status(500).json({ error: 'Failed to get funnel metrics' });
        }
    });
    router.get('/api/funnel/conversion-rate/:stepNumber', async (req, res) => {
        try {
            const { stepNumber } = req.params;
            const funnelName = req.query.funnel || 'onboarding';
            const rate = await service.getConversionRateByStep(funnelName, parseInt(stepNumber));
            res.json({ conversionRate: rate });
        }
        catch (error) {
            logger.error('Failed to get conversion rate', error);
            res.status(500).json({ error: 'Failed to get conversion rate' });
        }
    });
    router.post('/api/funnel/conversion/track', async (req, res) => {
        try {
            const { userId, segmentName } = req.body;
            await service.trackConversionBySegment(userId, segmentName);
            res.json({ success: true });
        }
        catch (error) {
            logger.error('Failed to track conversion', error);
            res.status(500).json({ error: 'Failed to track conversion' });
        }
    });
    router.get('/api/funnel/dropoff', async (req, res) => {
        try {
            const funnelName = req.query.funnel || 'onboarding';
            const fromStep = parseInt(req.query.from) || 0;
            const toStep = parseInt(req.query.to) || 1;
            const dropoff = await service.getDropoffRate(funnelName, fromStep, toStep);
            res.json({ dropoffRate: dropoff });
        }
        catch (error) {
            logger.error('Failed to get dropoff rate', error);
            res.status(500).json({ error: 'Failed to get dropoff rate' });
        }
    });
    return router;
}
//# sourceMappingURL=index.js.map