import { describe, it, expect, beforeEach, vi } from 'vitest';
import { CodeOwnershipGraphService } from '../index';
vi.mock('../../../lib/logger', () => ({
    getLogger: () => ({
        info: vi.fn(),
        error: vi.fn(),
        debug: vi.fn(),
        warn: vi.fn()
    })
}));
describe('CodeOwnershipGraphService', () => {
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
        service = new CodeOwnershipGraphService(mockPool);
    });
    it('should initialize service and create tables', async () => {
        for (let i = 0; i < 11; i++) {
            mockClient.query.mockResolvedValueOnce({});
        }
        await service.initialize();
        expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('file_ownership'));
        expect(mockClient.release).toHaveBeenCalled();
    });
    it('should record commit and update ownership', async () => {
        // First query: check if existing
        mockClient.query.mockResolvedValueOnce({ rows: [] });
        // Second query: insert
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        // Third query: get top contributor
        mockClient.query.mockResolvedValueOnce({ rows: [{ user_id: 'user-1' }] });
        // Fourth query: get all contributors
        mockClient.query.mockResolvedValueOnce({
            rows: [
                { user_id: 'user-1', commit_count: 10 },
                { user_id: 'user-2', commit_count: 5 }
            ]
        });
        // Fifth query: check if file ownership exists
        mockClient.query.mockResolvedValueOnce({ rows: [] });
        // Sixth query: insert file ownership
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        await service.recordCommit('src/index.ts', 'user-1', 'abc123');
        expect(mockClient.query).toHaveBeenCalled();
    });
    it('should get file ownership', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    file_path: 'src/index.ts',
                    primary_owner: 'user-1',
                    contributors: [{ userId: 'user-1', commitCount: 10, percentage: 66.7 }],
                    bus_factor: 1,
                    last_modified: new Date(),
                    created_at: new Date()
                }]
        });
        const ownership = await service.getFileOwnership('src/index.ts');
        expect(ownership).not.toBeNull();
        expect(ownership?.filePath).toBe('src/index.ts');
        expect(ownership?.primaryOwner).toBe('user-1');
    });
    it('should analyze bus factor', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    contributors: [
                        { userId: 'user-1', percentage: 55 },
                        { userId: 'user-2', percentage: 45 }
                    ]
                }]
        });
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        const busFactor = await service.analyzeBusFactor('src/index.ts');
        expect(busFactor).toBe(1);
    });
    it('should generate ownership graph', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    file_path: 'src/index.ts',
                    primary_owner: 'user-1',
                    contributors: [{ userId: 'user-1', percentage: 100, commitCount: 10 }],
                    bus_factor: 1
                }]
        });
        const graph = await service.getOwnershipGraph();
        expect(graph.nodes).toBeDefined();
        expect(graph.edges).toBeDefined();
        expect(graph.busFactor).toBeDefined();
        expect(graph.busFactor.critical).toContain('src/index.ts');
    });
    it('should generate contributor heatmap', async () => {
        mockClient.query.mockResolvedValueOnce({ rows: [{ total_commits: 100 }] });
        mockClient.query.mockResolvedValueOnce({ rows: [{ files_owned: 5 }] });
        mockClient.query.mockResolvedValueOnce({ rows: [{ bus_factor_1: 2 }] });
        mockClient.query.mockResolvedValueOnce({ rows: [{ recent_activity: 15 }] });
        mockClient.query.mockResolvedValueOnce({
            rows: [
                { file_path: 'src/index.ts' },
                { file_path: 'src/utils.ts' }
            ]
        });
        // Check if existing
        mockClient.query.mockResolvedValueOnce({ rows: [] });
        // Insert heatmap
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        const heatmap = await service.generateContributorHeatmap('user-1');
        expect(heatmap.userId).toBe('user-1');
        expect(heatmap.totalCommits).toBe(100);
        expect(heatmap.filesOwned).toBe(5);
    });
    it('should get contributor heatmap', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    user_id: 'user-1',
                    total_commits: 100,
                    files_owned: 5,
                    bus_factor_1_count: 2,
                    recent_activity: 15,
                    dominant_files: ['src/index.ts', 'src/utils.ts']
                }]
        });
        const heatmap = await service.getContributorHeatmap('user-1');
        expect(heatmap).not.toBeNull();
        expect(heatmap?.totalCommits).toBe(100);
    });
    it('should parse codeowners file', async () => {
        const content = `src/index.ts @user1 @user2
src/utils.ts @user1
*.test.ts @user3`;
        const codeowners = await service.parseCodeowners(content);
        expect(codeowners['src/index.ts']).toContain('@user1');
        expect(codeowners['src/index.ts']).toContain('@user2');
    });
    it('should cache codeowners', async () => {
        const content = `src/index.ts @user1
src/utils.ts @user2`;
        // Check if existing
        mockClient.query.mockResolvedValueOnce({ rows: [] });
        // Insert
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        await service.cacheCodeowners('CODEOWNERS', content);
        expect(mockClient.query).toHaveBeenCalled();
    });
    it('should get critical files', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [
                { file_path: 'src/index.ts' },
                { file_path: 'src/core.ts' }
            ]
        });
        const files = await service.getCriticalFiles();
        expect(files).toContain('src/index.ts');
        expect(files).toContain('src/core.ts');
    });
    it('should get top contributors', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [
                { user_id: 'user-1', commits: 100 },
                { user_id: 'user-2', commits: 80 },
                { user_id: 'user-3', commits: 50 }
            ]
        });
        const contributors = await service.getTopContributors(10);
        expect(contributors.length).toBe(3);
        expect(contributors[0].userId).toBe('user-1');
        expect(contributors[0].commits).toBe(100);
    });
    it('should get file change history', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [
                { user_id: 'user-1', commit_count: 5, committed_at: new Date() },
                { user_id: 'user-2', commit_count: 3, committed_at: new Date() }
            ]
        });
        const history = await service.getFileChangeHistory('src/index.ts', 30);
        expect(history.length).toBe(2);
    });
    it('should emit commit-recorded event', async () => {
        let emittedEvent;
        service.on('commit-recorded', (event) => {
            emittedEvent = event;
        });
        mockClient.query.mockResolvedValueOnce({ rows: [] });
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        mockClient.query.mockResolvedValueOnce({ rows: [{ user_id: 'user-1' }] });
        mockClient.query.mockResolvedValueOnce({
            rows: [{ user_id: 'user-1', commit_count: 10 }]
        });
        mockClient.query.mockResolvedValueOnce({ rows: [] });
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        await service.recordCommit('src/index.ts', 'user-1', 'abc123');
        expect(emittedEvent).toBeDefined();
        expect(emittedEvent.filePath).toBe('src/index.ts');
    });
    it('should emit bus-factor-analyzed event', async () => {
        let emittedEvent;
        service.on('bus-factor-analyzed', (event) => {
            emittedEvent = event;
        });
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    contributors: [{ userId: 'user-1', percentage: 55 }]
                }]
        });
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        await service.analyzeBusFactor('src/index.ts');
        expect(emittedEvent).toBeDefined();
        expect(emittedEvent.busFactor).toBe(1);
    });
    it('should emit heatmap-generated event', async () => {
        let emittedEvent;
        service.on('heatmap-generated', (event) => {
            emittedEvent = event;
        });
        for (let i = 0; i < 7; i++) {
            mockClient.query.mockResolvedValueOnce({ rows: [{ total_commits: 100 }] });
        }
        await service.generateContributorHeatmap('user-1');
        expect(emittedEvent).toBeDefined();
        expect(emittedEvent.userId).toBe('user-1');
    });
    it('should emit codeowners-cached event', async () => {
        let emittedEvent;
        service.on('codeowners-cached', (event) => {
            emittedEvent = event;
        });
        mockClient.query.mockResolvedValueOnce({ rows: [] });
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        await service.cacheCodeowners('CODEOWNERS', 'src/index.ts @user1');
        expect(emittedEvent).toBeDefined();
        expect(emittedEvent.filePath).toBe('CODEOWNERS');
    });
    it('should return null for non-existent file ownership', async () => {
        mockClient.query.mockResolvedValueOnce({ rows: [] });
        const ownership = await service.getFileOwnership('non-existent.ts');
        expect(ownership).toBeNull();
    });
    it('should return null for non-existent heatmap', async () => {
        mockClient.query.mockResolvedValueOnce({ rows: [] });
        const heatmap = await service.getContributorHeatmap('non-existent-user');
        expect(heatmap).toBeNull();
    });
    it('should handle multiple commits on same file', async () => {
        for (let i = 0; i < 3; i++) {
            mockClient.query.mockResolvedValueOnce({ rows: [{ id: 'id-' + i, commit_count: i + 1 }] });
            mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
            mockClient.query.mockResolvedValueOnce({ rows: [{ user_id: 'user-' + i }] });
            mockClient.query.mockResolvedValueOnce({
                rows: [{ user_id: 'user-' + i, commit_count: i + 1 }]
            });
            mockClient.query.mockResolvedValueOnce({ rows: [{ id: 'ownership-id' }] });
            mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        }
        await service.recordCommit('src/index.ts', 'user-1', 'abc123');
        await service.recordCommit('src/index.ts', 'user-2', 'def456');
        await service.recordCommit('src/index.ts', 'user-1', 'ghi789');
        expect(mockClient.query).toHaveBeenCalled();
    });
    it('should filter comments from codeowners', async () => {
        const content = `# This is a comment
src/index.ts @user1
# Another comment
src/utils.ts @user2`;
        const codeowners = await service.parseCodeowners(content);
        expect(Object.keys(codeowners).length).toBe(2);
        expect(codeowners['src/index.ts']).toBeDefined();
    });
});
//# sourceMappingURL=code-ownership-graph.test.js.map