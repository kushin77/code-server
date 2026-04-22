import { describe, it, expect, beforeEach, vi } from 'vitest';
import { TeamHealthDashboardService } from '../index';
vi.mock('../../../lib/logger', () => ({
    getLogger: () => ({
        info: vi.fn(),
        error: vi.fn(),
        debug: vi.fn(),
        warn: vi.fn()
    })
}));
describe('TeamHealthDashboardService', () => {
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
        service = new TeamHealthDashboardService(mockPool);
    });
    it('should initialize service and create tables', async () => {
        for (let i = 0; i < 12; i++) {
            mockClient.query.mockResolvedValueOnce({});
        }
        await service.initialize();
        expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('team_health_metrics'));
        expect(mockClient.release).toHaveBeenCalled();
    });
    it('should record flow time', async () => {
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        await service.recordFlowTime('team-1', 'user-1', 'coding', 45);
        expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('INSERT INTO flow_time_tracking'), expect.any(Array));
    });
    it('should record pairing session', async () => {
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        await service.recordPairingSession('team-1', 'user-1', 'user-2', 60);
        expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('INSERT INTO team_pairing_sessions'), expect.any(Array));
    });
    it('should record code review metrics', async () => {
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        await service.recordCodeReviewMetrics('team-1', 'pr-1', 'reviewer-1', 30, 120);
        expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('INSERT INTO code_review_metrics'), expect.any(Array));
    });
    it('should record AI utilization', async () => {
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        await service.recordAIUtilization('team-1', 'user-1', 'copilot-complete');
        expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('INSERT INTO ai_utilization_tracking'), expect.any(Array));
    });
    it('should calculate team health metrics', async () => {
        // Flow time query
        mockClient.query.mockResolvedValueOnce({
            rows: [{ avg_flow_time: 45 }]
        });
        // Pairing frequency query
        mockClient.query.mockResolvedValueOnce({
            rows: [{ pair_count: 5 }]
        });
        // Review latency query
        mockClient.query.mockResolvedValueOnce({
            rows: [{ avg_latency: 1800 }]
        });
        // AI utilization query
        mockClient.query.mockResolvedValueOnce({
            rows: [{ ai_uses: 20 }]
        });
        // Insert metrics
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        const metrics = await service.calculateTeamHealthMetrics('team-1');
        expect(metrics.teamId).toBe('team-1');
        expect(metrics.healthScore).toBeGreaterThanOrEqual(0);
        expect(metrics.healthScore).toBeLessThanOrEqual(100);
    });
    it('should get latest metrics', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    team_id: 'team-1',
                    average_flow_time_mins: 45,
                    pairing_frequency: 5,
                    review_latency_hours: 0.5,
                    ai_utilization_percent: 60,
                    collaboration_index: 50,
                    health_score: 75,
                    generated_at: new Date()
                }]
        });
        const metrics = await service.getLatestMetrics('team-1');
        expect(metrics).not.toBeNull();
        expect(metrics?.teamId).toBe('team-1');
        expect(metrics?.healthScore).toBe(75);
    });
    it('should generate weekly digest', async () => {
        // calculateTeamHealthMetrics calls
        mockClient.query.mockResolvedValueOnce({ rows: [{ avg_flow_time: 45 }] });
        mockClient.query.mockResolvedValueOnce({ rows: [{ pair_count: 5 }] });
        mockClient.query.mockResolvedValueOnce({ rows: [{ avg_latency: 1800 }] });
        mockClient.query.mockResolvedValueOnce({ rows: [{ ai_uses: 20 }] });
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        // Get top pairs
        mockClient.query.mockResolvedValueOnce({
            rows: [
                { user_id_1: 'user-1', user_id_2: 'user-2', sessions: 10 },
                { user_id_1: 'user-1', user_id_2: 'user-3', sessions: 8 }
            ]
        });
        // Get slow reviews
        mockClient.query.mockResolvedValueOnce({
            rows: [
                { pull_request_id: 'pr-1', time_to_first_review_mins: 120 }
            ]
        });
        // Insert digest
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        const digest = await service.generateWeeklyDigest('team-1');
        expect(digest.teamId).toBe('team-1');
        expect(digest.topPairs).toBeDefined();
        expect(digest.slowReviews).toBeDefined();
        expect(digest.summary).toBeDefined();
    });
    it('should get weekly digest', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    team_id: 'team-1',
                    week_start_date: '2024-01-01',
                    metrics: { healthScore: 75 },
                    top_pairs: [{ user1: 'user-1', user2: 'user-2' }],
                    slow_reviews: [{ pullRequestId: 'pr-1', latency: 120 }],
                    ai_trends: { usage: 60, impactScore: 60 },
                    summary: 'Team is healthy',
                    generated_at: new Date()
                }]
        });
        const digest = await service.getWeeklyDigest('team-1');
        expect(digest).not.toBeNull();
        expect(digest?.teamId).toBe('team-1');
    });
    it('should get team history', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [
                {
                    team_id: 'team-1',
                    average_flow_time_mins: 45,
                    pairing_frequency: 5,
                    review_latency_hours: 0.5,
                    ai_utilization_percent: 60,
                    collaboration_index: 50,
                    health_score: 75,
                    generated_at: new Date()
                }
            ]
        });
        const history = await service.getTeamHistory('team-1', 30);
        expect(history.length).toBe(1);
        expect(history[0].healthScore).toBe(75);
    });
    it('should emit flow-time-recorded event', async () => {
        let emittedEvent;
        service.on('flow-time-recorded', (event) => {
            emittedEvent = event;
        });
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        await service.recordFlowTime('team-1', 'user-1', 'coding', 45);
        expect(emittedEvent).toBeDefined();
        expect(emittedEvent.teamId).toBe('team-1');
    });
    it('should emit pairing-recorded event', async () => {
        let emittedEvent;
        service.on('pairing-recorded', (event) => {
            emittedEvent = event;
        });
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        await service.recordPairingSession('team-1', 'user-1', 'user-2', 60);
        expect(emittedEvent).toBeDefined();
        expect(emittedEvent.durationMins).toBe(60);
    });
    it('should emit review-recorded event', async () => {
        let emittedEvent;
        service.on('review-recorded', (event) => {
            emittedEvent = event;
        });
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        await service.recordCodeReviewMetrics('team-1', 'pr-1', 'reviewer-1', 30, 120);
        expect(emittedEvent).toBeDefined();
        expect(emittedEvent.timeToFirstReviewMins).toBe(30);
    });
    it('should emit metrics-calculated event', async () => {
        let emittedEvent;
        service.on('metrics-calculated', (event) => {
            emittedEvent = event;
        });
        mockClient.query.mockResolvedValueOnce({ rows: [{ avg_flow_time: 45 }] });
        mockClient.query.mockResolvedValueOnce({ rows: [{ pair_count: 5 }] });
        mockClient.query.mockResolvedValueOnce({ rows: [{ avg_latency: 1800 }] });
        mockClient.query.mockResolvedValueOnce({ rows: [{ ai_uses: 20 }] });
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        await service.calculateTeamHealthMetrics('team-1');
        expect(emittedEvent).toBeDefined();
        expect(emittedEvent.teamId).toBe('team-1');
    });
    it('should emit digest-generated event', async () => {
        let emittedEvent;
        service.on('digest-generated', (event) => {
            emittedEvent = event;
        });
        mockClient.query.mockResolvedValueOnce({ rows: [{ avg_flow_time: 45 }] });
        mockClient.query.mockResolvedValueOnce({ rows: [{ pair_count: 5 }] });
        mockClient.query.mockResolvedValueOnce({ rows: [{ avg_latency: 1800 }] });
        mockClient.query.mockResolvedValueOnce({ rows: [{ ai_uses: 20 }] });
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        mockClient.query.mockResolvedValueOnce({ rows: [] });
        mockClient.query.mockResolvedValueOnce({ rows: [] });
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        await service.generateWeeklyDigest('team-1');
        expect(emittedEvent).toBeDefined();
        expect(emittedEvent.teamId).toBe('team-1');
    });
    it('should return null for non-existent metrics', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: []
        });
        const metrics = await service.getLatestMetrics('non-existent');
        expect(metrics).toBeNull();
    });
    it('should return null for non-existent digest', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: []
        });
        const digest = await service.getWeeklyDigest('non-existent');
        expect(digest).toBeNull();
    });
    it('should handle empty team history', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: []
        });
        const history = await service.getTeamHistory('team-1', 30);
        expect(history).toEqual([]);
    });
    it('should calculate collaboration index correctly', async () => {
        mockClient.query.mockResolvedValueOnce({ rows: [{ avg_flow_time: 30 }] });
        mockClient.query.mockResolvedValueOnce({ rows: [{ pair_count: 10 }] });
        mockClient.query.mockResolvedValueOnce({ rows: [{ avg_latency: 900 }] });
        mockClient.query.mockResolvedValueOnce({ rows: [{ ai_uses: 50 }] });
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        const metrics = await service.calculateTeamHealthMetrics('team-1');
        expect(metrics.collaborationIndex).toBeGreaterThan(0);
        expect(metrics.collaborationIndex).toBeLessThanOrEqual(100);
    });
    it('should handle multiple review metrics', async () => {
        for (let i = 0; i < 3; i++) {
            mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        }
        await service.recordCodeReviewMetrics('team-1', 'pr-1', 'reviewer-1', 30, 120);
        await service.recordCodeReviewMetrics('team-1', 'pr-2', 'reviewer-2', 45, 180);
        await service.recordCodeReviewMetrics('team-1', 'pr-3', 'reviewer-1', 25, 100);
        expect(mockClient.query).toHaveBeenCalledTimes(3);
    });
});
//# sourceMappingURL=team-health-dashboard.test.js.map