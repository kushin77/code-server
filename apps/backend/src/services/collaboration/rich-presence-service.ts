#!/usr/bin/env node
// @file        apps/backend/src/services/collaboration/rich-presence-service.ts
// @module      collaboration/presence
// @description Rich presence system with file, function, task, and custom status tracking via Redis

import { EventEmitter } from 'events';
import { getLogger } from '../../lib/logger';

const logger = getLogger('RichPresenceService');

// Presence data structures
export interface PresenceStatus {
  userId: string;
  username: string;
  email?: string;
  avatarUrl?: string;
  status: 'online' | 'away' | 'idle' | 'offline';
  currentFile?: {
    path: string;
    line?: number;
    column?: number;
  };
  currentFunction?: {
    name: string;
    file: string;
    line: number;
  };
  currentTask?: {
    id: string;
    title: string;
    status: 'active' | 'paused' | 'completed';
  };
  customStatus?: {
    emoji?: string;
    text?: string;
    expiresAt?: number;
  };
  workspaceId: string;
  sessionId: string;
  lastActiveAt: number;
  cursorPosition?: { x: number; y: number };
  editingFile?: string;
}

export interface PresenceUpdate {
  userId: string;
  changes: Partial<PresenceStatus>;
}

export interface BulkPresenceQuery {
  workspaceId?: string;
  status?: 'online' | 'away' | 'idle' | 'offline';
  currentFile?: string;
  includeStats?: boolean;
}

export interface PresenceStats {
  totalUsers: number;
  onlineUsers: number;
  awayUsers: number;
  idleUsers: number;
  activeFiles: Record<string, number>; // filename -> count of users
  activeFunctions: Record<string, number>; // function name -> count of users
  activeTasks: Record<string, number>; // task id -> count of users
  workspaceStats: Record<string, { online: number; idle: number; away: number }>;
}

export class RichPresenceService extends EventEmitter {
  private presence: Map<string, PresenceStatus> = new Map();
  private redisPresenceCache: Map<string, PresenceStatus> = new Map(); // Simulated Redis with 4h TTL
  private presenceTTL: Map<string, number> = new Map(); // Track expiration timestamps
  private static instance: RichPresenceService;
  private readonly TTL_MS = 4 * 60 * 60 * 1000; // 4 hours
  private cleanupInterval?: NodeJS.Timeout;

  private constructor() {
    super();
    this.startCleanupTimer();
  }

  static getInstance(): RichPresenceService {
    if (!RichPresenceService.instance) {
      RichPresenceService.instance = new RichPresenceService();
    }
    return RichPresenceService.instance;
  }

  reset(): void {
    this.presence.clear();
    this.redisPresenceCache.clear();
    this.presenceTTL.clear();
    this.removeAllListeners();
    if (this.cleanupInterval) {
      clearInterval(this.cleanupInterval);
    }
    this.startCleanupTimer();
  }

  /**
   * Update or create presence
   */
  updatePresence(userId: string, updates: Partial<PresenceStatus>): PresenceStatus {
    const now = Date.now();
    const existingPresence = this.presence.get(userId);

    const presence: PresenceStatus = {
      userId,
      username: updates.username || existingPresence?.username || 'Unknown',
      email: updates.email || existingPresence?.email,
      avatarUrl: updates.avatarUrl || existingPresence?.avatarUrl,
      status: updates.status || existingPresence?.status || 'online',
      currentFile: updates.currentFile || existingPresence?.currentFile,
      currentFunction: updates.currentFunction || existingPresence?.currentFunction,
      currentTask: updates.currentTask || existingPresence?.currentTask,
      customStatus: updates.customStatus || existingPresence?.customStatus,
      workspaceId: updates.workspaceId || existingPresence?.workspaceId || '',
      sessionId: updates.sessionId || existingPresence?.sessionId || '',
      lastActiveAt: now,
      cursorPosition: updates.cursorPosition || existingPresence?.cursorPosition,
      editingFile: updates.editingFile || existingPresence?.editingFile,
    };

    this.presence.set(userId, presence);

    // Store in Redis cache with TTL
    this.redisPresenceCache.set(userId, presence);
    this.presenceTTL.set(userId, now + this.TTL_MS);

    logger.debug(`Presence updated for user ${userId}`);
    this.emit('presenceUpdated', { userId, presence, changes: updates });

    return presence;
  }

  /**
   * Set user status
   */
  setStatus(userId: string, status: 'online' | 'away' | 'idle' | 'offline'): PresenceStatus | null {
    const presence = this.presence.get(userId);
    if (!presence) {
      return null;
    }

    presence.status = status;
    this.presence.set(userId, presence);
    this.redisPresenceCache.set(userId, presence);
    this.presenceTTL.set(userId, Date.now() + this.TTL_MS);

    this.emit('statusChanged', { userId, status });
    return presence;
  }

