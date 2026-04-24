import { describe, it, expect, beforeEach } from 'vitest';
import { AnomalyDetectionEngine, AnomalyDetectionService } from '../index';
describe('AnomalyDetectionEngine', () => {
    let engine;
    beforeEach(() => {
        engine = new AnomalyDetectionEngine();
    });
    it('should calculate statistics for dataset', () => {
        const values = [1, 2, 3, 4, 5];
        const stats = engine.calculateDimensionStatistics(values, 'test');
        expect(stats.mean).toBe(3);
        expect(stats.stdDev).toBeGreaterThan(0);
    });
    it('should build profile from sufficient samples', () => {
        const events = Array.from({ length: 20 }, (_, i) => ({
            sessionId: `session-${i}`,
            userId: 'user1',
            timestamp: Date.now() - (20 - i) * 24 * 60 * 60 * 1000,
            loginHour: 9,
            filesAccessed: 50,
            fileExtensions: ['.ts'],
            directoriesAccessed: ['/src'],
            sessionDurationSeconds: 3600,
            bytesTransferred: 100 * 1024 * 1024,
        }));
        const profile = engine.buildProfile('user1', events);
        expect(profile.sampleCount).toBe(20);
        expect(profile.sessionDuration.mean).toBeGreaterThan(0);
    });
    it('should score normal behavior as low anomaly', () => {
        const events = Array.from({ length: 20 }, (_, i) => ({
            sessionId: `session-${i}`,
            userId: 'user2',
            timestamp: Date.now() - (20 - i) * 24 * 60 * 60 * 1000,
            loginHour: 9,
            filesAccessed: 50,
            fileExtensions: ['.ts'],
            directoriesAccessed: ['/src'],
            sessionDurationSeconds: 3600,
            bytesTransferred: 100 * 1024 * 1024,
        }));
        const profile = engine.buildProfile('user2', events);
        const normalEvent = {
            sessionId: 'test',
            userId: 'user2',
            timestamp: Date.now(),
            loginHour: 9,
            filesAccessed: 50,
            fileExtensions: ['.ts'],
            directoriesAccessed: ['/src'],
            sessionDurationSeconds: 3600,
            bytesTransferred: 100 * 1024 * 1024,
        };
        const score = engine.scoreSession(normalEvent, profile);
        expect(score.overallScore).toBeLessThan(0.5);
    });
    it('should score anomalous behavior as high', () => {
        const events = Array.from({ length: 20 }, (_, i) => ({
            sessionId: `session-${i}`,
            userId: 'user3',
            timestamp: Date.now() - (20 - i) * 24 * 60 * 60 * 1000,
            loginHour: 9,
            filesAccessed: 50,
            fileExtensions: ['.ts'],
            directoriesAccessed: ['/src'],
            sessionDurationSeconds: 3600,
            bytesTransferred: 100 * 1024 * 1024,
        }));
        const profile = engine.buildProfile('user3', events);
        const anomalousEvent = {
            sessionId: 'test',
            userId: 'user3',
            timestamp: Date.now(),
            loginHour: 3,
            filesAccessed: 500,
            fileExtensions: ['.ts'],
            directoriesAccessed: ['/sensitive'],
            sessionDurationSeconds: 30000,
            bytesTransferred: 1024 * 1024 * 1024,
        };
        const score = engine.scoreSession(anomalousEvent, profile);
        expect(score.overallScore).toBeGreaterThan(0.5);
    });
});
describe('AnomalyDetectionService', () => {
    let service;
    beforeEach(() => {
        service = new AnomalyDetectionService();
    });
    it('should detect anomalies in session', async () => {
        const events = Array.from({ length: 20 }, (_, i) => ({
            sessionId: `session-${i}`,
            userId: 'user4',
            timestamp: Date.now() - (20 - i) * 24 * 60 * 60 * 1000,
            loginHour: 9,
            filesAccessed: 50,
            fileExtensions: ['.ts'],
            directoriesAccessed: ['/src'],
            sessionDurationSeconds: 3600,
            bytesTransferred: 100 * 1024 * 1024,
        }));
        const anomalousEvent = {
            sessionId: 'test',
            userId: 'user4',
            timestamp: Date.now(),
            loginHour: 3,
            filesAccessed: 500,
            fileExtensions: ['.ts'],
            directoriesAccessed: ['/sensitive'],
            sessionDurationSeconds: 30000,
            bytesTransferred: 1024 * 1024 * 1024,
        };
        const result = await service.detectAnomalies(anomalousEvent, events);
        expect(result.isAnomaly).toBe(true);
        expect(result.alerts.length).toBeGreaterThan(0);
    });
    it('should return profile stats', async () => {
        const events = Array.from({ length: 20 }, (_, i) => ({
            sessionId: `session-${i}`,
            userId: 'user5',
            timestamp: Date.now() - (20 - i) * 24 * 60 * 60 * 1000,
            loginHour: 9,
            filesAccessed: 50,
            fileExtensions: ['.ts'],
            directoriesAccessed: ['/src'],
            sessionDurationSeconds: 3600,
            bytesTransferred: 100 * 1024 * 1024,
        }));
        await service.getOrCreateProfile('user5', events);
        const stats = service.getProfileStats('user5');
        expect(stats).not.toBeNull();
        expect(stats?.sampleCount).toBe(20);
    });
});
//# sourceMappingURL=anomaly-detection.test.js.map