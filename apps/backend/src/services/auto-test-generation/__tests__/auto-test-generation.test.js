#!/usr/bin/env node
// @file        apps/backend/src/services/auto-test-generation/__tests__/auto-test-generation.test.ts
// @module      collaboration/auto-test-generation
// @description Auto test generation service tests
// @owner       collab-3.9
// @status      active
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { AutoTestGenerationService } from '../index';
vi.mock('../../../lib/logger', () => ({
    getLogger: vi.fn(() => ({
        info: vi.fn(),
        error: vi.fn(),
        warn: vi.fn(),
        debug: vi.fn(),
    })),
}));
describe('AutoTestGenerationService', () => {
    let service;
    let mockPool;
    let mockClient;
    beforeEach(() => {
        mockClient = {
            query: vi.fn(),
            release: vi.fn(),
        };
        mockPool = {
            connect: vi.fn(async () => mockClient),
        };
        service = new AutoTestGenerationService(mockPool);
    });
    afterEach(() => {
        vi.clearAllMocks();
    });
    describe('initialization', () => {
        it('should initialize tables on first call', async () => {
            mockClient.query.mockResolvedValueOnce({}); // BEGIN
            mockClient.query.mockResolvedValueOnce({}); // CREATE test_suggestions
            mockClient.query.mockResolvedValueOnce({}); // CREATE test_generation_batches
            mockClient.query.mockResolvedValueOnce({}); // CREATE test_feedback
            mockClient.query.mockResolvedValueOnce({}); // CREATE test_execution_results
            mockClient.query.mockResolvedValueOnce({}); // CREATE indexes
            mockClient.query.mockResolvedValueOnce({}); // COMMIT
            await service.initialize();
            expect(mockClient.query).toHaveBeenCalledWith('BEGIN');
            expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('CREATE TABLE IF NOT EXISTS test_suggestions'));
            expect(mockClient.query.mock.calls.some(call => typeof call[0] === 'string' && call[0].includes('acceptance_at'))).toBe(false);
            expect(mockPool.connect).toHaveBeenCalled();
        });
        it('should not reinitialize if already initialized', async () => {
            mockClient.query.mockResolvedValue({});
            await service.initialize();
            const firstCallCount = mockPool.connect.mock.calls.length;
            await service.initialize();
            const secondCallCount = mockPool.connect.mock.calls.length;
            expect(secondCallCount).toBe(firstCallCount);
        });
    });
    describe('generateTestsForSession', () => {
        beforeEach(() => {
            mockClient.query.mockResolvedValue({});
        });
        it('should generate and store test suggestions', async () => {
            mockClient.query.mockResolvedValueOnce({}); // BEGIN
            mockClient.query.mockResolvedValueOnce({}); // INSERT batch
            mockClient.query.mockResolvedValueOnce({
                rows: [{ id: 'test-1', session_id: 'sess-1', file_name: 'api.ts', function_name: 'fetchUser', test_code: 'test code', coverage: 85, confidence: 92, ai_context: 'context', status: 'pending', created_at: new Date() }],
            }); // INSERT test 1
            mockClient.query.mockResolvedValueOnce({}); // COMMIT
            const request = { sessionId: 'sess-1', changedFiles: ['api.ts'], aiContext: 'context', bugDescription: 'Bug in user fetch', fixDescription: 'Added null check' };
            const tests = [{ id: 'test-1', sessionId: 'sess-1', fileName: 'api.ts', functionName: 'fetchUser', testCode: 'test code', coverage: 85, confidence: 92, aiContext: 'context', status: 'pending', createdAt: new Date() }];
            const result = await service.generateTestsForSession(request, tests);
            expect(result.length).toBe(1);
            expect(result[0].fileName).toBe('api.ts');
            expect(result[0].confidence).toBe(92);
        });
        it('should emit tests-generated event', async () => {
            mockClient.query.mockResolvedValue({});
            mockClient.query.mockResolvedValueOnce({});
            mockClient.query.mockResolvedValueOnce({});
            mockClient.query.mockResolvedValueOnce({ rows: [{ id: 'test-1', session_id: 'sess-1', file_name: 'api.ts', function_name: 'fn', test_code: 'code', coverage: 80, confidence: 90, ai_context: 'ctx', status: 'pending', created_at: new Date() }] });
            mockClient.query.mockResolvedValueOnce({});
            const eventSpy = vi.fn();
            service.on('tests-generated', eventSpy);
            const request = { sessionId: 'sess-1', changedFiles: ['api.ts'], aiContext: 'ctx', bugDescription: 'Bug', fixDescription: 'Fix' };
            const tests = [{ id: 'test-1', sessionId: 'sess-1', fileName: 'api.ts', functionName: 'fn', testCode: 'code', coverage: 80, confidence: 90, aiContext: 'ctx', status: 'pending', createdAt: new Date() }];
            await service.generateTestsForSession(request, tests);
            expect(eventSpy).toHaveBeenCalledWith(expect.objectContaining({ sessionId: 'sess-1' }));
        });
    });
    describe('getTestSuggestion', () => {
        it('should retrieve a test suggestion', async () => {
            mockClient.query.mockResolvedValueOnce({
                rows: [{ id: 'test-1', session_id: 'sess-1', file_name: 'api.ts', function_name: 'fn', test_code: 'code', coverage: 85, confidence: 90, ai_context: 'ctx', status: 'pending', created_at: new Date() }],
            });
            const test = await service.getTestSuggestion('test-1');
            expect(test).not.toBeNull();
            expect(test?.fileName).toBe('api.ts');
            expect(test?.confidence).toBe(90);
        });
        it('should return null for non-existent suggestion', async () => {
            mockClient.query.mockResolvedValueOnce({ rows: [] });
            const test = await service.getTestSuggestion('non-existent');
            expect(test).toBeNull();
        });
    });
    describe('acceptTestSuggestion', () => {
        it('should accept a test suggestion', async () => {
            mockClient.query.mockResolvedValueOnce({
                rows: [{ id: 'test-1', session_id: 'sess-1', file_name: 'api.ts', function_name: 'fn', test_code: 'code', coverage: 85, confidence: 90, ai_context: 'ctx', status: 'accepted', accepted_at: new Date(), created_at: new Date() }],
            });
            const test = await service.acceptTestSuggestion('test-1');
            expect(test.status).toBe('accepted');
            expect(test.acceptedAt).not.toBeNull();
        });
        it('should emit test-accepted event', async () => {
            mockClient.query.mockResolvedValueOnce({
                rows: [{ id: 'test-1', session_id: 'sess-1', file_name: 'api.ts', function_name: 'fn', test_code: 'code', coverage: 85, confidence: 90, ai_context: 'ctx', status: 'accepted', accepted_at: new Date(), created_at: new Date() }],
            });
            const eventSpy = vi.fn();
            service.on('test-accepted', eventSpy);
            await service.acceptTestSuggestion('test-1');
            expect(eventSpy).toHaveBeenCalled();
        });
    });
    describe('rejectTestSuggestion', () => {
        it('should reject a test suggestion with reason', async () => {
            mockClient.query.mockResolvedValueOnce({
                rows: [{ id: 'test-1', session_id: 'sess-1', file_name: 'api.ts', function_name: 'fn', test_code: 'code', coverage: 85, confidence: 90, ai_context: 'ctx', status: 'rejected', rejection_reason: 'Does not match requirements', created_at: new Date() }],
            });
            const test = await service.rejectTestSuggestion('test-1', 'Does not match requirements');
            expect(test.status).toBe('rejected');
            expect(test.rejectionReason).toBe('Does not match requirements');
        });
        it('should emit test-rejected event', async () => {
            mockClient.query.mockResolvedValueOnce({
                rows: [{ id: 'test-1', session_id: 'sess-1', file_name: 'api.ts', function_name: 'fn', test_code: 'code', coverage: 85, confidence: 90, ai_context: 'ctx', status: 'rejected', rejection_reason: 'Bad', created_at: new Date() }],
            });
            const eventSpy = vi.fn();
            service.on('test-rejected', eventSpy);
            await service.rejectTestSuggestion('test-1', 'Bad');
            expect(eventSpy).toHaveBeenCalled();
        });
    });
    describe('getSessionTestSuggestions', () => {
        it('should retrieve all test suggestions for a session', async () => {
            mockClient.query.mockResolvedValueOnce({
                rows: [
                    { id: 'test-1', session_id: 'sess-1', file_name: 'api.ts', function_name: 'fn1', test_code: 'code1', coverage: 85, confidence: 95, ai_context: 'ctx', status: 'pending', created_at: new Date() },
                    { id: 'test-2', session_id: 'sess-1', file_name: 'api.ts', function_name: 'fn2', test_code: 'code2', coverage: 80, confidence: 88, ai_context: 'ctx', status: 'pending', created_at: new Date() },
                ],
            });
            const tests = await service.getSessionTestSuggestions('sess-1');
            expect(tests.length).toBe(2);
            expect(tests[0].functionName).toBe('fn1');
        });
        it('should filter by status if provided', async () => {
            mockClient.query.mockResolvedValueOnce({
                rows: [{ id: 'test-1', session_id: 'sess-1', file_name: 'api.ts', function_name: 'fn', test_code: 'code', coverage: 85, confidence: 90, ai_context: 'ctx', status: 'accepted', accepted_at: new Date(), created_at: new Date() }],
            });
            const tests = await service.getSessionTestSuggestions('sess-1', 'accepted');
            expect(tests.length).toBe(1);
            expect(tests[0].status).toBe('accepted');
        });
    });
    describe('markTestAsUsed', () => {
        it('should mark a test as used', async () => {
            mockClient.query.mockResolvedValueOnce({
                rows: [{ id: 'test-1', session_id: 'sess-1', file_name: 'api.ts', function_name: 'fn', test_code: 'code', coverage: 85, confidence: 90, ai_context: 'ctx', status: 'used', used_at: new Date(), created_at: new Date() }],
            });
            const test = await service.markTestAsUsed('test-1');
            expect(test.status).toBe('used');
            expect(test.usedAt).not.toBeNull();
        });
        it('should emit test-used event', async () => {
            mockClient.query.mockResolvedValueOnce({
                rows: [{ id: 'test-1', session_id: 'sess-1', file_name: 'api.ts', function_name: 'fn', test_code: 'code', coverage: 85, confidence: 90, ai_context: 'ctx', status: 'used', used_at: new Date(), created_at: new Date() }],
            });
            const eventSpy = vi.fn();
            service.on('test-used', eventSpy);
            await service.markTestAsUsed('test-1');
            expect(eventSpy).toHaveBeenCalled();
        });
    });
    describe('recordTestExecution', () => {
        it('should record test execution result', async () => {
            mockClient.query.mockResolvedValueOnce({});
            const eventSpy = vi.fn();
            service.on('test-executed', eventSpy);
            await service.recordTestExecution('test-1', true, 150, undefined);
            expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('INSERT INTO test_execution_results'), expect.arrayContaining(['test-1', true, 150]));
            expect(eventSpy).toHaveBeenCalled();
        });
        it('should record test execution with error message', async () => {
            mockClient.query.mockResolvedValueOnce({});
            await service.recordTestExecution('test-1', false, 200, 'Expected 5 to be 10');
            expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('INSERT INTO test_execution_results'), expect.arrayContaining(['test-1', false, 200, 'Expected 5 to be 10']));
        });
    });
    describe('getTestMetrics', () => {
        it('should calculate metrics for a session', async () => {
            mockClient.query.mockResolvedValueOnce({
                rows: [{ total: '10', accepted: '7', rejected: '2', used: '6', avg_confidence: '87.5', avg_coverage: '83.2' }],
            });
            const metrics = await service.getTestMetrics('sess-1');
            expect(metrics.totalSuggestions).toBe(10);
            expect(metrics.accepted).toBe(7);
            expect(metrics.rejected).toBe(2);
            expect(metrics.used).toBe(6);
            expect(metrics.avgConfidence).toBe(87.5);
        });
    });
    describe('addFeedback', () => {
        it('should record feedback on test suggestion', async () => {
            mockClient.query.mockResolvedValueOnce({});
            const eventSpy = vi.fn();
            service.on('feedback-recorded', eventSpy);
            await service.addFeedback('test-1', 'user-1', 'helpful', 'Great test!');
            expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('INSERT INTO test_feedback'), expect.arrayContaining(['test-1', 'user-1', 'helpful', 'Great test!']));
            expect(eventSpy).toHaveBeenCalled();
        });
        it('should record feedback without comment', async () => {
            mockClient.query.mockResolvedValueOnce({});
            await service.addFeedback('test-1', 'user-1', 'incorrect');
            expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('INSERT INTO test_feedback'), expect.arrayContaining(['test-1', 'user-1', 'incorrect']));
        });
    });
});
//# sourceMappingURL=auto-test-generation.test.js.map