/**
 * @file        apps/backend/src/services/session-cost-tracking/index.ts
 * @module      collaboration/sessions
 * @description Session cost tracking and chargeback system for per-user and per-project billing
 */
import { EventEmitter } from 'events';
export class SessionCostTrackingService extends EventEmitter {
    static getInstance(config) {
        if (!SessionCostTrackingService.instance) {
            SessionCostTrackingService.instance = new SessionCostTrackingService(config);
        }
        return SessionCostTrackingService.instance;
    }
    constructor(config) {
        super();
        this.sessions = new Map();
        this.userSessions = new Map(); // userId -> sessionIds
        this.projectSessions = new Map(); // projectId -> sessionIds
        this.config = {
            computeCostPerMinute: 0.005, // $0.005 per compute minute
            storageCostPerGB: 0.1, // $0.10 per GB per month
            networkCostPerGB: 0.01, // $0.01 per GB
            apiCallCostPer1000: 0.01, // $0.01 per 1000 API calls
            concurrentSessionCost: 1.0, // $1 per concurrent session
        };
        if (config) {
            this.config = { ...this.config, ...config };
        }
        console.log('[SessionCostTracking] Session cost tracking service initialized');
    }
    /**
     * Start tracking a new session
     */
    startSession(sessionId, userId, projectId, teamId, metadata) {
        if (this.sessions.has(sessionId)) {
            throw new Error(`Session ${sessionId} already exists`);
        }
        const now = new Date();
        const session = {
            sessionId,
            userId,
            projectId,
            teamId,
            startTime: now,
            durationMinutes: 0,
            components: [],
            totalCost: 0,
            status: 'active',
            metadata,
        };
        this.sessions.set(sessionId, { session, lastUpdated: now });
        // Track user and project sessions
        if (!this.userSessions.has(userId)) {
            this.userSessions.set(userId, []);
        }
        this.userSessions.get(userId).push(sessionId);
        if (!this.projectSessions.has(projectId)) {
            this.projectSessions.set(projectId, []);
        }
        this.projectSessions.get(projectId).push(sessionId);
        this.emit('session-started', { sessionId, userId, projectId, startTime: now });
        return session;
    }
    /**
     * End tracking a session and finalize costs
     */
    endSession(sessionId) {
        const record = this.sessions.get(sessionId);
        if (!record) {
            throw new Error(`Session ${sessionId} not found`);
        }
        const now = new Date();
        const session = record.session;
        session.endTime = now;
        session.status = 'completed';
        // Calculate duration
        const durationMs = now.getTime() - session.startTime.getTime();
        session.durationMinutes = Math.ceil(durationMs / 60000);
        // Recalculate total cost
        session.totalCost = session.components.reduce((sum, comp) => sum + comp.totalCost, 0);
        // Add compute cost based on duration
        const computeCost = session.durationMinutes * this.config.computeCostPerMinute;
        session.components.push({
            type: 'compute',
            unit: 'minute',
            unitPrice: this.config.computeCostPerMinute,
            quantity: session.durationMinutes,
            totalCost: computeCost,
        });
        session.totalCost += computeCost;
        this.sessions.set(sessionId, { session, lastUpdated: now });
        this.emit('session-ended', {
            sessionId,
            userId: session.userId,
            projectId: session.projectId,
            durationMinutes: session.durationMinutes,
            totalCost: session.totalCost,
            endTime: now,
        });
        return session;
    }
    /**
     * Add a cost component to an active session (e.g., storage used, API calls)
     */
    addCostComponent(sessionId, component) {
        const record = this.sessions.get(sessionId);
        if (!record) {
            throw new Error(`Session ${sessionId} not found`);
        }
        const session = record.session;
        if (session.status !== 'active') {
            throw new Error(`Cannot add costs to non-active session`);
        }
        const componentWithCost = {
            ...component,
            totalCost: component.unitPrice * component.quantity,
        };
        session.components.push(componentWithCost);
        session.totalCost += componentWithCost.totalCost;
        record.lastUpdated = new Date();
        this.sessions.set(sessionId, record);
        this.emit('cost-added', { sessionId, component: componentWithCost });
        return session;
    }
    /**
     * Get session cost details
     */
    getSessionCost(sessionId) {
        return this.sessions.get(sessionId)?.session;
    }
    /**
     * Get user cost summary for a period
     */
    getUserCostSummary(userId, startDate, endDate, period = 'monthly') {
        const sessionIds = this.userSessions.get(userId) || [];
        let totalCost = 0;
        let sessionCount = 0;
        const costByProject = {};
        const costByComponent = {};
        sessionIds.forEach((sessionId) => {
            const record = this.sessions.get(sessionId);
            if (!record)
                return;
            const session = record.session;
            // Filter by date range
            if (session.startTime < startDate || (session.endTime && session.endTime > endDate)) {
                return;
            }
            totalCost += session.totalCost;
            sessionCount++;
            // Aggregate by project
            costByProject[session.projectId] = (costByProject[session.projectId] || 0) + session.totalCost;
            // Aggregate by component
            session.components.forEach((comp) => {
                costByComponent[comp.type] = (costByComponent[comp.type] || 0) + comp.totalCost;
            });
        });
        return {
            userId,
            period,
            startDate,
            endDate,
            totalCost,
            sessionCount,
            averageCostPerSession: sessionCount > 0 ? totalCost / sessionCount : 0,
            costByProject,
            costByComponent,
        };
    }
    /**
     * Get project cost summary for a period
     */
    getProjectCostSummary(projectId, startDate, endDate, period = 'monthly') {
        const sessionIds = this.projectSessions.get(projectId) || [];
        let totalCost = 0;
        let sessionCount = 0;
        const costByUser = {};
        const costByComponent = {};
        sessionIds.forEach((sessionId) => {
            const record = this.sessions.get(sessionId);
            if (!record)
                return;
            const session = record.session;
            // Filter by date range
            if (session.startTime < startDate || (session.endTime && session.endTime > endDate)) {
                return;
            }
            totalCost += session.totalCost;
            sessionCount++;
            // Aggregate by user
            costByUser[session.userId] = (costByUser[session.userId] || 0) + session.totalCost;
            // Aggregate by component
            session.components.forEach((comp) => {
                costByComponent[comp.type] = (costByComponent[comp.type] || 0) + comp.totalCost;
            });
        });
        return {
            projectId,
            period,
            startDate,
            endDate,
            totalCost,
            sessionCount,
            averageCostPerSession: sessionCount > 0 ? totalCost / sessionCount : 0,
            costByUser,
            costByComponent,
        };
    }
    /**
     * Get all sessions for a user
     */
    getUserSessions(userId) {
        const sessionIds = this.userSessions.get(userId) || [];
        return sessionIds
            .map((id) => this.sessions.get(id)?.session)
            .filter((s) => s !== undefined);
    }
    /**
     * Get all sessions for a project
     */
    getProjectSessions(projectId) {
        const sessionIds = this.projectSessions.get(projectId) || [];
        return sessionIds
            .map((id) => this.sessions.get(id)?.session)
            .filter((s) => s !== undefined);
    }
    /**
     * Get cost forecast for next period (linear extrapolation)
     */
    forecastUserCost(userId, days = 30) {
        const endDate = new Date();
        const startDate = new Date();
        startDate.setDate(endDate.getDate() - 7); // Last 7 days
        const summary = this.getUserCostSummary(userId, startDate, endDate, 'daily');
        const dailyAverageCost = summary.totalCost / 7;
        return dailyAverageCost * days;
    }
    /**
     * Get cost forecast for project (linear extrapolation)
     */
    forecastProjectCost(projectId, days = 30) {
        const endDate = new Date();
        const startDate = new Date();
        startDate.setDate(endDate.getDate() - 7); // Last 7 days
        const summary = this.getProjectCostSummary(projectId, startDate, endDate, 'daily');
        const dailyAverageCost = summary.totalCost / 7;
        return dailyAverageCost * days;
    }
    /**
     * Update pricing configuration
     */
    updatePricing(newPricing) {
        this.config = { ...this.config, ...newPricing };
        this.emit('pricing-updated', newPricing);
    }
    /**
     * Get all active sessions count
     */
    getActiveSessionsCount() {
        let count = 0;
        this.sessions.forEach((record) => {
            if (record.session.status === 'active') {
                count++;
            }
        });
        return count;
    }
    /**
     * Archive old sessions (older than specified days)
     */
    archiveOldSessions(olderThanDays) {
        const cutoffDate = new Date();
        cutoffDate.setDate(cutoffDate.getDate() - olderThanDays);
        let archivedCount = 0;
        const sessionIds = Array.from(this.sessions.keys());
        sessionIds.forEach((sessionId) => {
            const record = this.sessions.get(sessionId);
            if (!record)
                return;
            const session = record.session;
            if (session.status === 'completed' && session.endTime && session.endTime < cutoffDate) {
                session.status = 'archived';
                record.lastUpdated = new Date();
                this.sessions.set(sessionId, record);
                archivedCount++;
            }
        });
        if (archivedCount > 0) {
            this.emit('sessions-archived', { count: archivedCount, beforeDate: cutoffDate });
        }
        return archivedCount;
    }
    /**
     * Reset service state (for testing)
     */
    reset() {
        this.sessions.clear();
        this.userSessions.clear();
        this.projectSessions.clear();
        this.removeAllListeners();
    }
    /**
     * Shutdown service
     */
    shutdown() {
        this.reset();
        this.emit('shutdown');
    }
}
export default SessionCostTrackingService;
//# sourceMappingURL=index.js.map