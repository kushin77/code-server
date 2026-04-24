/**
 * Real-time Collaborative Plugin Manager Types
 * @file        apps/backend/src/services/plugin-manager/types.ts
 * @module      services/plugin-manager
 * @description Type definitions for collaborative plugin management
 */

/**
 * Plugin types
 */
export type PluginType = 'editor' | 'language' | 'terminal' | 'theme' | 'collaboration' | 'utility' | 'ai';

/**
 * Plugin status
 */
export type PluginStatus = 'installed' | 'enabled' | 'disabled' | 'updating' | 'error';

/**
 * Plugin installation source
 */
export type PluginSource = 'marketplace' | 'upload' | 'repository' | 'local';

/**
 * Plugin metadata
 */
export interface PluginMetadata {
  pluginId: string;
  name: string;
  version: string;
  description: string;
  author: string;
  type: PluginType;
  status: PluginStatus;
  source: PluginSource;
  installedAt: number;
  lastUpdatedAt: number;
  tags: string[];
  dependencies: string[];
  permissions: string[];
  size: number;
  sha256: string;
}

/**
 * Collaborative plugin configuration
 */
export interface PluginConfig {
  pluginId: string;
  settings: Record<string, unknown>;
  modifiedBy: string;
  modifiedAt: number;
}

/**
 * Plugin installation progress
 */
export interface PluginProgress {
  pluginId: string;
  operation: 'install' | 'update' | 'remove';
  percentComplete: number;
  status: 'pending' | 'active' | 'completed' | 'failed';
  message: string;
  timestamp: number;
}

/**
 * Plugin metrics
 */
export interface PluginMetrics {
  pluginId: string;
  cpuUsage: number;
  memoryUsage: number;
  activationTime: number;
  lastActiveAt: number;
  errorCount: number;
}

/**
 * Plugin audit entry
 */
export interface PluginAuditEntry {
  timestamp: number;
  userId: string;
  userEmail: string;
  action: string;
  pluginId: string;
  details: Record<string, unknown>;
}

/**
 * Plugin event
 */
export interface PluginEvent {
  eventId: string;
  pluginId: string;
  userId: string;
  eventType: 'plugin_installed' | 'plugin_enabled' | 'plugin_disabled' | 'plugin_removed' | 'plugin_updated' | 'config_changed';
  timestamp: number;
  data: Record<string, unknown>;
}

/**
 * Service configuration
 */
export interface PluginManagerConfig {
  enablePluginManagement: boolean;
  autoUpdateEnabled: boolean;
  maxPluginsInstalled: number;
  maxAuditEntries: number;
  allowedSources: PluginSource[];
  requirePermissionsApproval: boolean;
  metricsIntervalMs: number;
}

/**
 * Collaborative plugin manager service interface
 */
export interface IPluginManagerService {
  installPlugin(
    metadata: Omit<PluginMetadata, 'installedAt' | 'lastUpdatedAt' | 'status'>,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; progressId?: string };

  uninstallPlugin(
    pluginId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean };

  enablePlugin(
    pluginId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean };

  disablePlugin(
    pluginId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean };

  getPlugin(pluginId: string): PluginMetadata | undefined;

  listPlugins(type?: PluginType, status?: PluginStatus): PluginMetadata[];

  updatePluginConfig(
    pluginId: string,
    settings: Record<string, unknown>,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean };

  getPluginConfig(pluginId: string): PluginConfig | undefined;

  getPluginMetrics(pluginId: string): PluginMetrics | undefined;

  getPluginProgress(pluginId: string): PluginProgress | undefined;

  checkUpdates(pluginId?: string): { updatesAvailable: boolean; plugins: string[] };

  getAuditLog(limit?: number): PluginAuditEntry[];

  getPluginEvents(pluginId: string, limit?: number): PluginEvent[];

  updateConfig(config: Partial<PluginManagerConfig>): void;

  shutdown(): void;
}
