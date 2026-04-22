import { describe, it, expect, beforeEach, vi } from 'vitest';
import { ExpertiseHeatmapService } from '../index';
vi.mock('../../../lib/logger', () => ({
    getLogger: () => ({
        info: vi.fn(),
        error: vi.fn(),
        debug: vi.fn(),
        warn: vi.fn()
    })
}));
describe('ExpertiseHeatmapService', () => {
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
        service = new ExpertiseHeatmapService(mockPool);
    });
    it('initializes expertise tables', async () => {
        for (let i = 0; i < 7; i++) {
            mockClient.query.mockResolvedValueOnce({});
        }
        await service.initialize();
        expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('expertise_contributions'));
        expect(mockClient.release).toHaveBeenCalled();
    });
    it('records expertise contribution', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'contrib-1',
                    user_id: 'user-1',
                    file_path: 'src/index.ts',
                    function_name: 'main',
                    expertise_score: 72,
                    commit_count: 5,
                    created_at: new Date()
                }]
        });
        const contribution = await service.recordContribution('user-1', 'src/index.ts', 'main', 72, 5);
        expect(contribution.id).toBe('contrib-1');
        expect(contribution.expertiseScore).toBe(72);
    });
    it('generates file heatmap', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [
                { user_id: 'user-1', score: 72 },
                { user_id: 'user-2', score: 18 }
            ]
        });
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        const heatmap = await service.generateHeatmap('src/index.ts', 'file');
        expect(heatmap.target).toBe('src/index.ts');
        expect(heatmap.experts[0].userId).toBe('user-1');
        expect(Math.round(heatmap.experts[0].percentage)).toBe(80);
    });
    it('finds expert for file', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [{ user_id: 'user-1', score: 72 }]
        });
        mockClient.query.mockResolvedValueOnce({
            rows: [{ total: 90 }]
        });
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        const expert = await service.findExpert('src/index.ts', 'file');
        expect(expert?.userId).toBe('user-1');
        expect(Math.round(expert?.percentage || 0)).toBe(80);
    });
    it('lists contributions for a user', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [
                {
                    id: 'contrib-1',
                    user_id: 'user-1',
                    file_path: 'src/index.ts',
                    function_name: 'main',
                    expertise_score: 72,
                    commit_count: 5,
                    created_at: new Date()
                }
            ]
        });
        const contributions = await service.listContributions('user-1');
        expect(contributions).toHaveLength(1);
        expect(contributions[0].filePath).toBe('src/index.ts');
    });
    it('returns null for missing heatmap', async () => {
        mockClient.query.mockResolvedValueOnce({ rows: [] });
        const heatmap = await service.getLatestHeatmap('src/index.ts', 'file');
        expect(heatmap).toBeNull();
    });
    it('returns null for missing expert', async () => {
        mockClient.query.mockResolvedValueOnce({ rows: [] });
        const expert = await service.findExpert('src/index.ts', 'file');
        expect(expert).toBeNull();
    });
    it('emits contribution-recorded event', async () => {
        let emittedEvent;
        service.on('contribution-recorded', event => {
            emittedEvent = event;
        });
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'contrib-1',
                    user_id: 'user-1',
                    file_path: 'src/index.ts',
                    function_name: null,
                    expertise_score: 50,
                    commit_count: 1,
                    created_at: new Date()
                }]
        });
        await service.recordContribution('user-1', 'src/index.ts', null, 50, 1);
        expect(emittedEvent.id).toBe('contrib-1');
    });
    it('emits heatmap-generated event', async () => {
        let emittedEvent;
        service.on('heatmap-generated', event => {
            emittedEvent = event;
        });
        mockClient.query.mockResolvedValueOnce({ rows: [{ user_id: 'user-1', score: 72 }] });
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        await service.generateHeatmap('src/index.ts', 'file');
        expect(emittedEvent.target).toBe('src/index.ts');
    });
    it('emits expert-found event', async () => {
        let emittedEvent;
        service.on('expert-found', event => {
            emittedEvent = event;
        });
        mockClient.query.mockResolvedValueOnce({ rows: [{ user_id: 'user-1', score: 72 }] });
        mockClient.query.mockResolvedValueOnce({ rows: [{ total: 90 }] });
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        await service.findExpert('src/index.ts', 'file');
        expect(emittedEvent.userId).toBe('user-1');
    });
    it('supports function-level expertise', async () => {
        mockClient.query.mockResolvedValueOnce({ rows: [{ user_id: 'user-2', score: 60 }] });
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        const heatmap = await service.generateHeatmap('renderDashboard', 'function');
        expect(heatmap.targetType).toBe('function');
    });
});
//# sourceMappingURL=expertise-heatmap.test.js.map