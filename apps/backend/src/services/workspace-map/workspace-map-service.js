import { EventEmitter } from 'events';
import pino from 'pino';
export class WorkspaceMapService extends EventEmitter {
    constructor(options) {
        super();
        this.activeSessions = new Map();
        this.activeFiles = new Map();
        this.sessionHistory = [];
        this.metrics = {
            peakConcurrentUsers: 0,
            sessionStartTimes: new Map(),
        };
        this.workspaceId = options.workspaceId;
        this.logger = options.logger || pino({
            base: { service: 'workspace-map', workspace: options.workspaceId },
        });
    }
    static getInstance(options) {
        if (!this.instances.has(options.workspaceId)) {
            this.instances.set(options.workspaceId, new WorkspaceMapService(options));
        }
        return this.instances.get(options.workspaceId);
    }
    /**
     * Register a new user session
     */
    registerSession(userId, userName) {
        const session = {
            userId,
            userName,
            status: 'online',
            joinedAt: new Date(),
            lastActive: new Date(),
        };
        this.activeSessions.set(userId, session);
        this.metrics.sessionStartTimes.set(userId, new Date());
        this.updateMetrics();
        this.logger.info(`User ${userId} registered session in workspace ${this.workspaceId}`);
        this.emit('session-registered', { userId, session });
    }
    /**
     * Update user's current file and cursor position
     */
    updateUserActivity(userId, currentFile, cursorPosition) {
        const session = this.activeSessions.get(userId);
        if (!session) {
            this.logger.warn(`Session not found for user ${userId}`);
            return;
        }
        // Update session
        session.currentFile = currentFile;
        session.cursorPosition = cursorPosition;
        session.lastActive = new Date();
        session.status = 'online';
        // Track file activity
        if (!this.activeFiles.has(currentFile)) {
            this.activeFiles.set(currentFile, {
                path: currentFile,
                isOpen: true,
                activeUsers: [userId],
                lastModified: new Date(),
            });
        }
        else {
            const file = this.activeFiles.get(currentFile);
            if (!file.activeUsers.includes(userId)) {
                file.activeUsers.push(userId);
            }
            file.lastModified = new Date();
        }
        this.emit('user-activity-updated', { userId, currentFile, cursorPosition });
    }
    /**
     * Mark user as idle
     */
    markUserIdle(userId) {
        const session = this.activeSessions.get(userId);
        if (!session)
            return;
        session.status = 'idle';
        session.lastActive = new Date();
        this.emit('user-status-changed', { userId, status: 'idle' });
    }
    /**
     * Mark user as offline
     */
    unregisterSession(userId) {
        const session = this.activeSessions.get(userId);
        if (!session)
            return;
        // Remove from active files
        this.activeFiles.forEach((file) => {
            const idx = file.activeUsers.indexOf(userId);
            if (idx !== -1) {
                file.activeUsers.splice(idx, 1);
            }
        });
        this.sessionHistory.push(session);
        this.activeSessions.delete(userId);
        this.metrics.sessionStartTimes.delete(userId);
        this.logger.info(`User ${userId} unregistered session in workspace ${this.workspaceId}`);
        this.emit('session-unregistered', { userId });
    }
    /**
     * Get current workspace snapshot
     */
    getWorkspaceSnapshot() {
        const activeSessions = Array.from(this.activeSessions.values());
        const activeFiles = Array.from(this.activeFiles.values()).filter((f) => f.activeUsers.length > 0);
        // Calculate metrics
        let mostActiveFile = null;
        let maxUsers = 0;
        activeFiles.forEach((file) => {
            if (file.activeUsers.length > maxUsers) {
                maxUsers = file.activeUsers.length;
                mostActiveFile = file.path;
            }
        });
        const avgSessionDuration = this.sessionHistory.length > 0
            ? this.sessionHistory.reduce((sum, s) => {
                const startTime = this.metrics.sessionStartTimes.get(s.userId) || s.joinedAt;
                const endTime = new Date();
                return sum + (endTime.getTime() - startTime.getTime());
            }, 0) / this.sessionHistory.length
            : 0;
        return {
            workspaceId: this.workspaceId,
            timestamp: new Date(),
            activeSessions,
            activeFiles,
            totalActiveUsers: activeSessions.length,
            totalOpenFiles: activeFiles.length,
            metrics: {
                averageSessionDuration: avgSessionDuration,
                peakConcurrentUsers: this.metrics.peakConcurrentUsers,
                mostActiveFile,
            },
        };
    }
    /**
     * Get active files
     */
    getActiveFiles() {
        return Array.from(this.activeFiles.values()).filter((f) => f.activeUsers.length > 0);
    }
    /**
     * Get active sessions
     */
    getActiveSessions() {
        return Array.from(this.activeSessions.values());
    }
    /**
     * Get session by user ID
     */
    getSession(userId) {
        return this.activeSessions.get(userId);
    }
    /**
     * Get file activity
     */
    getFileActivity(filePath) {
        return this.activeFiles.get(filePath);
    }
    /**
     * Get all users working on a specific file
     */
    getUsersOnFile(filePath) {
        const file = this.activeFiles.get(filePath);
        if (!file)
            return [];
        return file.activeUsers
            .map((userId) => this.activeSessions.get(userId))
            .filter((session) => session !== undefined);
    }
    /**
     * Query active files by pattern
     */
    queryActiveFiles(pattern) {
        const regex = new RegExp(pattern);
        return this.getActiveFiles().filter((file) => regex.test(file.path));
    }
    /**
     * Get workspace statistics
     */
    getStatistics() {
        return {
            workspaceId: this.workspaceId,
            activeUsers: this.activeSessions.size,
            activeFiles: Array.from(this.activeFiles.values()).filter((f) => f.activeUsers.length > 0)
                .length,
            peakConcurrency: this.metrics.peakConcurrentUsers,
            totalSessionsRecorded: this.sessionHistory.length,
        };
    }
    /**
     * Update metrics
     */
    updateMetrics() {
        const currentUsers = this.activeSessions.size;
        if (currentUsers > this.metrics.peakConcurrentUsers) {
            this.metrics.peakConcurrentUsers = currentUsers;
            this.emit('peak-concurrency-updated', { peakConcurrentUsers: currentUsers });
        }
    }
    /**
     * Reset workspace state
     */
    reset() {
        this.activeSessions.clear();
        this.activeFiles.clear();
        this.sessionHistory = [];
        this.metrics = { peakConcurrentUsers: 0, sessionStartTimes: new Map() };
        this.emit('workspace-reset');
    }
    /**
     * Shutdown service
     */
    shutdown() {
        this.reset();
        WorkspaceMapService.instances.delete(this.workspaceId);
        this.emit('shutdown');
    }
}
WorkspaceMapService.instances = new Map();
export function createWorkspaceMapService(options) {
    return WorkspaceMapService.getInstance(options);
}
//# sourceMappingURL=workspace-map-service.js.map