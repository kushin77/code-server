import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { ResourceQuotasService } from '../resource-quotas-service.js';

describe('ResourceQuotasService', () => {
  let service: ResourceQuotasService;

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
      expect(allQuotas.find((q: any) => q.id === quota.id)).toBeUndefined();
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
      const svc = new ResourceQuotasService({}, mockAudit as any);
      await svc.initialize();

      await svc.createQuotaFromTier('user-alice', 'workspace-1', 'small');

      expect(mockAudit.emit).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'user-alice',
          action: 'create',
          resourceType: 'quota',
          metadata: expect.objectContaining({
            workspaceId: 'workspace-1',
            tier: 'small',
          }),
        })
      );

      await svc.shutdown();
    });

    it('should emit audit event when deleting quota', async () => {
      const mockAudit = { emit: vi.fn() };
      const svc = new ResourceQuotasService({}, mockAudit as any);
      await svc.initialize();

      const quota = await svc.createQuotaFromTier('user-bob', 'workspace-2', 'medium');
      mockAudit.emit.mockClear();

      await svc.deleteQuota(quota.id);

      expect(mockAudit.emit).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'user-bob',
          action: 'delete',
          resourceType: 'quota',
          metadata: expect.objectContaining({
            quotaId: quota.id,
            workspaceId: 'workspace-2',
          }),
        })
      );

      await svc.shutdown();
    });

    it('should emit audit event when updating quota tier', async () => {
      const mockAudit = { emit: vi.fn() };
      const svc = new ResourceQuotasService({}, mockAudit as any);
      await svc.initialize();

      const quota = await svc.createQuotaFromTier('user-charlie', 'workspace-3', 'small');
      mockAudit.emit.mockClear();

      await svc.updateQuotaTier(quota.id, 'large');

      expect(mockAudit.emit).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'user-charlie',
          action: 'update',
          resourceType: 'quota',
          metadata: expect.objectContaining({
            quotaId: quota.id,
            oldTier: 'small',
            newTier: 'large',
          }),
        })
      );

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
});
