#!/usr/bin/env node
// @file        apps/backend/src/services/shared-prompt-library/__tests__/shared-prompt-library.test.ts
// @module      collaboration/shared-prompt-library
// @description Comprehensive shared prompt library tests
// @owner       collab-3.5
// @status      active
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { SharedPromptLibraryService } from '../index';
vi.mock('../../../lib/logger', () => ({
    getLogger: vi.fn(() => ({
        info: vi.fn(),
        error: vi.fn(),
        warn: vi.fn(),
        debug: vi.fn(),
    })),
}));
describe('SharedPromptLibraryService', () => {
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
        service = new SharedPromptLibraryService(mockPool);
    });
    afterEach(() => {
        vi.clearAllMocks();
    });
    describe('initialization', () => {
        it('should initialize tables on first call', async () => {
            mockClient.query.mockResolvedValueOnce({}); // BEGIN
            mockClient.query.mockResolvedValueOnce({}); // CREATE prompts
            mockClient.query.mockResolvedValueOnce({}); // CREATE versions
            mockClient.query.mockResolvedValueOnce({}); // CREATE usage
            mockClient.query.mockResolvedValueOnce({}); // CREATE ratings
            mockClient.query.mockResolvedValueOnce({}); // CREATE indexes
            mockClient.query.mockResolvedValueOnce({}); // COMMIT
            await service.initialize();
            expect(mockClient.query).toHaveBeenCalledWith('BEGIN');
            expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('CREATE TABLE IF NOT EXISTS prompts'));
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
    describe('createPrompt', () => {
        beforeEach(() => {
            mockClient.query.mockResolvedValue({});
        });
        it('should create a prompt with default visibility', async () => {
            mockClient.query.mockResolvedValueOnce({}); // Insert prompt
            mockClient.query.mockResolvedValueOnce({}); // Insert version
            const prompt = await service.createPrompt('team-1', 'Code Review Guidelines', 'Check for edge cases...', 'code-review', 'user123');
            expect(prompt.name).toBe('Code Review Guidelines');
            expect(prompt.visibility).toBe('team');
            expect(prompt.version).toBe(1);
            expect(prompt.usageCount).toBe(0);
        });
        it('should create a prompt with custom options', async () => {
            mockClient.query.mockResolvedValueOnce({}); // Insert
            mockClient.query.mockResolvedValueOnce({}); // Version
            const prompt = await service.createPrompt('team-1', 'API Review', 'Check REST conventions...', 'code-review', 'user123', {
                description: 'API endpoint review checklist',
                visibility: 'public',
                tags: ['api', 'rest'],
            });
            expect(prompt.description).toBe('API endpoint review checklist');
            expect(prompt.visibility).toBe('public');
            expect(prompt.tags).toContain('api');
        });
        it('should reject oversized prompts', async () => {
            const largeContent = 'x'.repeat(10001);
            await expect(service.createPrompt('team-1', 'Large', largeContent, 'code-review', 'user123')).rejects.toThrow(/exceeds max length/);
        });
        it('should emit prompt-created event', async () => {
            mockClient.query.mockResolvedValueOnce({});
            mockClient.query.mockResolvedValueOnce({});
            const eventSpy = vi.fn();
            service.on('prompt-created', eventSpy);
            await service.createPrompt('team-1', 'Test Prompt', 'content', 'testing', 'user123');
            expect(eventSpy).toHaveBeenCalledWith(expect.objectContaining({ name: 'Test Prompt' }));
        });
    });
    describe('getPrompt', () => {
        it('should retrieve a prompt', async () => {
            mockClient.query.mockResolvedValueOnce({
                rows: [
                    {
                        id: 'prompt-1',
                        team_id: 'team-1',
                        name: 'Test Prompt',
                        category: 'code-review',
                        content: 'Test content',
                        description: 'Test description',
                        version: 1,
                        visibility: 'team',
                        created_by: 'user123',
                        updated_by: 'user123',
                        tags: ['test'],
                        usage_count: 5,
                        rating: 4.5,
                        rating_count: 2,
                        created_at: new Date(),
                        updated_at: new Date(),
                    },
                ],
            });
            const prompt = await service.getPrompt('prompt-1');
            expect(prompt).not.toBeNull();
            expect(prompt?.name).toBe('Test Prompt');
            expect(prompt?.usageCount).toBe(5);
        });
        it('should return null for non-existent prompt', async () => {
            mockClient.query.mockResolvedValueOnce({ rows: [] });
            const prompt = await service.getPrompt('non-existent');
            expect(prompt).toBeNull();
        });
    });
    describe('listTeamPrompts', () => {
        it('should list all team prompts', async () => {
            mockClient.query.mockResolvedValueOnce({
                rows: [
                    {
                        id: 'p1',
                        team_id: 'team-1',
                        name: 'Prompt 1',
                        category: 'code-review',
                        content: 'Content 1',
                        description: '',
                        version: 1,
                        visibility: 'team',
                        created_by: 'user123',
                        updated_by: 'user123',
                        tags: [],
                        usage_count: 0,
                        rating: 0,
                        rating_count: 0,
                        created_at: new Date(),
                        updated_at: new Date(),
                    },
                ],
            });
            const prompts = await service.listTeamPrompts('team-1');
            expect(prompts).toHaveLength(1);
            expect(prompts[0].name).toBe('Prompt 1');
        });
        it('should filter by category', async () => {
            mockClient.query.mockResolvedValueOnce({ rows: [] });
            await service.listTeamPrompts('team-1', 'testing');
            expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('AND category = $2'), expect.arrayContaining(['team-1', 'testing']));
        });
    });
    describe('updatePrompt', () => {
        it('should update prompt with new version', async () => {
            mockClient.query.mockResolvedValueOnce({}); // BEGIN
            mockClient.query.mockResolvedValueOnce({ rows: [{ version: 1 }] }); // Get version
            mockClient.query.mockResolvedValueOnce({}); // Update prompt
            mockClient.query.mockResolvedValueOnce({}); // Insert version
            mockClient.query.mockResolvedValueOnce({}); // COMMIT
            mockClient.query.mockResolvedValueOnce({
                rows: [
                    {
                        id: 'prompt-1',
                        team_id: 'team-1',
                        name: 'Updated Prompt',
                        category: 'code-review',
                        content: 'New content',
                        description: '',
                        version: 2,
                        visibility: 'team',
                        created_by: 'user123',
                        updated_by: 'user456',
                        tags: [],
                        usage_count: 0,
                        rating: 0,
                        rating_count: 0,
                        created_at: new Date(),
                        updated_at: new Date(),
                    },
                ],
            }); // Get updated prompt
            const updated = await service.updatePrompt('prompt-1', 'New content', 'user456', 'Added clarity');
            expect(updated.version).toBe(2);
            expect(updated.content).toBe('New content');
        });
    });
    describe('suggestPrompts', () => {
        it('should suggest matching prompts', async () => {
            mockClient.query.mockResolvedValueOnce({
                rows: [
                    {
                        id: 'p1',
                        name: 'Code Review',
                        content: 'Check for code quality and best practices...',
                    },
                    {
                        id: 'p2',
                        name: 'Testing Guide',
                        content: 'Write comprehensive unit tests...',
                    },
                ],
            });
            const suggestions = await service.suggestPrompts('team-1', 'need to review code quality');
            expect(suggestions.length).toBeGreaterThan(0);
            expect(suggestions[0].matchScore).toBeGreaterThanOrEqual(0);
            expect(suggestions[0].matchScore).toBeLessThanOrEqual(100);
        });
        it('should respect category filter', async () => {
            mockClient.query.mockResolvedValueOnce({ rows: [] });
            await service.suggestPrompts('team-1', 'context', 'testing');
            expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('AND category = $2'), expect.arrayContaining(['team-1', 'testing']));
        });
        it('should respect minMatchScore', async () => {
            mockClient.query.mockResolvedValueOnce({
                rows: [
                    {
                        id: 'p1',
                        name: 'Test',
                        content: 'xyz',
                    },
                ],
            });
            const suggestions = await service.suggestPrompts('team-1', 'completely different context');
            // Low match score should be filtered out
            const allFiltered = suggestions.every(s => s.matchScore >= 50);
            expect(allFiltered).toBe(true);
        });
    });
    describe('trackUsage', () => {
        it('should track prompt usage', async () => {
            mockClient.query.mockResolvedValueOnce({}); // Insert usage
            mockClient.query.mockResolvedValueOnce({}); // Update count
            const eventSpy = vi.fn();
            service.on('usage-tracked', eventSpy);
            await service.trackUsage('prompt-1', 'user123', { file: 'test.ts' });
            expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('INSERT INTO prompt_usage'), expect.arrayContaining(['prompt-1', 'user123']));
            expect(eventSpy).toHaveBeenCalled();
        });
    });
    describe('ratePrompt', () => {
        it('should rate a prompt', async () => {
            mockClient.query.mockResolvedValueOnce({}); // BEGIN
            mockClient.query.mockResolvedValueOnce({}); // Insert/update rating
            mockClient.query.mockResolvedValueOnce({ rows: [{ avg_rating: '4.5', count: '2' }] }); // Get avg
            mockClient.query.mockResolvedValueOnce({}); // Update prompt
            mockClient.query.mockResolvedValueOnce({}); // COMMIT
            const eventSpy = vi.fn();
            service.on('prompt-rated', eventSpy);
            await service.ratePrompt('prompt-1', 'user123', 5, 'Very helpful');
            expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('INSERT INTO prompt_ratings'), expect.arrayContaining(['prompt-1', 'user123', 5]));
            expect(eventSpy).toHaveBeenCalled();
        });
        it('should reject invalid ratings', async () => {
            await expect(service.ratePrompt('prompt-1', 'user123', 6)).rejects.toThrow(/between 0 and 5/);
            await expect(service.ratePrompt('prompt-1', 'user123', -1)).rejects.toThrow(/between 0 and 5/);
            await expect(service.ratePrompt('prompt-1', 'user123', 3.5)).rejects.toThrow(/integer/);
        });
    });
    describe('getPromptVersions', () => {
        it('should retrieve all versions of a prompt', async () => {
            mockClient.query.mockResolvedValueOnce({
                rows: [
                    {
                        id: 'v2',
                        prompt_id: 'prompt-1',
                        version: 2,
                        content: 'Version 2',
                        change_description: 'Added details',
                        created_by: 'user456',
                        created_at: new Date(),
                    },
                    {
                        id: 'v1',
                        prompt_id: 'prompt-1',
                        version: 1,
                        content: 'Version 1',
                        change_description: '',
                        created_by: 'user123',
                        created_at: new Date(),
                    },
                ],
            });
            const versions = await service.getPromptVersions('prompt-1');
            expect(versions).toHaveLength(2);
            expect(versions[0].version).toBe(2);
            expect(versions[1].version).toBe(1);
        });
    });
});
//# sourceMappingURL=shared-prompt-library.test.js.map