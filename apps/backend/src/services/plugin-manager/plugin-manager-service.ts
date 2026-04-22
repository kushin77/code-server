/**
 * Real-time Collaborative Plugin Manager Service
 * @file        apps/backend/src/services/plugin-manager/plugin-manager-service.ts
 * @module      services/plugin-manager
 * @description Collaborative plugin management system
 */

import { EventEmitter } from 'events';
import {
  PluginMetadata,
  PluginConfig,
  PluginProgress,
  PluginMetrics,
  PluginAuditEntry,
  PluginEvent,
  PluginManagerConfig,
  IPluginManagerService,
  PluginType,
  PluginStatus,
} from './types.js';

/**
 * Plugin Manager Service
 * Manages plugin lifecycle and collaborative configuration
 */
export class PluginManagerService extends EventEmitter implements IPluginManagerService {
  private static instance: PluginManagerService | undefined;
  private plugins: Map<string, PluginMetadata> = new Map();
  private configs: Map<string, PluginConfig> = new Map();
  private progress: Map<string, PluginProgress> = new Map();
  private metrics: Map<string, PluginMetrics> = new Map();
  private auditLogs: Map<string, PluginAuditEntry[]> = new Map(); // userId -> entries
  private events: Map<string, PluginEvent[]> = new Map(); // pluginId -> events
  private config: PluginManagerConfig = {
    enablePluginManagement: true,
    autoUpdateEnabled: false,
    maxPluginsInstalled: 100,
    maxAuditEntries: 5000,
    allowedSources: ['marketplace', 'upload', 'repository', 'local'],
    requirePermissionsApproval: true,
    metricsIntervalMs: 60000,
  };

  private constructor() {
    super();
    this.initialize();
  }

  /**
   * Get or create singleton instance
   */
  public static getInstance(config?: Partial<PluginManagerConfig>): PluginManagerService {
    if (!PluginManagerService.instance) {
      PluginManagerService.instance = new PluginManagerService();
    }
    if (config) {
      PluginManagerService.instance.updateConfig(config);
    }
    return PluginManagerService.instance;
  }

  /**
   * Reset singleton for testing
   */
  public static reset(): void {
    PluginManagerService.instance = undefined;
  }

  /**
   * Initialize service
   */
  private initialize(): void {
    this.emit('initialized', {
      data_object: { service: 'plugin-manager', status: 'initialized' },
      timestamp: Date.now(),
    });
  }