  /**
   * Update file being edited
   */
  setCurrentFile(userId: string, file: { path: string; line?: number; column?: number }): PresenceStatus | null {
    const presence = this.presence.get(userId);
    if (!presence) {
      return null;
    }

    presence.currentFile = file;
    presence.editingFile = file.path;
    this.presence.set(userId, presence);
    this.redisPresenceCache.set(userId, presence);
    this.presenceTTL.set(userId, Date.now() + this.TTL_MS);

    this.emit('fileChanged', { userId, file });
    return presence;
  }

  /**
   * Update current function being debugged/edited
   */
  setCurrentFunction(userId: string, func: { name: string; file: string; line: number }): PresenceStatus | null {
    const presence = this.presence.get(userId);
    if (!presence) {
      return null;
    }

    presence.currentFunction = func;
    this.presence.set(userId, presence);
    this.redisPresenceCache.set(userId, presence);
    this.presenceTTL.set(userId, Date.now() + this.TTL_MS);

    this.emit('functionChanged', { userId, function: func });
    return presence;
  }

  /**
   * Update current task
   */
  setCurrentTask(userId: string, task: { id: string; title: string; status: 'active' | 'paused' | 'completed' }): PresenceStatus | null {
    const presence = this.presence.get(userId);
    if (!presence) {
      return null;
    }

    presence.currentTask = task;
    this.presence.set(userId, presence);
    this.redisPresenceCache.set(userId, presence);
    this.presenceTTL.set(userId, Date.now() + this.TTL_MS);

    this.emit('taskChanged', { userId, task });
    return presence;
  }

  /**
   * Set custom status (emoji + text)
   */
  setCustomStatus(userId: string, customStatus: { emoji?: string; text?: string; expiresIn?: number }): PresenceStatus | null {
    const presence = this.presence.get(userId);
    if (!presence) {
      return null;
    }

    const expiresAt = customStatus.expiresIn ? Date.now() + customStatus.expiresIn : undefined;
    presence.customStatus = {
      emoji: customStatus.emoji,
      text: customStatus.text,
      expiresAt,
    };

    this.presence.set(userId, presence);
    this.redisPresenceCache.set(userId, presence);
    this.presenceTTL.set(userId, Date.now() + this.TTL_MS);

    this.emit('customStatusChanged', { userId, customStatus: presence.customStatus });
    return presence;
  }

  /**
   * Clear custom status
   */
  clearCustomStatus(userId: string): PresenceStatus | null {
    const presence = this.presence.get(userId);
    if (!presence) {
      return null;
    }

    presence.customStatus = undefined;
    this.presence.set(userId, presence);
    this.redisPresenceCache.set(userId, presence);
    this.presenceTTL.set(userId, Date.now() + this.TTL_MS);

    this.emit('customStatusCleared', { userId });
    return presence;
  }

  /**
   * Update cursor position
   */
  setCursorPosition(userId: string, position: { x: number; y: number }): PresenceStatus | null {
    const presence = this.presence.get(userId);
    if (!presence) {
      return null;
    }

    presence.cursorPosition = position;
    presence.lastActiveAt = Date.now();
    this.presence.set(userId, presence);
    this.redisPresenceCache.set(userId, presence);
    this.presenceTTL.set(userId, Date.now() + this.TTL_MS);

    this.emit('cursorMoved', { userId, position });
    return presence;
  }

  /**
   * Get presence for user
   */
  getPresence(userId: string): PresenceStatus | undefined {
    return this.presence.get(userId);
  }

  /**
   * Get all presences in workspace
   */
  getWorkspacePresence(workspaceId: string): PresenceStatus[] {
    return Array.from(this.presence.values()).filter((p) => p.workspaceId === workspaceId);
  }

  /**
   * Get users editing a specific file
   */
  getUsersOnFile(filePath: string): PresenceStatus[] {
    return Array.from(this.presence.values()).filter((p) => p.currentFile?.path === filePath);
  }

  /**
   * Get users in a specific function
   */
  getUsersOnFunction(functionName: string): PresenceStatus[] {
    return Array.from(this.presence.values()).filter((p) => p.currentFunction?.name === functionName);
  }

  /**
   * Get users on a specific task
   */
  getUsersOnTask(taskId: string): PresenceStatus[] {
    return Array.from(this.presence.values()).filter((p) => p.currentTask?.id === taskId);
  }

  /**
   * Get all online users
   */
  getOnlineUsers(): PresenceStatus[] {
    return Array.from(this.presence.values()).filter((p) => p.status === 'online' || p.status === 'idle');
  }

