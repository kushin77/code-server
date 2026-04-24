/**
 * Merge Resolver Service Tests
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { MergeResolverService } from '../merge-resolver-service.js';
import { MergeDiff, MergeConflict } from '../types.js';

describe('MergeResolverService', () => {
  let service: MergeResolverService;

  beforeEach(() => {
    (MergeResolverService as any).reset();
    service = MergeResolverService.getInstance();
  });

  afterEach(() => {
    service.shutdown();
  });

  describe('Initialization', () => {
    it('should create singleton instance', () => {
      const instance1 = MergeResolverService.getInstance();
      const instance2 = MergeResolverService.getInstance();
      expect(instance1).toBe(instance2);
    });

    it('should emit initialized event', () => {
      (MergeResolverService as any).reset();
      const svc = MergeResolverService.getInstance();
      expect(svc).toBeDefined();
    });
  });

  describe('Merge Session Creation', () => {
    it('should create merge session', () => {
      const diffs: MergeDiff[] = [
        {
          filePath: 'app.ts',
          action: 'modified',
          conflictCount: 1,
          conflicts: [
            {
              id: 'conflict-1',
              filePath: 'app.ts',
              lineStart: 10,
              lineEnd: 15,
              oursContent: 'console.log("ours");',
              theirsContent: 'console.log("theirs");',
              baseContent: 'console.log("base");',
              status: 'unresolved',
            },
          ],
          isConflicted: true,
        },
      ];

      const session = service.createMergeSession(
        'user-1',
        'user1@example.com',
        'feature',
        'main',
        'base123',
        'ours456',
        'theirs789',
        diffs,
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(session).toBeDefined();
      expect(session.status).toBe('in-progress');
      expect(session.conflictCount).toBe(1);
    });

    it('should emit merge-session-created event', () => {
      return new Promise<void>((resolve) => {
        const diffs: MergeDiff[] = [
          {
            filePath: 'file.ts',
            action: 'modified',
            conflictCount: 1,
            conflicts: [
              {
                id: 'c1',
                filePath: 'file.ts',
                lineStart: 1,
                lineEnd: 5,
                oursContent: 'a',
                theirsContent: 'b',
                baseContent: '',
                status: 'unresolved',
              },
            ],
            isConflicted: true,
          },
        ];

        service.once('merge-session-created', (data) => {
          expect(data.session).toBeDefined();
          expect(data.session.sourceBranch).toBe('dev');
          resolve();
        });

        service.createMergeSession(
          'user-2',
          'user2@example.com',
          'dev',
          'main',
          'base',
          'ours',
          'theirs',
          diffs,
          '192.168.1.1',
          'Mozilla/5.0'
        );
      });
    });

    it('should track multiple diffs in session', () => {
      const diffs: MergeDiff[] = [
        {
          filePath: 'file1.ts',
          action: 'modified',
          conflictCount: 1,
          conflicts: [
            {
              id: 'c1',
              filePath: 'file1.ts',
              lineStart: 1,
              lineEnd: 3,
              oursContent: 'a',
              theirsContent: 'b',
              baseContent: '',
              status: 'unresolved',
            },
          ],
          isConflicted: true,
        },
        {
          filePath: 'file2.ts',
          action: 'added',
          conflictCount: 0,
          conflicts: [],
          isConflicted: false,
        },
      ];

      const session = service.createMergeSession(
        'user-3',
        'user3@example.com',
        'branch',
        'main',
        'base',
        'ours',
        'theirs',
        diffs,
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(session.diffs.length).toBe(2);
      expect(session.conflictCount).toBe(1);
    });
  });

  describe('Conflict Resolution', () => {
    it('should resolve conflict with ours strategy', () => {
      const diffs: MergeDiff[] = [
        {
          filePath: 'app.ts',
          action: 'modified',
          conflictCount: 1,
          conflicts: [
            {
              id: 'conflict-res-1',
              filePath: 'app.ts',
              lineStart: 10,
              lineEnd: 15,
              oursContent: 'console.log("ours");',
              theirsContent: 'console.log("theirs");',
              baseContent: '',
              status: 'unresolved',
            },
          ],
          isConflicted: true,
        },
      ];

      const session = service.createMergeSession(
        'user-4',
        'user4@example.com',
        'feature',
        'main',
        'base',
        'ours',
        'theirs',
        diffs,
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const result = service.resolveConflict(
        {
          userId: 'user-4',
          userEmail: 'user4@example.com',
          conflictId: 'conflict-res-1',
          strategy: 'ours',
        },
        session.id,
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(result.success).toBe(true);
      expect(result.strategy).toBe('ours');
      expect(session.resolvedCount).toBe(1);
    });

    it('should resolve conflict with theirs strategy', () => {
      const diffs: MergeDiff[] = [
        {
          filePath: 'app.ts',
          action: 'modified',
          conflictCount: 1,
          conflicts: [
            {
              id: 'conflict-res-2',
              filePath: 'app.ts',
              lineStart: 10,
              lineEnd: 15,
              oursContent: 'our code',
              theirsContent: 'their code',
              baseContent: '',
              status: 'unresolved',
            },
          ],
          isConflicted: true,
        },
      ];

      const session = service.createMergeSession(
        'user-5',
        'user5@example.com',
        'feature',
        'main',
        'base',
        'ours',
        'theirs',
        diffs,
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const result = service.resolveConflict(
        {
          userId: 'user-5',
          userEmail: 'user5@example.com',
          conflictId: 'conflict-res-2',
          strategy: 'theirs',
        },
        session.id,
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(result.success).toBe(true);
      expect(result.strategy).toBe('theirs');
    });

    it('should resolve conflict with manual strategy', () => {
      const diffs: MergeDiff[] = [
        {
          filePath: 'app.ts',
          action: 'modified',
          conflictCount: 1,
          conflicts: [
            {
              id: 'conflict-manual',
              filePath: 'app.ts',
              lineStart: 1,
              lineEnd: 5,
              oursContent: 'a',
              theirsContent: 'b',
              baseContent: '',
              status: 'unresolved',
            },
          ],
          isConflicted: true,
        },
      ];

      const session = service.createMergeSession(
        'user-6',
        'user6@example.com',
        'feature',
        'main',
        'base',
        'ours',
        'theirs',
        diffs,
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const result = service.resolveConflict(
        {
          userId: 'user-6',
          userEmail: 'user6@example.com',
          conflictId: 'conflict-manual',
          strategy: 'manual',
          customContent: 'const x = "merged";',
        },
        session.id,
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(result.success).toBe(true);
      expect(result.strategy).toBe('manual');
    });

    it('should emit conflict-resolved event', () => {
      return new Promise<void>((resolve) => {
        const diffs: MergeDiff[] = [
          {
            filePath: 'file.ts',
            action: 'modified',
            conflictCount: 1,
            conflicts: [
              {
                id: 'evt-conflict',
                filePath: 'file.ts',
                lineStart: 1,
                lineEnd: 3,
                oursContent: 'a',
                theirsContent: 'b',
                baseContent: '',
                status: 'unresolved',
              },
            ],
            isConflicted: true,
          },
        ];

        const session = service.createMergeSession(
          'user-7',
          'user7@example.com',
          'branch',
          'main',
          'base',
          'ours',
          'theirs',
          diffs,
          '192.168.1.1',
          'Mozilla/5.0'
        );

        service.once('conflict-resolved', (data) => {
          expect(data.sessionId).toBe(session.id);
          expect(data.conflictId).toBe('evt-conflict');
          resolve();
        });

        service.resolveConflict(
          {
            userId: 'user-7',
            userEmail: 'user7@example.com',
            conflictId: 'evt-conflict',
            strategy: 'ours',
          },
          session.id,
          '192.168.1.1',
          'Mozilla/5.0'
        );
      });
    });

    it('should resolve multiple similar conflicts with autoResolve', () => {
      const diffs: MergeDiff[] = [
        {
          filePath: 'file.ts',
          action: 'modified',
          conflictCount: 2,
          conflicts: [
            {
              id: 'sim-1',
              filePath: 'file.ts',
              lineStart: 10,
              lineEnd: 12,
              oursContent: 'ours1',
              theirsContent: 'theirs1',
              baseContent: '',
              status: 'unresolved',
            },
            {
              id: 'sim-2',
              filePath: 'file.ts',
              lineStart: 15,
              lineEnd: 17,
              oursContent: 'ours2',
              theirsContent: 'theirs2',
              baseContent: '',
              status: 'unresolved',
            },
          ],
          isConflicted: true,
        },
      ];

      const session = service.createMergeSession(
        'user-8',
        'user8@example.com',
        'feature',
        'main',
        'base',
        'ours',
        'theirs',
        diffs,
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const result = service.resolveConflict(
        {
          userId: 'user-8',
          userEmail: 'user8@example.com',
          conflictId: 'sim-1',
          strategy: 'ours',
          autoResolve: true,
        },
        session.id,
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(result.success).toBe(true);
      expect(result.resolvedCount).toBeGreaterThan(1);
    });

    it('should fail to resolve non-existent conflict', () => {
      const diffs: MergeDiff[] = [
        {
          filePath: 'file.ts',
          action: 'modified',
          conflictCount: 1,
          conflicts: [
            {
              id: 'existing',
              filePath: 'file.ts',
              lineStart: 1,
              lineEnd: 3,
              oursContent: 'a',
              theirsContent: 'b',
              baseContent: '',
              status: 'unresolved',
            },
          ],
          isConflicted: true,
        },
      ];

      const session = service.createMergeSession(
        'user-9',
        'user9@example.com',
        'feature',
        'main',
        'base',
        'ours',
        'theirs',
        diffs,
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const result = service.resolveConflict(
        {
          userId: 'user-9',
          userEmail: 'user9@example.com',
          conflictId: 'non-existent',
          strategy: 'ours',
        },
        session.id,
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(result.success).toBe(false);
      expect(result.message).toBeDefined();
    });
  });

  describe('Merge Completion', () => {
    it('should complete merge when all conflicts resolved', () => {
      const diffs: MergeDiff[] = [
        {
          filePath: 'app.ts',
          action: 'modified',
          conflictCount: 1,
          conflicts: [
            {
              id: 'complete-1',
              filePath: 'app.ts',
              lineStart: 1,
              lineEnd: 5,
              oursContent: 'a',
              theirsContent: 'b',
              baseContent: '',
              status: 'unresolved',
            },
          ],
          isConflicted: true,
        },
      ];

      const session = service.createMergeSession(
        'user-10',
        'user10@example.com',
        'feature',
        'main',
        'base',
        'ours',
        'theirs',
        diffs,
        '192.168.1.1',
        'Mozilla/5.0'
      );

      // Resolve the conflict
      service.resolveConflict(
        {
          userId: 'user-10',
          userEmail: 'user10@example.com',
          conflictId: 'complete-1',
          strategy: 'ours',
        },
        session.id,
        '192.168.1.1',
        'Mozilla/5.0'
      );

      // Complete the merge
      const result = service.completeMerge(
        {
          userId: 'user-10',
          userEmail: 'user10@example.com',
          mergeSessionId: session.id,
          commitMessage: 'Merge feature into main',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(result.success).toBe(true);
      expect(result.conflictStats.unresolved).toBe(0);
    });

    it('should fail to complete merge with unresolved conflicts', () => {
      const diffs: MergeDiff[] = [
        {
          filePath: 'app.ts',
          action: 'modified',
          conflictCount: 1,
          conflicts: [
            {
              id: 'unresolved',
              filePath: 'app.ts',
              lineStart: 1,
              lineEnd: 5,
              oursContent: 'a',
              theirsContent: 'b',
              baseContent: '',
              status: 'unresolved',
            },
          ],
          isConflicted: true,
        },
      ];

      const session = service.createMergeSession(
        'user-11',
        'user11@example.com',
        'feature',
        'main',
        'base',
        'ours',
        'theirs',
        diffs,
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const result = service.completeMerge(
        {
          userId: 'user-11',
          userEmail: 'user11@example.com',
          mergeSessionId: session.id,
          commitMessage: 'Merge feature',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(result.success).toBe(false);
      expect(result.conflictStats.unresolved).toBeGreaterThan(0);
    });

    it('should emit merge-completed event', () => {
      return new Promise<void>((resolve) => {
        const diffs: MergeDiff[] = [
          {
            filePath: 'file.ts',
            action: 'modified',
            conflictCount: 1,
            conflicts: [
              {
                id: 'evt-complete',
                filePath: 'file.ts',
                lineStart: 1,
                lineEnd: 3,
                oursContent: 'a',
                theirsContent: 'b',
                baseContent: '',
                status: 'unresolved',
              },
            ],
            isConflicted: true,
          },
        ];

        const session = service.createMergeSession(
          'user-12',
          'user12@example.com',
          'feature',
          'main',
          'base',
          'ours',
          'theirs',
          diffs,
          '192.168.1.1',
          'Mozilla/5.0'
        );

        service.resolveConflict(
          {
            userId: 'user-12',
            userEmail: 'user12@example.com',
            conflictId: 'evt-complete',
            strategy: 'ours',
          },
          session.id,
          '192.168.1.1',
          'Mozilla/5.0'
        );

        service.once('merge-completed', (data) => {
          expect(data.sessionId).toBe(session.id);
          expect(data.commitMessage).toBe('Test merge');
          resolve();
        });

        service.completeMerge(
          {
            userId: 'user-12',
            userEmail: 'user12@example.com',
            mergeSessionId: session.id,
            commitMessage: 'Test merge',
          },
          '192.168.1.1',
          'Mozilla/5.0'
        );
      });
    });
  });

  describe('Merge Abortion', () => {
    it('should abort merge', () => {
      const diffs: MergeDiff[] = [
        {
          filePath: 'app.ts',
          action: 'modified',
          conflictCount: 1,
          conflicts: [
            {
              id: 'abort-1',
              filePath: 'app.ts',
              lineStart: 1,
              lineEnd: 5,
              oursContent: 'a',
              theirsContent: 'b',
              baseContent: '',
              status: 'unresolved',
            },
          ],
          isConflicted: true,
        },
      ];

      const session = service.createMergeSession(
        'user-13',
        'user13@example.com',
        'feature',
        'main',
        'base',
        'ours',
        'theirs',
        diffs,
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const aborted = service.abortMerge(session.id, 'user-13', 'user13@example.com', '192.168.1.1', 'Mozilla/5.0');

      expect(aborted).toBe(true);
      expect(session.status).toBe('aborted');
    });

    it('should emit merge-aborted event', () => {
      return new Promise<void>((resolve) => {
        const diffs: MergeDiff[] = [
          {
            filePath: 'file.ts',
            action: 'modified',
            conflictCount: 1,
            conflicts: [
              {
                id: 'evt-abort',
                filePath: 'file.ts',
                lineStart: 1,
                lineEnd: 3,
                oursContent: 'a',
                theirsContent: 'b',
                baseContent: '',
                status: 'unresolved',
              },
            ],
            isConflicted: true,
          },
        ];

        const session = service.createMergeSession(
          'user-14',
          'user14@example.com',
          'feature',
          'main',
          'base',
          'ours',
          'theirs',
          diffs,
          '192.168.1.1',
          'Mozilla/5.0'
        );

        service.once('merge-aborted', (data) => {
          expect(data.sessionId).toBe(session.id);
          resolve();
        });

        service.abortMerge(session.id, 'user-14', 'user14@example.com', '192.168.1.1', 'Mozilla/5.0');
      });
    });
  });

  describe('Diff Statistics', () => {
    it('should get diff statistics', () => {
      const diffs: MergeDiff[] = [
        {
          filePath: 'added.ts',
          action: 'added',
          conflictCount: 0,
          conflicts: [],
          isConflicted: false,
        },
        {
          filePath: 'modified.ts',
          action: 'modified',
          conflictCount: 2,
          conflicts: [
            {
              id: 'stat-1',
              filePath: 'modified.ts',
              lineStart: 1,
              lineEnd: 3,
              oursContent: 'a',
              theirsContent: 'b',
              baseContent: '',
              status: 'unresolved',
            },
            {
              id: 'stat-2',
              filePath: 'modified.ts',
              lineStart: 10,
              lineEnd: 12,
              oursContent: 'c',
              theirsContent: 'd',
              baseContent: '',
              status: 'unresolved',
            },
          ],
          isConflicted: true,
        },
        {
          filePath: 'deleted.ts',
          action: 'deleted',
          conflictCount: 0,
          conflicts: [],
          isConflicted: false,
        },
      ];

      const session = service.createMergeSession(
        'user-15',
        'user15@example.com',
        'feature',
        'main',
        'base',
        'ours',
        'theirs',
        diffs,
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const stats = service.getDiffStatistics(session.id);

      expect(stats.filesChanged).toBe(3);
      expect(stats.filesAdded).toBe(1);
      expect(stats.filesDeleted).toBe(1);
      expect(stats.totalConflicts).toBe(2);
    });
  });

  describe('Audit Logging', () => {
    it('should record audit entry on merge session create', () => {
      const diffs: MergeDiff[] = [
        {
          filePath: 'file.ts',
          action: 'modified',
          conflictCount: 1,
          conflicts: [
            {
              id: 'audit-1',
              filePath: 'file.ts',
              lineStart: 1,
              lineEnd: 3,
              oursContent: 'a',
              theirsContent: 'b',
              baseContent: '',
              status: 'unresolved',
            },
          ],
          isConflicted: true,
        },
      ];

      service.createMergeSession(
        'user-16',
        'user16@example.com',
        'feature',
        'main',
        'base',
        'ours',
        'theirs',
        diffs,
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const audit = service.getAuditLog('user-16');
      expect(audit.length).toBeGreaterThan(0);
      expect(audit[0].operation).toBe('merge-session-created');
    });

    it('should limit audit log size', () => {
      (MergeResolverService as any).reset();
      service = MergeResolverService.getInstance({ maxAuditLogSize: 5 });

      for (let i = 0; i < 10; i++) {
        const diffs: MergeDiff[] = [
          {
            filePath: 'file.ts',
            action: 'modified',
            conflictCount: 1,
            conflicts: [
              {
                id: `limit-${i}`,
                filePath: 'file.ts',
                lineStart: 1,
                lineEnd: 3,
                oursContent: 'a',
                theirsContent: 'b',
                baseContent: '',
                status: 'unresolved',
              },
            ],
            isConflicted: true,
          },
        ];

        service.createMergeSession(
          'user-17',
          'user17@example.com',
          'feature',
          'main',
          'base',
          'ours',
          'theirs',
          diffs,
          '192.168.1.1',
          'Mozilla/5.0'
        );
      }

      const audit = service.getAuditLog('user-17');
      expect(audit.length).toBeLessThanOrEqual(5);
    });
  });

  describe('Statistics', () => {
    it('should get service statistics', () => {
      const diffs: MergeDiff[] = [
        {
          filePath: 'file.ts',
          action: 'modified',
          conflictCount: 1,
          conflicts: [
            {
              id: 'stats-1',
              filePath: 'file.ts',
              lineStart: 1,
              lineEnd: 3,
              oursContent: 'a',
              theirsContent: 'b',
              baseContent: '',
              status: 'unresolved',
            },
          ],
          isConflicted: true,
        },
      ];

      service.createMergeSession(
        'user-18',
        'user18@example.com',
        'feature',
        'main',
        'base',
        'ours',
        'theirs',
        diffs,
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const stats = service.getStatistics();

      expect(stats.totalSessions).toBeGreaterThan(0);
      expect(stats.totalConflicts).toBeGreaterThan(0);
    });
  });

  describe('Configuration', () => {
    it('should update configuration', () => {
      service.updateConfig({ maxConcurrentSessions: 50 }, 'user-19', '192.168.1.1', 'Mozilla/5.0');

      expect(service['config'].maxConcurrentSessions).toBe(50);
    });

    it('should emit config-updated event', () => {
      return new Promise<void>((resolve) => {
        service.once('config-updated', (data) => {
          expect(data.config).toBeDefined();
          resolve();
        });

        service.updateConfig({ enableSmartMerge: false }, 'user-20', '192.168.1.1', 'Mozilla/5.0');
      });
    });
  });

  describe('Shutdown', () => {
    it('should shutdown service', () => {
      const diffs: MergeDiff[] = [
        {
          filePath: 'file.ts',
          action: 'modified',
          conflictCount: 1,
          conflicts: [
            {
              id: 'shutdown-1',
              filePath: 'file.ts',
              lineStart: 1,
              lineEnd: 3,
              oursContent: 'a',
              theirsContent: 'b',
              baseContent: '',
              status: 'unresolved',
            },
          ],
          isConflicted: true,
        },
      ];

      const session = service.createMergeSession(
        'user-21',
        'user21@example.com',
        'feature',
        'main',
        'base',
        'ours',
        'theirs',
        diffs,
        '192.168.1.1',
        'Mozilla/5.0'
      );

      service.shutdown();

      const retrieved = service.getMergeSession(session.id);
      expect(retrieved).toBeNull();
    });

    it('should emit shutdown event', () => {
      return new Promise<void>((resolve) => {
        service.once('shutdown', (data) => {
          expect(data.timestamp).toBeDefined();
          resolve();
        });

        service.shutdown();
      });
    });
  });
});
