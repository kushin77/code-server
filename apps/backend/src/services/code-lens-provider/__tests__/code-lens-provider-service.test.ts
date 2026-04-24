/**
 * Code Lens Provider Service Tests
 * @file        apps/backend/src/services/code-lens-provider/__tests__/code-lens-provider-service.test.ts
 * @module      services/code-lens-provider
 * @description Test suite for code lens provider functionality
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { CodeLensProvider } from '../code-lens-provider-service.js';

describe('Code Lens Provider Service', () => {
  let service: CodeLensProvider;

  beforeEach(() => {
    CodeLensProvider.reset();
    service = CodeLensProvider.getInstance();
  });

  afterEach(() => {
    service.shutdown();
  });

  // Initialization Tests
  describe('Initialization', () => {
    it('should initialize service', () => {
      expect(service).toBeDefined();
      expect((service as any).lenses).toBeDefined();
      expect((service as any).references).toBeDefined();
    });

    it('should return same instance on subsequent calls', () => {
      const instance1 = CodeLensProvider.getInstance();
      const instance2 = CodeLensProvider.getInstance();
      expect(instance1).toBe(instance2);
    });
  });

  // Code Lens Creation Tests
  describe('Code Lens Creation', () => {
    it('should create code lens', () => {
      const result = service.createCodeLens(
        {
          fileId: 'file1',
          position: { line: 10, column: 5 },
          title: 'References',
          command: 'goto.reference',
        },
        'user1',
        '192.168.1.1',
        'Mozilla'
      );

      expect(result.success).toBe(true);
      expect(result.lensId).toBeDefined();
    });

    it('should emit code-lens-created event', () => {
      return new Promise<void>((resolve) => {
        service.once('code-lens-created', (event) => {
          expect(event.data_object.fileId).toBe('file1');
          resolve();
        });

        service.createCodeLens(
          {
            fileId: 'file1',
            position: { line: 10, column: 5 },
            title: 'References',
          },
          'user1',
          '192.168.1.1',
          'Mozilla'
        );
      });
    });

    it('should retrieve created code lens', () => {
      const created = service.createCodeLens(
        {
          fileId: 'file1',
          position: { line: 10, column: 5 },
          title: 'References',
        },
        'user1',
        '192.168.1.1',
        'Mozilla'
      );

      const lens = service.getCodeLens(created.lensId!);

      expect(lens).toBeDefined();
      expect(lens?.title).toBe('References');
    });
  });

  // Code Lens Update Tests
  describe('Code Lens Updates', () => {
    it('should update code lens', () => {
      const created = service.createCodeLens(
        {
          fileId: 'file1',
          position: { line: 10, column: 5 },
          title: 'References',
        },
        'user1',
        '192.168.1.1',
        'Mozilla'
      );

      const result = service.updateCodeLens(
        created.lensId!,
        { title: 'Updated References' },
        'user1',
        '192.168.1.1',
        'Mozilla'
      );

      expect(result.success).toBe(true);
    });

    it('should emit code-lens-updated event', () => {
      return new Promise<void>((resolve) => {
        const created = service.createCodeLens(
          {
            fileId: 'file1',
            position: { line: 10, column: 5 },
            title: 'References',
          },
          'user1',
          '192.168.1.1',
          'Mozilla'
        );

        service.once('code-lens-updated', (event) => {
          expect(event.data_object.lensId).toBe(created.lensId);
          resolve();
        });

        service.updateCodeLens(
          created.lensId!,
          { title: 'Updated' },
          'user1',
          '192.168.1.1',
          'Mozilla'
        );
      });
    });
  });

  // Code Lens Deletion Tests
  describe('Code Lens Deletion', () => {
    it('should delete code lens', () => {
      const created = service.createCodeLens(
        {
          fileId: 'file1',
          position: { line: 10, column: 5 },
          title: 'References',
        },
        'user1',
        '192.168.1.1',
        'Mozilla'
      );

      const result = service.deleteCodeLens(created.lensId!, 'user1', '192.168.1.1', 'Mozilla');

      expect(result.success).toBe(true);
    });

    it('should emit code-lens-deleted event', () => {
      return new Promise<void>((resolve) => {
        const created = service.createCodeLens(
          {
            fileId: 'file1',
            position: { line: 10, column: 5 },
            title: 'References',
          },
          'user1',
          '192.168.1.1',
          'Mozilla'
        );

        service.once('code-lens-deleted', (event) => {
          expect(event.data_object.lensId).toBe(created.lensId);
          resolve();
        });

        service.deleteCodeLens(created.lensId!, 'user1', '192.168.1.1', 'Mozilla');
      });
    });
  });

  // Code Lens Resolution Tests
  describe('Code Lens Resolution', () => {
    it('should resolve code lens', () => {
      const created = service.createCodeLens(
        {
          fileId: 'file1',
          position: { line: 10, column: 5 },
          title: 'References',
        },
        'user1',
        '192.168.1.1',
        'Mozilla'
      );

      const result = service.resolveCodeLens(created.lensId!, 'user1', '192.168.1.1', 'Mozilla');

      expect(result.success).toBe(true);
      expect(result.metadata?.isResolved).toBe(true);
    });

    it('should emit code-lens-resolved event', () => {
      return new Promise<void>((resolve) => {
        const created = service.createCodeLens(
          {
            fileId: 'file1',
            position: { line: 10, column: 5 },
            title: 'References',
          },
          'user1',
          '192.168.1.1',
          'Mozilla'
        );

        service.once('code-lens-resolved', (event) => {
          expect(event.data_object.lensId).toBe(created.lensId);
          resolve();
        });

        service.resolveCodeLens(created.lensId!, 'user1', '192.168.1.1', 'Mozilla');
      });
    });

    it('should resolve lenses in file', () => {
      service.createCodeLens(
        {
          fileId: 'file1',
          position: { line: 10, column: 5 },
          title: 'References',
        },
        'user1',
        '192.168.1.1',
        'Mozilla'
      );

      service.createCodeLens(
        {
          fileId: 'file1',
          position: { line: 20, column: 10 },
          title: 'Implementations',
        },
        'user1',
        '192.168.1.1',
        'Mozilla'
      );

      const result = service.resolveLensesInFile('file1', 'user1', '192.168.1.1', 'Mozilla');

      expect(result.success).toBe(true);
      expect(result.resolvedCount).toBeGreaterThan(0);
    });

    it('should unresolve code lens', () => {
      const created = service.createCodeLens(
        {
          fileId: 'file1',
          position: { line: 10, column: 5 },
          title: 'References',
        },
        'user1',
        '192.168.1.1',
        'Mozilla'
      );

      service.resolveCodeLens(created.lensId!, 'user1', '192.168.1.1', 'Mozilla');
      const result = service.unresolveCodeLens(created.lensId!, 'user1', '192.168.1.1', 'Mozilla');

      expect(result.success).toBe(true);
    });
  });

  // Code Lens Query Tests
  describe('Code Lens Queries', () => {
    it('should get lenses in file', () => {
      service.createCodeLens(
        {
          fileId: 'file1',
          position: { line: 10, column: 5 },
          title: 'References',
        },
        'user1',
        '192.168.1.1',
        'Mozilla'
      );

      const lenses = service.getCodeLensesInFile('file1');

      expect(Array.isArray(lenses)).toBe(true);
      expect(lenses.length).toBeGreaterThan(0);
    });

    it('should get lenses in range', () => {
      service.createCodeLens(
        {
          fileId: 'file1',
          position: { line: 10, column: 5 },
          title: 'References',
        },
        'user1',
        '192.168.1.1',
        'Mozilla'
      );

      const lenses = service.getCodeLensesInRange('file1', {
        startLine: 5,
        endLine: 15,
      });

      expect(Array.isArray(lenses)).toBe(true);
    });

    it('should get unresolved lenses', () => {
      const unresolved = service.getUnresolvedLenses();

      expect(Array.isArray(unresolved)).toBe(true);
    });
  });

  // Reference Management Tests
  describe('Reference Management', () => {
    it('should add reference', () => {
      const created = service.createCodeLens(
        {
          fileId: 'file1',
          position: { line: 10, column: 5 },
          title: 'References',
        },
        'user1',
        '192.168.1.1',
        'Mozilla'
      );

      const result = service.addReference(
        {
          lensId: created.lensId!,
          referencingFile: 'file2',
          referencingPosition: { line: 20, column: 10 },
          referenceType: 'reference',
          isWeakReference: false,
        },
        'user1',
        '192.168.1.1',
        'Mozilla'
      );

      expect(result.success).toBe(true);
      expect(result.referenceId).toBeDefined();
    });

    it('should get references for lens', () => {
      const created = service.createCodeLens(
        {
          fileId: 'file1',
          position: { line: 10, column: 5 },
          title: 'References',
        },
        'user1',
        '192.168.1.1',
        'Mozilla'
      );

      service.addReference(
        {
          lensId: created.lensId!,
          referencingFile: 'file2',
          referencingPosition: { line: 20, column: 10 },
          referenceType: 'reference',
          isWeakReference: false,
        },
        'user1',
        '192.168.1.1',
        'Mozilla'
      );

      const refs = service.getReferencesForLens(created.lensId!);

      expect(Array.isArray(refs)).toBe(true);
    });

    it('should update reference counts', () => {
      const created = service.createCodeLens(
        {
          fileId: 'file1',
          position: { line: 10, column: 5 },
          title: 'References',
        },
        'user1',
        '192.168.1.1',
        'Mozilla'
      );

      const result = service.updateReferenceCounts(created.lensId!, 'user1', '192.168.1.1', 'Mozilla');

      expect(result.success).toBe(true);
    });

    it('should remove reference', () => {
      const created = service.createCodeLens(
        {
          fileId: 'file1',
          position: { line: 10, column: 5 },
          title: 'References',
        },
        'user1',
        '192.168.1.1',
        'Mozilla'
      );

      const ref = service.addReference(
        {
          lensId: created.lensId!,
          referencingFile: 'file2',
          referencingPosition: { line: 20, column: 10 },
          referenceType: 'reference',
          isWeakReference: false,
        },
        'user1',
        '192.168.1.1',
        'Mozilla'
      );

      const result = service.removeReference(ref.referenceId!, 'user1', '192.168.1.1', 'Mozilla');

      expect(result.success).toBe(true);
    });
  });

  // Batch Update Tests
  describe('Batch Updates', () => {
    it('should perform batch update', () => {
      const result = service.batchUpdate(
        {
          fileId: 'file1',
          addedLenses: [
            {
              lensId: 'lens-1',
              fileId: 'file1',
              position: { line: 10, column: 5 },
              title: 'References',
              isResolved: false,
            },
          ],
          removedLenses: [],
          updatedLenses: [],
        },
        'user1',
        '192.168.1.1',
        'Mozilla'
      );

      expect(result.success).toBe(true);
      expect(result.updateId).toBeDefined();
    });

    it('should emit batch-update-completed event', () => {
      return new Promise<void>((resolve) => {
        service.once('batch-update-completed', (event) => {
          expect(event.data_object.fileId).toBe('file1');
          resolve();
        });

        service.batchUpdate(
          {
            fileId: 'file1',
            addedLenses: [
              {
                lensId: 'lens-1',
                fileId: 'file1',
                position: { line: 10, column: 5 },
                title: 'References',
                isResolved: false,
              },
            ],
            removedLenses: [],
            updatedLenses: [],
          },
          'user1',
          '192.168.1.1',
          'Mozilla'
        );
      });
    });

    it('should get file lenses', () => {
      const lenses = service.getFileLenses('file1');

      expect(Array.isArray(lenses)).toBe(true);
    });
  });

  // Command Execution Tests
  describe('Command Execution', () => {
    it('should execute command', () => {
      const created = service.createCodeLens(
        {
          fileId: 'file1',
          position: { line: 10, column: 5 },
          title: 'References',
          command: 'goto.reference',
        },
        'user1',
        '192.168.1.1',
        'Mozilla'
      );

      const result = service.executeCommand(
        created.lensId!,
        'goto.reference',
        [],
        'user1',
        '192.168.1.1',
        'Mozilla'
      );

      expect(result.success).toBe(true);
      expect(result.executionId).toBeDefined();
    });

    it('should emit command-executed event', () => {
      return new Promise<void>((resolve) => {
        const created = service.createCodeLens(
          {
            fileId: 'file1',
            position: { line: 10, column: 5 },
            title: 'References',
            command: 'goto.reference',
          },
          'user1',
          '192.168.1.1',
          'Mozilla'
        );

        service.once('command-executed', (event) => {
          expect(event.data_object.lensId).toBe(created.lensId);
          resolve();
        });

        service.executeCommand(created.lensId!, 'goto.reference', [], 'user1', '192.168.1.1', 'Mozilla');
      });
    });

    it('should get command history', () => {
      const history = service.getCommandHistory();

      expect(Array.isArray(history)).toBe(true);
    });
  });

  // Cache Management Tests
  describe('Cache Management', () => {
    it('should invalidate cache', () => {
      const result = service.invalidateCache('file1', 'file-changed', 'user1', '192.168.1.1');

      expect(result.success).toBe(true);
    });

    it('should emit cache-invalidated event', () => {
      return new Promise<void>((resolve) => {
        service.once('cache-invalidated', (event) => {
          expect(event.data_object.fileId).toBe('file1');
          resolve();
        });

        service.invalidateCache('file1', 'file-changed', 'user1', '192.168.1.1');
      });
    });

    it('should get cache hit rate', () => {
      const hitRate = service.getCacheHitRate();

      expect(typeof hitRate).toBe('number');
      expect(hitRate).toBeGreaterThanOrEqual(0);
      expect(hitRate).toBeLessThanOrEqual(1);
    });

    it('should clear cache', () => {
      const result = service.clearCache('user1', '192.168.1.1', 'Mozilla');

      expect(result.success).toBe(true);
    });

    it('should emit cache-cleared event', () => {
      return new Promise<void>((resolve) => {
        service.once('cache-cleared', (event) => {
          expect(event.data_object).toBeDefined();
          resolve();
        });

        service.clearCache('user1', '192.168.1.1', 'Mozilla');
      });
    });
  });

  // Performance Metrics Tests
  describe('Performance Metrics', () => {
    it('should get performance metrics', () => {
      const metrics = service.getPerformanceMetrics();

      expect(Array.isArray(metrics)).toBe(true);
    });

    it('should record performance metric', () => {
      service.recordPerformanceMetric({
        lensId: 'lens-1',
        resolutionTimeMs: 100,
        referenceCountTime: 50,
        totalComputeTime: 150,
      });

      const metrics = service.getPerformanceMetrics('lens-1');

      expect(Array.isArray(metrics)).toBe(true);
    });
  });

  // Statistics Tests
  describe('Statistics', () => {
    it('should calculate statistics', () => {
      service.createCodeLens(
        {
          fileId: 'file1',
          position: { line: 10, column: 5 },
          title: 'References',
        },
        'user1',
        '192.168.1.1',
        'Mozilla'
      );

      const stats = service.getStatistics();

      expect(stats).toBeDefined();
      expect(stats.totalLenses).toBeGreaterThanOrEqual(0);
    });
  });

  // Audit Logging Tests
  describe('Audit Logging', () => {
    it('should emit audit-logged event', () => {
      return new Promise<void>((resolve) => {
        service.once('audit-logged', (event) => {
          expect(event.data_object.userId).toBeDefined();
          resolve();
        });

        service.createCodeLens(
          {
            fileId: 'file1',
            position: { line: 10, column: 5 },
            title: 'References',
          },
          'user1',
          '192.168.1.1',
          'Mozilla'
        );
      });
    });

    it('should retrieve audit log', () => {
      const log = service.getAuditLog();

      expect(Array.isArray(log)).toBe(true);
    });
  });

  // Configuration Tests
  describe('Configuration', () => {
    it('should update configuration', () => {
      return new Promise<void>((resolve) => {
        service.once('config-updated', (event) => {
          expect(event.data_object.config).toBeDefined();
          resolve();
        });

        service.updateConfig({ enableCodeLens: false });
      });
    });

    it('should get configuration', () => {
      const config = service.getConfig();

      expect(config).toBeDefined();
      expect(config.enableCodeLens).toBeDefined();
    });
  });

  // Shutdown Tests
  describe('Shutdown', () => {
    it('should shutdown service cleanly', () => {
      service.shutdown();

      expect((service as any).lenses.size).toBe(0);
      expect((service as any).references.size).toBe(0);
    });
  });
});
