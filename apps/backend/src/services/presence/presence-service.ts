/**
 * Rich Presence System Service
 * Real-time user presence tracking with Redis persistence and SOC2 audit logging
 */

import { EventEmitter } from 'events';
import {
  UserPresence,
  PresenceStatus,
  PresenceUpdate,
  PresenceEvent,
  PresenceAuditEntry,
  WorkspacePresenceSnapshot,
  PresenceStatistics,
  PresenceQuery,
  PresenceQueryResult,
  PresenceNotification,
  PresenceSettings,
  PresenceServiceConfig,
  PresenceHistoryEntry,
  ActivitySummary,
  ActivityContext,
} from './types.js';

/**
 * Rich Presence Service
 * Track user presence with Redis persistence and audit logging
 */
export class PresenceService extends EventEmitter {
  private isInitialized = false;
  private presence: Map<string, UserPresence> = new Map();
  private history: Map<string, PresenceHistoryEntry[]> = new Map(); // Per-user history
  private auditLog: Map<string, PresenceAuditEntry[]> = new Map(); // Per-user audit trail
  private settings: Map<string, PresenceSettings> = new Map();
  private notifications: Map<string, PresenceNotification[]> = new Map();
  private stats: PresenceStatistics = {
    totalUsers: 0,
    usersByStatus: {},
    usersByActivity: {},
    averageSessionDuration: 0,
    averageIdleTime: 0,
    workspaces: 0,
    usersPerWorkspace: {},
    mostActiveTime: 0,
    peakConcurrency: 0,
  };
  private config: PresenceServiceConfig;

  constructor(config?: Partial<PresenceServiceConfig>) {
    super();
    this.config = {
      enabled: true,
      auditLoggingEnabled: true,
      redisPersistenceEnabled: true,
      ttl: 14400000, // 4 hours
      idleThreshold: 900000, // 15 minutes
      awayThreshold: 1800000, // 30 minutes
      cleanupInterval: 300000, // 5 minutes
      maxPresencePerWorkspace: 1000,
      enableNotifications: true,
      maxAuditLogSize: 10000,
      ...config,
    };
  }

  /**
   * Initialize service
   */
  async initialize(): Promise<void> {
    if (this.isInitialized) return;
    this.isInitialized = true;

    // Start cleanup timer
    this.startCleanupTimer();

    this.emit('initialized');
  }

  /**
   * Shutdown service
   */
  async shutdown(): Promise<void> {
    this.stopCleanupTimer();
    this.emit('shutdown');
  }

  /**
   * Update user presence
   */
  async updatePresence(
    userId: string,
    userEmail: string,
    update: PresenceUpdate,
    ipAddress?: string,
    userAgent?: string,
    workspaceId?: string,
    sessionId?: string
  ): Promise<UserPresence> {
    if (!this.isInitialized) throw new Error('Service not initialized');

    const existing = this.presence.get(userId);
    const previousStatus = existing?.status;

    const now = Date.now();
    const presence: UserPresence = {
      userId,
      userEmail,
      status: update.status || previousStatus || 'online',
      lastActivity: now,
      currentActivity: update.currentActivity || existing?.currentActivity,
      currentFile: update.currentFile || existing?.currentFile,
      currentFunction: update.currentFunction || existing?.currentFunction,
      currentTask: update.currentTask || existing?.currentTask,
      debugState: update.debugState || existing?.debugState,
      customStatus: update.customStatus || existing?.customStatus,
      workspaceId: workspaceId || existing?.workspaceId,
      sessionId: sessionId || existing?.sessionId,
      createdAt: existing?.createdAt || now,
      updatedAt: now,
      expiresAt: now + this.config.ttl,
    };

    if (ipAddress) {
      presence.deviceInfo = {
        ...existing?.deviceInfo,
        platform: 'web',
        ipAddress,
        browser: userAgent,
      };
    }

    this.presence.set(userId, presence);

    // Log audit entry
    const auditEntry: PresenceAuditEntry = {
      id: `audit-${userId}-${Date.now()}`,
      userId,
      userEmail,
      operation: 'status-updated',
      status: 'success',
      resourceType: 'user-presence',
      resourceId: userId,
      ipAddress,
      userAgent,
      timestamp: now,
      previousStatus,
      newStatus: presence.status,
      details: {
        activity: update.currentActivity?.context,
        file: update.currentFile?.path,
      },
    };

    await this.logAudit(userId, auditEntry);

    // Add to history
    await this.addHistory(userId, {
      userId,
      status: presence.status,
      activity: update.currentActivity,
      timestamp: now,
    });

    this.updateStats();
    this.emit('presence-updated', { userId, presence });

    // Check for status change event
    if (previousStatus && previousStatus !== presence.status) {
      this.emit('status-changed', {
        userId,
        previousStatus,
        newStatus: presence.status,
        timestamp: now,
      } as PresenceEvent);
    }

    return presence;
  }

