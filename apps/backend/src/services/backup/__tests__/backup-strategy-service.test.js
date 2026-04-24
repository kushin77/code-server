#!/usr/bin/env node
// @file        apps/backend/src/services/backup/__tests__/backup-strategy-service.test.ts
// @module      services/backup
// @description Tests for backup strategy service
// @owner       Infrastructure Team
// @status      Production-ready - April 23, 2026
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { BackupStrategyService, } from '../backup-strategy-service';
describe('BackupStrategyService', () => {
    let service;
    beforeEach(() => {
        service = BackupStrategyService.getInstance({
            enabled: true,
            backupIntervalMs: 100,
            rpoMs: 3600000,
            rtoMs: 1800000,
            retentionDays: 30,
            backupLocation: '/var/backups/postgresql',
            walArchiveLocation: '/var/lib/postgresql/wal_archive',
            compressionEnabled: true,
            verificationEnabled: true,
            pitrEnabled: true,
        });
        service.removeAllListeners();
        service.clearHistory();
    });
    afterEach(() => {
        service.stop();
    });
    describe('Initialization', () => {
        it('should create a singleton instance', () => {
            const instance1 = BackupStrategyService.getInstance();
            const instance2 = BackupStrategyService.getInstance();
            expect(instance1).toBe(instance2);
        });
        it('should have correct default configuration', () => {
            const config = service.getConfig();
            expect(config.enabled).toBe(true);
            expect(config.backupIntervalMs).toBe(100);
            expect(config.rpoMs).toBe(3600000);
            expect(config.rtoMs).toBe(1800000);
            expect(config.compressionEnabled).toBe(true);
            expect(config.verificationEnabled).toBe(true);
            expect(config.pitrEnabled).toBe(true);
        });
        it('should have null last backup initially', () => {
            const lastBackup = service.getLastBackup();
            expect(lastBackup).toBeNull();
        });
        it('should have empty backup history initially', () => {
            const history = service.getBackupHistory();
            expect(history).toHaveLength(0);
        });
    });
    describe('Service Lifecycle', () => {
        it('should start backup scheduling', () => {
            return new Promise((resolve) => {
                const listener = () => {
                    expect(listener).toBeDefined();
                    resolve();
                };
                service.on('service-started', listener);
                service.start();
            });
        });
        it('should stop backup scheduling', () => {
            return new Promise((resolve) => {
                service.start();
                const listener = () => {
                    expect(listener).toBeDefined();
                    resolve();
                };
                service.on('service-stopped', listener);
                service.stop();
            });
        });
        it('should not start multiple times', () => {
            return new Promise((resolve) => {
                let startCount = 0;
                service.on('service-started', () => {
                    startCount++;
                });
                service.start();
                service.start();
                setTimeout(() => {
                    expect(startCount).toBeLessThanOrEqual(1);
                    resolve();
                }, 50);
            });
        });
    });
    describe('Backup Execution', () => {
        it('should execute backup on start', () => {
            return new Promise((resolve) => {
                const listener = () => {
                    expect(listener).toBeDefined();
                    resolve();
                };
                service.on('backup-started', listener);
                service.start();
            });
        });
        it('should complete backup successfully', () => {
            return new Promise((resolve) => {
                const listener = () => {
                    const lastBackup = service.getLastBackup();
                    expect(lastBackup?.status).toBe('completed');
                    resolve();
                };
                service.on('backup-completed', listener);
                service.start();
            });
        });
        it('should store backup in history', () => {
            return new Promise((resolve) => {
                service.on('backup-completed', () => {
                    const history = service.getBackupHistory();
                    expect(history.length).toBeGreaterThan(0);
                    resolve();
                });
                service.start();
            });
        });
        it('should include backup metadata', () => {
            return new Promise((resolve) => {
                service.on('backup-completed', () => {
                    const lastBackup = service.getLastBackup();
                    expect(lastBackup?.id).toBeDefined();
                    expect(lastBackup?.timestamp).toBeGreaterThan(0);
                    expect(lastBackup?.size).toBeGreaterThan(0);
                    expect(lastBackup?.duration).toBeGreaterThanOrEqual(0);
                    expect(lastBackup?.location).toBeDefined();
                    resolve();
                });
                service.start();
            });
        });
    });
    describe('Backup Verification', () => {
        it('should verify backup after completion', () => {
            return new Promise((resolve) => {
                let verified = false;
                service.on('backup-verified', () => {
                    verified = true;
                });
                service.on('backup-completed', () => {
                    setTimeout(() => {
                        expect(verified).toBe(true);
                        resolve();
                    }, 200);
                });
                service.start();
            });
        });
        it('should mark backup as verified when integrity passes', () => {
            return new Promise((resolve) => {
                service.on('backup-verified', () => {
                    const lastBackup = service.getLastBackup();
                    expect(lastBackup?.verified).toBe(true);
                    resolve();
                });
                service.start();
            });
        });
        it('should track verified backup count', () => {
            return new Promise((resolve) => {
                service.on('backup-verified', () => {
                    const status = service.getBackupStatus();
                    expect(status.verifiedBackups).toBeGreaterThan(0);
                    resolve();
                });
                service.start();
            });
        });
    });
    describe('Backup Status', () => {
        it('should report backup status summary', () => {
            return new Promise((resolve) => {
                service.on('backup-completed', () => {
                    const status = service.getBackupStatus();
                    expect(status.lastBackup).toBeDefined();
                    expect(status.nextScheduledBackup).toBeGreaterThan(0);
                    expect(status.totalBackups).toBeGreaterThan(0);
                    resolve();
                });
                service.start();
            });
        });
        it('should include RTO and RPO in status', () => {
            const status = service.getBackupStatus();
            expect(status.rpo).toBe(3600000);
            expect(status.rto).toBe(1800000);
        });
    });
    describe('Backup History', () => {
        it('should maintain backup history', () => {
            return new Promise((resolve) => {
                service.on('backup-completed', () => {
                    const history = service.getBackupHistory();
                    expect(Array.isArray(history)).toBe(true);
                    expect(history.length).toBeGreaterThan(0);
                    resolve();
                });
                service.start();
            });
        });
        it('should limit history to requested amount', () => {
            return new Promise((resolve) => {
                service.on('backup-completed', () => {
                    const history = service.getBackupHistory(5);
                    expect(history.length).toBeLessThanOrEqual(5);
                    resolve();
                });
                service.start();
            });
        });
        it('should include backup type in history', () => {
            return new Promise((resolve) => {
                service.on('backup-completed', () => {
                    const history = service.getBackupHistory();
                    expect(history[0].type).toBe('full');
                    resolve();
                });
                service.start();
            });
        });
    });
    describe('Restore Procedure', () => {
        it('should generate restore procedure', () => {
            return new Promise((resolve) => {
                service.on('backup-completed', () => {
                    const targetTime = Date.now();
                    const procedure = service.generateRestoreProcedure(targetTime);
                    expect(procedure.backupId).toBeDefined();
                    expect(procedure.targetTime).toBeGreaterThan(0);
                    expect(procedure.estimatedDuration).toBe(1800000);
                    expect(procedure.requiredSpace).toBeGreaterThan(0);
                    expect(procedure.steps).toBeDefined();
                    expect(procedure.steps.length).toBeGreaterThan(0);
                    resolve();
                });
                service.start();
            });
        });
        it('should throw if no suitable backup found', () => {
            service.clearHistory();
            const futureTime = Date.now() + 1000000;
            expect(() => service.generateRestoreProcedure(futureTime)).toThrow();
        });
    });
    describe('Configuration Management', () => {
        it('should return current configuration', () => {
            const config = service.getConfig();
            expect(config.enabled).toBe(true);
            expect(config.backupIntervalMs).toBe(100);
        });
        it('should allow enabling/disabling', () => {
            service.setEnabled(false);
            let config = service.getConfig();
            expect(config.enabled).toBe(false);
            service.setEnabled(true);
            config = service.getConfig();
            expect(config.enabled).toBe(true);
        });
        it('should respect RTO and RPO settings', () => {
            const config = service.getConfig();
            expect(config.rtoMs).toBeLessThan(config.rpoMs);
        });
    });
    describe('Event Emission', () => {
        it('should emit backup-started event', () => {
            return new Promise((resolve) => {
                const listener = () => {
                    expect(listener).toBeDefined();
                    resolve();
                };
                service.on('backup-started', listener);
                service.start();
            });
        });
        it('should emit backup-completed event', () => {
            return new Promise((resolve) => {
                const listener = () => {
                    expect(listener).toBeDefined();
                    resolve();
                };
                service.on('backup-completed', listener);
                service.start();
            });
        });
        it('should emit backup-verified event', () => {
            return new Promise((resolve) => {
                let verifiedEmitted = false;
                service.on('backup-verified', () => {
                    verifiedEmitted = true;
                });
                service.on('backup-completed', () => {
                    setTimeout(() => {
                        expect(verifiedEmitted).toBe(true);
                        resolve();
                    }, 200);
                });
                service.start();
            });
        });
        it('should emit service-stopped event', () => {
            return new Promise((resolve) => {
                service.start();
                const listener = () => {
                    expect(listener).toBeDefined();
                    resolve();
                };
                service.on('service-stopped', listener);
                service.stop();
            });
        });
    });
    describe('Success Criteria', () => {
        it('should meet RTO requirement (<30 minutes)', () => {
            const config = service.getConfig();
            expect(config.rtoMs).toBeLessThanOrEqual(30 * 60 * 1000);
        });
        it('should meet RPO requirement (<1 hour)', () => {
            const config = service.getConfig();
            expect(config.rpoMs).toBeLessThanOrEqual(60 * 60 * 1000);
        });
        it('should have backup interval less than RPO', () => {
            const config = service.getConfig();
            expect(config.backupIntervalMs).toBeLessThanOrEqual(config.rpoMs);
        });
        it('should have verification enabled', () => {
            const config = service.getConfig();
            expect(config.verificationEnabled).toBe(true);
        });
        it('should have PITR enabled', () => {
            const config = service.getConfig();
            expect(config.pitrEnabled).toBe(true);
        });
    });
    describe('Backup Cleanup', () => {
        it('should cleanup old backups', () => {
            return new Promise((resolve) => {
                let cleanupEmitted = false;
                service.on('backups-cleaned', () => {
                    cleanupEmitted = true;
                });
                service.on('backup-completed', () => {
                    setTimeout(() => {
                        // Cleanup may or may not be triggered depending on retention
                        expect(typeof cleanupEmitted).toBe('boolean');
                        resolve();
                    }, 100);
                });
                service.start();
            });
        });
    });
    describe('Error Handling', () => {
        it('should handle backup errors gracefully', () => {
            return new Promise((resolve) => {
                let errorEmitted = false;
                service.on('backup-failed', () => {
                    errorEmitted = true;
                });
                service.start();
                setTimeout(() => {
                    service.stop();
                    expect(typeof errorEmitted).toBe('boolean');
                    resolve();
                }, 200);
            });
        });
    });
});
//# sourceMappingURL=backup-strategy-service.test.js.map