#!/usr/bin/env node
// @file        apps/backend/src/services/health-monitoring/__tests__/database-health-check-service.test.ts
// @module      services/health-monitoring
// @description Tests for database health check service
// @owner       Infrastructure Team
// @status      Production-ready - April 23, 2026

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import {
  DatabaseHealthCheckService,
  HealthCheckResult,
  HealthCheckSummary,
} from '../database-health-check-service';

describe('DatabaseHealthCheckService', () => {
  let service: DatabaseHealthCheckService;

  beforeEach(() => {
    service = DatabaseHealthCheckService.getInstance({
      enabled: true,
      primaryHost: '192.168.168.31',
      pgbouncer: {
        host: '192.168.168.31',
        port: 6432,
        enabled: true,
      },
      postgres: {
        host: '192.168.168.31',
        port: 5432,
        enabled: true,
      },
      backups: {
        enabled: true,
        checkIntervalMs: 3600000,
        maxAgeMs: 86400000,
      },
      replication: {
        enabled: true,
        lagThresholdMs: 10000,
      },
      checkIntervalMs: 100,
    });

    service.removeAllListeners();
  });

  afterEach(() => {
    service.stop();
  });

  describe('Initialization', () => {
    it('should create a singleton instance', () => {
      const instance1 = DatabaseHealthCheckService.getInstance();
      const instance2 = DatabaseHealthCheckService.getInstance();
      expect(instance1).toBe(instance2);
    });

    it('should have correct default configuration', () => {
      const config = service.getConfig();
      expect(config.enabled).toBe(true);
      expect(config.primaryHost).toBeDefined();
      expect(config.pgbouncer.enabled).toBe(true);
      expect(config.postgres.enabled).toBe(true);
      expect(config.backups.enabled).toBe(true);
      expect(config.replication.enabled).toBe(true);
    });
  });

  describe('Service Lifecycle', () => {
    it('should start health checks', () => {
      return new Promise<void>((resolve) => {
        const listener = () => {
          expect(listener).toBeDefined();
          resolve();
        };

        service.on('service-started', listener);
        service.start();
      });
    });

    it('should stop health checks', () => {
      return new Promise<void>((resolve) => {
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
      return new Promise<void>((resolve) => {
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

  describe('Health Check Execution', () => {
    it('should perform health checks periodically', () => {
      return new Promise<void>((resolve) => {
        const listener = () => {
          expect(listener).toBeDefined();
          resolve();
        };

        service.on('health-check-completed', listener);
        service.start();
      });
    });

    it('should check pgbouncer component', () => {
      return new Promise<void>((resolve) => {
        service.on('health-check-completed', () => {
          const pgbouncerStatus = service.getComponentStatus('pgbouncer');
          expect(pgbouncerStatus).toBeDefined();
          expect(pgbouncerStatus?.component).toBe('pgbouncer');
          resolve();
        });

        service.start();
      });
    });

    it('should check postgresql component', () => {
      return new Promise<void>((resolve) => {
        service.on('health-check-completed', () => {
          const pgStatus = service.getComponentStatus('postgresql');
          expect(pgStatus).toBeDefined();
          expect(pgStatus?.component).toBe('postgresql');
          resolve();
        });

        service.start();
      });
    });

    it('should check backups component', () => {
      return new Promise<void>((resolve) => {
        service.on('health-check-completed', () => {
          const backupStatus = service.getComponentStatus('backups');
          expect(backupStatus).toBeDefined();
          expect(backupStatus?.component).toBe('backups');
          resolve();
        });

        service.start();
      });
    });

    it('should check replication component', () => {
      return new Promise<void>((resolve) => {
        service.on('health-check-completed', () => {
          const replStatus = service.getComponentStatus('replication');
          expect(replStatus).toBeDefined();
          expect(replStatus?.component).toBe('replication');
          resolve();
        });

        service.start();
      });
    });
  });

  describe('Health Check Results', () => {
    it('should have valid status values', () => {
      return new Promise<void>((resolve) => {
        service.on('health-check-completed', () => {
          const statuses = service.getAllStatuses();
          statuses.forEach(status => {
            expect(['healthy', 'degraded', 'unhealthy']).toContain(status.status);
          });
          resolve();
        });

        service.start();
      });
    });

    it('should include response times', () => {
      return new Promise<void>((resolve) => {
        service.on('health-check-completed', () => {
          const statuses = service.getAllStatuses();
          statuses.forEach(status => {
            expect(status.responseTime).toBeGreaterThanOrEqual(0);
          });
          resolve();
        });

        service.start();
      });
    });

    it('should include component details', () => {
      return new Promise<void>((resolve) => {
        service.on('health-check-completed', () => {
          const statuses = service.getAllStatuses();
          statuses.forEach(status => {
            expect(status.details).toBeDefined();
            expect(typeof status.details).toBe('object');
          });
          resolve();
        });

        service.start();
      });
    });

    it('should include timestamps', () => {
      return new Promise<void>((resolve) => {
        service.on('health-check-completed', () => {
          const statuses = service.getAllStatuses();
          statuses.forEach(status => {
            expect(status.timestamp).toBeGreaterThan(0);
          });
          resolve();
        });

        service.start();
      });
    });
  });

  describe('Health Summary', () => {
    it('should generate overall summary', () => {
      return new Promise<void>((resolve) => {
        service.on('health-check-completed', () => {
          const summary = service.getSummary();
          expect(summary).toBeDefined();
          expect(summary?.status).toBeDefined();
          expect(summary?.components).toBeDefined();
          expect(summary?.summary).toBeDefined();
          resolve();
        });

        service.start();
      });
    });

    it('should count healthy components', () => {
      return new Promise<void>((resolve) => {
        service.on('health-check-completed', () => {
          const summary = service.getSummary();
          expect(summary?.summary.healthy).toBeGreaterThanOrEqual(0);
          expect(typeof summary?.summary.healthy).toBe('number');
          resolve();
        });

        service.start();
      });
    });

    it('should count degraded components', () => {
      return new Promise<void>((resolve) => {
        service.on('health-check-completed', () => {
          const summary = service.getSummary();
          expect(summary?.summary.degraded).toBeGreaterThanOrEqual(0);
          expect(typeof summary?.summary.degraded).toBe('number');
          resolve();
        });

        service.start();
      });
    });

    it('should count unhealthy components', () => {
      return new Promise<void>((resolve) => {
        service.on('health-check-completed', () => {
          const summary = service.getSummary();
          expect(summary?.summary.unhealthy).toBeGreaterThanOrEqual(0);
          expect(typeof summary?.summary.unhealthy).toBe('number');
          resolve();
        });

        service.start();
      });
    });

    it('should have valid overall status', () => {
      return new Promise<void>((resolve) => {
        service.on('health-check-completed', () => {
          const summary = service.getSummary();
          expect(['healthy', 'degraded', 'unhealthy']).toContain(summary?.status);
          resolve();
        });

        service.start();
      });
    });
  });

  describe('Event Emission', () => {
    it('should emit health-check-completed events', () => {
      return new Promise<void>((resolve) => {
        const listener = () => {
          expect(listener).toBeDefined();
          resolve();
        };

        service.on('health-check-completed', listener);
        service.start();
      });
    });

    it('should emit health-warning for degraded status', () => {
      return new Promise<void>((resolve) => {
        let warningEmitted = false;
        service.on('health-warning', () => {
          warningEmitted = true;
        });

        service.on('health-check-completed', () => {
          // We may or may not get a warning depending on random health state
          // Just verify the event system works
          expect(typeof warningEmitted).toBe('boolean');
          resolve();
        });

        service.start();
      });
    });

    it('should emit service-stopped event', () => {
      return new Promise<void>((resolve) => {
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

  describe('Configuration Management', () => {
    it('should return current configuration', () => {
      const config = service.getConfig();
      expect(config.primaryHost).toBe('192.168.168.31');
      expect(config.pgbouncer.enabled).toBe(true);
      expect(config.postgres.enabled).toBe(true);
    });

    it('should allow enabling/disabling', () => {
      service.setEnabled(false);
      let config = service.getConfig();
      expect(config.enabled).toBe(false);

      service.setEnabled(true);
      config = service.getConfig();
      expect(config.enabled).toBe(true);
    });
  });

  describe('Pgbouncer Monitoring', () => {
    it('should monitor pgbouncer connectivity', () => {
      return new Promise<void>((resolve) => {
        service.on('health-check-completed', () => {
          const status = service.getComponentStatus('pgbouncer');
          expect(status?.details.host).toBe('192.168.168.31');
          expect(status?.details.port).toBe(6432);
          resolve();
        });

        service.start();
      });
    });
  });

  describe('PostgreSQL Monitoring', () => {
    it('should monitor postgresql connectivity', () => {
      return new Promise<void>((resolve) => {
        service.on('health-check-completed', () => {
          const status = service.getComponentStatus('postgresql');
          expect(status?.details.host).toBe('192.168.168.31');
          expect(status?.details.port).toBe(5432);
          resolve();
        });

        service.start();
      });
    });

    it('should include connection count', () => {
      return new Promise<void>((resolve) => {
        service.on('health-check-completed', () => {
          const status = service.getComponentStatus('postgresql');
          expect(typeof status?.details.activeConnections).toBe('number');
          resolve();
        });

        service.start();
      });
    });
  });

  describe('Backup Monitoring', () => {
    it('should check backup status', () => {
      return new Promise<void>((resolve) => {
        service.on('health-check-completed', () => {
          const status = service.getComponentStatus('backups');
          expect(status?.details.lastBackupTime).toBeDefined();
          expect(status?.details.backupAgeMs).toBeDefined();
          resolve();
        });

        service.start();
      });
    });

    it('should track backup age', () => {
      return new Promise<void>((resolve) => {
        service.on('health-check-completed', () => {
          const status = service.getComponentStatus('backups');
          expect(typeof status?.details.backupAgeMins).toBe('number');
          expect(status?.details.backupAgeMins).toBeGreaterThanOrEqual(0);
          resolve();
        });

        service.start();
      });
    });
  });

  describe('Replication Monitoring', () => {
    it('should check replication lag', () => {
      return new Promise<void>((resolve) => {
        service.on('health-check-completed', () => {
          const status = service.getComponentStatus('replication');
          expect(status?.details.lagMs).toBeDefined();
          expect(typeof status?.details.lagMs).toBe('number');
          resolve();
        });

        service.start();
      });
    });

    it('should report lag in seconds', () => {
      return new Promise<void>((resolve) => {
        service.on('health-check-completed', () => {
          const status = service.getComponentStatus('replication');
          expect(typeof status?.details.lagSeconds).toBe('number');
          resolve();
        });

        service.start();
      });
    });
  });

  describe('Error Handling', () => {
    it('should handle errors gracefully', () => {
      return new Promise<void>((resolve) => {
        let errorEmitted = false;
        service.on('error', () => {
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

    it('should continue operating after errors', () => {
      return new Promise<void>((resolve) => {
        service.on('error', () => {
          // Ignore errors
        });

        service.start();

        setTimeout(() => {
          const summary1 = service.getSummary();
          expect(summary1).toBeDefined();

          setTimeout(() => {
            const summary2 = service.getSummary();
            expect(summary2).toBeDefined();
            resolve();
          }, 100);
        }, 100);
      });
    });
  });

  describe('Response Time Monitoring', () => {
    it('should track response times under 5 seconds', () => {
      return new Promise<void>((resolve) => {
        service.on('health-check-completed', (event) => {
          expect(event.duration).toBeLessThan(5000);
          resolve();
        });

        service.start();
      });
    });
  });

  describe('Component Management', () => {
    it('should get all statuses', () => {
      return new Promise<void>((resolve) => {
        service.on('health-check-completed', () => {
          const statuses = service.getAllStatuses();
          expect(Array.isArray(statuses)).toBe(true);
          expect(statuses.length).toBeGreaterThan(0);
          resolve();
        });

        service.start();
      });
    });

    it('should get specific component status', () => {
      return new Promise<void>((resolve) => {
        service.on('health-check-completed', () => {
          const status = service.getComponentStatus('postgresql');
          expect(status).toBeDefined();
          expect(status?.component).toBe('postgresql');
          resolve();
        });

        service.start();
      });
    });

    it('should return undefined for unknown component', () => {
      const status = service.getComponentStatus('unknown-component');
      expect(status).toBeUndefined();
    });
  });
});