  /**
   * Install plugin
   */
  public installPlugin(
    metadata: Omit<PluginMetadata, 'installedAt' | 'lastUpdatedAt' | 'status'>,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; progressId?: string } {
    try {
      if (!this.config.enablePluginManagement) {
        return { success: false };
      }

      if (this.plugins.size >= this.config.maxPluginsInstalled) {
        throw new Error('Maximum plugins limit reached');
      }

      const pluginId = metadata.pluginId;
      const progressId = `prog-${Date.now()}-${Math.random().toString(16).slice(2)}`;

      const initialProgress: PluginProgress = {
        pluginId,
        operation: 'install',
        percentComplete: 0,
        status: 'pending',
        message: 'Starting installation...',
        timestamp: Date.now(),
      };

      this.progress.set(pluginId, initialProgress);

      // Async installation simulation
      setTimeout(() => {
        const fullMetadata: PluginMetadata = {
          ...metadata,
          status: 'installed',
          installedAt: Date.now(),
          lastUpdatedAt: Date.now(),
        };

        this.plugins.set(pluginId, fullMetadata);
        this.progress.get(pluginId)!.percentComplete = 100;
        this.progress.get(pluginId)!.status = 'completed';
        this.progress.get(pluginId)!.message = 'Installation complete';

        this.logAudit(userId, 'install-plugin', pluginId, {
          name: metadata.name,
          version: metadata.version,
        });

        this.logEvent(pluginId, userId, 'plugin_installed', {
          version: metadata.version,
        });

        this.emit('plugin-installed', {
          data_object: { pluginId, userId, name: metadata.name },
          timestamp: Date.now(),
        });
      }, 0);

      return { success: true, progressId };
    } catch (error) {
      this.logAudit(userId, 'install-plugin-failed', metadata.pluginId, {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Uninstall plugin
   */
  public uninstallPlugin(
    pluginId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean } {
    try {
      const plugin = this.plugins.get(pluginId);
      if (!plugin) {
        return { success: false };
      }

      this.plugins.delete(pluginId);
      this.configs.delete(pluginId);
      this.progress.delete(pluginId);
      this.metrics.delete(pluginId);

      this.logAudit(userId, 'uninstall-plugin', pluginId, {});
      this.logEvent(pluginId, userId, 'plugin_removed', {});

      this.emit('plugin-removed', {
        data_object: { pluginId, userId },
        timestamp: Date.now(),
      });

      return { success: true };
    } catch (error) {
      this.logAudit(userId, 'uninstall-plugin-failed', pluginId, {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Enable plugin
   */
  public enablePlugin(
    pluginId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean } {
    try {
      const plugin = this.plugins.get(pluginId);
      if (!plugin) {
        return { success: false };
      }

      plugin.status = 'enabled';
      this.logAudit(userId, 'enable-plugin', pluginId, {});
      this.logEvent(pluginId, userId, 'plugin_enabled', {});

      this.emit('plugin-enabled', {
        data_object: { pluginId, userId },
        timestamp: Date.now(),
      });

      return { success: true };
    } catch (error) {
      this.logAudit(userId, 'enable-plugin-failed', pluginId, {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Disable plugin
   */
  public disablePlugin(
    pluginId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean } {
    try {
      const plugin = this.plugins.get(pluginId);
      if (!plugin) {
        return { success: false };
      }

      plugin.status = 'disabled';
      this.logAudit(userId, 'disable-plugin', pluginId, {});
      this.logEvent(pluginId, userId, 'plugin_disabled', {});

      this.emit('plugin-disabled', {
        data_object: { pluginId, userId },
        timestamp: Date.now(),
      });

      return { success: true };
    } catch (error) {
      this.logAudit(userId, 'disable-plugin-failed', pluginId, {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Get plugin
   */
  public getPlugin(pluginId: string): PluginMetadata | undefined {
    return this.plugins.get(pluginId);
  }

  /**
   * List plugins
   */
  public listPlugins(type?: PluginType, status?: PluginStatus): PluginMetadata[] {
    return Array.from(this.plugins.values()).filter(p => 
      (!type || p.type === type) && (!status || p.status === status)
    );
  }

  /**
   * Update plugin configuration
   */
  public updatePluginConfig(
    pluginId: string,
    settings: Record<string, unknown>,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean } {
    try {
      if (!this.plugins.has(pluginId)) {
        return { success: false };
      }

      const config: PluginConfig = {
        pluginId,
        settings,
        modifiedBy: userId,
        modifiedAt: Date.now(),
      };

      this.configs.set(pluginId, config);

      this.logAudit(userId, 'update-plugin-config', pluginId, { settings });
      this.logEvent(pluginId, userId, 'config_changed', { settings });

      this.emit('plugin-config-updated', {
        data_object: { pluginId, userId, config },
        timestamp: Date.now(),
      });

      return { success: true };
    } catch (error) {
      this.logAudit(userId, 'update-plugin-config-failed', pluginId, {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Get plugin config
   */
  public getPluginConfig(pluginId: string): PluginConfig | undefined {
    return this.configs.get(pluginId);
  }

  /**
   * Get plugin metrics
   */
  public getPluginMetrics(pluginId: string): PluginMetrics | undefined {
    return this.metrics.get(pluginId);
  }

  /**
   * Get plugin progress
   */
  public getPluginProgress(pluginId: string): PluginProgress | undefined {
    return this.progress.get(pluginId);
  }

  /**
   * Check updates
   */
  public checkUpdates(pluginId?: string): { updatesAvailable: boolean; plugins: string[] } {
    // Simulated update check
    return { updatesAvailable: false, plugins: [] };
  }

  /**
   * Get audit log
   */
  public getAuditLog(limit?: number): PluginAuditEntry[] {
    const entries: PluginAuditEntry[] = [];
    for (const userEntries of this.auditLogs.values()) {
      entries.push(...userEntries);
    }
    entries.sort((a, b) => b.timestamp - a.timestamp);
    return entries.slice(0, limit || 100);
  }

  /**
   * Get plugin events
   */
  public getPluginEvents(pluginId: string, limit?: number): PluginEvent[] {
    const events = this.events.get(pluginId) || [];
    return events.sort((a, b) => b.timestamp - a.timestamp).slice(0, limit || 50);
  }

  /**
   * Log audit entry
   */
  private logAudit(userId: string, action: string, pluginId: string, details?: Record<string, unknown>): void {
    if (!this.auditLogs.has(userId)) {
      this.auditLogs.set(userId, []);
    }

    const entry: PluginAuditEntry = {
      timestamp: Date.now(),
      userId,
      userEmail: `user-${userId}@example.com`,
      action,
      pluginId,
      details: details || {},
    };

    const logs = this.auditLogs.get(userId)!;
    logs.push(entry);

    if (logs.length > this.config.maxAuditEntries) {
      logs.splice(0, logs.length - this.config.maxAuditEntries);
    }

    this.emit('audit-logged', {
      data_object: entry,
      timestamp: Date.now(),
    });
  }

  /**
   * Log plugin event
   */
  private logEvent(pluginId: string, userId: string, eventType: PluginEvent['eventType'], data?: Record<string, unknown>): void {
    if (!this.events.has(pluginId)) {
      this.events.set(pluginId, []);
    }

    const event: PluginEvent = {
      eventId: `event-${Date.now()}-${Math.random().toString(16).slice(2)}`,
      pluginId,
      userId,
      eventType,
      timestamp: Date.now(),
      data: data || {},
    };

    this.events.get(pluginId)!.push(event);
  }

  /**
   * Update configuration
   */
  public updateConfig(config: Partial<PluginManagerConfig>): void {
    this.config = { ...this.config, ...config };

    this.emit('config-updated', {
      data_object: { config: this.config },
      timestamp: Date.now(),
    });
  }

  /**
   * Shutdown service
   */
  public shutdown(): void {
    this.plugins.clear();
    this.configs.clear();
    this.progress.clear();
    this.metrics.clear();
    this.auditLogs.clear();
    this.events.clear();

    this.emit('shutdown', {
      data_object: { service: 'plugin-manager', status: 'shutdown' },
      timestamp: Date.now(),
    });
  }
}
