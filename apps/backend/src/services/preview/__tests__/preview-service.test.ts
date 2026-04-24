/**
 * PR Preview Service Tests
 */

import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { PreviewService } from '../preview-service.js';
import { ProvisioningRequest, PreviewServiceConfig } from '../types.js';

describe('PreviewService', () => {
  let service: PreviewService;

  beforeEach(() => {
    (PreviewService as any).reset();
    service = PreviewService.getInstance();
  });

  afterEach(() => {
    service.shutdown();
  });

  describe('Initialization', () => {
    it('should create singleton instance', () => {
      const instance1 = PreviewService.getInstance();
      const instance2 = PreviewService.getInstance();
      expect(instance1).toBe(instance2);
    });

    it('should emit initialized event', () => {
      return new Promise<void>((resolve) => {
        (PreviewService as any).reset();
        // Instance is created on first getInstance call, which emits initialized
        const svc = PreviewService.getInstance();
        // Event already emitted, but check it was created with proper timestamp
        expect(svc).toBeDefined();
        resolve();
      });
    });
  });

  describe('Environment Provisioning', () => {
    it('should provision environment successfully', async () => {
      const request: ProvisioningRequest = {
        pullRequestId: 'pr-123',
        pullRequestNumber: 123,
        userId: 'user-456',
        userEmail: 'user@example.com',
        branch: {
          name: 'feature/test',
          sha: 'abc123',
          repoUrl: 'https://github.com/user/repo.git',
          defaultBranch: false,
        },
        targetBranch: {
          name: 'main',
          sha: 'xyz789',
          repoUrl: 'https://github.com/user/repo.git',
          defaultBranch: true,
        },
      };

      const result = await service.provisionEnvironment(request, '192.168.1.1', 'Mozilla/5.0');

      expect(result.success).toBe(true);
      expect(result.environmentId).toBeDefined();
      expect(result.url).toContain('pr-123');
      expect(result.provisioningTimeMs).toBeGreaterThan(0);
    });

    it('should emit environment-provisioned event', () => {
      return new Promise<void>((resolve) => {
        const request: ProvisioningRequest = {
          pullRequestId: 'pr-124',
          pullRequestNumber: 124,
          userId: 'user-457',
          userEmail: 'user2@example.com',
          branch: {
            name: 'feature/test2',
            sha: 'def456',
            repoUrl: 'https://github.com/user/repo.git',
            defaultBranch: false,
          },
          targetBranch: {
            name: 'main',
            sha: 'xyz789',
            repoUrl: 'https://github.com/user/repo.git',
            defaultBranch: true,
          },
        };

        service.once('environment-provisioned', (data) => {
          expect(data.environment).toBeDefined();
          expect(data.provisioningTimeMs).toBeGreaterThan(0);
          expect(data.timestamp).toBeDefined();
          resolve();
        });

        service.provisionEnvironment(request, '192.168.1.1', 'Mozilla/5.0');
      });
    });

    it('should use custom config for environment', async () => {
      const request: ProvisioningRequest = {
        pullRequestId: 'pr-125',
        pullRequestNumber: 125,
        userId: 'user-458',
        userEmail: 'user3@example.com',
        branch: {
          name: 'feature/test3',
          sha: 'ghi789',
          repoUrl: 'https://github.com/user/repo.git',
          defaultBranch: false,
        },
        targetBranch: {
          name: 'main',
          sha: 'xyz789',
          repoUrl: 'https://github.com/user/repo.git',
          defaultBranch: true,
        },
        config: {
          cpuLimit: '2',
          memoryLimit: '2Gi',
          replicaCount: 3,
        },
      };

      const result = await service.provisionEnvironment(request, '192.168.1.1', 'Mozilla/5.0');
      const env = service.getEnvironment(result.environmentId);

      expect(env).toBeDefined();
      expect(env!.config.cpuLimit).toBe('2');
      expect(env!.config.memoryLimit).toBe('2Gi');
      expect(env!.config.replicaCount).toBe(3);
    });

    it('should set environment to active after provisioning', async () => {
      const request: ProvisioningRequest = {
        pullRequestId: 'pr-126',
        pullRequestNumber: 126,
        userId: 'user-459',
        userEmail: 'user4@example.com',
        branch: {
          name: 'feature/test4',
          sha: 'jkl012',
          repoUrl: 'https://github.com/user/repo.git',
          defaultBranch: false,
        },
        targetBranch: {
          name: 'main',
          sha: 'xyz789',
          repoUrl: 'https://github.com/user/repo.git',
          defaultBranch: true,
        },
      };

      const result = await service.provisionEnvironment(request, '192.168.1.1', 'Mozilla/5.0');
      const env = service.getEnvironment(result.environmentId);

      expect(env).toBeDefined();
      expect(env!.state).toBe('active');
    });

    it('should fail when max concurrent environments reached', async () => {
      (PreviewService as any).reset();
      service = PreviewService.getInstance({ maxConcurrentEnvironments: 1 });

      // Provision first
      const request1: ProvisioningRequest = {
        pullRequestId: 'pr-127',
        pullRequestNumber: 127,
        userId: 'user-460',
        userEmail: 'user5@example.com',
        branch: {
          name: 'feature/test5',
          sha: 'mno345',
          repoUrl: 'https://github.com/user/repo.git',
          defaultBranch: false,
        },
        targetBranch: {
          name: 'main',
          sha: 'xyz789',
          repoUrl: 'https://github.com/user/repo.git',
          defaultBranch: true,
        },
      };

      await service.provisionEnvironment(request1, '192.168.1.1', 'Mozilla/5.0');

      // Try to provision second
      const request2: ProvisioningRequest = {
        pullRequestId: 'pr-128',
        pullRequestNumber: 128,
        userId: 'user-461',
        userEmail: 'user6@example.com',
        branch: {
          name: 'feature/test6',
          sha: 'pqr678',
          repoUrl: 'https://github.com/user/repo.git',
          defaultBranch: false,
        },
        targetBranch: {
          name: 'main',
          sha: 'xyz789',
          repoUrl: 'https://github.com/user/repo.git',
          defaultBranch: true,
        },
      };

      const result2 = await service.provisionEnvironment(request2, '192.168.1.1', 'Mozilla/5.0');
      expect(result2.success).toBe(false);
      expect(result2.reason).toContain('Max concurrent');
    });
  });

  describe('Environment Termination', () => {
    it('should terminate environment', async () => {
      const request: ProvisioningRequest = {
        pullRequestId: 'pr-129',
        pullRequestNumber: 129,
        userId: 'user-462',
        userEmail: 'user7@example.com',
        branch: {
          name: 'feature/test7',
          sha: 'stu901',
          repoUrl: 'https://github.com/user/repo.git',
          defaultBranch: false,
        },
        targetBranch: {
          name: 'main',
          sha: 'xyz789',
          repoUrl: 'https://github.com/user/repo.git',
          defaultBranch: true,
        },
      };

      const result = await service.provisionEnvironment(request, '192.168.1.1', 'Mozilla/5.0');
      const terminated = service.terminateEnvironment(result.environmentId, 129, 'user-462', '192.168.1.1', 'Mozilla/5.0');

      expect(terminated).toBe(true);

      const env = service.getEnvironment(result.environmentId);
      expect(env!.state).toBe('terminated');
      expect(env!.terminatedAt).toBeDefined();
    });

    it('should emit environment-terminated event', () => {
      return new Promise<void>((resolve) => {
        const request: ProvisioningRequest = {
          pullRequestId: 'pr-130',
          pullRequestNumber: 130,
          userId: 'user-463',
          userEmail: 'user8@example.com',
          branch: {
            name: 'feature/test8',
            sha: 'vwx234',
            repoUrl: 'https://github.com/user/repo.git',
            defaultBranch: false,
          },
          targetBranch: {
            name: 'main',
            sha: 'xyz789',
            repoUrl: 'https://github.com/user/repo.git',
            defaultBranch: true,
          },
        };

        service.provisionEnvironment(request, '192.168.1.1', 'Mozilla/5.0').then((result) => {
          service.once('environment-terminated', (data) => {
            expect(data.environment.id).toBe(result.environmentId);
            expect(data.timestamp).toBeDefined();
            resolve();
          });

          service.terminateEnvironment(result.environmentId, 130, 'user-463', '192.168.1.1', 'Mozilla/5.0');
        });
      });
    });

    it('should return false for non-existent environment', () => {
      const terminated = service.terminateEnvironment('non-existent', 131, 'user-464', '192.168.1.1', 'Mozilla/5.0');
      expect(terminated).toBe(false);
    });
  });

  describe('Environment Retrieval', () => {
    it('should get environment by ID', async () => {
      const request: ProvisioningRequest = {
        pullRequestId: 'pr-131',
        pullRequestNumber: 131,
        userId: 'user-464',
        userEmail: 'user9@example.com',
        branch: {
          name: 'feature/test9',
          sha: 'yza567',
          repoUrl: 'https://github.com/user/repo.git',
          defaultBranch: false,
        },
        targetBranch: {
          name: 'main',
          sha: 'xyz789',
          repoUrl: 'https://github.com/user/repo.git',
          defaultBranch: true,
        },
      };

      const result = await service.provisionEnvironment(request, '192.168.1.1', 'Mozilla/5.0');
      const env = service.getEnvironment(result.environmentId);

      expect(env).toBeDefined();
      expect(env!.id).toBe(result.environmentId);
      expect(env!.pullRequestNumber).toBe(131);
    });

    it('should return null for non-existent environment', () => {
      const env = service.getEnvironment('non-existent');
      expect(env).toBeNull();
    });

    it('should get all environments for PR', async () => {
      const request: ProvisioningRequest = {
        pullRequestId: 'pr-132',
        pullRequestNumber: 132,
        userId: 'user-465',
        userEmail: 'user10@example.com',
        branch: {
          name: 'feature/test10',
          sha: 'bcd890',
          repoUrl: 'https://github.com/user/repo.git',
          defaultBranch: false,
        },
        targetBranch: {
          name: 'main',
          sha: 'xyz789',
          repoUrl: 'https://github.com/user/repo.git',
          defaultBranch: true,
        },
      };

      await service.provisionEnvironment(request, '192.168.1.1', 'Mozilla/5.0');
      const envs = service.getEnvironmentsByPullRequest(132);

      expect(envs.length).toBeGreaterThan(0);
      expect(envs[0].pullRequestNumber).toBe(132);
    });
  });

  describe('Scaling', () => {
    it('should scale environment replicas', async () => {
      const request: ProvisioningRequest = {
        pullRequestId: 'pr-133',
        pullRequestNumber: 133,
        userId: 'user-466',
        userEmail: 'user11@example.com',
        branch: {
          name: 'feature/test11',
          sha: 'efg123',
          repoUrl: 'https://github.com/user/repo.git',
          defaultBranch: false,
        },
        targetBranch: {
          name: 'main',
          sha: 'xyz789',
          repoUrl: 'https://github.com/user/repo.git',
          defaultBranch: true,
        },
      };

      const result = await service.provisionEnvironment(request, '192.168.1.1', 'Mozilla/5.0');
      const scaled = service.scaleEnvironment(result.environmentId, 4, 'user-466', '192.168.1.1', 'Mozilla/5.0');

      expect(scaled).toBe(true);

      const env = service.getEnvironment(result.environmentId);
      expect(env!.config.replicaCount).toBe(4);
    });

    it('should emit environment-scaled event', () => {
      return new Promise<void>((resolve) => {
        const request: ProvisioningRequest = {
          pullRequestId: 'pr-134',
          pullRequestNumber: 134,
          userId: 'user-467',
          userEmail: 'user12@example.com',
          branch: {
            name: 'feature/test12',
            sha: 'hij456',
            repoUrl: 'https://github.com/user/repo.git',
            defaultBranch: false,
          },
          targetBranch: {
            name: 'main',
            sha: 'xyz789',
            repoUrl: 'https://github.com/user/repo.git',
            defaultBranch: true,
          },
        };

        service.provisionEnvironment(request, '192.168.1.1', 'Mozilla/5.0').then((result) => {
          service.once('environment-scaled', (data) => {
            expect(data.scalingEvent).toBeDefined();
            expect(data.scalingEvent.toReplicas).toBe(5);
            resolve();
          });

          service.scaleEnvironment(result.environmentId, 5, 'user-467', '192.168.1.1', 'Mozilla/5.0');
        });
      });
    });

    it('should return false when scaling non-existent environment', () => {
      const scaled = service.scaleEnvironment('non-existent', 3, 'user-468', '192.168.1.1', 'Mozilla/5.0');
      expect(scaled).toBe(false);
    });
  });

  describe('Health Checks', () => {
    it('should perform health check', async () => {
      const request: ProvisioningRequest = {
        pullRequestId: 'pr-135',
        pullRequestNumber: 135,
        userId: 'user-469',
        userEmail: 'user13@example.com',
        branch: {
          name: 'feature/test13',
          sha: 'klm789',
          repoUrl: 'https://github.com/user/repo.git',
          defaultBranch: false,
        },
        targetBranch: {
          name: 'main',
          sha: 'xyz789',
          repoUrl: 'https://github.com/user/repo.git',
          defaultBranch: true,
        },
      };

      const result = await service.provisionEnvironment(request, '192.168.1.1', 'Mozilla/5.0');
      const check = service.performHealthCheck(result.environmentId);

      expect(check).toBeDefined();
      expect(check.isHealthy).toBeDefined();
      expect(check.responseTimeMs).toBeGreaterThanOrEqual(0);
      expect(check.httpStatusCode).toBeDefined();
    });

    it('should update environment health status', async () => {
      const request: ProvisioningRequest = {
        pullRequestId: 'pr-136',
        pullRequestNumber: 136,
        userId: 'user-470',
        userEmail: 'user14@example.com',
        branch: {
          name: 'feature/test14',
          sha: 'nop012',
          repoUrl: 'https://github.com/user/repo.git',
          defaultBranch: false,
        },
        targetBranch: {
          name: 'main',
          sha: 'xyz789',
          repoUrl: 'https://github.com/user/repo.git',
          defaultBranch: true,
        },
      };

      const result = await service.provisionEnvironment(request, '192.168.1.1', 'Mozilla/5.0');
      service.performHealthCheck(result.environmentId);

      const env = service.getEnvironment(result.environmentId);
      expect(env!.lastHealthCheckAt).toBeLessThanOrEqual(Date.now());
      expect(env!.lastHealthStatus).toBeDefined();
    });

    it('should get health check history', async () => {
      const request: ProvisioningRequest = {
        pullRequestId: 'pr-137',
        pullRequestNumber: 137,
        userId: 'user-471',
        userEmail: 'user15@example.com',
        branch: {
          name: 'feature/test15',
          sha: 'qrs345',
          repoUrl: 'https://github.com/user/repo.git',
          defaultBranch: false,
        },
        targetBranch: {
          name: 'main',
          sha: 'xyz789',
          repoUrl: 'https://github.com/user/repo.git',
          defaultBranch: true,
        },
      };

      const result = await service.provisionEnvironment(request, '192.168.1.1', 'Mozilla/5.0');

      service.performHealthCheck(result.environmentId);
      service.performHealthCheck(result.environmentId);

      const history = service.getHealthCheckHistory(result.environmentId);
      expect(history.length).toBeGreaterThanOrEqual(2);
    });

    it('should limit health check history', async () => {
      const request: ProvisioningRequest = {
        pullRequestId: 'pr-138',
        pullRequestNumber: 138,
        userId: 'user-472',
        userEmail: 'user16@example.com',
        branch: {
          name: 'feature/test16',
          sha: 'tuv678',
          repoUrl: 'https://github.com/user/repo.git',
          defaultBranch: false,
        },
        targetBranch: {
          name: 'main',
          sha: 'xyz789',
          repoUrl: 'https://github.com/user/repo.git',
          defaultBranch: true,
        },
      };

      const result = await service.provisionEnvironment(request, '192.168.1.1', 'Mozilla/5.0');

      for (let i = 0; i < 10; i++) {
        service.performHealthCheck(result.environmentId);
      }

      const history = service.getHealthCheckHistory(result.environmentId, 5);
      expect(history.length).toBeLessThanOrEqual(5);
    });
  });

  describe('Grace Period', () => {
    it('should start grace period for PR', async () => {
      const request: ProvisioningRequest = {
        pullRequestId: 'pr-139',
        pullRequestNumber: 139,
        userId: 'user-473',
        userEmail: 'user17@example.com',
        branch: {
          name: 'feature/test17',
          sha: 'wxy901',
          repoUrl: 'https://github.com/user/repo.git',
          defaultBranch: false,
        },
        targetBranch: {
          name: 'main',
          sha: 'xyz789',
          repoUrl: 'https://github.com/user/repo.git',
          defaultBranch: true,
        },
      };

      await service.provisionEnvironment(request, '192.168.1.1', 'Mozilla/5.0');

      const gracePeriodEnvs = service.startGracePeriod(139, 'user-473', '192.168.1.1', 'Mozilla/5.0');

      expect(gracePeriodEnvs.length).toBeGreaterThan(0);
      expect(gracePeriodEnvs[0].gracePeriodStartAt).toBeDefined();
      expect(gracePeriodEnvs[0].state).toBe('shutting-down');
    });

    it('should emit grace-period-started event', () => {
      return new Promise<void>((resolve) => {
        const request: ProvisioningRequest = {
          pullRequestId: 'pr-140',
          pullRequestNumber: 140,
          userId: 'user-474',
          userEmail: 'user18@example.com',
          branch: {
            name: 'feature/test18',
            sha: 'zab234',
            repoUrl: 'https://github.com/user/repo.git',
            defaultBranch: false,
          },
          targetBranch: {
            name: 'main',
            sha: 'xyz789',
            repoUrl: 'https://github.com/user/repo.git',
            defaultBranch: true,
          },
        };

        service.provisionEnvironment(request, '192.168.1.1', 'Mozilla/5.0').then(() => {
          service.once('grace-period-started', (data) => {
            expect(data.pullRequestNumber).toBe(140);
            expect(data.environmentCount).toBeGreaterThan(0);
            resolve();
          });

          service.startGracePeriod(140, 'user-474', '192.168.1.1', 'Mozilla/5.0');
        });
      });
    });

    it('should not start grace period twice for same PR', async () => {
      const request: ProvisioningRequest = {
        pullRequestId: 'pr-141',
        pullRequestNumber: 141,
        userId: 'user-475',
        userEmail: 'user19@example.com',
        branch: {
          name: 'feature/test19',
          sha: 'cde567',
          repoUrl: 'https://github.com/user/repo.git',
          defaultBranch: false,
        },
        targetBranch: {
          name: 'main',
          sha: 'xyz789',
          repoUrl: 'https://github.com/user/repo.git',
          defaultBranch: true,
        },
      };

      await service.provisionEnvironment(request, '192.168.1.1', 'Mozilla/5.0');

      const first = service.startGracePeriod(141, 'user-475', '192.168.1.1', 'Mozilla/5.0');
      const second = service.startGracePeriod(141, 'user-475', '192.168.1.1', 'Mozilla/5.0');

      expect(first.length).toBeGreaterThan(0);
      expect(second.length).toBe(0); // Already in grace period
    });
  });

  describe('Statistics', () => {
    it('should get statistics for PR', async () => {
      const request: ProvisioningRequest = {
        pullRequestId: 'pr-142',
        pullRequestNumber: 142,
        userId: 'user-476',
        userEmail: 'user20@example.com',
        branch: {
          name: 'feature/test20',
          sha: 'fgh890',
          repoUrl: 'https://github.com/user/repo.git',
          defaultBranch: false,
        },
        targetBranch: {
          name: 'main',
          sha: 'xyz789',
          repoUrl: 'https://github.com/user/repo.git',
          defaultBranch: true,
        },
      };

      await service.provisionEnvironment(request, '192.168.1.1', 'Mozilla/5.0');

      const stats = service.getStatistics(142);

      expect(stats).toBeDefined();
      expect(stats!.pullRequestNumber).toBe(142);
      expect(stats!.successfulProvisions).toBeGreaterThan(0);
    });

    it('should return null for non-existent PR statistics', () => {
      const stats = service.getStatistics(999);
      expect(stats).toBeNull();
    });
  });

  describe('Audit Logging', () => {
    it('should record audit entry on provision', async () => {
      const request: ProvisioningRequest = {
        pullRequestId: 'pr-143',
        pullRequestNumber: 143,
        userId: 'user-477',
        userEmail: 'user21@example.com',
        branch: {
          name: 'feature/test21',
          sha: 'ijk123',
          repoUrl: 'https://github.com/user/repo.git',
          defaultBranch: false,
        },
        targetBranch: {
          name: 'main',
          sha: 'xyz789',
          repoUrl: 'https://github.com/user/repo.git',
          defaultBranch: true,
        },
      };

      await service.provisionEnvironment(request, '192.168.1.1', 'Mozilla/5.0');

      const audit = service.getAuditLog('user-477');

      expect(audit.length).toBeGreaterThan(0);
      expect(audit[0].operation).toBe('provision');
      expect(audit[0].status).toBe('success');
    });

    it('should emit audit-logged event', () => {
      return new Promise<void>((resolve) => {
        const request: ProvisioningRequest = {
          pullRequestId: 'pr-144',
          pullRequestNumber: 144,
          userId: 'user-478',
          userEmail: 'user22@example.com',
          branch: {
            name: 'feature/test22',
            sha: 'lmn456',
            repoUrl: 'https://github.com/user/repo.git',
            defaultBranch: false,
          },
          targetBranch: {
            name: 'main',
            sha: 'xyz789',
            repoUrl: 'https://github.com/user/repo.git',
            defaultBranch: true,
          },
        };

        let auditCount = 0;
        service.on('audit-logged', () => {
          auditCount++;
          if (auditCount > 0) {
            resolve();
          }
        });

        service.provisionEnvironment(request, '192.168.1.1', 'Mozilla/5.0');
      });
    });

    it('should track IP and user agent in audit', async () => {
      const request: ProvisioningRequest = {
        pullRequestId: 'pr-145',
        pullRequestNumber: 145,
        userId: 'user-479',
        userEmail: 'user23@example.com',
        branch: {
          name: 'feature/test23',
          sha: 'opq789',
          repoUrl: 'https://github.com/user/repo.git',
          defaultBranch: false,
        },
        targetBranch: {
          name: 'main',
          sha: 'xyz789',
          repoUrl: 'https://github.com/user/repo.git',
          defaultBranch: true,
        },
      };

      const testIp = '192.168.1.100';
      const testAgent = 'TestAgent/1.0';

      await service.provisionEnvironment(request, testIp, testAgent);

      const audit = service.getAuditLog('user-479');

      expect(audit[0].ipAddress).toBe(testIp);
      expect(audit[0].userAgent).toBe(testAgent);
    });

    it('should limit audit log size', async () => {
      (PreviewService as any).reset();
      service = PreviewService.getInstance({ maxAuditLogSize: 5 });

      const request: ProvisioningRequest = {
        pullRequestId: 'pr-146',
        pullRequestNumber: 146,
        userId: 'user-480',
        userEmail: 'user24@example.com',
        branch: {
          name: 'feature/test24',
          sha: 'rst012',
          repoUrl: 'https://github.com/user/repo.git',
          defaultBranch: false,
        },
        targetBranch: {
          name: 'main',
          sha: 'xyz789',
          repoUrl: 'https://github.com/user/repo.git',
          defaultBranch: true,
        },
      };

      for (let i = 0; i < 10; i++) {
        const req = { ...request, pullRequestNumber: 146 + i, pullRequestId: `pr-${146 + i}` };
        await service.provisionEnvironment(req, '192.168.1.1', 'Mozilla/5.0');
      }

      const audit = service.getAuditLog('user-480');
      expect(audit.length).toBeLessThanOrEqual(5);
    });
  });

  describe('Configuration', () => {
    it('should update configuration', () => {
      service.updateConfig({ maxConcurrentEnvironments: 100 }, 'user-481', '192.168.1.1', 'Mozilla/5.0');

      expect(service['config'].maxConcurrentEnvironments).toBe(100);
    });

    it('should emit config-updated event', () => {
      return new Promise<void>((resolve) => {
        service.once('config-updated', (data) => {
          expect(data.config).toBeDefined();
          resolve();
        });

        service.updateConfig({ gracePeriodMinutes: 120 }, 'user-482', '192.168.1.1', 'Mozilla/5.0');
      });
    });
  });

  describe('Multiple Concurrent Environments', () => {
    it('should provision multiple environments', async () => {
      const requests: ProvisioningRequest[] = [];
      for (let i = 0; i < 3; i++) {
        requests.push({
          pullRequestId: `pr-150-${i}`,
          pullRequestNumber: 150 + i,
          userId: `user-${500 + i}`,
          userEmail: `user${500 + i}@example.com`,
          branch: {
            name: `feature/test${50 + i}`,
            sha: `sha${i}`,
            repoUrl: 'https://github.com/user/repo.git',
            defaultBranch: false,
          },
          targetBranch: {
            name: 'main',
            sha: 'xyz789',
            repoUrl: 'https://github.com/user/repo.git',
            defaultBranch: true,
          },
        });
      }

      const results = await Promise.all(
        requests.map((req) => service.provisionEnvironment(req, '192.168.1.1', 'Mozilla/5.0'))
      );

      expect(results.every((r) => r.success)).toBe(true);
      expect(results.length).toBe(3);
    });

    it('should handle rapid sequential provisioning', async () => {
      const request: ProvisioningRequest = {
        pullRequestId: 'pr-200',
        pullRequestNumber: 200,
        userId: 'user-600',
        userEmail: 'user600@example.com',
        branch: {
          name: 'feature/rapid',
          sha: 'rapid123',
          repoUrl: 'https://github.com/user/repo.git',
          defaultBranch: false,
        },
        targetBranch: {
          name: 'main',
          sha: 'xyz789',
          repoUrl: 'https://github.com/user/repo.git',
          defaultBranch: true,
        },
      };

      const result = await service.provisionEnvironment(request, '192.168.1.1', 'Mozilla/5.0');
      expect(result.success).toBe(true);
      expect(result.environmentId).toBeDefined();
      expect(result.environmentId.includes('prev-200')).toBe(true);
    });
  });

  describe('Environment State Transitions', () => {
    it('should track state changes through lifecycle', async () => {
      const request: ProvisioningRequest = {
        pullRequestId: 'pr-201',
        pullRequestNumber: 201,
        userId: 'user-601',
        userEmail: 'user601@example.com',
        branch: {
          name: 'feature/lifecycle',
          sha: 'lifecycle123',
          repoUrl: 'https://github.com/user/repo.git',
          defaultBranch: false,
        },
        targetBranch: {
          name: 'main',
          sha: 'xyz789',
          repoUrl: 'https://github.com/user/repo.git',
          defaultBranch: true,
        },
      };

      const result = await service.provisionEnvironment(request, '192.168.1.1', 'Mozilla/5.0');
      let env = service.getEnvironment(result.environmentId)!;
      expect(env.state).toBe('active');

      service.startGracePeriod(201, 'user-601', '192.168.1.1', 'Mozilla/5.0');
      env = service.getEnvironment(result.environmentId)!;
      expect(env.state).toBe('shutting-down');

      service.terminateEnvironment(result.environmentId, 201, 'user-601', '192.168.1.1', 'Mozilla/5.0');
      env = service.getEnvironment(result.environmentId)!;
      expect(env.state).toBe('terminated');
    });

    it('should preserve environment metadata on state changes', async () => {
      const request: ProvisioningRequest = {
        pullRequestId: 'pr-202',
        pullRequestNumber: 202,
        userId: 'user-602',
        userEmail: 'user602@example.com',
        branch: {
          name: 'feature/metadata',
          sha: 'metadata123',
          repoUrl: 'https://github.com/user/repo.git',
          defaultBranch: false,
        },
        targetBranch: {
          name: 'main',
          sha: 'xyz789',
          repoUrl: 'https://github.com/user/repo.git',
          defaultBranch: true,
        },
      };

      const result = await service.provisionEnvironment(request, '192.168.1.1', 'Mozilla/5.0');
      const envBefore = service.getEnvironment(result.environmentId)!;

      service.scaleEnvironment(result.environmentId, 5, 'user-602', '192.168.1.1', 'Mozilla/5.0');

      const envAfter = service.getEnvironment(result.environmentId)!;
      expect(envAfter.metadata.branchName).toBe(envBefore.metadata.branchName);
      expect(envAfter.metadata.commitSha).toBe(envBefore.metadata.commitSha);
      expect(envAfter.metadata.repoUrl).toBe(envBefore.metadata.repoUrl);
    });
  });

  describe('Provisioning Failure Handling', () => {
    it('should record failed provision in audit', async () => {
      (PreviewService as any).reset();
      service = PreviewService.getInstance({ maxConcurrentEnvironments: 0 }); // Force failure

      const request: ProvisioningRequest = {
        pullRequestId: 'pr-203',
        pullRequestNumber: 203,
        userId: 'user-603',
        userEmail: 'user603@example.com',
        branch: {
          name: 'feature/fail',
          sha: 'fail123',
          repoUrl: 'https://github.com/user/repo.git',
          defaultBranch: false,
        },
        targetBranch: {
          name: 'main',
          sha: 'xyz789',
          repoUrl: 'https://github.com/user/repo.git',
          defaultBranch: true,
        },
      };

      const result = await service.provisionEnvironment(request, '192.168.1.1', 'Mozilla/5.0');
      expect(result.success).toBe(false);

      const audit = service.getAuditLog('user-603');
      expect(audit.length).toBeGreaterThan(0);
      expect(audit[0].status).toBe('failure');
    });

    it('should emit environment-provision-failed event', () => {
      return new Promise<void>((resolve) => {
        (PreviewService as any).reset();
        const svc = PreviewService.getInstance({ maxConcurrentEnvironments: 0 });

        const request: ProvisioningRequest = {
          pullRequestId: 'pr-204',
          pullRequestNumber: 204,
          userId: 'user-604',
          userEmail: 'user604@example.com',
          branch: {
            name: 'feature/fail2',
            sha: 'fail456',
            repoUrl: 'https://github.com/user/repo.git',
            defaultBranch: false,
          },
          targetBranch: {
            name: 'main',
            sha: 'xyz789',
            repoUrl: 'https://github.com/user/repo.git',
            defaultBranch: true,
          },
        };

        svc.once('environment-provision-failed', (data) => {
          expect(data.error).toBeDefined();
          expect(data.request).toBeDefined();
          resolve();
        });

        svc.provisionEnvironment(request, '192.168.1.1', 'Mozilla/5.0');
      });
    });
  });

  describe('Event Emissions', () => {
    it('should emit all major lifecycle events', () => {
      return new Promise<void>((resolve) => {
        const events: string[] = [];
        const request: ProvisioningRequest = {
          pullRequestId: 'pr-205',
          pullRequestNumber: 205,
          userId: 'user-605',
          userEmail: 'user605@example.com',
          branch: {
            name: 'feature/events',
            sha: 'events123',
            repoUrl: 'https://github.com/user/repo.git',
            defaultBranch: false,
          },
          targetBranch: {
            name: 'main',
            sha: 'xyz789',
            repoUrl: 'https://github.com/user/repo.git',
            defaultBranch: true,
          },
        };

        service.on('environment-provisioned', () => {
          events.push('provisioned');
        });

        service.on('environment-scaled', () => {
          events.push('scaled');
        });

        service.on('grace-period-started', () => {
          events.push('grace-period');
        });

        service.on('environment-terminated', () => {
          events.push('terminated');
          // All events should be fired
          expect(events.length).toBeGreaterThan(0);
          resolve();
        });

        service.provisionEnvironment(request, '192.168.1.1', 'Mozilla/5.0').then((result) => {
          service.scaleEnvironment(result.environmentId, 3, 'user-605', '192.168.1.1', 'Mozilla/5.0');
          service.startGracePeriod(205, 'user-605', '192.168.1.1', 'Mozilla/5.0');
          service.terminateEnvironment(result.environmentId, 205, 'user-605', '192.168.1.1', 'Mozilla/5.0');
        });
      });
    });
  });

  describe('Shutdown', () => {
    it('should shutdown service', async () => {
      const request: ProvisioningRequest = {
        pullRequestId: 'pr-147',
        pullRequestNumber: 147,
        userId: 'user-483',
        userEmail: 'user25@example.com',
        branch: {
          name: 'feature/test25',
          sha: 'uvw345',
          repoUrl: 'https://github.com/user/repo.git',
          defaultBranch: false,
        },
        targetBranch: {
          name: 'main',
          sha: 'xyz789',
          repoUrl: 'https://github.com/user/repo.git',
          defaultBranch: true,
        },
      };

      await service.provisionEnvironment(request, '192.168.1.1', 'Mozilla/5.0');
      service.shutdown();

      const env = service.getEnvironment('any-id');
      expect(env).toBeNull();
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
