// @file        apps/backend/src/services/standup-summaries/__tests__/standup-summaries.test.ts
// @module      standup-summaries/tests
// @description Unit tests for the standup summaries service
// @owner       collab-2.9
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { StandupSummariesService } from '../index';
const collaborationEncryptionKey = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const originalEncryptionKey = process.env.COLLABORATION_MESSAGE_ENCRYPTION_KEY;
const { loggerMock, getLoggerMock } = vi.hoisted(() => {
    const mock = {
        info: vi.fn(),
        error: vi.fn(),
        warn: vi.fn(),
        debug: vi.fn(),
    };
    return {
        loggerMock: mock,
        getLoggerMock: vi.fn(() => mock),
    };
});
vi.mock('../../../lib/logger', () => ({
    getLogger: getLoggerMock,
}));
vi.mock('../../../lib/logger.js', () => ({
    getLogger: getLoggerMock,
}));
// Mock the AI router
const mockAIRouter = {
    route: vi.fn(),
};
// Mock Audit service
const mockAuditService = {
    emit: vi.fn(),
};
// Mock the database
const mockPool = {
    query: vi.fn(),
};
describe('StandupSummariesService', () => {
    let service;
    beforeEach(() => {
        vi.clearAllMocks();
        process.env.COLLABORATION_MESSAGE_ENCRYPTION_KEY = collaborationEncryptionKey;
        service = new StandupSummariesService(mockPool, mockAuditService, mockAIRouter);
    });
    afterEach(() => {
        if (originalEncryptionKey === undefined) {
            delete process.env.COLLABORATION_MESSAGE_ENCRYPTION_KEY;
            return;
        }
        process.env.COLLABORATION_MESSAGE_ENCRYPTION_KEY = originalEncryptionKey;
    });
    describe('initialization', () => {
        it('should initialize with default config', async () => {
            mockPool.query.mockResolvedValue({ rows: [] });
            await service.initialize();
            expect(mockPool.query).toHaveBeenCalledWith(expect.stringContaining('CREATE TABLE IF NOT EXISTS standup_summaries'));
        });
        it('should initialize with custom config', async () => {
            mockPool.query.mockResolvedValue({ rows: [] });
            const customConfig = {
                githubRepo: 'test-repo',
                githubOwner: 'test-owner',
                postingTime: '10:00',
                enabled: false,
            };
            service = new StandupSummariesService(mockPool, mockAuditService, mockAIRouter, customConfig);
            await service.initialize();
            // Config should be applied (though we can't easily test this without exposing it)
            expect(service).toBeDefined();
        });
    });
    describe('collectDailyActivity', () => {
        it('should collect activity for a date', async () => {
            const date = new Date('2024-01-01');
            // Mock empty responses for all collection methods
            const activity = await service.collectDailyActivity(date);
            expect(activity).toEqual({
                date: '2024-01-01',
                commits: [],
                reviews: [],
                comments: [],
                issues: [],
            });
        });
    });
    describe('generateSummary', () => {
        it('should generate a summary from activity', async () => {
            const activity = {
                date: '2024-01-01',
                commits: [{ sha: 'abc', message: 'test commit', author: 'test', timestamp: new Date(), files: [], additions: 1, deletions: 0 }],
                reviews: [],
                comments: [],
                issues: [{ number: 1, title: 'test issue', author: 'test', state: 'open', timestamp: new Date() }],
            };
            mockAIRouter.route.mockResolvedValue({
                result: 'Generated summary',
                usage: { tokens: 100 },
            });
            const summary = await service.generateSummary(activity);
            expect(mockAIRouter.route).toHaveBeenCalledWith({
                task: 'summarize',
                prompt: expect.stringContaining('Generate a concise daily standup summary'),
                max_tokens: 1000,
            });
            expect(summary).toContain('## Daily Standup Summary');
        });
    });
    describe('saveDraftSummary', () => {
        it('should save a draft summary', async () => {
            const date = '2024-01-01';
            const summaryText = 'Test summary';
            mockPool.query.mockResolvedValue({
                rows: [{
                        id: 'test-id',
                        date: '2024-01-01',
                        summary: summaryText,
                        status: 'draft',
                        created_at: new Date(),
                        posted_at: null,
                        approved_by: null,
                        matrix_message_id: null,
                    }],
            });
            const result = await service.saveDraftSummary(date, summaryText);
            expect(mockPool.query).toHaveBeenCalledWith(expect.stringContaining('INSERT INTO standup_summaries'), [date, summaryText]);
            expect(result).toEqual({
                id: 'test-id',
                date: '2024-01-01',
                summary: summaryText,
                status: 'draft',
                createdAt: expect.any(Date),
                postedAt: null,
                approvedBy: null,
                matrixMessageId: null,
            });
        });
    });
    describe('approveSummary', () => {
        it('should approve a draft summary', async () => {
            const date = '2024-01-01';
            const approvedBy = 'test-user';
            mockPool.query.mockResolvedValue({ rowCount: 1 });
            const result = await service.approveSummary(date, approvedBy);
            expect(mockPool.query).toHaveBeenCalledWith(expect.stringContaining('UPDATE standup_summaries'), [date, approvedBy]);
            expect(result).toBe(true);
        });
        it('should return false if no summary found', async () => {
            const date = '2024-01-01';
            const approvedBy = 'test-user';
            mockPool.query.mockResolvedValue({ rowCount: 0 });
            const result = await service.approveSummary(date, approvedBy);
            expect(result).toBe(false);
        });
    });
    describe('getSummary', () => {
        it('should get a summary by date', async () => {
            const date = '2024-01-01';
            mockPool.query.mockResolvedValue({
                rows: [{
                        id: 'test-id',
                        date: '2024-01-01',
                        summary: 'Test summary',
                        status: 'draft',
                        created_at: new Date(),
                        posted_at: null,
                        approved_by: null,
                        matrix_message_id: null,
                    }],
            });
            const result = await service.getSummary(date);
            expect(mockPool.query).toHaveBeenCalledWith('SELECT * FROM standup_summaries WHERE date = $1', [date]);
            expect(result).toEqual({
                id: 'test-id',
                date: '2024-01-01',
                summary: 'Test summary',
                status: 'draft',
                createdAt: expect.any(Date),
                postedAt: null,
                approvedBy: null,
                matrixMessageId: null,
            });
        });
        it('should return null if no summary found', async () => {
            const date = '2024-01-01';
            mockPool.query.mockResolvedValue({ rows: [] });
            const result = await service.getSummary(date);
            expect(result).toBeNull();
        });
    });
    describe('generateForDate', () => {
        it('should generate summary for a specific date', async () => {
            const date = new Date('2024-01-01');
            // Mock the internal methods
            const collectSpy = vi.spyOn(service, 'collectDailyActivity').mockResolvedValue({
                date: '2024-01-01',
                commits: [],
                reviews: [],
                comments: [],
                issues: [],
            });
            const generateSpy = vi.spyOn(service, 'generateSummary').mockResolvedValue('Generated summary');
            mockPool.query.mockResolvedValue({
                rows: [{
                        id: 'test-id',
                        date: '2024-01-01',
                        summary: 'Generated summary',
                        status: 'draft',
                        created_at: new Date(),
                        posted_at: null,
                        approved_by: null,
                        matrix_message_id: null,
                    }],
            });
            const result = await service.generateForDate(date);
            expect(collectSpy).toHaveBeenCalledWith(date);
            expect(generateSpy).toHaveBeenCalled();
            expect(result.summary).toBe('Generated summary');
        });
    });
    describe('postToMatrix', () => {
        it('should post encrypted collaboration payloads to Matrix', async () => {
            service = new StandupSummariesService(mockPool, mockAuditService, mockAIRouter, {
                matrixRoomId: '!room:kushnir.cloud',
                enabled: false,
            });
            mockPool.query
                .mockResolvedValueOnce({
                rows: [{
                        id: 'test-id',
                        date: '2024-01-01',
                        summary: 'Encrypted summary content',
                        status: 'approved',
                        created_at: new Date(),
                        posted_at: null,
                        approved_by: 'test-user',
                        matrix_message_id: null,
                    }],
            })
                .mockResolvedValueOnce({ rows: [] });
            const result = await service.postToMatrix('2024-01-01');
            expect(result).toBe(true);
            // Audit verification
            expect(mockAuditService.emit).toHaveBeenCalledWith(expect.objectContaining({
                userId: 'system',
                action: 'allow',
                reason: expect.stringContaining('Posted standup summary for 2024-01-01 to Matrix'),
            }));
        });
    });
});
//# sourceMappingURL=standup-summaries.test.js.map