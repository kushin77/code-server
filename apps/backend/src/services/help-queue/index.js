#!/usr/bin/env node
// @file        apps/backend/src/services/help-queue/index.ts
// @module      collaboration/help-queue
// @description Async help queue with AI enrichment, expert routing, and SLA tracking
// @owner       collab-4.7
// @status      active
import { EventEmitter } from 'events';
import { getLogger } from '../../lib/logger';
export class HelpQueueService extends EventEmitter {
    constructor(pool, auditService, config = {}) {
        super();
        this.logger = getLogger('HelpQueueService');
        this.initialized = false;
        this.pool = pool;
        this.auditService = auditService;
        console.log('DEBUG: HelpQueueService started with auditService:', !!this.auditService);
        this.config = {
            urgentSlaHours: config.urgentSlaHours || 2,
            normalSlaHours: config.normalSlaHours || 24,
            lowSlaDays: config.lowSlaDays || 7,
            maxConcurrentPerExpert: config.maxConcurrentPerExpert || 5,
        };
    }
    async initialize() {
        if (this.initialized)
            return;
        try {
            await this.createTables();
            this.initialized = true;
            this.logger.info('Help queue database schema initialized');
        }
        catch (error) {
            this.logger.error('Failed to initialize help queue schema', { error });
            throw error;
        }
    }
    async createTables() {
        const client = await this.pool.connect();
        try {
            await client.query('BEGIN');
            // Help requests
            await client.query(`
        CREATE TABLE IF NOT EXISTS help_requests (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id TEXT NOT NULL,
          code_snippet JSONB NOT NULL,
          question TEXT NOT NULL,
          enriched_question TEXT,
          urgency TEXT NOT NULL CHECK (urgency IN ('urgent', 'normal', 'low')),
          status TEXT NOT NULL CHECK (status IN ('open', 'assigned', 'in-progress', 'resolved', 'closed')),
          tags TEXT[],
          assigned_to TEXT,
          resolved_at TIMESTAMP WITH TIME ZONE,
          sla_due_at TIMESTAMP WITH TIME ZONE NOT NULL,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        )
      `);
            // Help responses
            await client.query(`
        CREATE TABLE IF NOT EXISTS help_responses (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          request_id UUID NOT NULL REFERENCES help_requests(id) ON DELETE CASCADE,
          expert_id TEXT NOT NULL,
          response TEXT NOT NULL,
          code_proposal TEXT,
          verified_by_expert BOOLEAN DEFAULT false,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        )
      `);
            // SLA tracking
            await client.query(`
        CREATE TABLE IF NOT EXISTS sla_metrics (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          request_id UUID NOT NULL REFERENCES help_requests(id) ON DELETE CASCADE,
          urgency TEXT NOT NULL,
          created_at TIMESTAMP WITH TIME ZONE NOT NULL,
          sla_due_at TIMESTAMP WITH TIME ZONE NOT NULL,
          resolved_at TIMESTAMP WITH TIME ZONE,
          sla_breached BOOLEAN,
          resolution_time_ms INTEGER
        )
      `);
            // Expert profiles
            await client.query(`
        CREATE TABLE IF NOT EXISTS expert_profiles (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id TEXT NOT NULL UNIQUE,
          expertise TEXT[] NOT NULL,
          current_queue_size INTEGER DEFAULT 0,
          average_resolution_time_ms INTEGER,
          sla_breach_rate NUMERIC(4, 3),
          is_available BOOLEAN DEFAULT true,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        )
      `);
            // Request history for audit
            await client.query(`
        CREATE TABLE IF NOT EXISTS help_request_history (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          request_id UUID NOT NULL REFERENCES help_requests(id) ON DELETE CASCADE,
          status_from TEXT,
          status_to TEXT NOT NULL,
          changed_by TEXT,
          reason TEXT,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        )
      `);
            // Indexes
            await client.query(`
        CREATE INDEX IF NOT EXISTS idx_help_requests_user ON help_requests(user_id);
        CREATE INDEX IF NOT EXISTS idx_help_requests_status ON help_requests(status);
        CREATE INDEX IF NOT EXISTS idx_help_requests_urgency ON help_requests(urgency);
        CREATE INDEX IF NOT EXISTS idx_help_requests_assigned ON help_requests(assigned_to);
        CREATE INDEX IF NOT EXISTS idx_help_responses_request ON help_responses(request_id);
        CREATE INDEX IF NOT EXISTS idx_help_responses_expert ON help_responses(expert_id);
        CREATE INDEX IF NOT EXISTS idx_sla_metrics_breached ON sla_metrics(sla_breached);
        CREATE INDEX IF NOT EXISTS idx_expert_profiles_available ON expert_profiles(is_available);
        CREATE INDEX IF NOT EXISTS idx_request_history_request ON help_request_history(request_id);
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
    async createRequest(userId, codeSnippet, question, urgency = 'normal', tags) {
        const client = await this.pool.connect();
        try {
            const slaDueAt = this.calculateSlaDueDate(urgency);
            const id = require('crypto').randomUUID();
            await client.query(`INSERT INTO help_requests (id, user_id, code_snippet, question, urgency, status, tags, sla_due_at)
         VALUES ($1, $2, $3, $4, $5, 'open', $6, $7)`, [id, userId, JSON.stringify(codeSnippet), question, urgency, tags || [], slaDueAt]);
            // SOC2: Audit request creation
            this.auditService?.emit({
                userId,
                action: 'create',
                resource: `help-request:${id}`,
                resourceType: 'help-request',
                reason: `Help request created by ${userId}`,
                metadata: { urgency, tags, filePath: codeSnippet.filePath }
            });
            this.logger.info('Help request created', { requestId: id, userId, urgency });
            return {
                id,
                userId,
                codeSnippet,
                question,
                urgency,
                status: 'open',
                tags,
                createdAt: new Date(),
                updatedAt: new Date(),
                slaDueAt,
            };
        }
        catch (error) {
            this.logger.error('Failed to create help request', { error, userId });
            throw error;
        }
        finally {
            client.release();
        }
    }
    async enrichQuestion(requestId, enrichedQuestion) {
        const client = await this.pool.connect();
        try {
            await client.query(`UPDATE help_requests SET enriched_question = $1, updated_at = NOW()
         WHERE id = $2`, [enrichedQuestion, requestId]);
            this.logger.info('Question enriched', { requestId });
        }
        catch (error) {
            this.logger.error('Failed to enrich question', { error, requestId });
            throw error;
        }
        finally {
            client.release();
        }
    }
    async assignToExpert(requestId, expertId) {
        const client = await this.pool.connect();
        try {
            await client.query('BEGIN');
            // Check expert availability
            const expertResult = await client.query(`SELECT current_queue_size FROM expert_profiles WHERE user_id = $1`, [expertId]);
            if (expertResult.rows.length === 0) {
                throw new Error(`Expert ${expertId} not found`);
            }
            const queueSize = expertResult.rows[0].current_queue_size || 0;
            if (queueSize >= this.config.maxConcurrentPerExpert) {
                throw new Error(`Expert ${expertId} is at max capacity`);
            }
            // Update request
            await client.query(`UPDATE help_requests SET assigned_to = $1, status = 'assigned', updated_at = NOW()
         WHERE id = $2`, [expertId, requestId]);
            // Update expert queue size
            await client.query(`UPDATE expert_profiles SET current_queue_size = current_queue_size + 1
         WHERE user_id = $1`, [expertId]);
            // Record history
            await client.query(`INSERT INTO help_request_history (request_id, status_from, status_to, changed_by, reason)
         VALUES ($1, 'open', 'assigned', $2, 'Assigned to expert')`, [requestId, expertId]);
            await client.query('COMMIT');
            this.auditService?.emit({
                userId: expertId,
                action: 'update',
                resource: `help-request:${requestId}`,
                resourceType: 'help-request',
                reason: 'Assigned help request to expert',
                metadata: { requestId, expertId }
            });
            this.logger.info('Request assigned to expert', { requestId, expertId });
        }
        catch (error) {
            await client.query('ROLLBACK');
            this.logger.error('Failed to assign request', { error, requestId, expertId });
            throw error;
        }
        finally {
            client.release();
        }
    }
    async respondToRequest(requestId, expertId, response, codeProposal) {
        const client = await this.pool.connect();
        try {
            const responseId = require('crypto').randomUUID();
            await client.query(`INSERT INTO help_responses (id, request_id, expert_id, response, code_proposal)
         VALUES ($1, $2, $3, $4, $5)`, [responseId, requestId, expertId, response, codeProposal || null]);
            this.auditService?.emit({
                userId: expertId,
                action: 'create',
                resource: `help-response:${responseId}`,
                resourceType: 'help-response',
                reason: 'Added help response',
                metadata: { requestId, codeProposal: !!codeProposal }
            });
            this.logger.info('Response added', { requestId, expertId });
        }
        catch (error) {
            this.logger.error('Failed to add response', { error, requestId });
            throw error;
        }
        finally {
            client.release();
        }
    }
    async resolveRequest(requestId, expertId) {
        const client = await this.pool.connect();
        try {
            await client.query('BEGIN');
            // Get request details
            const requestResult = await client.query(`SELECT user_id, assigned_to, urgency, created_at, sla_due_at FROM help_requests WHERE id = $1`, [requestId]);
            if (requestResult.rows.length === 0) {
                throw new Error(`Request ${requestId} not found`);
            }
            const request = requestResult.rows[0];
            const now = new Date();
            const resolutionTimeMs = now.getTime() - new Date(request.created_at).getTime();
            const slaBreached = now > new Date(request.sla_due_at);
            // Update request
            await client.query(`UPDATE help_requests SET status = 'resolved', resolved_at = NOW(), updated_at = NOW()
         WHERE id = $1`, [requestId]);
            // Record SLA metric
            await client.query(`INSERT INTO sla_metrics (request_id, urgency, created_at, sla_due_at, resolved_at, sla_breached, resolution_time_ms)
         VALUES ($1, $2, $3, $4, $5, $6, $7)`, [requestId, request.urgency, request.created_at, request.sla_due_at, now, slaBreached, resolutionTimeMs]);
            // Update expert queue size
            await client.query(`UPDATE expert_profiles SET current_queue_size = GREATEST(0, current_queue_size - 1)
         WHERE user_id = $1`, [request.assigned_to]);
            // Record history
            await client.query(`INSERT INTO help_request_history (request_id, status_from, status_to, changed_by, reason)
         VALUES ($1, 'in-progress', 'resolved', $2, 'Resolved by expert')`, [requestId, expertId]);
            await client.query('COMMIT');
            this.auditService?.emit({
                userId: expertId,
                action: 'update',
                resource: `help-request:${requestId}`,
                resourceType: 'help-request',
                reason: 'Resolved help request',
                metadata: { slaBreached, resolutionTimeMs, urgency: request.urgency }
            });
            this.logger.info('Request resolved', { requestId, slaBreached, resolutionTimeMs });
            return {
                requestId,
                urgency: request.urgency,
                createdAt: new Date(request.created_at),
                slaDueAt: new Date(request.sla_due_at),
                resolvedAt: now,
                slaBreached,
                resolutionTimeMs,
            };
        }
        catch (error) {
            await client.query('ROLLBACK');
            this.logger.error('Failed to resolve request', { error, requestId });
            throw error;
        }
        finally {
            client.release();
        }
    }
    async getRequest(requestId) {
        const client = await this.pool.connect();
        try {
            const result = await client.query(`SELECT * FROM help_requests WHERE id = $1`, [requestId]);
            if (result.rows.length === 0) {
                return null;
            }
            const row = result.rows[0];
            return {
                id: row.id,
                userId: row.user_id,
                codeSnippet: row.code_snippet,
                question: row.question,
                enrichedQuestion: row.enriched_question,
                urgency: row.urgency,
                status: row.status,
                tags: row.tags,
                createdAt: new Date(row.created_at),
                updatedAt: new Date(row.updated_at),
                assignedTo: row.assigned_to,
                resolvedAt: row.resolved_at ? new Date(row.resolved_at) : undefined,
                slaDueAt: new Date(row.sla_due_at),
            };
        }
        catch (error) {
            this.logger.error('Failed to get request', { error, requestId });
            throw error;
        }
        finally {
            client.release();
        }
    }
    async getUserRequests(userId, status) {
        const client = await this.pool.connect();
        try {
            let query = 'SELECT * FROM help_requests WHERE user_id = $1';
            const params = [userId];
            if (status) {
                query += ' AND status = $2';
                params.push(status);
            }
            query += ' ORDER BY created_at DESC';
            const result = await client.query(query, params);
            return result.rows.map(row => ({
                id: row.id,
                userId: row.user_id,
                codeSnippet: row.code_snippet,
                question: row.question,
                enrichedQuestion: row.enriched_question,
                urgency: row.urgency,
                status: row.status,
                tags: row.tags,
                createdAt: new Date(row.created_at),
                updatedAt: new Date(row.updated_at),
                assignedTo: row.assigned_to,
                resolvedAt: row.resolved_at ? new Date(row.resolved_at) : undefined,
                slaDueAt: new Date(row.sla_due_at),
            }));
        }
        catch (error) {
            this.logger.error('Failed to get user requests', { error, userId });
            throw error;
        }
        finally {
            client.release();
        }
    }
    async getOpenRequests(limit = 10) {
        const client = await this.pool.connect();
        try {
            const result = await client.query(`SELECT * FROM help_requests WHERE status IN ('open', 'assigned')
         ORDER BY urgency = 'urgent' DESC, created_at ASC LIMIT $1`, [limit]);
            return result.rows.map(row => ({
                id: row.id,
                userId: row.user_id,
                codeSnippet: row.code_snippet,
                question: row.question,
                enrichedQuestion: row.enriched_question,
                urgency: row.urgency,
                status: row.status,
                tags: row.tags,
                createdAt: new Date(row.created_at),
                updatedAt: new Date(row.updated_at),
                assignedTo: row.assigned_to,
                resolvedAt: row.resolved_at ? new Date(row.resolved_at) : undefined,
                slaDueAt: new Date(row.sla_due_at),
            }));
        }
        catch (error) {
            this.logger.error('Failed to get open requests', { error });
            throw error;
        }
        finally {
            client.release();
        }
    }
    async getSLAMetrics(timeframeMs = 7 * 24 * 60 * 60 * 1000) {
        const client = await this.pool.connect();
        try {
            const result = await client.query(`SELECT 
          COUNT(*) as total_requests,
          SUM(CASE WHEN sla_breached THEN 1 ELSE 0 END) as sla_breached,
          AVG(resolution_time_ms) as avg_resolution_time
         FROM sla_metrics 
         WHERE created_at >= NOW() - INTERVAL '1 ms' * $1`, [timeframeMs]);
            const row = result.rows[0];
            const totalRequests = parseInt(row.total_requests, 10);
            const slaBreached = parseInt(row.sla_breached || '0', 10);
            return {
                totalRequests,
                slaBreached,
                breachRate: totalRequests > 0 ? slaBreached / totalRequests : 0,
                avgResolutionTime: parseInt(row.avg_resolution_time || '0', 10),
            };
        }
        catch (error) {
            this.logger.error('Failed to get SLA metrics', { error });
            throw error;
        }
        finally {
            client.release();
        }
    }
    async registerExpert(userId, expertise) {
        const client = await this.pool.connect();
        try {
            await client.query(`INSERT INTO expert_profiles (user_id, expertise) VALUES ($1, $2)
         ON CONFLICT (user_id) DO UPDATE SET expertise = $2`, [userId, expertise]);
            this.auditService?.emit({
                userId,
                action: 'update',
                resource: `expert:${userId}`,
                resourceType: 'expert',
                reason: 'Registered help queue expert',
                metadata: { expertise }
            });
            this.logger.info('Expert registered', { userId, expertise });
        }
        catch (error) {
            this.logger.error('Failed to register expert', { error, userId });
            throw error;
        }
        finally {
            client.release();
        }
    }
    async getAvailableExperts(tags) {
        const client = await this.pool.connect();
        try {
            let query = `SELECT * FROM expert_profiles WHERE is_available = true`;
            const params = [];
            if (tags && tags.length > 0) {
                query += ` AND expertise && $1`;
                params.push(tags);
            }
            query += ` ORDER BY current_queue_size ASC`;
            const result = await client.query(query, params);
            return result.rows.map(row => ({
                userId: row.user_id,
                expertise: row.expertise,
                currentQueueSize: row.current_queue_size,
                averageResolutionTime: row.average_resolution_time_ms || 0,
                slaBreachRate: parseFloat(row.sla_breach_rate || '0'),
                isAvailable: row.is_available,
            }));
        }
        catch (error) {
            this.logger.error('Failed to get available experts', { error });
            throw error;
        }
        finally {
            client.release();
        }
    }
    calculateSlaDueDate(urgency) {
        const now = new Date();
        switch (urgency) {
            case 'urgent':
                return new Date(now.getTime() + this.config.urgentSlaHours * 60 * 60 * 1000);
            case 'normal':
                return new Date(now.getTime() + this.config.normalSlaHours * 60 * 60 * 1000);
            case 'low':
                return new Date(now.getTime() + this.config.lowSlaDays * 24 * 60 * 60 * 1000);
            default:
                return new Date(now.getTime() + this.config.normalSlaHours * 60 * 60 * 1000);
        }
    }
}
//# sourceMappingURL=index.js.map