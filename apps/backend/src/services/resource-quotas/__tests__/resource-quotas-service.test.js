import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { ResourceQuotasService } from '../resource-quotas-service.js';
describe('ResourceQuotasService', () => {
    let service;
    beforeEach(async () => {
        service = new ResourceQuotasService();
        await service.initialize();
    });
    afterEach(async () => {
        await service.shutdown();
    });
    describe('Core Functionality', () => {
        it('should create quota from tier', async () => {
            const quota = await service.createQuotaFromTier('user-1', 'workspace-1', 'small');
            expect(quota).toBeDefined();
            expect(quota.name).toBe('small');
            expect(quota.cpu.cores).toBe(0.5);
        });
        it('should delete quota', async () => {
            const quota = await service.createQuotaFromTier('user-2', 'workspace-2', 'medium');
            await service.deleteQuota(quota.id);
            const allQuotas = await service.getAllQuotas();
            expect(allQuotas.find((q) => q.id === quota.id)).toBeUndefined();
        });
        it('should update quota tier', async () => {
            const quota = await service.createQuotaFromTier('user-3', 'workspace-3', 'small');
            const updated = await service.updateQuotaTier(quota.id, 'large');
            expect(updated.cpu.cores).toBe(4);
        });
    });
    describe('Audit Logging', () => {
        it('should emit audit event when creating quota', async () => {
            const mockAudit = { emit: vi.fn() };
            const svc = new ResourceQuotasService({}, mockAudit);
            await svc.initialize();
            await svc.createQuotaFromTier('user-alice', 'workspace-1', 'small');
            expect(mockAudit.emit).toHaveBeenCalledWith(expect.objectContaining({
                userId: 'user-alice',
                action: 'create',
                resourceType: 'quota',
                metadata: expect.objectContaining({
                    workspaceId: 'workspace-1',
                    tier: 'small',
                }),
            }));
            await svc.shutdown();
        });
        it('should emit audit event when deleting quota', async () => {
            const mockAudit = { emit: vi.fn() };
            const svc = new ResourceQuotasService({}, mockAudit);
            await svc.initialize();
            const quota = await svc.createQuotaFromTier('user-bob', 'workspace-2', 'medium');
            mockAudit.emit.mockClear();
            await svc.deleteQuota(quota.id);
            expect(mockAudit.emit).toHaveBeenCalledWith(expect.objectContaining({
                userId: 'user-bob',
                action: 'delete',
                resourceType: 'quota',
                metadata: expect.objectContaining({
                    quotaId: quota.id,
                    workspaceId: 'workspace-2',
                }),
            }));
            await svc.shutdown();
        });
        it('should emit audit event when updating quota tier', async () => {
            const mockAudit = { emit: vi.fn() };
            const svc = new ResourceQuotasService({}, mockAudit);
            await svc.initialize();
            const quota = await svc.createQuotaFromTier('user-charlie', 'workspace-3', 'small');
            mockAudit.emit.mockClear();
            await svc.updateQuotaTier(quota.id, 'large');
            expect(mockAudit.emit).toHaveBeenCalledWith(expect.objectContaining({
                userId: 'user-charlie',
                action: 'update',
                resourceType: 'quota',
                metadata: expect.objectContaining({
                    quotaId: quota.id,
                    oldTier: 'small',
                    newTier: 'large',
                }),
            }));
            await svc.shutdown();
        });
        it('should work without audit service', async () => {
            const svc = new ResourceQuotasService();
            await svc.initialize();
            const quota = await svc.createQuotaFromTier('user-dave', 'workspace-4', 'medium');
            expect(quota.name).toBe('medium');
            await svc.shutdown();
        });
    });
    describe('Cost Tracking', () => {
        it('should record usage samples and calculate a cost report', async () => {
            const quota = await service.createQuotaFromTier('user-cost', 'workspace-cost', 'small');
            await service.recordUsageSample(quota.id, {
                cpuPercent: 50,
                cpuCoresUsed: 2,
                memoryMB: 4096,
                memoryPercent: 50,
                diskIOReadBytesPerSec: 100,
                diskIOWriteBytesPerSec: 100,
                diskIOReadPercent: 10,
                diskIOWritePercent: 10,
                ingressMbps: 1,
                egressMbps: 1,
                ingressPercent: 10,
                egressPercent: 10,
                storageGBUsed: 10,
                gpuCountUsed: 1,
                timestamp: 0,
            });
            await service.recordUsageSample(quota.id, {
                cpuPercent: 50,
                cpuCoresUsed: 2,
                memoryMB: 4096,
                memoryPercent: 50,
                diskIOReadBytesPerSec: 100,
                diskIOWriteBytesPerSec: 100,
                diskIOReadPercent: 10,
                diskIOWritePercent: 10,
                ingressMbps: 1,
                egressMbps: 1,
                ingressPercent: 10,
                egressPercent: 10,
                storageGBUsed: 10,
                gpuCountUsed: 1,
                timestamp: 60 * 60 * 1000,
            });
            const report = await service.getCostReport(quota.id, 0, 2 * 60 * 60 * 1000);
            expect(report.quotaId).toBe(quota.id);
            expect(report.sampleCount).toBe(2);
            expect(report.projectId).toBe('workspace-cost');
            expect(report.cpuHours).toBeCloseTo(4, 5);
            expect(report.memoryGbHours).toBeCloseTo(8, 5);
            expect(report.storageGbDays).toBeCloseTo(0.833333, 5);
            expect(report.gpuHours).toBeCloseTo(2, 5);
        });
        it('should aggregate monthly reports by workspace', async () => {
            const quotaOne = await service.createQuotaFromTier('user-report', 'workspace-report', 'small');
            const quotaTwo = await service.createQuotaFromTier('user-report', 'workspace-report', 'medium');
            await service.recordUsageSample(quotaOne.id, {
                cpuPercent: 25,
                cpuCoresUsed: 1,
                memoryMB: 1024,
                memoryPercent: 25,
                diskIOReadBytesPerSec: 100,
                diskIOWriteBytesPerSec: 100,
                diskIOReadPercent: 10,
                diskIOWritePercent: 10,
                ingressMbps: 1,
                egressMbps: 1,
                ingressPercent: 10,
                egressPercent: 10,
                storageGBUsed: 2,
                gpuCountUsed: 0,
                timestamp: 0,
            });
            await service.recordUsageSample(quotaOne.id, {
                cpuPercent: 25,
                cpuCoresUsed: 1,
                memoryMB: 1024,
                memoryPercent: 25,
                diskIOReadBytesPerSec: 100,
                diskIOWriteBytesPerSec: 100,
                diskIOReadPercent: 10,
                diskIOWritePercent: 10,
                ingressMbps: 1,
                egressMbps: 1,
                ingressPercent: 10,
                egressPercent: 10,
                storageGBUsed: 2,
                gpuCountUsed: 0,
                timestamp: 60 * 60 * 1000,
            });
            await service.recordUsageSample(quotaTwo.id, {
                cpuPercent: 75,
                cpuCoresUsed: 3,
                memoryMB: 6144,
                memoryPercent: 75,
                diskIOReadBytesPerSec: 100,
                diskIOWriteBytesPerSec: 100,
                diskIOReadPercent: 10,
                diskIOWritePercent: 10,
                ingressMbps: 1,
                egressMbps: 1,
                ingressPercent: 10,
                egressPercent: 10,
                storageGBUsed: 4,
                gpuCountUsed: 2,
                timestamp: 0,
            });
            await service.recordUsageSample(quotaTwo.id, {
                cpuPercent: 75,
                cpuCoresUsed: 3,
                memoryMB: 6144,
                memoryPercent: 75,
                diskIOReadBytesPerSec: 100,
                diskIOWriteBytesPerSec: 100,
                diskIOReadPercent: 10,
                diskIOWritePercent: 10,
                ingressMbps: 1,
                egressMbps: 1,
                ingressPercent: 10,
                egressPercent: 10,
                storageGBUsed: 4,
                gpuCountUsed: 2,
                timestamp: 60 * 60 * 1000,
            });
            const report = await service.getMonthlyCostReport('user-report', 'workspace-report', 0, 2 * 60 * 60 * 1000);
            expect(report.projectId).toBe('workspace-report');
            expect(report.quotas).toHaveLength(2);
            expect(report.totals.cpuHours).toBeCloseTo(8, 5);
            expect(report.totals.memoryGbHours).toBeCloseTo(14, 5);
            expect(report.totals.storageGbDays).toBeCloseTo(0.5, 5);
            expect(report.totals.gpuHours).toBeCloseTo(4, 5);
        });
        it('should emit budget alerts when thresholds are exceeded', async () => {
            const quota = await service.createQuotaFromTier('user-budget', 'workspace-budget', 'small');
            service.setBudgetThresholds('workspace', 'workspace-budget', {
                cpuHours: 1,
                memoryGbHours: 1,
            });
            await service.recordUsageSample(quota.id, {
                cpuPercent: 100,
                cpuCoresUsed: 2,
                memoryMB: 4096,
                memoryPercent: 100,
                diskIOReadBytesPerSec: 100,
                diskIOWriteBytesPerSec: 100,
                diskIOReadPercent: 10,
                diskIOWritePercent: 10,
                ingressMbps: 1,
                egressMbps: 1,
                ingressPercent: 10,
                egressPercent: 10,
                storageGBUsed: 0,
                gpuCountUsed: 0,
                timestamp: 0,
            });
            await service.recordUsageSample(quota.id, {
                cpuPercent: 100,
                cpuCoresUsed: 2,
                memoryMB: 4096,
                memoryPercent: 100,
                diskIOReadBytesPerSec: 100,
                diskIOWriteBytesPerSec: 100,
                diskIOReadPercent: 10,
                diskIOWritePercent: 10,
                ingressMbps: 1,
                egressMbps: 1,
                ingressPercent: 10,
                egressPercent: 10,
                storageGBUsed: 0,
                gpuCountUsed: 0,
                timestamp: 60 * 60 * 1000,
            });
            await service.getMonthlyCostReport('user-budget', 'workspace-budget', 0, 2 * 60 * 60 * 1000);
            const alerts = service.getBudgetAlerts('workspace', 'workspace-budget');
            expect(alerts.length).toBeGreaterThan(0);
            expect(alerts.some((alert) => alert.metric === 'cpuHours')).toBe(true);
            expect(alerts.some((alert) => alert.metric === 'memoryGbHours')).toBe(true);
            const acknowledged = service.acknowledgeBudgetAlert(alerts[0].alertId, 'tester');
            expect(acknowledged).toBe(true);
            expect(service.getBudgetAlerts('workspace', 'workspace-budget')[0].acknowledgedBy).toBe('tester');
        });
    });
});
//# sourceMappingURL=resource-quotas-service.test.js.map