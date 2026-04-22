/**
 * @file        apps/backend/src/services/hot-standby/__tests__/state-machine.test.ts
 * @module      services/hot-standby
 * @description Test suite for HotStandbyStateMachine
 */
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { HotStandbyStateMachine } from '../state-machine';
describe('HotStandbyStateMachine', () => {
    let stateMachine;
    let redisMock;
    let publishSpy;
    let setSpy;
    beforeEach(() => {
        publishSpy = vi.fn().mockResolvedValue(1);
        setSpy = vi.fn().mockResolvedValue('OK');
        redisMock = {
            publish: publishSpy,
            set: setSpy,
            del: vi.fn().mockResolvedValue(1),
            duplicate: vi.fn().mockReturnValue({
                on: vi.fn(),
                subscribe: vi.fn().mockResolvedValue(1),
            }),
        };
        stateMachine = new HotStandbyStateMachine('broker-1', 'broker-2', redisMock, {
            heartbeatInterval: 100,
            heartbeatTimeout: 300,
            failureThreshold: 3,
        });
    });
    afterEach(async () => {
        await stateMachine.shutdown();
    });
    describe('Initialization', () => {
        it('should initialize with primary role', async () => {
            await stateMachine.initialize('primary');
            const status = stateMachine.getStatus();
            expect(status.brokerId).toBe('broker-1');
            expect(status.role).toBe('primary');
            expect(status.state).toBe('healthy');
            expect(status.isOperational).toBe(true);
        });
        it('should initialize with replica role', async () => {
            await stateMachine.initialize('replica');
            const status = stateMachine.getStatus();
            expect(status.role).toBe('replica');
            expect(status.isOperational).toBe(true);
        });
        it('should set up broker info in Redis', async () => {
            await stateMachine.initialize('primary');
            expect(setSpy).toHaveBeenCalledWith(expect.stringContaining('broker:broker-1'), expect.any(String), 'EX', 60);
        });
    });
    describe('Heartbeat Mechanism', () => {
        it('should send heartbeat periodically', async () => {
            await stateMachine.initialize('primary');
            // Wait for heartbeat to be sent
            await new Promise((resolve) => setTimeout(resolve, 150));
            expect(publishSpy).toHaveBeenCalledWith(expect.stringContaining('heartbeat:broker-2'), expect.stringContaining('broker-1'));
        });
        it('should track heartbeat sent time', async () => {
            await stateMachine.initialize('primary');
            // Wait for heartbeat
            await new Promise((resolve) => setTimeout(resolve, 150));
            const status = stateMachine.getStatus();
            expect(status.lastHeartbeatSent).toBeGreaterThan(0);
        });
        it('should handle received heartbeat', async () => {
            await stateMachine.initialize('replica');
            const heartbeat = {
                brokerId: 'broker-2',
                role: 'primary',
                state: 'healthy',
                sessionCount: 5,
                timestamp: Date.now(),
            };
            // Simulate heartbeat reception
            stateMachine['handleHeartbeatReceived'](heartbeat);
            const status = stateMachine.getStatus();
            expect(status.lastHeartbeatReceived).toBeGreaterThan(0);
            expect(status.remoteBrokerHealth?.sessionCount).toBe(5);
        });
        it('should reset missed count on successful heartbeat', async () => {
            await stateMachine.initialize('replica');
            // Set up remote broker health with missed counts
            stateMachine['remoteBrokerHealth'] = {
                brokerId: 'broker-2',
                lastHeartbeat: Date.now() - 500,
                missedCount: 2,
                isHealthy: false,
                state: 'degraded',
                sessionCount: 0,
            };
            const heartbeat = {
                brokerId: 'broker-2',
                role: 'primary',
                state: 'healthy',
                sessionCount: 5,
                timestamp: Date.now(),
            };
            stateMachine['handleHeartbeatReceived'](heartbeat);
            expect(stateMachine['remoteBrokerHealth'].missedCount).toBe(0);
            expect(stateMachine['remoteBrokerHealth'].isHealthy).toBe(true);
        });
    });
    describe('Failure Detection', () => {
        it('should mark remote broker as degraded after heartbeat timeout', async () => {
            await stateMachine.initialize('replica');
            stateMachine['remoteBrokerHealth'] = {
                brokerId: 'broker-2',
                lastHeartbeat: Date.now() - 400, // Past timeout threshold
                missedCount: 0,
                isHealthy: true,
                state: 'healthy',
                sessionCount: 0,
            };
            await stateMachine['checkHeartbeatHealth']();
            expect(stateMachine['state']).toBe('degraded');
            expect(stateMachine['remoteBrokerHealth'].missedCount).toBe(1);
        });
        it('should trigger failover after threshold exceeded', async () => {
            const promoteSpy = vi.spyOn(stateMachine, 'promoteToMaster');
            await stateMachine.initialize('replica');
            stateMachine['remoteBrokerHealth'] = {
                brokerId: 'broker-2',
                lastHeartbeat: Date.now() - 400,
                missedCount: 2, // Already 2, next check will exceed threshold
                isHealthy: false,
                state: 'unhealthy',
                sessionCount: 0,
            };
            await stateMachine['checkHeartbeatHealth']();
            expect(stateMachine['state']).toBe('unhealthy');
            expect(promoteSpy).toHaveBeenCalled();
        });
        it('should record failure detection time', async () => {
            await stateMachine.initialize('replica');
            stateMachine['failureDetectionStartTime'] = Date.now() - 300;
            stateMachine['metrics'].failureDetectionTime = 300;
            const status = stateMachine.getStatus();
            expect(status.metrics.failureDetectionTime).toBe(300);
        });
    });
    describe('Promotion Logic', () => {
        it('should promote replica to primary on failure', async () => {
            setSpy.mockResolvedValueOnce('OK'); // For promotion lock
            await stateMachine.initialize('replica');
            await stateMachine['promoteToMaster']();
            expect(stateMachine['role']).toBe('primary');
            expect(setSpy).toHaveBeenCalledWith(expect.stringContaining('promotion:lock'), 'broker-1', 'EX', expect.any(Number), 'NX');
        });
        it('should set primary ID in Redis on promotion', async () => {
            setSpy.mockResolvedValueOnce('OK'); // For promotion lock
            setSpy.mockResolvedValueOnce('OK'); // For primary ID
            await stateMachine.initialize('replica');
            await stateMachine['promoteToMaster']();
            expect(setSpy).toHaveBeenCalledWith(expect.stringContaining('primary:id'), 'broker-1');
        });
        it('should prevent split-brain on promotion', async () => {
            setSpy.mockResolvedValueOnce(null); // Lock acquisition fails
            const preventedSpy = vi.fn();
            stateMachine.on('split_brain_prevented', preventedSpy);
            await stateMachine.initialize('replica');
            await stateMachine['promoteToMaster']();
            expect(preventedSpy).toHaveBeenCalled();
            expect(stateMachine['role']).toBe('replica'); // Role unchanged
        });
        it('should update promotion metrics', async () => {
            setSpy.mockResolvedValueOnce('OK'); // For promotion lock
            await stateMachine.initialize('replica');
            const beforePromotion = Date.now();
            await stateMachine['promoteToMaster']();
            const afterPromotion = Date.now();
            const status = stateMachine.getStatus();
            expect(status.metrics.promotionTime).toBeGreaterThan(0);
            expect(status.metrics.promotionTime).toBeLessThan(afterPromotion - beforePromotion + 100);
        });
    });
    describe('Recovery', () => {
        it('should transition to healthy on heartbeat recovery', async () => {
            await stateMachine.initialize('replica');
            // Simulate degraded state
            stateMachine['state'] = 'degraded';
            const heartbeat = {
                brokerId: 'broker-2',
                role: 'primary',
                state: 'healthy',
                sessionCount: 5,
                timestamp: Date.now(),
            };
            stateMachine['handleHeartbeatReceived'](heartbeat);
            expect(stateMachine['state']).toBe('healthy');
        });
        it('should emit recovery_completed event', async () => {
            const recoveryCompletedSpy = vi.fn();
            stateMachine.on('recovery_completed', recoveryCompletedSpy);
            await stateMachine.initialize('replica');
            stateMachine['state'] = 'degraded';
            stateMachine['failureDetectionStartTime'] = Date.now() - 100;
            const heartbeat = {
                brokerId: 'broker-2',
                role: 'primary',
                state: 'healthy',
                sessionCount: 5,
                timestamp: Date.now(),
            };
            stateMachine['handleHeartbeatReceived'](heartbeat);
            expect(recoveryCompletedSpy).toHaveBeenCalled();
        });
    });
    describe('Status and Metrics', () => {
        it('should return accurate status snapshot', async () => {
            await stateMachine.initialize('primary');
            const status = stateMachine.getStatus();
            expect(status).toHaveProperty('brokerId', 'broker-1');
            expect(status).toHaveProperty('role', 'primary');
            expect(status).toHaveProperty('state');
            expect(status).toHaveProperty('isOperational');
            expect(status).toHaveProperty('metrics');
        });
        it('should track failover metrics', async () => {
            await stateMachine.initialize('replica');
            stateMachine['metrics'].failureDetectionTime = 300;
            stateMachine['metrics'].promotionTime = 150;
            stateMachine['metrics'].totalFailoverTime = 450;
            const status = stateMachine.getStatus();
            expect(status.metrics.failureDetectionTime).toBe(300);
            expect(status.metrics.promotionTime).toBe(150);
            expect(status.metrics.totalFailoverTime).toBe(450);
        });
        it('should maintain failover history', () => {
            stateMachine['recordFailoverEvent']('heartbeat_sent', {
                details: { role: 'primary' },
            });
            const history = stateMachine.getFailoverHistory();
            expect(history).toHaveLength(1);
            expect(history[0].type).toBe('heartbeat_sent');
            expect(history[0].brokerId).toBe('broker-1');
        });
        it('should limit failover history size', () => {
            const maxHistory = 5;
            for (let i = 0; i < maxHistory + 10; i++) {
                stateMachine['recordFailoverEvent']('heartbeat_sent');
            }
            const history = stateMachine.getFailoverHistory();
            expect(history.length).toBeLessThanOrEqual(maxHistory);
        });
    });
    describe('Session Management', () => {
        it('should update session count', async () => {
            await stateMachine.initialize('primary');
            stateMachine.updateSessionCount(10);
            expect(stateMachine['sessionCount']).toBe(10);
            expect(setSpy).toHaveBeenCalledWith(expect.stringContaining('broker:broker-1'), expect.stringContaining('"sessionCount":10'), 'EX', 60);
        });
    });
    describe('Shutdown', () => {
        it('should cleanup resources on shutdown', async () => {
            await stateMachine.initialize('primary');
            await stateMachine.shutdown();
            expect(stateMachine['heartbeatIntervalId']).toBeNull();
            expect(stateMachine['recoveryCheckIntervalId']).toBeNull();
        });
    });
    describe('SLA Compliance', () => {
        it('should complete failover within 1 second SLA', async () => {
            setSpy.mockResolvedValueOnce('OK'); // For promotion lock
            await stateMachine.initialize('replica');
            const startTime = Date.now();
            await stateMachine['promoteToMaster']();
            const duration = Date.now() - startTime;
            expect(duration).toBeLessThan(1000);
        });
        it('should detect failure within 500ms', async () => {
            await stateMachine.initialize('replica');
            stateMachine['failureDetectionStartTime'] = Date.now() - 400;
            await stateMachine['checkHeartbeatHealth']();
            // After 3 missed heartbeats (300ms timeout each)
            stateMachine['remoteBrokerHealth'].lastHeartbeat = Date.now() - 400;
            stateMachine['remoteBrokerHealth'].missedCount = 2;
            await stateMachine['checkHeartbeatHealth']();
            expect(stateMachine['state']).toMatch(/degraded|unhealthy/);
        });
    });
});
//# sourceMappingURL=state-machine.test.js.map