// @file        apps/backend/src/services/onboarding/persistence.ts
// @module      services/onboarding
// @description Progress persistence utilities for onboarding sessions
//              Saves and loads session state to persistent storage
//
import * as fs from 'fs';
import * as path from 'path';
import { promisify } from 'util';
import { logger } from '../../lib/logger';
const writeFile = promisify(fs.writeFile);
const readFile = promisify(fs.readFile);
const mkdir = promisify(fs.mkdir);
/**
 * OnboardingPersistence - handles saving and loading session state
 */
export class OnboardingPersistence {
    constructor(storageDir = './.onboarding-sessions', auditService) {
        this.auditService = auditService;
        this.storageDir = storageDir;
    }
    /**
     * Initialize storage directory
     */
    async initialize() {
        try {
            if (!fs.existsSync(this.storageDir)) {
                await mkdir(this.storageDir, { recursive: true });
                logger.info('Onboarding session storage directory created', { dir: this.storageDir });
            }
        }
        catch (error) {
            logger.error('Failed to initialize onboarding storage', error);
            throw error;
        }
    }
    /**
     * Save session to persistent storage
     */
    async saveSession(session) {
        try {
            await this.initialize();
            const filePath = this.getSessionFilePath(session.sessionId);
            const data = JSON.stringify(session, null, 2);
            await writeFile(filePath, data, 'utf-8');
            if (this.auditService) {
                this.auditService.emit({
                    userId: session.userId || 'system',
                    action: 'update',
                    resourceType: 'session',
                    resource: `onboarding-session:${session.sessionId}`,
                    metadata: {
                        filePath,
                        status: session.status,
                    },
                    reason: 'SOC2: Persisting onboarding session state',
                });
            }
            logger.debug('Onboarding session saved', {
                sessionId: session.sessionId,
                filePath,
            });
        }
        catch (error) {
            logger.error('Failed to save onboarding session', error);
            throw error;
        }
    }
    /**
     * Load session from persistent storage
     */
    async loadSession(sessionId) {
        try {
            const filePath = this.getSessionFilePath(sessionId);
            if (!fs.existsSync(filePath)) {
                return null;
            }
            const data = await readFile(filePath, 'utf-8');
            const session = JSON.parse(data);
            if (this.auditService) {
                this.auditService.emit({
                    userId: session.userId || 'system',
                    action: 'read',
                    resourceType: 'session',
                    resource: `onboarding-session:${sessionId}`,
                    metadata: {
                        filePath,
                        status: session.status,
                    },
                    reason: 'SOC2: Reading onboarding session state',
                });
            }
            logger.debug('Onboarding session loaded', {
                sessionId,
                filePath,
            });
            return session;
        }
        catch (error) {
            logger.error('Failed to load onboarding session', error);
            throw error;
        }
    }
    /**
     * Save session progress checkpoint
     */
    async saveCheckpoint(sessionId, checkpoint) {
        try {
            await this.initialize();
            const checkpointDir = path.join(this.storageDir, sessionId, 'checkpoints');
            if (!fs.existsSync(checkpointDir)) {
                await mkdir(checkpointDir, { recursive: true });
            }
            const filePath = path.join(checkpointDir, `checkpoint-${checkpoint.timestamp}.json`);
            const data = JSON.stringify(checkpoint, null, 2);
            await writeFile(filePath, data, 'utf-8');
            if (this.auditService) {
                this.auditService.emit({
                    userId: 'system',
                    action: 'create',
                    resourceType: 'checkpoint',
                    resource: `onboarding-checkpoint:${sessionId}:${checkpoint.timestamp}`,
                    metadata: {
                        filePath,
                        stepIndex: checkpoint.stepIndex,
                        completedSteps: checkpoint.completedSteps,
                        skippedSteps: checkpoint.skippedSteps,
                    },
                    reason: 'SOC2: Creating onboarding progress checkpoint',
                });
            }
            logger.debug('Onboarding checkpoint saved', {
                sessionId,
                checkpointTime: new Date(checkpoint.timestamp).toISOString(),
            });
        }
        catch (error) {
            logger.error('Failed to save onboarding checkpoint', error);
            throw error;
        }
    }
    /**
     * Load latest checkpoint
     */
    async loadLatestCheckpoint(sessionId) {
        try {
            const checkpointDir = path.join(this.storageDir, sessionId, 'checkpoints');
            if (!fs.existsSync(checkpointDir)) {
                return null;
            }
            const files = fs.readdirSync(checkpointDir).sort().reverse();
            if (files.length === 0) {
                return null;
            }
            const latestFile = files[0];
            const filePath = path.join(checkpointDir, latestFile);
            const data = await readFile(filePath, 'utf-8');
            const checkpoint = JSON.parse(data);
            if (this.auditService) {
                this.auditService.emit({
                    userId: 'system',
                    action: 'read',
                    resourceType: 'checkpoint',
                    resource: `onboarding-checkpoint:${sessionId}:${latestFile}`,
                    metadata: {
                        filePath,
                        fileName: latestFile,
                    },
                    reason: 'SOC2: Reading latest onboarding checkpoint',
                });
            }
            return checkpoint;
        }
        catch (error) {
            logger.error('Failed to load latest checkpoint', error);
            throw error;
        }
    }
    /**
     * List all checkpoints for a session
     */
    async listCheckpoints(sessionId) {
        try {
            const checkpointDir = path.join(this.storageDir, sessionId, 'checkpoints');
            if (!fs.existsSync(checkpointDir)) {
                return [];
            }
            return fs.readdirSync(checkpointDir).sort();
        }
        catch (error) {
            logger.error('Failed to list checkpoints', error);
            throw error;
        }
    }
    /**
     * Delete session data
     */
    async deleteSession(sessionId) {
        try {
            const sessionDir = path.join(this.storageDir, sessionId);
            if (fs.existsSync(sessionDir)) {
                fs.rmSync(sessionDir, { recursive: true, force: true });
                if (this.auditService) {
                    this.auditService.emit({
                        userId: 'system',
                        action: 'delete',
                        resourceType: 'session',
                        resource: `onboarding-session:${sessionId}:checkpoints`,
                        metadata: {
                            sessionDir,
                        },
                        reason: 'SOC2: Onboarding session checkpoint deletion',
                    });
                }
                logger.info('Onboarding session deleted', { sessionId });
            }
            const filePath = this.getSessionFilePath(sessionId);
            if (fs.existsSync(filePath)) {
                fs.rmSync(filePath);
                if (this.auditService) {
                    this.auditService.emit({
                        userId: 'system',
                        action: 'delete',
                        resourceType: 'session',
                        resource: `onboarding-session:${sessionId}`,
                        metadata: {
                            filePath,
                        },
                        reason: 'SOC2: Onboarding session deletion',
                    });
                }
            }
        }
        catch (error) {
            logger.error('Failed to delete onboarding session', error);
            throw error;
        }
    }
    /**
     * Get all sessions
     */
    async getAllSessions() {
        try {
            await this.initialize();
            if (!fs.existsSync(this.storageDir)) {
                return [];
            }
            const files = fs.readdirSync(this.storageDir).filter((f) => f.endsWith('.json'));
            const sessions = [];
            for (const file of files) {
                const filePath = path.join(this.storageDir, file);
                const data = await readFile(filePath, 'utf-8');
                sessions.push(JSON.parse(data));
            }
            return sessions;
        }
        catch (error) {
            logger.error('Failed to get all sessions', error);
            throw error;
        }
    }
    /**
     * Get session statistics
     */
    async getSessionStats() {
        try {
            const sessions = await this.getAllSessions();
            const completed = sessions.filter((s) => s.completedAt);
            const avgDuration = completed.length > 0
                ? completed.reduce((sum, s) => sum + (s.totalDurationMs || 0), 0) / completed.length
                : 0;
            return {
                totalSessions: sessions.length,
                completedSessions: completed.length,
                averageDurationMs: avgDuration,
                completionRate: (completed.length / sessions.length) * 100 || 0,
            };
        }
        catch (error) {
            logger.error('Failed to get session stats', error);
            throw error;
        }
    }
    /**
     * Export session as JSON
     */
    async exportSession(sessionId) {
        try {
            const session = await this.loadSession(sessionId);
            if (!session) {
                throw new Error(`Session not found: ${sessionId}`);
            }
            return JSON.stringify(session, null, 2);
        }
        catch (error) {
            logger.error('Failed to export session', error);
            throw error;
        }
    }
    /**
     * Get session file path
     */
    getSessionFilePath(sessionId) {
        return path.join(this.storageDir, `${sessionId}.json`);
    }
}
/**
 * Export global persistence instance
 */
export const onboardingPersistence = new OnboardingPersistence();
//# sourceMappingURL=persistence.js.map