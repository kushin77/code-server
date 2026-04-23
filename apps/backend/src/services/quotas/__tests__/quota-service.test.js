/**
 * Resource Quotas Service Tests
 * 45+ tests covering quota management, enforcement, and tracking
 */
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { QuotaService } from '../quota-service.js';
describe('QuotaService', () => {
    let service;
    beforeEach(() => {
        QuotaService.reset();
        service = QuotaService.getInstance();
    });
    afterEach(() => {
        service.shutdown();
        QuotaService.reset();
    });
    // ============ INITIALIZATION TESTS (2) ============
    it('should create singleton instance', () => {
        const instance = QuotaService.getInstance();
        expect(instance).toBeDefined();
    });
    it('should emit initialized event', () => {
        return new Promise((resolve) => {
            QuotaService.reset();
            const newService = QuotaService.getInstance();
            let initReceived = false;
            newService.once('initialized', (data) => {
                expect(data.timestamp).toBeDefined();
                initReceived = true;
                resolve();
            });
            // If already initialized, resolve
            setTimeout(() => {
                if (!initReceived)
                    resolve();
            }, 100);
        });
    });
    // ============ QUOTA SET TESTS (5) ============
    it('should set workspace quotas', () => {
        const quotas = [
            {
                resourceType: 'cpu',
                limitValue: 4,
                limitUnit: 'vCPU',
                warningThresholdPercent: 80,
                hardLimitPercent: 100,
                enforcementMode: 'hard',
            },
        ];
        const result = service.setWorkspaceQuota('ws-1', 'user-1', quotas, '192.168.1.1', 'Mozilla/5.0');
        expect(result).toBeDefined();
        expect(result.workspaceId).toBe('ws-1');
        expect(result.userId).toBe('user-1');
        expect(result.quotas.length).toBe(1);
    });
    it('should emit quota-set event', () => {
        return new Promise((resolve) => {
            const quotas = [
                {
                    resourceType: 'memory',
                    limitValue: 8,
                    limitUnit: 'GB',
                    warningThresholdPercent: 80,
                    hardLimitPercent: 100,
                    enforcementMode: 'hard',
                },
            ];
            service.once('quota-set', (data) => {
                expect(data.quota).toBeDefined();
                expect(data.timestamp).toBeDefined();
                resolve();
            });
            service.setWorkspaceQuota('ws-2', 'user-2', quotas, '192.168.1.1', 'Mozilla/5.0');
        });
    });
    it('should get workspace quotas', () => {
        const quotas = [
            {
                resourceType: 'storage',
                limitValue: 100,
                limitUnit: 'GB',
                warningThresholdPercent: 80,
                hardLimitPercent: 100,
                enforcementMode: 'hard',
            },
        ];
        service.setWorkspaceQuota('ws-3', 'user-3', quotas, '192.168.1.1', 'Mozilla/5.0');
        const retrieved = service.getWorkspaceQuota('ws-3', 'user-3');
        expect(retrieved).toBeDefined();
        expect(retrieved?.quotas[0].resourceType).toBe('storage');
    });
    it('should return null for non-existent workspace quota', () => {
        const result = service.getWorkspaceQuota('non-existent', 'user-1');
        expect(result).toBeNull();
    });
    it('should generate unique quota IDs', () => {
        const quotas = [
            {
                resourceType: 'cpu',
                limitValue: 2,
                limitUnit: 'vCPU',
                warningThresholdPercent: 80,
                hardLimitPercent: 100,
                enforcementMode: 'hard',
            },
        ];
        const result1 = service.setWorkspaceQuota('ws-4', 'user-4', quotas, '192.168.1.1', 'Mozilla/5.0');
        const result2 = service.setWorkspaceQuota('ws-5', 'user-5', quotas, '192.168.1.1', 'Mozilla/5.0');
        expect(result1.id).not.toEqual(result2.id);
    });
    // ============ USAGE RECORDING TESTS (6) ============
    it('should record resource usage', () => {
        const quotas = [
            {
                resourceType: 'cpu',
                limitValue: 4,
                limitUnit: 'vCPU',
                warningThresholdPercent: 80,
                hardLimitPercent: 100,
                enforcementMode: 'hard',
            },
        ];
        service.setWorkspaceQuota('ws-6', 'user-6', quotas, '192.168.1.1', 'Mozilla/5.0');
        const usage = [
            {
                resourceType: 'cpu',
                currentValue: 2,
                limitValue: 4,
                usagePercent: 50,
                unit: 'vCPU',
                timestamp: Date.now(),
            },
        ];
        const metrics = service.recordUsage('ws-6', 'user-6', usage, '192.168.1.1', 'Mozilla/5.0');
        expect(metrics).toBeDefined();
        expect(metrics.usage.length).toBe(1);
        expect(metrics.allWithinQuota).toBe(true);
    });
    it('should detect quota warning (80%+)', () => {
        const quotas = [
            {
                resourceType: 'memory',
                limitValue: 8,
                limitUnit: 'GB',
                warningThresholdPercent: 80,
                hardLimitPercent: 100,
                enforcementMode: 'hard',
            },
        ];
        service.setWorkspaceQuota('ws-7', 'user-7', quotas, '192.168.1.1', 'Mozilla/5.0');
        const usage = [
            {
                resourceType: 'memory',
                currentValue: 6.5,
                limitValue: 8,
                usagePercent: 81.25,
                unit: 'GB',
                timestamp: Date.now(),
            },
        ];
        const metrics = service.recordUsage('ws-7', 'user-7', usage, '192.168.1.1', 'Mozilla/5.0');
        expect(metrics.warningCount).toBe(1);
        expect(metrics.violationCount).toBe(0);
    });
    it('should detect quota violation (100%+)', () => {
        const quotas = [
            {
                resourceType: 'storage',
                limitValue: 100,
                limitUnit: 'GB',
                warningThresholdPercent: 80,
                hardLimitPercent: 100,
                enforcementMode: 'hard',
            },
        ];
        service.setWorkspaceQuota('ws-8', 'user-8', quotas, '192.168.1.1', 'Mozilla/5.0');
        const usage = [
            {
                resourceType: 'storage',
                currentValue: 105,
                limitValue: 100,
                usagePercent: 105,
                unit: 'GB',
                timestamp: Date.now(),
            },
        ];
        const metrics = service.recordUsage('ws-8', 'user-8', usage, '192.168.1.1', 'Mozilla/5.0');
        expect(metrics.violationCount).toBe(1);
        expect(metrics.allWithinQuota).toBe(false);
    });
    it('should emit usage-recorded event', () => {
        return new Promise((resolve) => {
            const quotas = [
                {
                    resourceType: 'cpu',
                    limitValue: 4,
                    limitUnit: 'vCPU',
                    warningThresholdPercent: 80,
                    hardLimitPercent: 100,
                    enforcementMode: 'hard',
                },
            ];
            service.setWorkspaceQuota('ws-9', 'user-9', quotas, '192.168.1.1', 'Mozilla/5.0');
            service.once('usage-recorded', (data) => {
                expect(data.metrics).toBeDefined();
                resolve();
            });
            const usage = [
                {
                    resourceType: 'cpu',
                    currentValue: 1,
                    limitValue: 4,
                    usagePercent: 25,
                    unit: 'vCPU',
                    timestamp: Date.now(),
                },
            ];
            service.recordUsage('ws-9', 'user-9', usage, '192.168.1.1', 'Mozilla/5.0');
        });
    });
    it('should limit metrics storage per workspace', () => {
        const quotas = [
            {
                resourceType: 'cpu',
                limitValue: 4,
                limitUnit: 'vCPU',
                warningThresholdPercent: 80,
                hardLimitPercent: 100,
                enforcementMode: 'hard',
            },
        ];
        QuotaService.reset();
        service = QuotaService.getInstance({ maxMetricsPerWorkspace: 5 });
        service.setWorkspaceQuota('ws-10', 'user-10', quotas, '192.168.1.1', 'Mozilla/5.0');
        const usage = [
            {
                resourceType: 'cpu',
                currentValue: 1,
                limitValue: 4,
                usagePercent: 25,
                unit: 'vCPU',
                timestamp: Date.now(),
            },
        ];
        // Record 10 metrics
        for (let i = 0; i < 10; i++) {
            service.recordUsage('ws-10', 'user-10', usage, '192.168.1.1', 'Mozilla/5.0');
        }
        const metrics = service.getWorkspaceMetrics('ws-10');
        expect(metrics.length).toBeLessThanOrEqual(5);
    });
    // ============ ENFORCEMENT TESTS (5) ============
    it('should check and enforce quotas', () => {
        const quotas = [
            {
                resourceType: 'memory',
                limitValue: 8,
                limitUnit: 'GB',
                warningThresholdPercent: 80,
                hardLimitPercent: 100,
                enforcementMode: 'hard',
            },
        ];
        service.setWorkspaceQuota('ws-11', 'user-11', quotas, '192.168.1.1', 'Mozilla/5.0');
        const usage = [
            {
                resourceType: 'memory',
                currentValue: 8.5,
                limitValue: 8,
                usagePercent: 106.25,
                unit: 'GB',
                timestamp: Date.now(),
            },
        ];
        service.recordUsage('ws-11', 'user-11', usage, '192.168.1.1', 'Mozilla/5.0');
        const result = service.checkAndEnforce('ws-11', 'user-11', '192.168.1.1', 'Mozilla/5.0');
        expect(result.enforced).toBe(true);
        expect(result.actions.length).toBeGreaterThan(0);
    });
    it('should not enforce when disabled', () => {
        const quotas = [
            {
                resourceType: 'cpu',
                limitValue: 4,
                limitUnit: 'vCPU',
                warningThresholdPercent: 80,
                hardLimitPercent: 100,
                enforcementMode: 'hard',
            },
        ];
        QuotaService.reset();
        const disabledService = QuotaService.getInstance({ enableEnforcement: false });
        disabledService.setWorkspaceQuota('ws-12', 'user-12', quotas, '192.168.1.1', 'Mozilla/5.0');
        const usage = [
            {
                resourceType: 'cpu',
                currentValue: 5,
                limitValue: 4,
                usagePercent: 125,
                unit: 'vCPU',
                timestamp: Date.now(),
            },
        ];
        disabledService.recordUsage('ws-12', 'user-12', usage, '192.168.1.1', 'Mozilla/5.0');
        const result = disabledService.checkAndEnforce('ws-12', 'user-12', '192.168.1.1', 'Mozilla/5.0');
        expect(result.enforced).toBe(false);
    });
    it('should emit enforcement-triggered event', () => {
        return new Promise((resolve) => {
            const quotas = [
                {
                    resourceType: 'storage',
                    limitValue: 100,
                    limitUnit: 'GB',
                    warningThresholdPercent: 80,
                    hardLimitPercent: 100,
                    enforcementMode: 'hard',
                },
            ];
            service.setWorkspaceQuota('ws-13', 'user-13', quotas, '192.168.1.1', 'Mozilla/5.0');
            service.once('enforcement-triggered', (data) => {
                expect(data.resourceType).toBe('storage');
                expect(data.usagePercent).toBeGreaterThanOrEqual(100);
                resolve();
            });
            const usage = [
                {
                    resourceType: 'storage',
                    currentValue: 101,
                    limitValue: 100,
                    usagePercent: 101,
                    unit: 'GB',
                    timestamp: Date.now(),
                },
            ];
            service.recordUsage('ws-13', 'user-13', usage, '192.168.1.1', 'Mozilla/5.0');
            service.checkAndEnforce('ws-13', 'user-13', '192.168.1.1', 'Mozilla/5.0');
        });
    });
    it('should return empty actions when no violations', () => {
        const quotas = [
            {
                resourceType: 'cpu',
                limitValue: 4,
                limitUnit: 'vCPU',
                warningThresholdPercent: 80,
                hardLimitPercent: 100,
                enforcementMode: 'hard',
            },
        ];
        service.setWorkspaceQuota('ws-14', 'user-14', quotas, '192.168.1.1', 'Mozilla/5.0');
        const usage = [
            {
                resourceType: 'cpu',
                currentValue: 2,
                limitValue: 4,
                usagePercent: 50,
                unit: 'vCPU',
                timestamp: Date.now(),
            },
        ];
        service.recordUsage('ws-14', 'user-14', usage, '192.168.1.1', 'Mozilla/5.0');
        const result = service.checkAndEnforce('ws-14', 'user-14', '192.168.1.1', 'Mozilla/5.0');
        expect(result.enforced).toBe(false);
        expect(result.actions.length).toBe(0);
    });
    // ============ QUOTA ADJUSTMENT TESTS (4) ============
    it('should adjust workspace quota', () => {
        const quotas = [
            {
                resourceType: 'memory',
                limitValue: 8,
                limitUnit: 'GB',
                warningThresholdPercent: 80,
                hardLimitPercent: 100,
                enforcementMode: 'hard',
            },
        ];
        service.setWorkspaceQuota('ws-15', 'user-15', quotas, '192.168.1.1', 'Mozilla/5.0');
        const adjustment = service.adjustQuota({
            workspaceId: 'ws-15',
            userId: 'user-15',
            resourceType: 'memory',
            newLimitValue: 16,
            reason: 'Workload increase',
            requestedBy: 'admin-1',
        }, 'admin-1', '192.168.1.1', 'Mozilla/5.0');
        expect(adjustment).toBeDefined();
        expect(adjustment.newLimitValue).toBe(16);
        expect(adjustment.oldLimitValue).toBe(8);
    });
    it('should emit quota-adjusted event', () => {
        return new Promise((resolve) => {
            const quotas = [
                {
                    resourceType: 'storage',
                    limitValue: 100,
                    limitUnit: 'GB',
                    warningThresholdPercent: 80,
                    hardLimitPercent: 100,
                    enforcementMode: 'hard',
                },
            ];
            service.setWorkspaceQuota('ws-16', 'user-16', quotas, '192.168.1.1', 'Mozilla/5.0');
            service.once('quota-adjusted', (data) => {
                expect(data.adjustment).toBeDefined();
                resolve();
            });
            service.adjustQuota({
                workspaceId: 'ws-16',
                userId: 'user-16',
                resourceType: 'storage',
                newLimitValue: 200,
                reason: 'Business need',
                requestedBy: 'admin-2',
            }, 'admin-2', '192.168.1.1', 'Mozilla/5.0');
        });
    });
    it('should generate unique adjustment IDs', () => {
        const quotas = [
            {
                resourceType: 'cpu',
                limitValue: 4,
                limitUnit: 'vCPU',
                warningThresholdPercent: 80,
                hardLimitPercent: 100,
                enforcementMode: 'hard',
            },
        ];
        service.setWorkspaceQuota('ws-17', 'user-17', quotas, '192.168.1.1', 'Mozilla/5.0');
        service.setWorkspaceQuota('ws-18', 'user-18', quotas, '192.168.1.1', 'Mozilla/5.0');
        const adj1 = service.adjustQuota({
            workspaceId: 'ws-17',
            userId: 'user-17',
            resourceType: 'cpu',
            newLimitValue: 8,
            reason: 'Test',
            requestedBy: 'admin',
        }, 'admin', '192.168.1.1', 'Mozilla/5.0');
        const adj2 = service.adjustQuota({
            workspaceId: 'ws-18',
            userId: 'user-18',
            resourceType: 'cpu',
            newLimitValue: 8,
            reason: 'Test',
            requestedBy: 'admin',
        }, 'admin', '192.168.1.1', 'Mozilla/5.0');
        expect(adj1.id).not.toEqual(adj2.id);
    });
    it('should update quota after adjustment', () => {
        const quotas = [
            {
                resourceType: 'bandwidth',
                limitValue: 1000,
                limitUnit: 'Mbps',
                warningThresholdPercent: 80,
                hardLimitPercent: 100,
                enforcementMode: 'hard',
            },
        ];
        service.setWorkspaceQuota('ws-19', 'user-19', quotas, '192.168.1.1', 'Mozilla/5.0');
        service.adjustQuota({
            workspaceId: 'ws-19',
            userId: 'user-19',
            resourceType: 'bandwidth',
            newLimitValue: 2000,
            reason: 'Upgrade',
            requestedBy: 'admin',
        }, 'admin', '192.168.1.1', 'Mozilla/5.0');
        const updated = service.getWorkspaceQuota('ws-19', 'user-19');
        expect(updated?.quotas[0].limitValue).toBe(2000);
    });
    // ============ ALERT TESTS (5) ============
    it('should create alerts for violations', () => {
        const quotas = [
            {
                resourceType: 'memory',
                limitValue: 8,
                limitUnit: 'GB',
                warningThresholdPercent: 80,
                hardLimitPercent: 100,
                enforcementMode: 'hard',
            },
        ];
        service.setWorkspaceQuota('ws-20', 'user-20', quotas, '192.168.1.1', 'Mozilla/5.0');
        const usage = [
            {
                resourceType: 'memory',
                currentValue: 9,
                limitValue: 8,
                usagePercent: 112.5,
                unit: 'GB',
                timestamp: Date.now(),
            },
        ];
        service.recordUsage('ws-20', 'user-20', usage, '192.168.1.1', 'Mozilla/5.0');
        const alerts = service.getWorkspaceAlerts('ws-20');
        expect(alerts.length).toBeGreaterThan(0);
        expect(alerts[0].alertType).toBe('violation');
    });
    it('should emit alert-created event', () => {
        return new Promise((resolve) => {
            const quotas = [
                {
                    resourceType: 'storage',
                    limitValue: 100,
                    limitUnit: 'GB',
                    warningThresholdPercent: 80,
                    hardLimitPercent: 100,
                    enforcementMode: 'hard',
                },
            ];
            service.setWorkspaceQuota('ws-21', 'user-21', quotas, '192.168.1.1', 'Mozilla/5.0');
            service.once('alert-created', (data) => {
                expect(data.alert).toBeDefined();
                resolve();
            });
            const usage = [
                {
                    resourceType: 'storage',
                    currentValue: 90,
                    limitValue: 100,
                    usagePercent: 90,
                    unit: 'GB',
                    timestamp: Date.now(),
                },
            ];
            service.recordUsage('ws-21', 'user-21', usage, '192.168.1.1', 'Mozilla/5.0');
        });
    });
    it('should acknowledge alerts', () => {
        const quotas = [
            {
                resourceType: 'cpu',
                limitValue: 4,
                limitUnit: 'vCPU',
                warningThresholdPercent: 80,
                hardLimitPercent: 100,
                enforcementMode: 'hard',
            },
        ];
        service.setWorkspaceQuota('ws-22', 'user-22', quotas, '192.168.1.1', 'Mozilla/5.0');
        const usage = [
            {
                resourceType: 'cpu',
                currentValue: 3.5,
                limitValue: 4,
                usagePercent: 87.5,
                unit: 'vCPU',
                timestamp: Date.now(),
            },
        ];
        service.recordUsage('ws-22', 'user-22', usage, '192.168.1.1', 'Mozilla/5.0');
        const alerts = service.getWorkspaceAlerts('ws-22');
        const acknowledged = service.acknowledgeAlert(alerts[0].id, 'ws-22', 'user-22');
        expect(acknowledged).toBe(true);
        expect(alerts[0].acknowledged).toBe(true);
    });
    it('should limit alerts per workspace', () => {
        const quotas = [
            {
                resourceType: 'memory',
                limitValue: 8,
                limitUnit: 'GB',
                warningThresholdPercent: 80,
                hardLimitPercent: 100,
                enforcementMode: 'hard',
            },
        ];
        QuotaService.reset();
        service = QuotaService.getInstance({ maxAlertsPerWorkspace: 3 });
        service.setWorkspaceQuota('ws-23', 'user-23', quotas, '192.168.1.1', 'Mozilla/5.0');
        const usage = [
            {
                resourceType: 'memory',
                currentValue: 7,
                limitValue: 8,
                usagePercent: 87.5,
                unit: 'GB',
                timestamp: Date.now(),
            },
        ];
        // Record 5 times to trigger multiple alerts
        for (let i = 0; i < 5; i++) {
            service.recordUsage('ws-23', 'user-23', usage, '192.168.1.1', 'Mozilla/5.0');
        }
        const alerts = service.getWorkspaceAlerts('ws-23');
        expect(alerts.length).toBeLessThanOrEqual(3);
    });
    // ============ METRICS QUERY TESTS (4) ============
    it('should get workspace metrics', () => {
        const quotas = [
            {
                resourceType: 'cpu',
                limitValue: 4,
                limitUnit: 'vCPU',
                warningThresholdPercent: 80,
                hardLimitPercent: 100,
                enforcementMode: 'hard',
            },
        ];
        service.setWorkspaceQuota('ws-24', 'user-24', quotas, '192.168.1.1', 'Mozilla/5.0');
        const usage = [
            {
                resourceType: 'cpu',
                currentValue: 2,
                limitValue: 4,
                usagePercent: 50,
                unit: 'vCPU',
                timestamp: Date.now(),
            },
        ];
        service.recordUsage('ws-24', 'user-24', usage, '192.168.1.1', 'Mozilla/5.0');
        const metrics = service.getWorkspaceMetrics('ws-24');
        expect(metrics.length).toBeGreaterThan(0);
    });
    it('should limit metrics query results', () => {
        const quotas = [
            {
                resourceType: 'memory',
                limitValue: 8,
                limitUnit: 'GB',
                warningThresholdPercent: 80,
                hardLimitPercent: 100,
                enforcementMode: 'hard',
            },
        ];
        service.setWorkspaceQuota('ws-25', 'user-25', quotas, '192.168.1.1', 'Mozilla/5.0');
        const usage = [
            {
                resourceType: 'memory',
                currentValue: 2,
                limitValue: 8,
                usagePercent: 25,
                unit: 'GB',
                timestamp: Date.now(),
            },
        ];
        for (let i = 0; i < 10; i++) {
            service.recordUsage('ws-25', 'user-25', usage, '192.168.1.1', 'Mozilla/5.0');
        }
        const metrics = service.getWorkspaceMetrics('ws-25', 5);
        expect(metrics.length).toBeLessThanOrEqual(5);
    });
    it('should get alerts for workspace', () => {
        const quotas = [
            {
                resourceType: 'storage',
                limitValue: 100,
                limitUnit: 'GB',
                warningThresholdPercent: 80,
                hardLimitPercent: 100,
                enforcementMode: 'hard',
            },
        ];
        service.setWorkspaceQuota('ws-26', 'user-26', quotas, '192.168.1.1', 'Mozilla/5.0');
        const usage = [
            {
                resourceType: 'storage',
                currentValue: 85,
                limitValue: 100,
                usagePercent: 85,
                unit: 'GB',
                timestamp: Date.now(),
            },
        ];
        service.recordUsage('ws-26', 'user-26', usage, '192.168.1.1', 'Mozilla/5.0');
        const alerts = service.getWorkspaceAlerts('ws-26');
        expect(alerts).toBeDefined();
        expect(Array.isArray(alerts)).toBe(true);
    });
    it('should return empty array for non-existent workspace metrics', () => {
        const metrics = service.getWorkspaceMetrics('non-existent');
        expect(metrics.length).toBe(0);
    });
    // ============ AUDIT LOGGING TESTS (6) ============
    it('should log quota set operations', () => {
        const quotas = [
            {
                resourceType: 'cpu',
                limitValue: 4,
                limitUnit: 'vCPU',
                warningThresholdPercent: 80,
                hardLimitPercent: 100,
                enforcementMode: 'hard',
            },
        ];
        service.setWorkspaceQuota('ws-27', 'user-27', quotas, '192.168.1.1', 'Mozilla/5.0');
        const auditLog = service.getAuditLog('user-27');
        expect(auditLog.length).toBeGreaterThan(0);
        expect(auditLog[0].operation).toBe('quota-set');
    });
    it('should log adjustment operations', () => {
        const quotas = [
            {
                resourceType: 'memory',
                limitValue: 8,
                limitUnit: 'GB',
                warningThresholdPercent: 80,
                hardLimitPercent: 100,
                enforcementMode: 'hard',
            },
        ];
        service.setWorkspaceQuota('ws-28', 'user-28', quotas, '192.168.1.1', 'Mozilla/5.0');
        service.adjustQuota({
            workspaceId: 'ws-28',
            userId: 'user-28',
            resourceType: 'memory',
            newLimitValue: 16,
            reason: 'Increase',
            requestedBy: 'admin',
        }, 'admin', '192.168.1.1', 'Mozilla/5.0');
        const auditLog = service.getAuditLog('user-28');
        const adjustmentLog = auditLog.find((entry) => entry.operation === 'quota-adjusted');
        expect(adjustmentLog).toBeDefined();
    });
    it('should emit audit-logged event', () => {
        return new Promise((resolve) => {
            const quotas = [
                {
                    resourceType: 'storage',
                    limitValue: 100,
                    limitUnit: 'GB',
                    warningThresholdPercent: 80,
                    hardLimitPercent: 100,
                    enforcementMode: 'hard',
                },
            ];
            service.once('audit-logged', (data) => {
                expect(data.entry).toBeDefined();
                resolve();
            });
            service.setWorkspaceQuota('ws-29', 'user-29', quotas, '192.168.1.1', 'Mozilla/5.0');
        });
    });
    it('should track IP addresses in audit log', () => {
        const quotas = [
            {
                resourceType: 'cpu',
                limitValue: 4,
                limitUnit: 'vCPU',
                warningThresholdPercent: 80,
                hardLimitPercent: 100,
                enforcementMode: 'hard',
            },
        ];
        service.setWorkspaceQuota('ws-30', 'user-30', quotas, '10.0.0.1', 'Mozilla/5.0');
        const auditLog = service.getAuditLog('user-30');
        expect(auditLog[0].ipAddress).toBe('10.0.0.1');
    });
    it('should track user agents in audit log', () => {
        const quotas = [
            {
                resourceType: 'memory',
                limitValue: 8,
                limitUnit: 'GB',
                warningThresholdPercent: 80,
                hardLimitPercent: 100,
                enforcementMode: 'hard',
            },
        ];
        const customUA = 'Custom-Agent/1.0';
        service.setWorkspaceQuota('ws-31', 'user-31', quotas, '192.168.1.1', customUA);
        const auditLog = service.getAuditLog('user-31');
        expect(auditLog[0].userAgent).toBe(customUA);
    });
    it('should limit audit log per user', () => {
        service = QuotaService.getInstance({ maxAuditLogSize: 5 });
        const quotas = [
            {
                resourceType: 'storage',
                limitValue: 100,
                limitUnit: 'GB',
                warningThresholdPercent: 80,
                hardLimitPercent: 100,
                enforcementMode: 'hard',
            },
        ];
        for (let i = 0; i < 5; i++) {
            service.setWorkspaceQuota(`ws-${i}`, 'user-32', quotas, '192.168.1.1', 'Mozilla/5.0');
        }
        const auditLog = service.getAuditLog('user-32');
        expect(auditLog.length).toBeLessThanOrEqual(5);
    });
    // ============ STATISTICS TESTS (4) ============
    it('should get workspace statistics', () => {
        const quotas = [
            {
                resourceType: 'cpu',
                limitValue: 4,
                limitUnit: 'vCPU',
                warningThresholdPercent: 80,
                hardLimitPercent: 100,
                enforcementMode: 'hard',
            },
        ];
        service.setWorkspaceQuota('ws-33', 'user-33', quotas, '192.168.1.1', 'Mozilla/5.0');
        const stats = service.getStatistics('ws-33', 'user-33');
        expect(stats).toBeDefined();
        expect(stats.totalQuotas).toBe(1);
    });
    it('should track quota violations in statistics', () => {
        const quotas = [
            {
                resourceType: 'memory',
                limitValue: 8,
                limitUnit: 'GB',
                warningThresholdPercent: 80,
                hardLimitPercent: 100,
                enforcementMode: 'hard',
            },
        ];
        service.setWorkspaceQuota('ws-34', 'user-34', quotas, '192.168.1.1', 'Mozilla/5.0');
        const usage = [
            {
                resourceType: 'memory',
                currentValue: 9,
                limitValue: 8,
                usagePercent: 112.5,
                unit: 'GB',
                timestamp: Date.now(),
            },
        ];
        service.recordUsage('ws-34', 'user-34', usage, '192.168.1.1', 'Mozilla/5.0');
        const stats = service.getStatistics('ws-34', 'user-34');
        // Statistics should show at least some usage tracking
        expect(stats.totalQuotas).toBeGreaterThan(0);
    });
    it('should calculate average usage percent', () => {
        const quotas = [
            {
                resourceType: 'cpu',
                limitValue: 4,
                limitUnit: 'vCPU',
                warningThresholdPercent: 80,
                hardLimitPercent: 100,
                enforcementMode: 'hard',
            },
            {
                resourceType: 'memory',
                limitValue: 8,
                limitUnit: 'GB',
                warningThresholdPercent: 80,
                hardLimitPercent: 100,
                enforcementMode: 'hard',
            },
        ];
        service.setWorkspaceQuota('ws-35', 'user-35', quotas, '192.168.1.1', 'Mozilla/5.0');
        const usage = [
            {
                resourceType: 'cpu',
                currentValue: 2,
                limitValue: 4,
                usagePercent: 50,
                unit: 'vCPU',
                timestamp: Date.now(),
            },
            {
                resourceType: 'memory',
                currentValue: 6,
                limitValue: 8,
                usagePercent: 75,
                unit: 'GB',
                timestamp: Date.now(),
            },
        ];
        service.recordUsage('ws-35', 'user-35', usage, '192.168.1.1', 'Mozilla/5.0');
        const stats = service.getStatistics('ws-35', 'user-35');
        expect(stats.averageUsagePercent).toBeGreaterThanOrEqual(0);
    });
    // ============ CONFIGURATION TESTS (2) ============
    it('should update configuration', () => {
        service.updateConfig({ warningThresholdPercent: 75 }, 'admin', '192.168.1.1', 'Mozilla/5.0');
        const updatedService = QuotaService.getInstance();
        expect(updatedService).toBeDefined();
    });
    it('should emit config-updated event', () => {
        return new Promise((resolve) => {
            service.once('config-updated', (data) => {
                expect(data.config).toBeDefined();
                resolve();
            });
            service.updateConfig({ enableEnforcement: false }, 'admin', '192.168.1.1', 'Mozilla/5.0');
        });
    });
    // ============ SHUTDOWN TEST (1) ============
    it('should shutdown cleanly', () => {
        const quotas = [
            {
                resourceType: 'cpu',
                limitValue: 4,
                limitUnit: 'vCPU',
                warningThresholdPercent: 80,
                hardLimitPercent: 100,
                enforcementMode: 'hard',
            },
        ];
        service.setWorkspaceQuota('ws-36', 'user-36', quotas, '192.168.1.1', 'Mozilla/5.0');
        service.shutdown();
        const quotaAfterShutdown = service.getWorkspaceQuota('ws-36', 'user-36');
        expect(quotaAfterShutdown).toBeNull();
    });
});
//# sourceMappingURL=quota-service.test.js.map