#!/usr/bin/env node
// @file        apps/backend/src/services/collaboration/rich-presence-service.ts
// @module      collaboration/presence
// @description Rich presence system with file, function, task, and custom status tracking via Redis
import { EventEmitter } from 'events';
import { getLogger } from '../../lib/logger';
import { getTracer, withSpanSync } from '../../lib/tracing';
const logger = getLogger('RichPresenceService');
const tracer = getTracer('collaboration/rich-presence');
export class RichPresenceService extends EventEmitter {
    constructor() {
        super();
        this.presence = new Map();
        this.redisPresenceCache = new Map(); // Simulated Redis with 4h TTL
        this.presenceTTL = new Map(); // Track expiration timestamps
        this.TTL_MS = 4 * 60 * 60 * 1000; // 4 hours
        this.startCleanupTimer();
    }
    static getInstance() {
        if (!RichPresenceService.instance) {
            RichPresenceService.instance = new RichPresenceService();
        }
        return RichPresenceService.instance;
    }
    reset() {
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
    updatePresence(userId, updates) {
        const existingPresence = this.presence.get(userId);
        return withSpanSync(tracer, 'collaboration.presence.updatePresence', {
            'user.id': userId,
            'workspace.id': updates.workspaceId || existingPresence?.workspaceId || '',
        }, () => {
            const now = Date.now();
            const presence = {
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
        });
    }
    /**
     * Set user status
     */
    setStatus(userId, status) {
        return withSpanSync(tracer, 'collaboration.presence.setStatus', {
            'user.id': userId,
            'presence.status': status,
        }, () => {
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
        });
    }
    /**
     * Update file being edited
     */
    setCurrentFile(userId, file) {
        return withSpanSync(tracer, 'collaboration.presence.setCurrentFile', {
            'user.id': userId,
            'file.path': file.path,
        }, () => {
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
        });
    }
    /**
     * Update current function being debugged/edited
     */
    setCurrentFunction(userId, func) {
        return withSpanSync(tracer, 'collaboration.presence.setCurrentFunction', {
            'user.id': userId,
            'function.name': func.name,
            'function.file': func.file,
        }, () => {
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
        });
    }
    /**
     * Update current task
     */
    setCurrentTask(userId, task) {
        return withSpanSync(tracer, 'collaboration.presence.setCurrentTask', {
            'user.id': userId,
            'task.id': task.id,
        }, () => {
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
        });
    }
    /**
     * Set custom status (emoji + text)
     */
    setCustomStatus(userId, customStatus) {
        return withSpanSync(tracer, 'collaboration.presence.setCustomStatus', {
            'user.id': userId,
        }, () => {
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
        });
    }
    /**
     * Clear custom status
     */
    clearCustomStatus(userId) {
        return withSpanSync(tracer, 'collaboration.presence.clearCustomStatus', {
            'user.id': userId,
        }, () => {
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
        });
    }
    /**
     * Update cursor position
     */
    setCursorPosition(userId, position) {
        return withSpanSync(tracer, 'collaboration.presence.setCursorPosition', {
            'user.id': userId,
        }, () => {
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
        });
    }
    /**
     * Get presence for user
     */
    getPresence(userId) {
        return this.presence.get(userId);
    }
    /**
     * Get all presences in workspace
     */
    getWorkspacePresence(workspaceId) {
        return Array.from(this.presence.values()).filter((p) => p.workspaceId === workspaceId);
    }
    /**
     * Get users editing a specific file
     */
    getUsersOnFile(filePath) {
        return Array.from(this.presence.values()).filter((p) => p.currentFile?.path === filePath);
    }
    /**
     * Get users in a specific function
     */
    getUsersOnFunction(functionName) {
        return Array.from(this.presence.values()).filter((p) => p.currentFunction?.name === functionName);
    }
    /**
     * Get users on a specific task
     */
    getUsersOnTask(taskId) {
        return Array.from(this.presence.values()).filter((p) => p.currentTask?.id === taskId);
    }
    /**
     * Get all online users
     */
    getOnlineUsers() {
        return Array.from(this.presence.values()).filter((p) => p.status === 'online' || p.status === 'idle');
    }
    /**
     * Bulk presence query with filtering
     */
    queryPresence(query) {
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
    removePresence(userId) {
        return withSpanSync(tracer, 'collaboration.presence.removePresence', {
            'user.id': userId,
        }, () => {
            const result = this.presence.delete(userId);
            this.redisPresenceCache.delete(userId);
            this.presenceTTL.delete(userId);
            if (result) {
                logger.debug(`Presence removed for user ${userId}`);
                this.emit('presenceRemoved', { userId });
            }
            return result;
        });
    }
    /**
     * Get presence statistics
     */
    getStatistics() {
        const presences = Array.from(this.presence.values());
        const stats = {
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
            if (presence.status === 'online')
                stats.workspaceStats[presence.workspaceId].online += 1;
            if (presence.status === 'idle')
                stats.workspaceStats[presence.workspaceId].idle += 1;
            if (presence.status === 'away')
                stats.workspaceStats[presence.workspaceId].away += 1;
        }
        return stats;
    }
    /**
     * Broadcast presence update to all users (for real-time sync)
     */
    broadcastPresenceUpdate(userId) {
        return withSpanSync(tracer, 'collaboration.presence.broadcastPresenceUpdate', {
            'user.id': userId,
        }, () => {
            const presence = this.presence.get(userId);
            if (!presence) {
                return null;
            }
            this.emit('presenceBroadcast', presence);
            return presence;
        });
    }
    /**
     * Get presence from Redis cache (simulated)
     */
    getFromCache(userId) {
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
    getAllCached() {
        const results = [];
        const now = Date.now();
        for (const [userId] of this.presenceTTL) {
            const expiresAt = this.presenceTTL.get(userId);
            if (expiresAt && now > expiresAt) {
                this.removePresence(userId);
            }
            else {
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
    countByStatus(workspaceId) {
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
    startCleanupTimer() {
        // Clean expired entries every 30 minutes
        this.cleanupInterval = setInterval(() => {
            const now = Date.now();
            const expiredUsers = [];
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
//# sourceMappingURL=rich-presence-service.js.map