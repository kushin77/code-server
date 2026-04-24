import { describe, expect, it, beforeEach } from 'vitest';
import EdgeRelayManager from '../EdgeRelayManager';
describe('EdgeRelayManager', () => {
    let manager;
    beforeEach(() => {
        manager = new EdgeRelayManager({
            regions: ['us-east-1', 'eu-west-1', 'ap-south-1'],
            targetLatencyMs: 50,
            affinityTimeoutMs: 300000,
            healthStalenessMs: 30000,
            maxSessionsPerRelay: 100,
        });
        manager.registerRelay({
            relayId: 'relay-us-east-1-a',
            regionId: 'us-east-1',
            endpoint: 'wss://relay-us-east-1-a.example.com',
            healthy: true,
            latencyMs: 28,
            capacity: 100,
        });
        manager.registerRelay({
            relayId: 'relay-eu-west-1-a',
            regionId: 'eu-west-1',
            endpoint: 'wss://relay-eu-west-1-a.example.com',
            healthy: true,
            latencyMs: 46,
            capacity: 100,
        });
        manager.registerRelay({
            relayId: 'relay-ap-south-1-a',
            regionId: 'ap-south-1',
            endpoint: 'wss://relay-ap-south-1-a.example.com',
            healthy: true,
            latencyMs: 96,
            capacity: 100,
        });
    });
    it('selects the lowest-latency relay under the target threshold', () => {
        const decision = manager.selectRelay({
            sessionId: 'session-1',
            preferredRegions: ['eu-west-1', 'us-east-1'],
        });
        expect(decision.relayId).toBe('relay-us-east-1-a');
        expect(decision.estimatedLatency).toBeLessThanOrEqual(50);
        expect(decision.reason).toMatch(/target latency|session affinity/);
    });
    it('preserves session affinity on repeated selection', () => {
        const firstDecision = manager.selectRelay({
            sessionId: 'session-2',
            preferredRegions: ['eu-west-1'],
        });
        const secondDecision = manager.selectRelay({
            sessionId: 'session-2',
            preferredRegions: ['ap-south-1'],
        });
        expect(firstDecision.relayId).toBe(secondDecision.relayId);
        expect(secondDecision.reason).toBe('session affinity');
    });
    it('migrates a session when the relay becomes unhealthy', () => {
        const initialDecision = manager.selectRelay({
            sessionId: 'session-3',
            preferredRegions: ['us-east-1'],
        });
        manager.updateRelayHealth(initialDecision.relayId, false);
        const migratedDecision = manager.migrateSession('session-3', 'relay-eu-west-1-a', 'relay failure');
        expect(migratedDecision.relayId).toBe('relay-eu-west-1-a');
        expect(migratedDecision.migrated).toBe(true);
        expect(manager.getRelay('relay-eu-west-1-a')?.activeSessions).toBe(1);
    });
    it('drains a relay and migrates attached sessions away', () => {
        manager.selectRelay({ sessionId: 'session-4' });
        manager.selectRelay({ sessionId: 'session-5' });
        const migratedSessions = manager.drainRelay('relay-us-east-1-a');
        expect(migratedSessions.length).toBeGreaterThan(0);
        expect(manager.getRelay('relay-us-east-1-a')?.draining).toBe(true);
    });
    it('reports relay health and migration metrics', () => {
        manager.selectRelay({ sessionId: 'session-6' });
        manager.migrateSession('session-6', 'relay-eu-west-1-a', 'latency spike');
        const metrics = manager.getMetrics();
        expect(metrics.totalRelays).toBe(3);
        expect(metrics.healthyRelays).toBeGreaterThanOrEqual(2);
        expect(metrics.totalSelections).toBeGreaterThan(0);
        expect(metrics.totalMigrations).toBe(1);
    });
});
//# sourceMappingURL=EdgeRelayManager.test.js.map