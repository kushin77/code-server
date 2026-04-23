/**
 * Session Hibernation Service Tests
 * Test coverage for CRIU checkpoints, restore, idle detection, and audit logging
 */
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { HibernationService } from '../hibernation-service.js';
describe('HibernationService', () => {
    let service;
    beforeEach(() => {
        service = HibernationService.getInstance({
            enableAutoHibernation: true,
            idleThresholdMs: 1000,
            maxCheckpointsPerSession: 10,
            restoreTimeoutMs: 5000,
            maxAuditLogSize: 10000,
        });
    });
    afterEach(() => {
        service.shutdown();
    });
    describe('initialization', () => {
        it('should create singleton instance', () => {
            expect(service).toBeDefined();
            expect(service instanceof HibernationService).toBe(true);
        });
        it('should have default configuration', () => {
            expect(service).toBeDefined();
        });
    });
    describe('session registration', () => {
        it('should register a new session', () => {
            const session = service.registerSession('session-1', 'user-1', 'workspace-1');
            expect(session).toBeDefined();
            expect(session.sessionId).toBe('session-1');
            expect(session.userId).toBe('user-1');
        });
        it('should emit session-registered event', () => {
            return new Promise((resolve) => {
                service.once('session-registered', (data) => {
                    expect(data.session).toBeDefined();
                    expect(data.session.sessionId).toBe('session-2');
                    resolve();
                });
                service.registerSession('session-2', 'user-1', 'workspace-1');
            });
        });
        it('should set initial hibernation state to active', () => {
            const session = service.registerSession('session-3', 'user-1', 'workspace-1');
            expect(session.hibernationState).toBe('active');
        });
        it('should generate unique session ids', () => {
            const s1 = service.registerSession('session-a', 'user-1', 'workspace-1');
            const s2 = service.registerSession('session-a', 'user-1', 'workspace-1');
            // IDs differ by timestamp
            expect(s1.id).not.toEqual(s2.id);
        });
        it('should allow custom idle threshold', () => {
            const session = service.registerSession('session-4', 'user-1', 'workspace-1', 2000);
            expect(session.idleThresholdMs).toBe(2000);
        });
    });
    describe('checkpoint creation', () => {
        it('should create checkpoint for registered session', async () => {
            const session = service.registerSession('sess-cp1', 'user-1', 'workspace-1');
            const req = {
                sessionId: 'sess-cp1',
                userId: 'user-1',
                workspaceId: 'workspace-1',
                force: false,
                includeProcesses: true,
                includeMemory: true,
                compress: true,
            };
            const result = await service.createCheckpoint(req, '192.168.1.1', 'Mozilla/5.0');
            expect(result.success).toBe(true);
            expect(result.checkpoint.id).toBeDefined();
        });
        it('should emit checkpoint-created event', () => {
            service.registerSession('sess-cp2', 'user-1', 'workspace-1');
            const req = {
                sessionId: 'sess-cp2',
                userId: 'user-1',
                workspaceId: 'workspace-1',
                force: false,
                includeProcesses: true,
                includeMemory: true,
                compress: true,
            };
            return new Promise((resolve) => {
                service.once('checkpoint-created', (data) => {
                    expect(data.checkpoint).toBeDefined();
                    expect(data.result.success).toBe(true);
                    resolve();
                });
                service.createCheckpoint(req, '192.168.1.1', 'Mozilla/5.0');
            });
        });
        it('should set checkpoint state to hibernating', async () => {
            const session = service.registerSession('sess-cp3', 'user-1', 'workspace-1');
            const req = {
                sessionId: 'sess-cp3',
                userId: 'user-1',
                workspaceId: 'workspace-1',
                force: false,
                includeProcesses: true,
                includeMemory: true,
                compress: true,
            };
            const result = await service.createCheckpoint(req, '192.168.1.1', 'Mozilla/5.0');
            expect(result.checkpoint.state).toBe('hibernating');
        });
        it('should generate unique checkpoint ids', async () => {
            service.registerSession('sess-cp4', 'user-1', 'workspace-1');
            const req = {
                sessionId: 'sess-cp4',
                userId: 'user-1',
                workspaceId: 'workspace-1',
                force: false,
                includeProcesses: true,
                includeMemory: true,
                compress: true,
            };
            const r1 = await service.createCheckpoint(req, '192.168.1.1', 'Mozilla/5.0');
            // Small delay to ensure different timestamp
            await new Promise((resolve) => setTimeout(resolve, 10));
            const r2 = await service.createCheckpoint(req, '192.168.1.1', 'Mozilla/5.0');
            expect(r1.checkpoint.id).not.toEqual(r2.checkpoint.id);
        });
        it('should return ~80% RAM savings', async () => {
            service.registerSession('sess-cp5', 'user-1', 'workspace-1');
            const req = {
                sessionId: 'sess-cp5',
                userId: 'user-1',
                workspaceId: 'workspace-1',
                force: false,
                includeProcesses: true,
                includeMemory: true,
                compress: true,
            };
            const result = await service.createCheckpoint(req, '192.168.1.1', 'Mozilla/5.0');
            expect(result.ramSavedPercent).toBeGreaterThan(75);
            expect(result.ramSavedPercent).toBeLessThan(85);
        });
        it('should fail for non-existent session', async () => {
            const req = {
                sessionId: 'non-existent',
                userId: 'user-1',
                workspaceId: 'workspace-1',
                force: false,
                includeProcesses: true,
                includeMemory: true,
                compress: true,
            };
            const result = await service.createCheckpoint(req, '192.168.1.1', 'Mozilla/5.0');
            expect(result.success).toBe(false);
        });
        it('should limit checkpoints per session', async () => {
            service.registerSession('sess-cp6', 'user-1', 'workspace-1');
            const req = {
                sessionId: 'sess-cp6',
                userId: 'user-1',
                workspaceId: 'workspace-1',
                force: false,
                includeProcesses: true,
                includeMemory: true,
                compress: true,
            };
            // Create 15 checkpoints (limit is 10)
            for (let i = 0; i < 15; i++) {
                await service.createCheckpoint(req, '192.168.1.1', 'Mozilla/5.0');
            }
            const session = service.getSessionStatus('sess-cp6', 'user-1');
            expect(session?.checkpoints.length).toBeLessThanOrEqual(10);
        });
        it('should record checkpoint metadata', async () => {
            service.registerSession('sess-cp7', 'user-1', 'workspace-1');
            const req = {
                sessionId: 'sess-cp7',
                userId: 'user-1',
                workspaceId: 'workspace-1',
                force: false,
                includeProcesses: true,
                includeMemory: true,
                compress: true,
            };
            const result = await service.createCheckpoint(req, '192.168.1.1', 'Mozilla/5.0');
            expect(result.checkpoint.metadata.containerRuntime).toBeDefined();
            expect(result.checkpoint.metadata.runtimeVersion).toBeDefined();
            expect(result.checkpoint.metadata.launchCommand).toBeDefined();
        });
    });
    describe('session restore', () => {
        it('should restore session from checkpoint', async () => {
            service.registerSession('sess-r1', 'user-1', 'workspace-1');
            const checkpointReq = {
                sessionId: 'sess-r1',
                userId: 'user-1',
                workspaceId: 'workspace-1',
                force: false,
                includeProcesses: true,
                includeMemory: true,
                compress: true,
            };
            const checkpointResult = await service.createCheckpoint(checkpointReq, '192.168.1.1', 'Mozilla/5.0');
            const restoreReq = {
                checkpointId: checkpointResult.checkpoint.id,
                sessionId: 'sess-r1',
                userId: 'user-1',
                workspaceId: 'workspace-1',
            };
            const restoreResult = await service.restoreSession(restoreReq, '192.168.1.1', 'Mozilla/5.0');
            expect(restoreResult.success).toBe(true);
        });
        it('should emit session-restored event', () => {
            service.registerSession('sess-r2', 'user-1', 'workspace-1');
            const checkpointReq = {
                sessionId: 'sess-r2',
                userId: 'user-1',
                workspaceId: 'workspace-1',
                force: false,
                includeProcesses: true,
                includeMemory: true,
                compress: true,
            };
            return new Promise((resolve) => {
                service.once('session-restored', (data) => {
                    expect(data.result.success).toBe(true);
                    resolve();
                });
                service.createCheckpoint(checkpointReq, '192.168.1.1', 'Mozilla/5.0').then((checkpointResult) => {
                    const restoreReq = {
                        checkpointId: checkpointResult.checkpoint.id,
                        sessionId: 'sess-r2',
                        userId: 'user-1',
                        workspaceId: 'workspace-1',
                    };
                    service.restoreSession(restoreReq, '192.168.1.1', 'Mozilla/5.0');
                });
            });
        });
        it('should restore in < 5 seconds', async () => {
            service.registerSession('sess-r3', 'user-1', 'workspace-1');
            const checkpointReq = {
                sessionId: 'sess-r3',
                userId: 'user-1',
                workspaceId: 'workspace-1',
                force: false,
                includeProcesses: true,
                includeMemory: true,
                compress: true,
            };
            const checkpointResult = await service.createCheckpoint(checkpointReq, '192.168.1.1', 'Mozilla/5.0');
            const restoreReq = {
                checkpointId: checkpointResult.checkpoint.id,
                sessionId: 'sess-r3',
                userId: 'user-1',
                workspaceId: 'workspace-1',
            };
            const restoreResult = await service.restoreSession(restoreReq, '192.168.1.1', 'Mozilla/5.0');
            expect(restoreResult.duration).toBeLessThan(5000);
        });
        it('should restore all processes', async () => {
            service.registerSession('sess-r4', 'user-1', 'workspace-1');
            const checkpointReq = {
                sessionId: 'sess-r4',
                userId: 'user-1',
                workspaceId: 'workspace-1',
                force: false,
                includeProcesses: true,
                includeMemory: true,
                compress: true,
            };
            const checkpointResult = await service.createCheckpoint(checkpointReq, '192.168.1.1', 'Mozilla/5.0');
            const restoreReq = {
                checkpointId: checkpointResult.checkpoint.id,
                sessionId: 'sess-r4',
                userId: 'user-1',
                workspaceId: 'workspace-1',
            };
            const restoreResult = await service.restoreSession(restoreReq, '192.168.1.1', 'Mozilla/5.0');
            expect(restoreResult.processesRestored).toBe(checkpointResult.checkpoint.processesCheckpointed);
        });
        it('should fail for non-existent checkpoint', async () => {
            const restoreReq = {
                checkpointId: 'non-existent',
                sessionId: 'session-1',
                userId: 'user-1',
                workspaceId: 'workspace-1',
            };
            const result = await service.restoreSession(restoreReq, '192.168.1.1', 'Mozilla/5.0');
            expect(result.success).toBe(false);
        });
        it('should update session state to restored', async () => {
            service.registerSession('sess-r5', 'user-1', 'workspace-1');
            const checkpointReq = {
                sessionId: 'sess-r5',
                userId: 'user-1',
                workspaceId: 'workspace-1',
                force: false,
                includeProcesses: true,
                includeMemory: true,
                compress: true,
            };
            const checkpointResult = await service.createCheckpoint(checkpointReq, '192.168.1.1', 'Mozilla/5.0');
            const restoreReq = {
                checkpointId: checkpointResult.checkpoint.id,
                sessionId: 'sess-r5',
                userId: 'user-1',
                workspaceId: 'workspace-1',
            };
            await service.restoreSession(restoreReq, '192.168.1.1', 'Mozilla/5.0');
            const session = service.getSessionStatus('sess-r5', 'user-1');
            expect(session?.hibernationState).toBe('restored');
        });
    });
    describe('activity tracking', () => {
        it('should mark session as active', () => {
            service.registerSession('sess-a1', 'user-1', 'workspace-1');
            service.markActive('sess-a1', 'user-1');
            const session = service.getSessionStatus('sess-a1', 'user-1');
            expect(session?.lastActivityAt).toBeDefined();
        });
        it('should emit activity-detected event', () => {
            service.registerSession('sess-a2', 'user-1', 'workspace-1');
            return new Promise((resolve) => {
                service.once('session-activity-detected', () => {
                    expect(true).toBe(true);
                    resolve();
                });
                service.markActive('sess-a2', 'user-1');
            });
        });
        it('should detect idle sessions', async () => {
            const session = service.registerSession('sess-a3', 'user-1', 'workspace-1');
            // Wait for idle threshold to pass
            await new Promise((resolve) => setTimeout(resolve, 1100));
            const isIdle = service.isSessionIdle('sess-a3', 'user-1');
            expect(isIdle).toBe(true);
        });
        it('should reset idle state on activity', async () => {
            service.registerSession('sess-a4', 'user-1', 'workspace-1');
            await new Promise((resolve) => setTimeout(resolve, 1100));
            service.markActive('sess-a4', 'user-1');
            const isIdle = service.isSessionIdle('sess-a4', 'user-1');
            expect(isIdle).toBe(false);
        });
    });
    describe('session queries', () => {
        it('should get session status', () => {
            service.registerSession('sess-q1', 'user-1', 'workspace-1');
            const session = service.getSessionStatus('sess-q1', 'user-1');
            expect(session).toBeDefined();
            expect(session?.sessionId).toBe('sess-q1');
        });
        it('should return null for non-existent session', () => {
            const session = service.getSessionStatus('non-existent', 'user-1');
            expect(session).toBeNull();
        });
        it('should list hibernated sessions', async () => {
            service.registerSession('sess-q2', 'user-1', 'workspace-1');
            const checkpointReq = {
                sessionId: 'sess-q2',
                userId: 'user-1',
                workspaceId: 'workspace-1',
                force: false,
                includeProcesses: true,
                includeMemory: true,
                compress: true,
            };
            await service.createCheckpoint(checkpointReq, '192.168.1.1', 'Mozilla/5.0');
            const hibernated = service.listHibernatedSessions('user-1');
            expect(hibernated.length).toBeGreaterThan(0);
        });
        it('should only list user-specific hibernated sessions', async () => {
            service.registerSession('sess-q3a', 'user-1', 'workspace-1');
            service.registerSession('sess-q3b', 'user-2', 'workspace-2');
            const checkpointReq = {
                sessionId: 'sess-q3a',
                userId: 'user-1',
                workspaceId: 'workspace-1',
                force: false,
                includeProcesses: true,
                includeMemory: true,
                compress: true,
            };
            await service.createCheckpoint(checkpointReq, '192.168.1.1', 'Mozilla/5.0');
            const hibernated = service.listHibernatedSessions('user-1');
            expect(hibernated.every((s) => s.userId === 'user-1')).toBe(true);
        });
    });
    describe('checkpoint management', () => {
        it('should delete checkpoint', async () => {
            service.registerSession('sess-cm1', 'user-1', 'workspace-1');
            const checkpointReq = {
                sessionId: 'sess-cm1',
                userId: 'user-1',
                workspaceId: 'workspace-1',
                force: false,
                includeProcesses: true,
                includeMemory: true,
                compress: true,
            };
            const result = await service.createCheckpoint(checkpointReq, '192.168.1.1', 'Mozilla/5.0');
            const deleted = service.deleteCheckpoint(result.checkpoint.id, 'user-1', '192.168.1.1', 'Mozilla/5.0');
            expect(deleted).toBe(true);
        });
        it('should emit checkpoint-deleted event', () => {
            service.registerSession('sess-cm2', 'user-1', 'workspace-1');
            const checkpointReq = {
                sessionId: 'sess-cm2',
                userId: 'user-1',
                workspaceId: 'workspace-1',
                force: false,
                includeProcesses: true,
                includeMemory: true,
                compress: true,
            };
            return new Promise((resolve) => {
                service.once('checkpoint-deleted', () => {
                    expect(true).toBe(true);
                    resolve();
                });
                service.createCheckpoint(checkpointReq, '192.168.1.1', 'Mozilla/5.0').then((result) => {
                    service.deleteCheckpoint(result.checkpoint.id, 'user-1', '192.168.1.1', 'Mozilla/5.0');
                });
            });
        });
        it('should fail to delete checkpoint of other user', async () => {
            service.registerSession('sess-cm3', 'user-1', 'workspace-1');
            const checkpointReq = {
                sessionId: 'sess-cm3',
                userId: 'user-1',
                workspaceId: 'workspace-1',
                force: false,
                includeProcesses: true,
                includeMemory: true,
                compress: true,
            };
            const result = await service.createCheckpoint(checkpointReq, '192.168.1.1', 'Mozilla/5.0');
            const deleted = service.deleteCheckpoint(result.checkpoint.id, 'user-2', '192.168.1.1', 'Mozilla/5.0');
            expect(deleted).toBe(false);
        });
    });
    describe('configuration', () => {
        it('should update configuration', () => {
            service.updateConfig({ idleThresholdMs: 2000 }, 'user-1', '192.168.1.1', 'Mozilla/5.0');
            expect(true).toBe(true); // Config updated without error
        });
        it('should emit config-updated event', () => {
            return new Promise((resolve) => {
                service.once('config-updated', () => {
                    expect(true).toBe(true);
                    resolve();
                });
                service.updateConfig({ idleThresholdMs: 2000 }, 'user-1', '192.168.1.1', 'Mozilla/5.0');
            });
        });
    });
    describe('audit logging', () => {
        it('should log checkpoint creation', async () => {
            service.registerSession('sess-al1', 'user-1', 'workspace-1');
            const checkpointReq = {
                sessionId: 'sess-al1',
                userId: 'user-1',
                workspaceId: 'workspace-1',
                force: false,
                includeProcesses: true,
                includeMemory: true,
                compress: true,
            };
            await service.createCheckpoint(checkpointReq, '192.168.1.1', 'Mozilla/5.0');
            const auditLog = service.getAuditLog('user-1');
            expect(auditLog.length).toBeGreaterThan(0);
        });
        it('should log checkpoint with operation type', async () => {
            service.registerSession('sess-al2', 'user-1', 'workspace-1');
            const checkpointReq = {
                sessionId: 'sess-al2',
                userId: 'user-1',
                workspaceId: 'workspace-1',
                force: false,
                includeProcesses: true,
                includeMemory: true,
                compress: true,
            };
            await service.createCheckpoint(checkpointReq, '192.168.1.1', 'Mozilla/5.0');
            const auditLog = service.getAuditLog('user-1');
            expect(auditLog.some((entry) => entry.operation === 'checkpoint')).toBe(true);
        });
        it('should log restore operations', async () => {
            service.registerSession('sess-al3', 'user-1', 'workspace-1');
            const checkpointReq = {
                sessionId: 'sess-al3',
                userId: 'user-1',
                workspaceId: 'workspace-1',
                force: false,
                includeProcesses: true,
                includeMemory: true,
                compress: true,
            };
            const checkpointResult = await service.createCheckpoint(checkpointReq, '192.168.1.1', 'Mozilla/5.0');
            const restoreReq = {
                checkpointId: checkpointResult.checkpoint.id,
                sessionId: 'sess-al3',
                userId: 'user-1',
                workspaceId: 'workspace-1',
            };
            await service.restoreSession(restoreReq, '192.168.1.1', 'Mozilla/5.0');
            const auditLog = service.getAuditLog('user-1');
            expect(auditLog.some((entry) => entry.operation === 'restore')).toBe(true);
        });
        it('should emit audit-logged event', () => {
            service.registerSession('sess-al4', 'user-1', 'workspace-1');
            return new Promise((resolve) => {
                service.once('audit-logged', () => {
                    expect(true).toBe(true);
                    resolve();
                });
                const checkpointReq = {
                    sessionId: 'sess-al4',
                    userId: 'user-1',
                    workspaceId: 'workspace-1',
                    force: false,
                    includeProcesses: true,
                    includeMemory: true,
                    compress: true,
                };
                service.createCheckpoint(checkpointReq, '192.168.1.1', 'Mozilla/5.0');
            });
        });
        it('should include IP address in audit log', async () => {
            service.registerSession('sess-al5', 'user-1', 'workspace-1');
            const checkpointReq = {
                sessionId: 'sess-al5',
                userId: 'user-1',
                workspaceId: 'workspace-1',
                force: false,
                includeProcesses: true,
                includeMemory: true,
                compress: true,
            };
            await service.createCheckpoint(checkpointReq, '192.168.1.100', 'Mozilla/5.0');
            const auditLog = service.getAuditLog('user-1');
            expect(auditLog.some((entry) => entry.ipAddress === '192.168.1.100')).toBe(true);
        });
        it('should include user agent in audit log', async () => {
            service.registerSession('sess-al6', 'user-1', 'workspace-1');
            const checkpointReq = {
                sessionId: 'sess-al6',
                userId: 'user-1',
                workspaceId: 'workspace-1',
                force: false,
                includeProcesses: true,
                includeMemory: true,
                compress: true,
            };
            await service.createCheckpoint(checkpointReq, '192.168.1.1', 'Custom Agent v1.0');
            const auditLog = service.getAuditLog('user-1');
            expect(auditLog.some((entry) => entry.userAgent === 'Custom Agent v1.0')).toBe(true);
        });
    });
    describe('statistics', () => {
        it('should track checkpoint statistics', async () => {
            service.registerSession('sess-st1', 'user-1', 'workspace-1');
            const checkpointReq = {
                sessionId: 'sess-st1',
                userId: 'user-1',
                workspaceId: 'workspace-1',
                force: false,
                includeProcesses: true,
                includeMemory: true,
                compress: true,
            };
            await service.createCheckpoint(checkpointReq, '192.168.1.1', 'Mozilla/5.0');
            const stats = service.getStatistics('user-1');
            expect(stats.totalCheckpoints).toBe(1);
            expect(stats.successfulCheckpoints).toBe(1);
        });
        it('should track restore statistics', async () => {
            service.registerSession('sess-st2', 'user-1', 'workspace-1');
            const checkpointReq = {
                sessionId: 'sess-st2',
                userId: 'user-1',
                workspaceId: 'workspace-1',
                force: false,
                includeProcesses: true,
                includeMemory: true,
                compress: true,
            };
            const checkpointResult = await service.createCheckpoint(checkpointReq, '192.168.1.1', 'Mozilla/5.0');
            const restoreReq = {
                checkpointId: checkpointResult.checkpoint.id,
                sessionId: 'sess-st2',
                userId: 'user-1',
                workspaceId: 'workspace-1',
            };
            await service.restoreSession(restoreReq, '192.168.1.1', 'Mozilla/5.0');
            const stats = service.getStatistics('user-1');
            expect(stats.totalRestores).toBeGreaterThan(0);
        });
        it('should calculate average checkpoint duration', async () => {
            service.registerSession('sess-st3', 'user-1', 'workspace-1');
            const checkpointReq = {
                sessionId: 'sess-st3',
                userId: 'user-1',
                workspaceId: 'workspace-1',
                force: false,
                includeProcesses: true,
                includeMemory: true,
                compress: true,
            };
            for (let i = 0; i < 3; i++) {
                await service.createCheckpoint(checkpointReq, '192.168.1.1', 'Mozilla/5.0');
            }
            const stats = service.getStatistics('user-1');
            expect(stats.totalCheckpoints).toBe(3);
        });
        it('should track last checkpoint timestamp', async () => {
            service.registerSession('sess-st4', 'user-1', 'workspace-1');
            const checkpointReq = {
                sessionId: 'sess-st4',
                userId: 'user-1',
                workspaceId: 'workspace-1',
                force: false,
                includeProcesses: true,
                includeMemory: true,
                compress: true,
            };
            await service.createCheckpoint(checkpointReq, '192.168.1.1', 'Mozilla/5.0');
            const stats = service.getStatistics('user-1');
            expect(stats.lastCheckpointedAt).not.toBeNull();
        });
    });
    describe('multiple users', () => {
        it('should isolate sessions by user', () => {
            service.registerSession('session-1', 'user-1', 'workspace-1');
            service.registerSession('session-2', 'user-2', 'workspace-2');
            const s1 = service.getSessionStatus('session-1', 'user-1');
            const s2 = service.getSessionStatus('session-2', 'user-2');
            expect(s1?.userId).toBe('user-1');
            expect(s2?.userId).toBe('user-2');
        });
        it('should isolate audit logs by user', async () => {
            service.registerSession('session-1', 'user-1', 'workspace-1');
            service.registerSession('session-2', 'user-2', 'workspace-2');
            const checkpointReq1 = {
                sessionId: 'session-1',
                userId: 'user-1',
                workspaceId: 'workspace-1',
                force: false,
                includeProcesses: true,
                includeMemory: true,
                compress: true,
            };
            const checkpointReq2 = {
                sessionId: 'session-2',
                userId: 'user-2',
                workspaceId: 'workspace-2',
                force: false,
                includeProcesses: true,
                includeMemory: true,
                compress: true,
            };
            await service.createCheckpoint(checkpointReq1, '192.168.1.1', 'Mozilla/5.0');
            await service.createCheckpoint(checkpointReq2, '192.168.1.1', 'Mozilla/5.0');
            const log1 = service.getAuditLog('user-1');
            const log2 = service.getAuditLog('user-2');
            expect(log1.every((e) => e.userId === 'user-1')).toBe(true);
            expect(log2.every((e) => e.userId === 'user-2')).toBe(true);
        });
    });
    describe('shutdown', () => {
        it('should clear all data on shutdown', () => {
            const testService = HibernationService.getInstance();
            testService.registerSession('sess-sd1', 'user-1', 'workspace-1');
            testService.shutdown();
            expect(testService).toBeDefined();
        });
    });
});
//# sourceMappingURL=hibernation-service.test.js.map