  /**
   * Bulk presence query with filtering
   */
  queryPresence(query: BulkPresenceQuery): PresenceStatus[] {
    let results = Array.from(this.presence.values());

    if (query.workspaceId) {
      results = results.filter((p) => p.workspaceId === query.workspaceId);
    }

    if (query.status) {
      results = results.filter((p) => p.status === query.status);
    }

    if (query.currentFile) {
      results = results.filter((p) => p.currentFile?.path === query.currentFile);
    }

    return results;
  }

  /**
   * Remove presence
   */
  removePresence(userId: string): boolean {
    const result = this.presence.delete(userId);
    this.redisPresenceCache.delete(userId);
    this.presenceTTL.delete(userId);

    if (result) {
      logger.debug(`Presence removed for user ${userId}`);
      this.emit('presenceRemoved', { userId });
    }

    return result;
  }

  /**
   * Get presence statistics
   */
  getStatistics(): PresenceStats {
    const presences = Array.from(this.presence.values());

    const stats: PresenceStats = {
      totalUsers: presences.length,
      onlineUsers: presences.filter((p) => p.status === 'online').length,
      awayUsers: presences.filter((p) => p.status === 'away').length,
      idleUsers: presences.filter((p) => p.status === 'idle').length,
      activeFiles: {},
      activeFunctions: {},
      activeTasks: {},
      workspaceStats: {},
    };

    // Count active files
    for (const presence of presences) {
      if (presence.currentFile?.path) {
        stats.activeFiles[presence.currentFile.path] = (stats.activeFiles[presence.currentFile.path] || 0) + 1;
      }

      if (presence.currentFunction?.name) {
        stats.activeFunctions[presence.currentFunction.name] = (stats.activeFunctions[presence.currentFunction.name] || 0) + 1;
      }

      if (presence.currentTask?.id) {
        stats.activeTasks[presence.currentTask.id] = (stats.activeTasks[presence.currentTask.id] || 0) + 1;
      }

      // Workspace stats
      if (!stats.workspaceStats[presence.workspaceId]) {
        stats.workspaceStats[presence.workspaceId] = { online: 0, idle: 0, away: 0 };
      }

      if (presence.status === 'online') stats.workspaceStats[presence.workspaceId].online += 1;
      if (presence.status === 'idle') stats.workspaceStats[presence.workspaceId].idle += 1;
      if (presence.status === 'away') stats.workspaceStats[presence.workspaceId].away += 1;
    }

    return stats;
  }

  /**
   * Broadcast presence update to all users (for real-time sync)
   */
  broadcastPresenceUpdate(userId: string): PresenceStatus | null {
    const presence = this.presence.get(userId);
    if (!presence) {
      return null;
    }

    this.emit('presenceBroadcast', presence);
    return presence;
  }

  /**
   * Get presence from Redis cache (simulated)
   */
  getFromCache(userId: string): PresenceStatus | undefined {
    // Check if expired
    const expiresAt = this.presenceTTL.get(userId);
    if (expiresAt && Date.now() > expiresAt) {
      this.removePresence(userId);
      return undefined;
    }

    return this.redisPresenceCache.get(userId);
  }

  /**
   * Get all cached presences
   */
  getAllCached(): PresenceStatus[] {
    const results: PresenceStatus[] = [];
    const now = Date.now();

    for (const [userId] of this.presenceTTL) {
      const expiresAt = this.presenceTTL.get(userId);
      if (expiresAt && now > expiresAt) {
        this.removePresence(userId);
      } else {
        const presence = this.redisPresenceCache.get(userId);
        if (presence) {
          results.push(presence);
        }
      }
    }

    return results;
  }

  /**
   * Get active count by status (Redis-like operation)
   */
  countByStatus(workspaceId?: string): Record<string, number> {
    let presences = Array.from(this.presence.values());

    if (workspaceId) {
      presences = presences.filter((p) => p.workspaceId === workspaceId);
    }

    return {
      online: presences.filter((p) => p.status === 'online').length,
      away: presences.filter((p) => p.status === 'away').length,
      idle: presences.filter((p) => p.status === 'idle').length,
      offline: presences.filter((p) => p.status === 'offline').length,
    };
  }

  // Private helper methods

  private startCleanupTimer(): void {
    // Clean expired entries every 30 minutes
    this.cleanupInterval = setInterval(() => {
      const now = Date.now();
      const expiredUsers: string[] = [];

      for (const [userId, expiresAt] of this.presenceTTL) {
        if (now > expiresAt) {
          expiredUsers.push(userId);
        }
      }

      for (const userId of expiredUsers) {
        this.removePresence(userId);
        logger.debug(`Expired presence for user ${userId}`);
        this.emit('presenceExpired', { userId });
      }
    }, 30 * 60 * 1000);
  }
}

export default RichPresenceService.getInstance();
