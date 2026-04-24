// @file        apps/session-broker/src/preview-environment-manager.ts
// @module      session-management/preview-environments
// @description Preview environment management for ephemeral workspaces in KC IDE
//
// Manages creation, lifecycle, and cleanup of temporary preview environments.

import * as winston from 'winston';
import * as fs from 'fs';
import * as path from 'path';
import { RedisSessionStore, SessionContext } from './redis-session-store';

const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || 'info',
  format: winston.format.json(),
  transports: [new winston.transports.Console()],
});

export enum PreviewEnvironmentStatus {
  PROVISIONING = 'provisioning',
  ACTIVE = 'active',
  SUSPENDING = 'suspending',
  SUSPENDED = 'suspended',
  TERMINATING = 'terminating',
  TERMINATED = 'terminated',
}

export interface PreviewEnvironment {
  id: string;
  parentSessionId: string;
  name: string;
  description: string;
  status: PreviewEnvironmentStatus;
  createdBy: string;
  createdAt: Date;
  expiresAt: Date;
  config: {
    inheritExtensions: boolean;
    inheritDebugConfig: boolean;
    environmentVariables: Record<string, string>;
    workspaceSettings: Record<string, unknown>;
  };
  resourceAllocation: {
    cpuLimitMillis: number;
    memoryLimitMb: number;
  };
  snapshotId?: string;
}

export interface PreviewEnvironmentMetrics {
  environmentId: string;
  cpuUsagePercent: number;
  memoryUsageMb: number;
  activeConnectionCount: number;
  uptime: number; // milliseconds
}

/**
 * Manages preview environments for temporary workspaces.
 * Idempotent: safe to create/suspend/resume same environment multiple times.
 */
export class PreviewEnvironmentManager {
  private environmentStore: Map<string, PreviewEnvironment> = new Map();
  private metricsStore: Map<string, PreviewEnvironmentMetrics> = new Map();
  private nasBasePath: string;

  constructor(
    private sessionStore: RedisSessionStore,
    nasBasePath: string = process.env.NAS_MOUNT_PATH || '/mnt/nas/persistent/code-server-enterprise'
  ) {
    this.nasBasePath = nasBasePath;
    this.initializeDirectories();
  }

  /**
   * Initialize NAS directories for preview environments.
   */
  private initializeDirectories(): void {
    try {
      const previewDir = path.join(this.nasBasePath, 'preview-environments');
      if (!fs.existsSync(previewDir)) {
        fs.mkdirSync(previewDir, { recursive: true });
        logger.info('Initialized preview environments directory', { path: previewDir });
      }
    } catch (error) {
      logger.error('Failed to initialize preview environments directory', { error });
    }
  }

