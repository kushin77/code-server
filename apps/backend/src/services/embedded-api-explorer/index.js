#!/usr/bin/env node
/**
 * @file        apps/backend/src/services/embedded-api-explorer/index.ts
 * @module      services/developer-experience
 * @description REST/GraphQL API explorer with OpenAPI import and response diff
 */
import { EventEmitter } from 'events';
import { getLogger } from '../../lib/logger';
export class EmbeddedAPIExplorerService extends EventEmitter {
    constructor(pool) {
        super();
        this.logger = getLogger('EmbeddedAPIExplorerService');
        this.pool = pool;
    }
    async initialize() {
        this.logger.info('Initializing EmbeddedAPIExplorerService');
        await this.createTables();
    }
    async createTables() {
        const client = await this.pool.connect();
        try {
            // Create api_requests table
            await client.query(`
        CREATE TABLE IF NOT EXISTS api_requests (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id UUID NOT NULL,
          method VARCHAR(20) NOT NULL,
          url TEXT NOT NULL,
          headers JSONB DEFAULT '{}',
          body TEXT,
          variables JSONB,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      `);
            // Create api_responses table
            await client.query(`
        CREATE TABLE IF NOT EXISTS api_responses (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          request_id UUID NOT NULL REFERENCES api_requests(id) ON DELETE CASCADE,
          status_code INTEGER,
          headers JSONB DEFAULT '{}',
          body TEXT,
          execution_time_ms FLOAT,
          timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      `);
            // Create api_openapi_imports table
            await client.query(`
        CREATE TABLE IF NOT EXISTS api_openapi_imports (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id UUID NOT NULL,
          openapi_spec JSONB NOT NULL,
          title VARCHAR(255),
          version VARCHAR(50),
          imported_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      `);
            // Create api_request_history table
            await client.query(`
        CREATE TABLE IF NOT EXISTS api_request_history (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id UUID NOT NULL,
          request_id UUID NOT NULL,
          executed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY (request_id) REFERENCES api_requests(id) ON DELETE CASCADE
        )
      `);
            // Create api_shared_requests table
            await client.query(`
        CREATE TABLE IF NOT EXISTS api_shared_requests (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          request_id UUID NOT NULL REFERENCES api_requests(id) ON DELETE CASCADE,
          shared_by_user_id UUID NOT NULL,
          shared_with_user_id UUID,
          team_id UUID,
          shared_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      `);
            // Create indexes
            await client.query(`CREATE INDEX IF NOT EXISTS idx_api_requests_user_id ON api_requests(user_id)`);
            await client.query(`CREATE INDEX IF NOT EXISTS idx_api_responses_request_id ON api_responses(request_id)`);
            await client.query(`CREATE INDEX IF NOT EXISTS idx_api_openapi_imports_user_id ON api_openapi_imports(user_id)`);
            await client.query(`CREATE INDEX IF NOT EXISTS idx_api_request_history_user_id ON api_request_history(user_id)`);
            await client.query(`CREATE INDEX IF NOT EXISTS idx_api_shared_requests_request_id ON api_shared_requests(request_id)`);
            this.logger.info('API explorer tables created successfully');
        }
        finally {
            client.release();
        }
    }
    async createRequest(userId, method, url, headers, body, variables) {
        const client = await this.pool.connect();
        try {
            const result = await client.query(`INSERT INTO api_requests (user_id, method, url, headers, body, variables)
         VALUES ($1, $2, $3, $4, $5, $6)
         RETURNING id`, [userId, method, url, JSON.stringify(headers), body, JSON.stringify(variables)]);
            const requestId = result.rows[0].id;
            this.emit('request-created', { requestId, method, url });
            return requestId;
        }
        finally {
            client.release();
        }
    }
    async getRequest(requestId) {
        const client = await this.pool.connect();
        try {
            const result = await client.query(`SELECT id, user_id, method, url, headers, body, variables, created_at FROM api_requests WHERE id = $1`, [requestId]);
            if (result.rows.length === 0)
                return null;
            const row = result.rows[0];
            return {
                id: row.id,
                userId: row.user_id,
                method: row.method,
                url: row.url,
                headers: row.headers,
                body: row.body,
                variables: row.variables,
                createdAt: row.created_at
            };
        }
        finally {
            client.release();
        }
    }
    async executeRequest(requestId, injectedVars) {
        const client = await this.pool.connect();
        try {
            const request = await this.getRequest(requestId);
            if (!request)
                throw new Error('Request not found');
            // Inject environment variables
            let finalUrl = request.url;
            let finalHeaders = { ...request.headers };
            let finalBody = request.body || '';
            if (injectedVars) {
                Object.entries(injectedVars).forEach(([key, value]) => {
                    finalUrl = finalUrl.replace(`$${key}`, value);
                    Object.keys(finalHeaders).forEach(h => {
                        finalHeaders[h] = finalHeaders[h].replace(`$${key}`, value);
                    });
                    finalBody = finalBody.replace(`$${key}`, value);
                });
            }
            const startTime = Date.now();
            // Mock execution (in real scenario, would make actual HTTP request)
            let statusCode = 200;
            let responseBody = '{}';
            try {
                // Simulate API call with timeout
                await new Promise(resolve => setTimeout(resolve, 50));
                statusCode = 200;
                responseBody = JSON.stringify({ success: true, data: { endpoint: finalUrl, method: request.method } });
            }
            catch (error) {
                statusCode = 500;
                responseBody = JSON.stringify({ error: 'Request failed' });
            }
            const executionTime = Date.now() - startTime;
            // Record response
            await client.query(`INSERT INTO api_responses (request_id, status_code, headers, body, execution_time_ms)
         VALUES ($1, $2, $3, $4, $5)`, [requestId, statusCode, JSON.stringify(finalHeaders), responseBody, executionTime]);
            // Record in history
            const requestData = await this.getRequest(requestId);
            if (requestData) {
                await client.query(`INSERT INTO api_request_history (user_id, request_id) VALUES ($1, $2)`, [requestData.userId, requestId]);
            }
            this.emit('request-executed', { requestId, statusCode, executionTime });
            return {
                requestId,
                statusCode,
                headers: finalHeaders,
                body: responseBody,
                executionTime,
                timestamp: new Date()
            };
        }
        finally {
            client.release();
        }
    }
    async importOpenAPI(userId, openApiSpec) {
        const client = await this.pool.connect();
        try {
            const title = openApiSpec.info?.title || 'Imported API';
            const version = openApiSpec.info?.version || '1.0.0';
            const result = await client.query(`INSERT INTO api_openapi_imports (user_id, openapi_spec, title, version)
         VALUES ($1, $2, $3, $4)
         RETURNING id`, [userId, JSON.stringify(openApiSpec), title, version]);
            const importId = result.rows[0].id;
            // Auto-create requests from OpenAPI paths
            if (openApiSpec.paths) {
                for (const [path, pathItem] of Object.entries(openApiSpec.paths)) {
                    for (const [method, operation] of Object.entries(pathItem)) {
                        if (['get', 'post', 'put', 'delete', 'patch'].includes(method.toLowerCase())) {
                            await this.createRequest(userId, method.toUpperCase(), path, {}, undefined);
                        }
                    }
                }
            }
            this.emit('openapi-imported', { importId, title, version });
            return importId;
        }
        finally {
            client.release();
        }
    }
    async getResponses(requestId, limit = 10) {
        const client = await this.pool.connect();
        try {
            const result = await client.query(`SELECT id, request_id, status_code, headers, body, execution_time_ms, timestamp
         FROM api_responses
         WHERE request_id = $1
         ORDER BY timestamp DESC
         LIMIT $2`, [requestId, limit]);
            return result.rows.map(row => ({
                requestId: row.request_id,
                statusCode: row.status_code,
                headers: row.headers,
                body: row.body,
                executionTime: row.execution_time_ms,
                timestamp: row.timestamp
            }));
        }
        finally {
            client.release();
        }
    }
    async compareResponses(responseId1, responseId2) {
        const client = await this.pool.connect();
        try {
            // Fetch both responses
            const result1 = await client.query(`SELECT request_id, body FROM api_responses WHERE id = $1`, [responseId1]);
            const result2 = await client.query(`SELECT request_id, body FROM api_responses WHERE id = $1`, [responseId2]);
            if (result1.rows.length === 0 || result2.rows.length === 0) {
                throw new Error('One or both responses not found');
            }
            const body1 = this.normalizeResponseBody(result1.rows[0].body);
            const body2 = this.normalizeResponseBody(result2.rows[0].body);
            // Simple diff calculation
            const added = this.findKeys(body2, body1);
            const removed = this.findKeys(body1, body2);
            const changed = this.findChanged(body1, body2);
            // Calculate similarity (0-100)
            const similarity = 100 - (Object.keys(added).length + Object.keys(removed).length + Object.keys(changed).length) * 10;
            return {
                requestId1: result1.rows[0].request_id,
                requestId2: result2.rows[0].request_id,
                added,
                removed,
                changed,
                similarity: Math.max(0, similarity)
            };
        }
        finally {
            client.release();
        }
    }
    findKeys(obj, exclude) {
        const result = {};
        for (const key in obj) {
            if (!(key in exclude)) {
                result[key] = obj[key];
            }
        }
        return result;
    }
    findChanged(obj1, obj2) {
        const result = {};
        for (const key in obj1) {
            if (key in obj2 && JSON.stringify(obj1[key]) !== JSON.stringify(obj2[key])) {
                result[key] = { from: obj1[key], to: obj2[key] };
            }
        }
        return result;
    }
    normalizeResponseBody(body) {
        if (body && typeof body === 'object') {
            return body;
        }
        if (typeof body !== 'string') {
            return {};
        }
        try {
            const parsed = JSON.parse(body);
            return parsed && typeof parsed === 'object' ? parsed : { _raw: body };
        }
        catch {
            return { _raw: body };
        }
    }
    async shareRequest(requestId, sharedByUserId, sharedWithUserId, teamId) {
        const client = await this.pool.connect();
        try {
            await client.query(`INSERT INTO api_shared_requests (request_id, shared_by_user_id, shared_with_user_id, team_id)
         VALUES ($1, $2, $3, $4)`, [requestId, sharedByUserId, sharedWithUserId, teamId]);
            this.emit('request-shared', { requestId, sharedByUserId });
        }
        finally {
            client.release();
        }
    }
    async getSharedRequests(userId, teamId) {
        const client = await this.pool.connect();
        try {
            let query = `SELECT r.id, r.method, r.url, r.created_at, s.shared_by_user_id
                   FROM api_shared_requests s
                   JOIN api_requests r ON s.request_id = r.id
                   WHERE s.shared_with_user_id = $1`;
            const params = [userId];
            if (teamId) {
                query += ` AND s.team_id = $2`;
                params.push(teamId);
            }
            query += ` ORDER BY s.shared_at DESC`;
            const result = await client.query(query, params);
            return result.rows;
        }
        finally {
            client.release();
        }
    }
    async getRequestHistory(userId, limit = 50) {
        const client = await this.pool.connect();
        try {
            const result = await client.query(`SELECT h.executed_at, r.id, r.method, r.url
         FROM api_request_history h
         JOIN api_requests r ON h.request_id = r.id
         WHERE h.user_id = $1
         ORDER BY h.executed_at DESC
         LIMIT $2`, [userId, limit]);
            return result.rows;
        }
        finally {
            client.release();
        }
    }
    async deleteRequest(requestId) {
        const client = await this.pool.connect();
        try {
            await client.query(`DELETE FROM api_requests WHERE id = $1`, [requestId]);
            this.emit('request-deleted', { requestId });
        }
        finally {
            client.release();
        }
    }
    async cleanupOldResponses(daysOld = 30) {
        const client = await this.pool.connect();
        try {
            const cutoffDate = new Date();
            cutoffDate.setDate(cutoffDate.getDate() - daysOld);
            const result = await client.query(`DELETE FROM api_responses WHERE timestamp < $1`, [cutoffDate]);
            this.emit('responses-cleaned', { count: result.rowCount, daysOld });
            return result.rowCount || 0;
        }
        finally {
            client.release();
        }
    }
}
export async function initializeEmbeddedAPIExplorerRoutes(service) {
    const { Router } = require('express');
    const router = Router();
    const logger = getLogger('EmbeddedAPIExplorerRoutes');
    router.post('/api/requests', async (req, res) => {
        try {
            const { userId, method, url, headers, body, variables } = req.body;
            const requestId = await service.createRequest(userId, method, url, headers, body, variables);
            res.json({ requestId });
        }
        catch (error) {
            logger.error('Failed to create request', error);
            res.status(500).json({ error: 'Failed to create request' });
        }
    });
    router.get('/api/requests/:requestId', async (req, res) => {
        try {
            const request = await service.getRequest(req.params.requestId);
            if (!request) {
                res.status(404).json({ error: 'Request not found' });
                return;
            }
            res.json(request);
        }
        catch (error) {
            logger.error('Failed to get request', error);
            res.status(500).json({ error: 'Failed to get request' });
        }
    });
    router.post('/api/requests/:requestId/execute', async (req, res) => {
        try {
            const { injectedVars } = req.body;
            const response = await service.executeRequest(req.params.requestId, injectedVars);
            res.json(response);
        }
        catch (error) {
            logger.error('Failed to execute request', error);
            res.status(500).json({ error: 'Failed to execute request' });
        }
    });
    router.post('/api/openapi/import', async (req, res) => {
        try {
            const { userId, openApiSpec } = req.body;
            const importId = await service.importOpenAPI(userId, openApiSpec);
            res.json({ importId });
        }
        catch (error) {
            logger.error('Failed to import OpenAPI', error);
            res.status(500).json({ error: 'Failed to import OpenAPI' });
        }
    });
    router.get('/api/requests/:requestId/responses', async (req, res) => {
        try {
            const responses = await service.getResponses(req.params.requestId);
            res.json(responses);
        }
        catch (error) {
            logger.error('Failed to get responses', error);
            res.status(500).json({ error: 'Failed to get responses' });
        }
    });
    router.post('/api/responses/compare', async (req, res) => {
        try {
            const { responseId1, responseId2 } = req.body;
            const diff = await service.compareResponses(responseId1, responseId2);
            res.json(diff);
        }
        catch (error) {
            logger.error('Failed to compare responses', error);
            res.status(500).json({ error: 'Failed to compare responses' });
        }
    });
    router.post('/api/requests/:requestId/share', async (req, res) => {
        try {
            const { sharedByUserId, sharedWithUserId, teamId } = req.body;
            await service.shareRequest(req.params.requestId, sharedByUserId, sharedWithUserId, teamId);
            res.json({ success: true });
        }
        catch (error) {
            logger.error('Failed to share request', error);
            res.status(500).json({ error: 'Failed to share request' });
        }
    });
    router.get('/api/shared-requests', async (req, res) => {
        try {
            const { userId, teamId } = req.query;
            const requests = await service.getSharedRequests(userId, teamId);
            res.json(requests);
        }
        catch (error) {
            logger.error('Failed to get shared requests', error);
            res.status(500).json({ error: 'Failed to get shared requests' });
        }
    });
    router.get('/api/request-history', async (req, res) => {
        try {
            const { userId } = req.query;
            const history = await service.getRequestHistory(userId);
            res.json(history);
        }
        catch (error) {
            logger.error('Failed to get request history', error);
            res.status(500).json({ error: 'Failed to get request history' });
        }
    });
    router.delete('/api/requests/:requestId', async (req, res) => {
        try {
            await service.deleteRequest(req.params.requestId);
            res.json({ success: true });
        }
        catch (error) {
            logger.error('Failed to delete request', error);
            res.status(500).json({ error: 'Failed to delete request' });
        }
    });
    return router;
}
//# sourceMappingURL=index.js.map