  /**
   * Mark user as online
   */
  async markOnline(
    userId: string,
    userEmail: string,
    workspaceId?: string,
    sessionId?: string,
    ipAddress?: string,
    userAgent?: string
  ): Promise<UserPresence> {
    return this.updatePresence(
      userId,
      userEmail,
      { status: 'online' },
      ipAddress,
      userAgent,
      workspaceId,
      sessionId
    );
  }

  /**
   * Mark user as offline
   */
  async markOffline(
    userId: string,
    userEmail: string,
    ipAddress?: string,
    userAgent?: string
  ): Promise<void> {
    const now = Date.now();

    // Log audit entry
    const auditEntry: PresenceAuditEntry = {
      id: `audit-${userId}-offline-${Date.now()}`,
      userId,
      userEmail,
      operation: 'offline',
      status: 'success',
      resourceType: 'user-presence',
      resourceId: userId,
      ipAddress,
      userAgent,
      timestamp: now,
      newStatus: 'offline',
    };

    await this.logAudit(userId, auditEntry);

    this.presence.delete(userId);
    this.updateStats();

    this.emit('user-offline', { userId, timestamp: now });
  }

  /**
   * Get user presence
   */
  async getPresence(userId: string): Promise<UserPresence | undefined> {
    const presence = this.presence.get(userId);
    if (presence && presence.expiresAt > Date.now()) {
      return presence;
    }
    return undefined;
  }

  /**
   * Query presence
   */
  async queryPresence(query: PresenceQuery): Promise<PresenceQueryResult> {
    let results: UserPresence[] = Array.from(this.presence.values()).filter(
      (p) => p.expiresAt > Date.now() // Filter out expired entries
    );

    // Filter by workspace
    if (query.workspaceId) {
      results = results.filter((p) => p.workspaceId === query.workspaceId);
    }

    // Filter by user
    if (query.userId) {
      results = results.filter((p) => p.userId === query.userId);
    }

    // Filter by status
    if (query.status) {
      results = results.filter((p) => p.status === query.status);
    }

    // Filter by activity
    if (query.activity) {
      results = results.filter((p) => p.currentActivity?.context === query.activity);
    }

    // Sort by last activity
    results.sort((a, b) => b.lastActivity - a.lastActivity);

    // Paginate
    const limit = query.limit || 20;
    const offset = query.offset || 0;

    return {
      presence: results.slice(offset, offset + limit),
      total: results.length,
      limit,
      offset,
    };
  }

  /**
   * Get workspace presence snapshot
   */
  async getWorkspacePresence(workspaceId: string): Promise<WorkspacePresenceSnapshot> {
    const result = await this.queryPresence({ workspaceId, limit: 10000 });

    const presenceByStatus: Record<PresenceStatus, number> = {
      online: 0,
      idle: 0,
      away: 0,
      offline: 0,
      busy: 0,
    };

    const presenceByActivity: Record<ActivityContext, number> = {
      file: 0,
      function: 0,
      task: 0,
      debug: 0,
      terminal: 0,
      chat: 0,
      custom: 0,
    };

    for (const presence of result.presence) {
      presenceByStatus[presence.status]++;
      if (presence.currentActivity) {
        presenceByActivity[presence.currentActivity.context]++;
      }
    }

    return {
      workspaceId,
      activeUsers: result.total,
      totalUsers: result.total,
      presenceByStatus,
      presenceByActivity,
      timestamp: Date.now(),
      users: result.presence,
    };
  }

