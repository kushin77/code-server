import { describe, it, expect, beforeEach, vi } from 'vitest';
import { EmbeddedAPIExplorerService } from '../index';
vi.mock('../../../lib/logger', () => ({
    getLogger: () => ({
        info: vi.fn(),
        error: vi.fn(),
        debug: vi.fn(),
        warn: vi.fn()
    })
}));
describe('EmbeddedAPIExplorerService', () => {
    let service;
    let mockPool;
    let mockClient;
    beforeEach(() => {
        mockClient = {
            query: vi.fn(),
            release: vi.fn()
        };
        mockPool = {
            connect: vi.fn().mockResolvedValue(mockClient)
        };
        service = new EmbeddedAPIExplorerService(mockPool);
    });
    it('should initialize service and create tables', async () => {
        mockClient.query.mockResolvedValueOnce({});
        mockClient.query.mockResolvedValueOnce({});
        mockClient.query.mockResolvedValueOnce({});
        mockClient.query.mockResolvedValueOnce({});
        mockClient.query.mockResolvedValueOnce({});
        mockClient.query.mockResolvedValueOnce({});
        mockClient.query.mockResolvedValueOnce({});
        mockClient.query.mockResolvedValueOnce({});
        mockClient.query.mockResolvedValueOnce({});
        await service.initialize();
        expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('api_requests'));
        expect(mockClient.release).toHaveBeenCalled();
    });
    it('should create a request', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [{ id: 'req-1' }]
        });
        const requestId = await service.createRequest('user-1', 'GET', 'https://api.example.com/users', { 'Authorization': 'Bearer token' });
        expect(requestId).toBe('req-1');
    });
    it('should get a request', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'req-1',
                    user_id: 'user-1',
                    method: 'GET',
                    url: 'https://api.example.com/users',
                    headers: { 'Authorization': 'Bearer token' },
                    body: null,
                    variables: null,
                    created_at: new Date()
                }]
        });
        const request = await service.getRequest('req-1');
        expect(request).not.toBeNull();
        expect(request?.method).toBe('GET');
        expect(request?.url).toBe('https://api.example.com/users');
    });
    it('should return null for non-existent request', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: []
        });
        const request = await service.getRequest('non-existent');
        expect(request).toBeNull();
    });
    it('should execute a request with env var injection', async () => {
        // First getRequest call in executeRequest
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'req-1',
                    user_id: 'user-1',
                    method: 'GET',
                    url: 'https://api.example.com/$apiVersion/users',
                    headers: { 'Authorization': 'Bearer $token' },
                    body: null,
                    variables: null,
                    created_at: new Date()
                }]
        });
        // INSERT INTO api_responses
        mockClient.query.mockResolvedValueOnce({
            rowCount: 1
        });
        // Second getRequest call to record in history
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'req-1',
                    user_id: 'user-1',
                    method: 'GET',
                    url: 'https://api.example.com/$apiVersion/users',
                    headers: {},
                    body: null,
                    variables: null,
                    created_at: new Date()
                }]
        });
        // INSERT INTO api_request_history
        mockClient.query.mockResolvedValueOnce({
            rowCount: 1
        });
        const response = await service.executeRequest('req-1', { apiVersion: 'v1', token: 'abc123' });
        expect(response.statusCode).toBe(200);
        expect(response.executionTime).toBeGreaterThanOrEqual(0);
    });
    it('should import OpenAPI spec', async () => {
        const openApiSpec = {
            info: { title: 'Test API', version: '1.0.0' },
            paths: {
                '/users': {
                    get: { summary: 'Get users' },
                    post: { summary: 'Create user' }
                }
            }
        };
        mockClient.query.mockResolvedValueOnce({
            rows: [{ id: 'import-1' }]
        });
        mockClient.query.mockResolvedValueOnce({
            rows: [{ id: 'req-1' }]
        });
        mockClient.query.mockResolvedValueOnce({
            rows: [{ id: 'req-2' }]
        });
        const importId = await service.importOpenAPI('user-1', openApiSpec);
        expect(importId).toBe('import-1');
    });
    it('should get responses for a request', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [
                {
                    id: 'resp-1',
                    request_id: 'req-1',
                    status_code: 200,
                    headers: {},
                    body: '{"data": "test"}',
                    execution_time_ms: 100,
                    timestamp: new Date()
                }
            ]
        });
        const responses = await service.getResponses('req-1');
        expect(responses.length).toBe(1);
        expect(responses[0].statusCode).toBe(200);
    });
    it('should compare responses', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [{ request_id: 'req-1', body: '{"name": "John", "age": 30}' }]
        });
        mockClient.query.mockResolvedValueOnce({
            rows: [{ request_id: 'req-1', body: '{"name": "Jane", "age": 25, "city": "NYC"}' }]
        });
        const diff = await service.compareResponses('resp-1', 'resp-2');
        expect(diff.added).toBeDefined();
        expect(diff.removed).toBeDefined();
        expect(diff.changed).toBeDefined();
        expect(diff.similarity).toBeGreaterThanOrEqual(0);
    });
    it('should compare plain-text responses without parsing errors', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [{ request_id: 'req-1', body: 'plain text response a' }]
        });
        mockClient.query.mockResolvedValueOnce({
            rows: [{ request_id: 'req-2', body: 'plain text response b' }]
        });
        const diff = await service.compareResponses('resp-1', 'resp-2');
        expect(diff.requestId1).toBe('req-1');
        expect(diff.requestId2).toBe('req-2');
        expect(diff.added).toBeDefined();
        expect(diff.removed).toBeDefined();
    });
    it('should share request', async () => {
        mockClient.query.mockResolvedValueOnce({});
        await service.shareRequest('req-1', 'user-1', 'user-2');
        expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('INSERT INTO api_shared_requests'), expect.any(Array));
    });
    it('should get shared requests', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [
                {
                    id: 'req-1',
                    method: 'GET',
                    url: 'https://api.example.com/users',
                    created_at: new Date(),
                    shared_by_user_id: 'user-1'
                }
            ]
        });
        const requests = await service.getSharedRequests('user-2');
        expect(requests.length).toBe(1);
        expect(requests[0].method).toBe('GET');
    });
    it('should emit request-created event', async () => {
        let emittedEvent;
        service.on('request-created', (event) => {
            emittedEvent = event;
        });
        mockClient.query.mockResolvedValueOnce({
            rows: [{ id: 'req-1' }]
        });
        await service.createRequest('user-1', 'POST', 'https://api.example.com/users', {});
        expect(emittedEvent).toBeDefined();
        expect(emittedEvent.requestId).toBe('req-1');
    });
    it('should emit request-executed event', async () => {
        let emittedEvent;
        service.on('request-executed', (event) => {
            emittedEvent = event;
        });
        // First getRequest call in executeRequest
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'req-1',
                    user_id: 'user-1',
                    method: 'GET',
                    url: 'https://api.example.com/users',
                    headers: {},
                    body: null,
                    variables: null,
                    created_at: new Date()
                }]
        });
        // INSERT INTO api_responses
        mockClient.query.mockResolvedValueOnce({
            rowCount: 1
        });
        // Second getRequest call to record in history
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'req-1',
                    user_id: 'user-1',
                    method: 'GET',
                    url: 'https://api.example.com/users',
                    headers: {},
                    body: null,
                    variables: null,
                    created_at: new Date()
                }]
        });
        // INSERT INTO api_request_history
        mockClient.query.mockResolvedValueOnce({
            rowCount: 1
        });
        await service.executeRequest('req-1');
        expect(emittedEvent).toBeDefined();
        expect(emittedEvent.statusCode).toBe(200);
    });
    it('should delete request', async () => {
        mockClient.query.mockResolvedValueOnce({});
        await service.deleteRequest('req-1');
        expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('DELETE FROM api_requests'), expect.any(Array));
    });
    it('should get request history', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [
                {
                    executed_at: new Date(),
                    id: 'req-1',
                    method: 'GET',
                    url: 'https://api.example.com/users'
                }
            ]
        });
        const history = await service.getRequestHistory('user-1');
        expect(history.length).toBe(1);
    });
    it('should cleanup old responses', async () => {
        mockClient.query.mockResolvedValueOnce({
            rowCount: 100
        });
        const count = await service.cleanupOldResponses(30);
        expect(count).toBe(100);
    });
    it('should emit openapi-imported event', async () => {
        let emittedEvent;
        service.on('openapi-imported', (event) => {
            emittedEvent = event;
        });
        const openApiSpec = {
            info: { title: 'Test API', version: '1.0.0' },
            paths: {}
        };
        mockClient.query.mockResolvedValueOnce({
            rows: [{ id: 'import-1' }]
        });
        await service.importOpenAPI('user-1', openApiSpec);
        expect(emittedEvent).toBeDefined();
        expect(emittedEvent.title).toBe('Test API');
    });
    it('should emit request-shared event', async () => {
        let emittedEvent;
        service.on('request-shared', (event) => {
            emittedEvent = event;
        });
        mockClient.query.mockResolvedValueOnce({});
        await service.shareRequest('req-1', 'user-1', 'user-2');
        expect(emittedEvent).toBeDefined();
        expect(emittedEvent.requestId).toBe('req-1');
    });
    it('should emit responses-cleaned event', async () => {
        let emittedEvent;
        service.on('responses-cleaned', (event) => {
            emittedEvent = event;
        });
        mockClient.query.mockResolvedValueOnce({
            rowCount: 50
        });
        await service.cleanupOldResponses(30);
        expect(emittedEvent).toBeDefined();
        expect(emittedEvent.count).toBe(50);
    });
    it('should emit request-deleted event', async () => {
        let emittedEvent;
        service.on('request-deleted', (event) => {
            emittedEvent = event;
        });
        mockClient.query.mockResolvedValueOnce({});
        await service.deleteRequest('req-1');
        expect(emittedEvent).toBeDefined();
        expect(emittedEvent.requestId).toBe('req-1');
    });
    it('should handle GraphQL requests', async () => {
        const graphQLQuery = '{ users { id name email } }';
        const variables = { limit: 10 };
        mockClient.query.mockResolvedValueOnce({
            rows: [{ id: 'req-1' }]
        });
        const requestId = await service.createRequest('user-1', 'GraphQL', 'https://api.example.com/graphql', {}, graphQLQuery, variables);
        expect(requestId).toBe('req-1');
    });
});
//# sourceMappingURL=embedded-api-explorer.test.js.map