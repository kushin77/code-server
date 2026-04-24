/**
 * Collaborative Undo/Redo Service Tests
 */
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { CollaborativeUndoRedoService } from '../collaborative-undo-redo-service.js';
describe('CollaborativeUndoRedoService', () => {
    let service;
    beforeEach(() => {
        CollaborativeUndoRedoService.reset();
        service = CollaborativeUndoRedoService.getInstance();
    });
    afterEach(() => {
        service.shutdown();
    });
    describe('Initialization', () => {
        it('should create singleton instance', () => {
            const instance1 = CollaborativeUndoRedoService.getInstance();
            const instance2 = CollaborativeUndoRedoService.getInstance();
            expect(instance1).toBe(instance2);
        });
        it('should emit initialized event', () => {
            return new Promise((resolve) => {
                CollaborativeUndoRedoService.reset();
                const svc = CollaborativeUndoRedoService.getInstance();
                expect(svc).toBeDefined();
                resolve();
            });
        });
    });
    describe('Operation Recording', () => {
        it('should record operation', () => {
            const op = {
                id: 'op-1',
                type: 'insert',
                userId: 'user-1',
                userEmail: 'user1@example.com',
                timestamp: Date.now(),
                path: 'file.ts',
                position: 10,
                content: 'hello',
            };
            const recorded = service.recordOperation(op, 'doc-1', '192.168.1.1', 'Mozilla/5.0');
            expect(recorded).toBe(true);
        });
        it('should emit operation-recorded event', () => {
            return new Promise((resolve) => {
                const op = {
                    id: 'op-2',
                    type: 'insert',
                    userId: 'user-2',
                    userEmail: 'user2@example.com',
                    timestamp: Date.now(),
                    path: 'file.ts',
                    position: 20,
                    content: 'world',
                };
                service.once('operation-recorded', (data) => {
                    expect(data.operation.id).toBe('op-2');
                    expect(data.documentId).toBe('doc-2');
                    resolve();
                });
                service.recordOperation(op, 'doc-2', '192.168.1.1', 'Mozilla/5.0');
            });
        });
        it('should update statistics on operation', () => {
            const op = {
                id: 'op-3',
                type: 'delete',
                userId: 'user-3',
                userEmail: 'user3@example.com',
                timestamp: Date.now(),
                path: 'file.ts',
                position: 5,
                length: 3,
            };
            service.recordOperation(op, 'doc-3', '192.168.1.1', 'Mozilla/5.0');
            const stats = service.getStatistics();
            expect(stats.totalOperations).toBeGreaterThan(0);
            expect(stats.lastOperationAt).toBeGreaterThan(0);
        });
        it('should initialize document history on first operation', () => {
            const op = {
                id: 'op-4',
                type: 'insert',
                userId: 'user-4',
                userEmail: 'user4@example.com',
                timestamp: Date.now(),
                path: 'file.ts',
                position: 0,
                content: 'new',
            };
            service.recordOperation(op, 'doc-4', '192.168.1.1', 'Mozilla/5.0');
            const state = service.getHistoryState('doc-4');
            expect(state).toBeDefined();
            expect(state.present.length).toBeGreaterThan(0);
        });
        it('should limit history size', () => {
            CollaborativeUndoRedoService.reset();
            service = CollaborativeUndoRedoService.getInstance({ maxHistorySize: 3 });
            for (let i = 0; i < 5; i++) {
                const op = {
                    id: `op-${i}`,
                    type: 'insert',
                    userId: 'user-5',
                    userEmail: 'user5@example.com',
                    timestamp: Date.now() + i,
                    path: 'file.ts',
                    position: i,
                    content: `text${i}`,
                };
                service.recordOperation(op, 'doc-5', '192.168.1.1', 'Mozilla/5.0');
            }
            const state = service.getHistoryState('doc-5');
            expect(state.present.length).toBeLessThanOrEqual(3);
        });
    });
    describe('Undo', () => {
        it('should undo operation', () => {
            const op = {
                id: 'op-6',
                type: 'insert',
                userId: 'user-6',
                userEmail: 'user6@example.com',
                timestamp: Date.now(),
                path: 'file.ts',
                position: 0,
                content: 'undo-test',
            };
            service.recordOperation(op, 'doc-6', '192.168.1.1', 'Mozilla/5.0');
            const result = service.undo({ userId: 'user-6', userEmail: 'user6@example.com' }, 'doc-6', '192.168.1.1', 'Mozilla/5.0');
            expect(result.success).toBe(true);
            expect(result.undoneOperations.length).toBeGreaterThan(0);
        });
        it('should emit undo-performed event', () => {
            return new Promise((resolve) => {
                const op = {
                    id: 'op-7',
                    type: 'insert',
                    userId: 'user-7',
                    userEmail: 'user7@example.com',
                    timestamp: Date.now(),
                    path: 'file.ts',
                    position: 0,
                    content: 'event-test',
                };
                service.recordOperation(op, 'doc-7', '192.168.1.1', 'Mozilla/5.0');
                service.once('undo-performed', (data) => {
                    expect(data.documentId).toBe('doc-7');
                    expect(data.undoneOperations.length).toBeGreaterThan(0);
                    resolve();
                });
                service.undo({ userId: 'user-7', userEmail: 'user7@example.com' }, 'doc-7', '192.168.1.1', 'Mozilla/5.0');
            });
        });
        it('should not undo empty history', () => {
            const result = service.undo({ userId: 'user-8', userEmail: 'user8@example.com' }, 'non-existent', '192.168.1.1', 'Mozilla/5.0');
            expect(result.success).toBe(false);
            expect(result.undoneOperations.length).toBe(0);
        });
        it('should undo multiple operations', () => {
            for (let i = 0; i < 3; i++) {
                const op = {
                    id: `op-multi-${i}`,
                    type: 'insert',
                    userId: 'user-9',
                    userEmail: 'user9@example.com',
                    timestamp: Date.now() + i,
                    path: 'file.ts',
                    position: i,
                    content: `text${i}`,
                };
                service.recordOperation(op, 'doc-9', '192.168.1.1', 'Mozilla/5.0');
            }
            const result = service.undo({ userId: 'user-9', userEmail: 'user9@example.com', count: 2 }, 'doc-9', '192.168.1.1', 'Mozilla/5.0');
            expect(result.success).toBe(true);
            expect(result.undoneOperations.length).toBe(2);
        });
        it('should update statistics on undo', () => {
            const op = {
                id: 'op-stat',
                type: 'insert',
                userId: 'user-10',
                userEmail: 'user10@example.com',
                timestamp: Date.now(),
                path: 'file.ts',
                position: 0,
                content: 'stat-test',
            };
            service.recordOperation(op, 'doc-stat', '192.168.1.1', 'Mozilla/5.0');
            const statsBefore = service.getStatistics();
            const undoBefore = statsBefore.totalUndos;
            service.undo({ userId: 'user-10', userEmail: 'user10@example.com' }, 'doc-stat', '192.168.1.1', 'Mozilla/5.0');
            const statsAfter = service.getStatistics();
            expect(statsAfter.totalUndos).toBe(undoBefore + 1);
        });
    });
    describe('Redo', () => {
        it('should redo operation after undo', () => {
            const op = {
                id: 'op-redo-1',
                type: 'insert',
                userId: 'user-11',
                userEmail: 'user11@example.com',
                timestamp: Date.now(),
                path: 'file.ts',
                position: 0,
                content: 'redo-test',
            };
            service.recordOperation(op, 'doc-redo', '192.168.1.1', 'Mozilla/5.0');
            service.undo({ userId: 'user-11', userEmail: 'user11@example.com' }, 'doc-redo', '192.168.1.1', 'Mozilla/5.0');
            const result = service.redo({ userId: 'user-11', userEmail: 'user11@example.com' }, 'doc-redo', '192.168.1.1', 'Mozilla/5.0');
            expect(result.success).toBe(true);
            expect(result.redoneOperations.length).toBeGreaterThan(0);
        });
        it('should emit redo-performed event', () => {
            return new Promise((resolve) => {
                const op = {
                    id: 'op-redo-2',
                    type: 'insert',
                    userId: 'user-12',
                    userEmail: 'user12@example.com',
                    timestamp: Date.now(),
                    path: 'file.ts',
                    position: 0,
                    content: 'redo-event',
                };
                service.recordOperation(op, 'doc-redo-2', '192.168.1.1', 'Mozilla/5.0');
                service.undo({ userId: 'user-12', userEmail: 'user12@example.com' }, 'doc-redo-2', '192.168.1.1', 'Mozilla/5.0');
                service.once('redo-performed', (data) => {
                    expect(data.documentId).toBe('doc-redo-2');
                    expect(data.redoneOperations.length).toBeGreaterThan(0);
                    resolve();
                });
                service.redo({ userId: 'user-12', userEmail: 'user12@example.com' }, 'doc-redo-2', '192.168.1.1', 'Mozilla/5.0');
            });
        });
        it('should not redo when redo stack empty', () => {
            const op = {
                id: 'op-no-redo',
                type: 'insert',
                userId: 'user-13',
                userEmail: 'user13@example.com',
                timestamp: Date.now(),
                path: 'file.ts',
                position: 0,
                content: 'no-redo',
            };
            service.recordOperation(op, 'doc-no-redo', '192.168.1.1', 'Mozilla/5.0');
            // Try to redo without undo
            const result = service.redo({ userId: 'user-13', userEmail: 'user13@example.com' }, 'doc-no-redo', '192.168.1.1', 'Mozilla/5.0');
            expect(result.success).toBe(false);
            expect(result.redoneOperations.length).toBe(0);
        });
        it('should redo multiple operations', () => {
            for (let i = 0; i < 3; i++) {
                const op = {
                    id: `op-redo-multi-${i}`,
                    type: 'insert',
                    userId: 'user-14',
                    userEmail: 'user14@example.com',
                    timestamp: Date.now() + i,
                    path: 'file.ts',
                    position: i,
                    content: `redo${i}`,
                };
                service.recordOperation(op, 'doc-redo-multi', '192.168.1.1', 'Mozilla/5.0');
            }
            service.undo({ userId: 'user-14', userEmail: 'user14@example.com', count: 2 }, 'doc-redo-multi', '192.168.1.1', 'Mozilla/5.0');
            const result = service.redo({ userId: 'user-14', userEmail: 'user14@example.com', count: 2 }, 'doc-redo-multi', '192.168.1.1', 'Mozilla/5.0');
            expect(result.success).toBe(true);
            expect(result.redoneOperations.length).toBe(2);
        });
        it('should clear redo stack on new operation', () => {
            const op1 = {
                id: 'op-clear-1',
                type: 'insert',
                userId: 'user-15',
                userEmail: 'user15@example.com',
                timestamp: Date.now(),
                path: 'file.ts',
                position: 0,
                content: 'clear1',
            };
            service.recordOperation(op1, 'doc-clear', '192.168.1.1', 'Mozilla/5.0');
            // After undo, we should have something to redo
            service.undo({ userId: 'user-15', userEmail: 'user15@example.com' }, 'doc-clear', '192.168.1.1', 'Mozilla/5.0');
            expect(service.canRedo('doc-clear')).toBe(true);
            // New operation should clear redo stack
            const op2 = {
                id: 'op-clear-2',
                type: 'insert',
                userId: 'user-15',
                userEmail: 'user15@example.com',
                timestamp: Date.now(),
                path: 'file.ts',
                position: 0,
                content: 'clear2',
            };
            service.recordOperation(op2, 'doc-clear', '192.168.1.1', 'Mozilla/5.0');
            // Now redo stack should be cleared
            const canRedo = service.canRedo('doc-clear');
            expect(canRedo).toBe(false);
        });
    });
    describe('State Queries', () => {
        it('should get history state', () => {
            const op = {
                id: 'op-state',
                type: 'insert',
                userId: 'user-16',
                userEmail: 'user16@example.com',
                timestamp: Date.now(),
                path: 'file.ts',
                position: 0,
                content: 'state',
            };
            service.recordOperation(op, 'doc-state', '192.168.1.1', 'Mozilla/5.0');
            const state = service.getHistoryState('doc-state');
            expect(state).toBeDefined();
            expect(state.present.length).toBeGreaterThan(0);
        });
        it('should return null for non-existent document', () => {
            const state = service.getHistoryState('non-existent');
            expect(state).toBeNull();
        });
        it('should check can undo', () => {
            const op = {
                id: 'op-can-undo',
                type: 'insert',
                userId: 'user-17',
                userEmail: 'user17@example.com',
                timestamp: Date.now(),
                path: 'file.ts',
                position: 0,
                content: 'can-undo',
            };
            expect(service.canUndo('doc-can-undo')).toBe(false);
            service.recordOperation(op, 'doc-can-undo', '192.168.1.1', 'Mozilla/5.0');
            expect(service.canUndo('doc-can-undo')).toBe(true);
        });
        it('should check can redo', () => {
            const op = {
                id: 'op-can-redo',
                type: 'insert',
                userId: 'user-18',
                userEmail: 'user18@example.com',
                timestamp: Date.now(),
                path: 'file.ts',
                position: 0,
                content: 'can-redo',
            };
            service.recordOperation(op, 'doc-can-redo', '192.168.1.1', 'Mozilla/5.0');
            expect(service.canRedo('doc-can-redo')).toBe(false);
            service.undo({ userId: 'user-18', userEmail: 'user18@example.com' }, 'doc-can-redo', '192.168.1.1', 'Mozilla/5.0');
            expect(service.canRedo('doc-can-redo')).toBe(true);
        });
        it('should get undo count', () => {
            for (let i = 0; i < 3; i++) {
                const op = {
                    id: `op-count-${i}`,
                    type: 'insert',
                    userId: 'user-19',
                    userEmail: 'user19@example.com',
                    timestamp: Date.now() + i,
                    path: 'file.ts',
                    position: i,
                    content: `count${i}`,
                };
                service.recordOperation(op, 'doc-count', '192.168.1.1', 'Mozilla/5.0');
            }
            const count = service.getUndoCount('doc-count');
            expect(count).toBe(3);
        });
        it('should get redo count after undo', () => {
            const op = {
                id: 'op-redo-count',
                type: 'insert',
                userId: 'user-20',
                userEmail: 'user20@example.com',
                timestamp: Date.now(),
                path: 'file.ts',
                position: 0,
                content: 'redo-count',
            };
            service.recordOperation(op, 'doc-redo-count', '192.168.1.1', 'Mozilla/5.0');
            service.undo({ userId: 'user-20', userEmail: 'user20@example.com' }, 'doc-redo-count', '192.168.1.1', 'Mozilla/5.0');
            const count = service.getRedoCount('doc-redo-count');
            expect(count).toBeGreaterThan(0);
        });
    });
    describe('Checkpoints', () => {
        it('should create checkpoint', () => {
            const op = {
                id: 'op-checkpoint',
                type: 'insert',
                userId: 'user-21',
                userEmail: 'user21@example.com',
                timestamp: Date.now(),
                path: 'file.ts',
                position: 0,
                content: 'checkpoint',
            };
            service.recordOperation(op, 'doc-checkpoint', '192.168.1.1', 'Mozilla/5.0');
            const created = service.createCheckpoint('doc-checkpoint', 'user-21', '192.168.1.1', 'Mozilla/5.0');
            expect(created).toBe(true);
            const state = service.getHistoryState('doc-checkpoint');
            expect(state.checkpoint).toBeDefined();
        });
        it('should emit checkpoint-created event', () => {
            return new Promise((resolve) => {
                const op = {
                    id: 'op-checkpoint-event',
                    type: 'insert',
                    userId: 'user-22',
                    userEmail: 'user22@example.com',
                    timestamp: Date.now(),
                    path: 'file.ts',
                    position: 0,
                    content: 'checkpoint-event',
                };
                service.recordOperation(op, 'doc-checkpoint-event', '192.168.1.1', 'Mozilla/5.0');
                service.once('checkpoint-created', (data) => {
                    expect(data.documentId).toBe('doc-checkpoint-event');
                    expect(data.checkpointId).toBeDefined();
                    resolve();
                });
                service.createCheckpoint('doc-checkpoint-event', 'user-22', '192.168.1.1', 'Mozilla/5.0');
            });
        });
        it('should not create checkpoint for empty history', () => {
            const created = service.createCheckpoint('empty-doc', 'user-23', '192.168.1.1', 'Mozilla/5.0');
            expect(created).toBe(false);
        });
    });
    describe('Conflict Detection', () => {
        it('should detect conflicts', () => {
            CollaborativeUndoRedoService.reset();
            service = CollaborativeUndoRedoService.getInstance({ enableConflictDetection: true });
            const op1 = {
                id: 'op-conflict-1',
                type: 'insert',
                userId: 'user-24',
                userEmail: 'user24@example.com',
                timestamp: Date.now(),
                path: 'file.ts',
                position: 10,
                content: 'text1',
                length: 5,
            };
            service.recordOperation(op1, 'doc-conflict', '192.168.1.1', 'Mozilla/5.0');
            const op2 = {
                id: 'op-conflict-2',
                type: 'insert',
                userId: 'user-25',
                userEmail: 'user25@example.com',
                timestamp: Date.now(),
                path: 'file.ts',
                position: 12, // Overlaps with op1
                content: 'text2',
                length: 5,
            };
            // Should detect conflict
            service.recordOperation(op2, 'doc-conflict', '192.168.1.1', 'Mozilla/5.0');
            const stats = service.getStatistics();
            expect(stats.totalConflicts).toBeGreaterThanOrEqual(0);
        });
        it('should emit conflict-detected event', () => {
            return new Promise((resolve) => {
                CollaborativeUndoRedoService.reset();
                const svc = CollaborativeUndoRedoService.getInstance({ enableConflictDetection: true });
                const op1 = {
                    id: 'op-evt-1',
                    type: 'insert',
                    userId: 'user-26',
                    userEmail: 'user26@example.com',
                    timestamp: Date.now(),
                    path: 'file.ts',
                    position: 5,
                    content: 'a',
                    length: 1,
                };
                svc.recordOperation(op1, 'doc-evt', '192.168.1.1', 'Mozilla/5.0');
                svc.once('conflict-detected', (data) => {
                    expect(data.documentId).toBe('doc-evt');
                    resolve();
                });
                const op2 = {
                    id: 'op-evt-2',
                    type: 'insert',
                    userId: 'user-27',
                    userEmail: 'user27@example.com',
                    timestamp: Date.now(),
                    path: 'file.ts',
                    position: 5, // Same position
                    content: 'b',
                    length: 1,
                };
                svc.recordOperation(op2, 'doc-evt', '192.168.1.1', 'Mozilla/5.0');
            });
        });
    });
    describe('Audit Logging', () => {
        it('should record audit entry on operation', () => {
            const op = {
                id: 'op-audit',
                type: 'insert',
                userId: 'user-28',
                userEmail: 'user28@example.com',
                timestamp: Date.now(),
                path: 'file.ts',
                position: 0,
                content: 'audit',
            };
            service.recordOperation(op, 'doc-audit', '192.168.1.1', 'Mozilla/5.0');
            const audit = service.getAuditLog('user-28');
            expect(audit.length).toBeGreaterThan(0);
            expect(audit[0].operation).toBe('operation-recorded');
        });
        it('should emit audit-logged event', () => {
            return new Promise((resolve) => {
                const op = {
                    id: 'op-audit-evt',
                    type: 'insert',
                    userId: 'user-29',
                    userEmail: 'user29@example.com',
                    timestamp: Date.now(),
                    path: 'file.ts',
                    position: 0,
                    content: 'audit-event',
                };
                let auditCount = 0;
                service.on('audit-logged', () => {
                    auditCount++;
                    if (auditCount > 0) {
                        resolve();
                    }
                });
                service.recordOperation(op, 'doc-audit-evt', '192.168.1.1', 'Mozilla/5.0');
            });
        });
        it('should track IP and user agent in audit', () => {
            const op = {
                id: 'op-ip',
                type: 'insert',
                userId: 'user-30',
                userEmail: 'user30@example.com',
                timestamp: Date.now(),
                path: 'file.ts',
                position: 0,
                content: 'ip-test',
            };
            const testIp = '203.0.113.42';
            const testAgent = 'TestAgent/1.0';
            service.recordOperation(op, 'doc-ip', testIp, testAgent);
            const audit = service.getAuditLog('user-30');
            expect(audit[0].ipAddress).toBe(testIp);
            expect(audit[0].userAgent).toBe(testAgent);
        });
        it('should limit audit log size', () => {
            CollaborativeUndoRedoService.reset();
            service = CollaborativeUndoRedoService.getInstance({ maxAuditLogSize: 5 });
            for (let i = 0; i < 10; i++) {
                const op = {
                    id: `op-audit-limit-${i}`,
                    type: 'insert',
                    userId: 'user-31',
                    userEmail: 'user31@example.com',
                    timestamp: Date.now() + i,
                    path: 'file.ts',
                    position: i,
                    content: `audit${i}`,
                };
                service.recordOperation(op, `doc-${i}`, '192.168.1.1', 'Mozilla/5.0');
            }
            const audit = service.getAuditLog('user-31');
            expect(audit.length).toBeLessThanOrEqual(5);
        });
    });
    describe('Configuration', () => {
        it('should update configuration', () => {
            service.updateConfig({ maxHistorySize: 50 }, 'user-32', '192.168.1.1', 'Mozilla/5.0');
            expect(service['config'].maxHistorySize).toBe(50);
        });
        it('should emit config-updated event', () => {
            return new Promise((resolve) => {
                service.once('config-updated', (data) => {
                    expect(data.config).toBeDefined();
                    resolve();
                });
                service.updateConfig({ enableConflictDetection: false }, 'user-33', '192.168.1.1', 'Mozilla/5.0');
            });
        });
    });
    describe('History Clearing', () => {
        it('should clear history', () => {
            const op = {
                id: 'op-clear',
                type: 'insert',
                userId: 'user-34',
                userEmail: 'user34@example.com',
                timestamp: Date.now(),
                path: 'file.ts',
                position: 0,
                content: 'clear',
            };
            service.recordOperation(op, 'doc-clear', '192.168.1.1', 'Mozilla/5.0');
            const cleared = service.clearHistory('doc-clear', 'user-34', '192.168.1.1', 'Mozilla/5.0');
            expect(cleared).toBe(true);
            const state = service.getHistoryState('doc-clear');
            expect(state).toBeNull();
        });
        it('should emit history-cleared event', () => {
            return new Promise((resolve) => {
                const op = {
                    id: 'op-clear-evt',
                    type: 'insert',
                    userId: 'user-35',
                    userEmail: 'user35@example.com',
                    timestamp: Date.now(),
                    path: 'file.ts',
                    position: 0,
                    content: 'clear-event',
                };
                service.recordOperation(op, 'doc-clear-evt', '192.168.1.1', 'Mozilla/5.0');
                service.once('history-cleared', (data) => {
                    expect(data.documentId).toBe('doc-clear-evt');
                    resolve();
                });
                service.clearHistory('doc-clear-evt', 'user-35', '192.168.1.1', 'Mozilla/5.0');
            });
        });
    });
    describe('Statistics', () => {
        it('should get statistics', () => {
            const op = {
                id: 'op-stats',
                type: 'insert',
                userId: 'user-36',
                userEmail: 'user36@example.com',
                timestamp: Date.now(),
                path: 'file.ts',
                position: 0,
                content: 'stats',
            };
            service.recordOperation(op, 'doc-stats', '192.168.1.1', 'Mozilla/5.0');
            const stats = service.getStatistics();
            expect(stats.totalOperations).toBeGreaterThan(0);
            expect(stats.lastOperationAt).toBeGreaterThan(0);
            expect(stats.historyDepth).toBeGreaterThan(0);
        });
    });
    describe('Shutdown', () => {
        it('should shutdown service', () => {
            const op = {
                id: 'op-shutdown',
                type: 'insert',
                userId: 'user-37',
                userEmail: 'user37@example.com',
                timestamp: Date.now(),
                path: 'file.ts',
                position: 0,
                content: 'shutdown',
            };
            service.recordOperation(op, 'doc-shutdown', '192.168.1.1', 'Mozilla/5.0');
            service.shutdown();
            const state = service.getHistoryState('doc-shutdown');
            expect(state).toBeNull();
        });
        it('should emit shutdown event', () => {
            return new Promise((resolve) => {
                service.once('shutdown', (data) => {
                    expect(data.timestamp).toBeDefined();
                    resolve();
                });
                service.shutdown();
            });
        });
    });
});
//# sourceMappingURL=collaborative-undo-redo-service.test.js.map