  /**
   * Update custom status
   */
  async setCustomStatus(
    userId: string,
    userEmail: string,
    text: string,
    emoji?: string,
    expiresAt?: number,
    ipAddress?: string,
    userAgent?: string
  ): Promise<UserPresence> {
    return this.updatePresence(
      userId,
      userEmail,
      {
        customStatus: {
          text,
          emoji,
          expiresAt,
        },
      },
      ipAddress,
      userAgent
    );
  }

  /**
   * Update activity
   */
  async updateActivity(
    userId: string,
    userEmail: string,
    context: ActivityContext,
    description: string,
    details?: Record<string, unknown>,
    ipAddress?: string,
    userAgent?: string
  ): Promise<UserPresence> {
    return this.updatePresence(
      userId,
      userEmail,
      {
        currentActivity: {
          context,
          description,
          details,
        },
      },
      ipAddress,
      userAgent
    );
  }

  /**
   * Get user presence settings
   */
  async getSettings(userId: string): Promise<PresenceSettings | undefined> {
    return this.settings.get(userId);
  }

  /**
   * Update user presence settings
   */
  async updateSettings(
    userId: string,
    settings: Partial<PresenceSettings>
  ): Promise<PresenceSettings> {
    let userSettings = this.settings.get(userId);
    if (!userSettings) {
      userSettings = {
        userId,
        showPresence: true,
        broadcastActivity: true,
        broadcastStatus: true,
        broadcastFile: false,
        broadcastFunction: false,
        broadcastTask: true,
        broadcastCustomStatus: true,
        privacyLevel: 'workspace',
        notifyOnCollaboratorOnline: true,
        notifyOnCollaboratorOffline: false,
        notifyOnActivityChange: false,
        idleThreshold: this.config.idleThreshold,
        awayThreshold: this.config.awayThreshold,
        createdAt: Date.now(),
        updatedAt: Date.now(),
      };
    }

    userSettings = {
      ...userSettings,
      ...settings,
      userId,
      updatedAt: Date.now(),
    };

    this.settings.set(userId, userSettings);
    this.emit('settings-updated', { userId });

    return userSettings;
  }

  /**
   * Get audit log for user
   */
  async getAuditLog(userId: string, limit?: number): Promise<PresenceAuditEntry[]> {
    const log = this.auditLog.get(userId) || [];
    if (limit) {
      return log.slice(-limit);
    }
    return log;
  }

  /**
   * Get presence history
   */
  async getHistory(userId: string, limit?: number): Promise<PresenceHistoryEntry[]> {
    const history = this.history.get(userId) || [];
    if (limit) {
      return history.slice(-limit);
    }
    return history;
  }

  /**
   * Get activity summary
   */
  async getActivitySummary(userId: string, date: string): Promise<ActivitySummary | undefined> {
    const history = this.history.get(userId) || [];

    // Filter to date
    const dateStart = new Date(date).getTime();
    const dateEnd = dateStart + 86400000; // 24 hours

    const dayEntries = history.filter((h) => h.timestamp >= dateStart && h.timestamp < dateEnd);

    if (dayEntries.length === 0) return undefined;

    let onlineTime = 0;
    let idleTime = 0;
    let awayTime = 0;
    const activities: Record<ActivityContext, number> = {
      file: 0,
      function: 0,
      task: 0,
      debug: 0,
      terminal: 0,
      chat: 0,
      custom: 0,
    };

    for (let i = 0; i < dayEntries.length - 1; i++) {
      const current = dayEntries[i];
      const next = dayEntries[i + 1];
      const duration = next.timestamp - current.timestamp;

      if (current.status === 'online') {
        onlineTime += duration;
      } else if (current.status === 'idle') {
        idleTime += duration;
      } else if (current.status === 'away') {
        awayTime += duration;
      }

      if (current.activity) {
        activities[current.activity.context]++;
      }
    }

    const mostUsed = Object.entries(activities).sort((a, b) => b[1] - a[1])[0][0] as ActivityContext;

    return {
      userId,
      date,
      onlineTime,
      idleTime,
      awayTime,
      sessionCount: dayEntries.filter((h) => h.status === 'online').length,
      averageSessionDuration: onlineTime / Math.max(1, dayEntries.length),
      mostUsedActivity: mostUsed,
      filesEdited: activities.file,
      functionsEdited: activities.function,
      tasksCompleted: activities.task,
    };
  }