  /**
   * Create a new preview environment from a parent session.
   * Idempotent: creating same preview twice returns existing environment with updated expiry.
   */
  async createPreviewEnvironment(
    parentSessionId: string,
    name: string,
    createdBy: string,
    durationHours: number = 8,
    cpuLimitMillis: number = 1000,
    memoryLimitMb: number = 512
  ): Promise<PreviewEnvironment | null> {
    try {
      const parentSession = await this.sessionStore.getSession(parentSessionId);
      if (!parentSession) {
        logger.error('Cannot create preview: parent session not found', { parentSessionId });
        return null;
      }

      // Check for existing preview with same name (idempotent)
      const existingPreview = Array.from(this.environmentStore.values()).find(
        e => e.parentSessionId === parentSessionId && e.name === name && e.status !== PreviewEnvironmentStatus.TERMINATED
      );

      if (existingPreview) {
        existingPreview.expiresAt = new Date(Date.now() + durationHours * 60 * 60 * 1000);
        logger.info('Updated existing preview environment', { parentSessionId, name });
        return existingPreview;
      }

      // Create new preview
      const environment: PreviewEnvironment = {
        id: `preview-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
        parentSessionId,
        name,
        description: `Preview environment for testing`,
        status: PreviewEnvironmentStatus.PROVISIONING,
        createdBy,
        createdAt: new Date(),
        expiresAt: new Date(Date.now() + durationHours * 60 * 60 * 1000),
        config: {
          inheritExtensions: true,
          inheritDebugConfig: true,
          environmentVariables: { ...parentSession.config.environment },
          workspaceSettings: { ...parentSession.config.workspaceSettings },
        },
        resourceAllocation: {
          cpuLimitMillis,
          memoryLimitMb,
        },
      };

      this.environmentStore.set(environment.id, environment);
      this.initializeMetrics(environment.id);

      logger.info('Created preview environment', { id: environment.id, parentSessionId, name });
      return environment;
    } catch (error) {
      logger.error('Failed to create preview environment', { error, parentSessionId, name });
      return null;
    }
  }

  /**
   * Activate a preview environment.
   * Idempotent: activating already-active environment is a no-op.
   */
  async activatePreviewEnvironment(environmentId: string): Promise<boolean> {
    try {
      const environment = this.environmentStore.get(environmentId);
      if (!environment) {
        logger.error('Preview environment not found', { environmentId });
        return false;
      }

      if (environment.status === PreviewEnvironmentStatus.ACTIVE) {
        logger.info('Preview environment already active', { environmentId });
        return true; // Idempotent
      }

      if (environment.status === PreviewEnvironmentStatus.SUSPENDED) {
        environment.status = PreviewEnvironmentStatus.ACTIVE;
        logger.info('Resumed preview environment', { environmentId });
        return true;
      }

      environment.status = PreviewEnvironmentStatus.ACTIVE;
      logger.info('Activated preview environment', { environmentId });
      return true;
    } catch (error) {
      logger.error('Failed to activate preview environment', { error, environmentId });
      return false;
    }
  }

  /**
   * Suspend a preview environment (preserve state).
   * Idempotent: suspending already-suspended environment is a no-op.
   */
  async suspendPreviewEnvironment(environmentId: string): Promise<boolean> {
    try {
      const environment = this.environmentStore.get(environmentId);
      if (!environment) {
        logger.error('Preview environment not found', { environmentId });
        return false;
      }

      if (environment.status === PreviewEnvironmentStatus.SUSPENDED) {
        logger.info('Preview environment already suspended', { environmentId });
        return true; // Idempotent
      }

      environment.status = PreviewEnvironmentStatus.SUSPENDED;
      logger.info('Suspended preview environment', { environmentId });
      return true;
    } catch (error) {
      logger.error('Failed to suspend preview environment', { error, environmentId });
      return false;
    }
  }

  /**
   * Terminate a preview environment (cleanup).
   * Idempotent: terminating already-terminated environment is a no-op.
   */
  async terminatePreviewEnvironment(environmentId: string): Promise<boolean> {
    try {
      const environment = this.environmentStore.get(environmentId);
      if (!environment) {
        logger.info('Preview environment already terminated or not found', { environmentId });
        return true; // Idempotent
      }

      if (environment.status === PreviewEnvironmentStatus.TERMINATED) {
        logger.info('Preview environment already terminated', { environmentId });
        return true; // Idempotent
      }

      environment.status = PreviewEnvironmentStatus.TERMINATED;
      this.metricsStore.delete(environmentId);

      logger.info('Terminated preview environment', { environmentId });
      return true;
    } catch (error) {
      logger.error('Failed to terminate preview environment', { error, environmentId });
      return false;
    }
  }

  /**
   * List all active preview environments for a parent session.
   */
  async listPreviewEnvironments(parentSessionId: string): Promise<PreviewEnvironment[]> {
    try {
      return Array.from(this.environmentStore.values()).filter(
        e => e.parentSessionId === parentSessionId && e.status !== PreviewEnvironmentStatus.TERMINATED
      );
    } catch (error) {
      logger.error('Failed to list preview environments', { error, parentSessionId });
      return [];
    }
  }

  /**
   * Get metrics for a preview environment.
   */
  async getMetrics(environmentId: string): Promise<PreviewEnvironmentMetrics | null> {
    try {
      const metrics = this.metricsStore.get(environmentId);
      if (!metrics) {
        logger.warn('Metrics not found', { environmentId });
        return null;
      }
      return metrics;
    } catch (error) {
      logger.error('Failed to get metrics', { error, environmentId });
      return null;
    }
  }

  /**
   * Initialize metrics tracking for a preview environment.
   */
  private initializeMetrics(environmentId: string): void {
    this.metricsStore.set(environmentId, {
      environmentId,
      cpuUsagePercent: 0,
      memoryUsageMb: 0,
      activeConnectionCount: 0,
      uptime: 0,
    });
  }

  /**
   * Cleanup expired preview environments.
   * Idempotent: safe to run multiple times.
   */
  async cleanupExpiredEnvironments(): Promise<number> {
    try {
      let cleanedCount = 0;
      const now = new Date();

      for (const environment of this.environmentStore.values()) {
        if (environment.status !== PreviewEnvironmentStatus.TERMINATED && now > environment.expiresAt) {
          await this.terminatePreviewEnvironment(environment.id);
          cleanedCount++;
        }
      }

      logger.info('Cleaned up expired preview environments', { count: cleanedCount });
      return cleanedCount;
    } catch (error) {
      logger.error('Failed to cleanup expired environments', { error });
      return 0;
    }
  }
}