  /**
   * Get statistics
   */
  async getStatistics(): Promise<PresenceStatistics> {
    return { ...this.stats };
  }

  /**
   * Get all presence
   */
  async getAllPresence(): Promise<UserPresence[]> {
    return Array.from(this.presence.values()).filter((p) => p.expiresAt > Date.now());
  }

  /**
   * Get notification for user
   */
  async getNotifications(userId: string, limit?: number): Promise<PresenceNotification[]> {
    const notifs = this.notifications.get(userId) || [];
    if (limit) {
      return notifs.slice(-limit);
    }
    return notifs;
  }

  /**
   * Private: Log audit entry
   */
  private async logAudit(userId: string, entry: PresenceAuditEntry): Promise<void> {
    let log = this.auditLog.get(userId);
    if (!log) {
      log = [];
      this.auditLog.set(userId, log);
    }

    log.push(entry);

    // Keep only maxAuditLogSize entries
    if (log.length > this.config.maxAuditLogSize) {
      log.splice(0, log.length - this.config.maxAuditLogSize);
    }

    this.emit('audit-logged', { userId, entry });
  }

  /**
   * Private: Add to history
   */
  private async addHistory(userId: string, entry: PresenceHistoryEntry): Promise<void> {
    let history = this.history.get(userId);
    if (!history) {
      history = [];
      this.history.set(userId, history);
    }

    history.push(entry);

    // Keep only last 10000 entries per user
    if (history.length > 10000) {
      history.splice(0, history.length - 10000);
    }
  }

  /**
   * Private: Update statistics
   */
  private updateStats(): void {
    const now = Date.now();
    const active = Array.from(this.presence.values()).filter((p) => p.expiresAt > now);

    this.stats.totalUsers = active.length;
    this.stats.usersByStatus = { online: 0, idle: 0, away: 0, offline: 0, busy: 0 };
    this.stats.usersByActivity = {
      file: 0,
      function: 0,
      task: 0,
      debug: 0,
      terminal: 0,
      chat: 0,
      custom: 0,
    };
    this.stats.usersPerWorkspace = {};

    for (const presence of active) {
      this.stats.usersByStatus[presence.status]++;

      if (presence.currentActivity) {
        this.stats.usersByActivity[presence.currentActivity.context]++;
      }

      if (presence.workspaceId) {
        this.stats.usersPerWorkspace[presence.workspaceId] =
          (this.stats.usersPerWorkspace[presence.workspaceId] || 0) + 1;
      }
    }

    this.stats.workspaces = Object.keys(this.stats.usersPerWorkspace).length;
    this.stats.peakConcurrency = Math.max(this.stats.totalUsers, this.stats.peakConcurrency || 0);
  }

  /**
   * Private: Start cleanup timer
   */
  private cleanupTimer: NodeJS.Timeout | null = null;

  private startCleanupTimer(): void {
    this.cleanupTimer = setInterval(() => {
      const now = Date.now();
      for (const [userId, presence] of this.presence.entries()) {
        if (presence.expiresAt <= now) {
          this.presence.delete(userId);
        }
      }
      this.updateStats();
    }, this.config.cleanupInterval);
  }

  /**
   * Private: Stop cleanup timer
   */
  private stopCleanupTimer(): void {
    if (this.cleanupTimer) {
      clearInterval(this.cleanupTimer);
      this.cleanupTimer = null;
    }
  }

  /**
   * Get global singleton instance
   */
  private static instance: PresenceService;

  static getInstance(config?: Partial<PresenceServiceConfig>): PresenceService {
    if (!PresenceService.instance) {
      PresenceService.instance = new PresenceService(config);
    }
    return PresenceService.instance;
  }
}
