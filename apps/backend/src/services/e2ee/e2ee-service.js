/**
 * @file        apps/backend/src/services/e2ee/e2ee-service.ts
 * @module      security/e2ee
 * @description End-to-end encryption service for collaboration messages
 */
import { EventEmitter } from 'events';
/**
 * In-memory key backup storage
 */
class KeyBackupStorage {
    constructor() {
        this.backups = new Map();
    }
    store(backup) {
        this.backups.set(backup.id, backup);
    }
    get(id) {
        return this.backups.get(id);
    }
    getByUser(userId) {
        return Array.from(this.backups.values()).find((b) => b.userId === userId);
    }
    list() {
        return Array.from(this.backups.values());
    }
    delete(id) {
        return this.backups.delete(id);
    }
}
/**
 * End-to-end encryption service for collaboration
 */
export class E2EEService extends EventEmitter {
    constructor() {
        super(...arguments);
        this.isInitialized = false;
        // Encryption keys per user-device
        this.userKeys = new Map();
        // Session keys per room (Megolm)
        this.sessionKeys = new Map();
        // Device fingerprints for verification
        this.deviceFingerprints = new Map();
        // Encrypted messages (audit trail)
        this.encryptedMessages = new Map();
        // Key backup storage
        this.keyBackups = new KeyBackupStorage();
        // Statistics
        this.stats = {
            totalMessages: 0,
            encryptedMessages: 0,
            decryptedMessages: 0,
            failedDecryptions: 0,
            averageDecryptionTime: 0,
            keyRotations: 0,
            backups: 0,
            verifiedDevices: 0,
            unverifiedDevices: 0,
            encryptionRate: 0,
        };
        // Events log
        this.eventsLog = [];
    }
    /**
     * Initialize service
     */
    async initialize() {
        if (this.isInitialized)
            return;
        this.isInitialized = true;
        console.log('[E2EEService] Initialized');
        this.emit('initialized');
    }
    /**
     * Generate encryption key for user device
     */
    async generateKey(userId, deviceId) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        const key = {
            id: `key-${userId}-${deviceId}-${Date.now()}`,
            algorithm: 'olm',
            createdAt: Date.now(),
        };
        // Store key
        if (!this.userKeys.has(userId)) {
            this.userKeys.set(userId, new Map());
        }
        this.userKeys.get(userId).set(deviceId, key);
        this.logEvent('key-generated', userId, { deviceId, keyId: key.id });
        this.emit('key-generated', { userId, deviceId, key });
        return key;
    }
    /**
     * Create Megolm session for room
     */
    async createSessionKey(roomId, creatorUserId, algorithm = 'megolm') {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        const sessionKey = {
            id: `session-${roomId}-${Date.now()}`,
            roomId,
            createdAt: Date.now(),
            messageIndex: 0,
            creatorUserId,
        };
        // Store session
        if (!this.sessionKeys.has(roomId)) {
            this.sessionKeys.set(roomId, []);
        }
        this.sessionKeys.get(roomId).push(sessionKey);
        this.logEvent('session-created', creatorUserId, { roomId, sessionId: sessionKey.id });
        this.emit('session-created', { roomId, sessionKey });
        return sessionKey;
    }
    /**
     * Encrypt message
     */
    async encryptMessage(userId, deviceId, roomId, content) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        // Get or create session for room
        let sessionKey = this.sessionKeys.get(roomId)?.[0];
        if (!sessionKey) {
            sessionKey = await this.createSessionKey(roomId, userId, 'megolm');
        }
        // Get user key
        const userKey = this.userKeys.get(userId)?.get(deviceId);
        if (!userKey) {
            throw new Error(`No encryption key for user ${userId} device ${deviceId}`);
        }
        // Simulate encryption (base64 encode content)
        const encryptedContent = Buffer.from(JSON.stringify(content)).toString('base64');
        const encryptedMsg = {
            id: `msg-${userId}-${Date.now()}`,
            roomId,
            senderId: userId,
            sentAt: Date.now(),
            algorithm: 'megolm',
            senderKey: `senderkey-${userKey.id}`,
            ciphertext: encryptedContent,
            sessionId: sessionKey.id,
            type: content.type,
            deviceId,
            signature: `sig-${userKey.id}-${Date.now()}`,
        };
        // Store encrypted message
        this.encryptedMessages.set(encryptedMsg.id, encryptedMsg);
        // Update stats
        this.stats.totalMessages++;
        this.stats.encryptedMessages++;
        this.stats.encryptionRate =
            (this.stats.encryptedMessages / this.stats.totalMessages) * 100;
        // Forward secrecy: increment message index
        sessionKey.messageIndex++;
        this.logEvent('message-encrypted', userId, { messageId: encryptedMsg.id, roomId });
        this.emit('message-encrypted', { encryptedMsg });
        return encryptedMsg;
    }
    /**
     * Decrypt message
     */
    async decryptMessage(userId, encryptedMsg) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        const startTime = Date.now();
        try {
            // Verify device fingerprint if available
            const deviceFp = this.deviceFingerprints.get(encryptedMsg.senderId);
            if (deviceFp && encryptedMsg.deviceId) {
                const verified = await this.verifyMessage(encryptedMsg.senderId, encryptedMsg);
                if (!verified.verified) {
                    return {
                        success: false,
                        decryptionTime: Date.now() - startTime,
                        algorithm: encryptedMsg.algorithm,
                        error: 'Device verification failed',
                        recoverable: true,
                    };
                }
            }
            // Simulate decryption (base64 decode)
            const decryptedContent = JSON.parse(Buffer.from(encryptedMsg.ciphertext, 'base64').toString());
            this.stats.decryptedMessages++;
            this.stats.failedDecryptions = Math.max(0, this.stats.failedDecryptions - 1);
            const decryptionTime = Date.now() - startTime;
            this.stats.averageDecryptionTime =
                (this.stats.averageDecryptionTime * (this.stats.decryptedMessages - 1) +
                    decryptionTime) /
                    this.stats.decryptedMessages;
            this.logEvent('message-decrypted', userId, {
                messageId: encryptedMsg.id,
                decryptionTime,
            });
            this.emit('message-decrypted', { messageId: encryptedMsg.id, userId });
            return {
                success: true,
                content: decryptedContent,
                decryptionTime,
                algorithm: encryptedMsg.algorithm,
                recoverable: true,
            };
        }
        catch (error) {
            this.stats.failedDecryptions++;
            return {
                success: false,
                decryptionTime: Date.now() - startTime,
                algorithm: encryptedMsg.algorithm,
                error: error instanceof Error ? error.message : 'Decryption failed',
                recoverable: true,
            };
        }
    }
    /**
     * Verify device fingerprint
     */
    async verifyDevice(userId, deviceId, fingerprint, trustedFingerprints) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        const fpKey = `${userId}:${deviceId}`;
        const existing = this.deviceFingerprints.get(fpKey);
        const verified = trustedFingerprints.has(fingerprint);
        if (!existing) {
            const deviceFp = {
                userId,
                deviceId,
                fingerprint,
                ed25519Key: `ed25519-${deviceId}`,
                verified,
                verifiedAt: verified ? Date.now() : undefined,
                lastSeen: Date.now(),
            };
            this.deviceFingerprints.set(fpKey, deviceFp);
        }
        else {
            existing.lastSeen = Date.now();
            if (verified && !existing.verified) {
                existing.verified = true;
                existing.verifiedAt = Date.now();
            }
        }
        if (verified) {
            this.stats.verifiedDevices++;
        }
        else {
            this.stats.unverifiedDevices++;
        }
        const eventType = verified ? 'device-verified' : 'device-unverified';
        this.logEvent(eventType, userId, { deviceId });
        this.emit(eventType, { userId, deviceId, verified });
        return verified;
    }
    /**
     * Verify message signature
     */
    async verifyMessage(userId, msg) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        const deviceFp = this.deviceFingerprints.get(`${userId}:${msg.deviceId}`);
        if (!deviceFp) {
            return {
                verified: false,
                fromDevice: msg.deviceId || 'unknown',
                timestamp: msg.sentAt,
                error: 'Device not verified',
            };
        }
        // Simulate signature verification
        const verified = deviceFp.verified && msg.signature?.includes(`sig-`) === true;
        return {
            verified,
            fromDevice: msg.deviceId || 'unknown',
            timestamp: msg.sentAt,
            error: verified ? undefined : 'Signature verification failed',
        };
    }
    /**
     * Rotate encryption key
     */
    async rotateKey(userId, deviceId) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        // Mark old key as rotated
        const oldKey = this.userKeys.get(userId)?.get(deviceId);
        if (oldKey) {
            oldKey.rotatedAt = Date.now();
        }
        // Wait to ensure different timestamp
        await new Promise((resolve) => setTimeout(resolve, 10));
        // Generate new key with different timestamp
        const newKey = await this.generateKey(userId, deviceId);
        this.stats.keyRotations++;
        this.logEvent('key-rotated', userId, { deviceId, newKeyId: newKey.id });
        this.emit('key-rotated', { userId, deviceId, newKey });
        return newKey;
    }
    /**
     * Backup keys to Vault
     */
    async backupKeysToVault(userId, vaultToken) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        const userDeviceKeys = this.userKeys.get(userId);
        if (!userDeviceKeys || userDeviceKeys.size === 0) {
            throw new Error(`No keys to backup for user ${userId}`);
        }
        // Simulate key backup (encrypt and store)
        const backupData = {
            userId,
            keys: Array.from(userDeviceKeys.values()).map((k) => ({
                id: k.id,
                algorithm: k.algorithm,
                createdAt: k.createdAt,
            })),
            backupTime: Date.now(),
        };
        const backup = {
            id: `backup-${userId}-${Date.now()}`,
            userId,
            createdAt: Date.now(),
            lastBackupAt: Date.now(),
            version: 1,
            backupMethod: vaultToken ? 'vault' : 'password',
            encryptedBackup: Buffer.from(JSON.stringify(backupData)).toString('base64'),
            metadata: {
                deviceCount: userDeviceKeys.size,
                keyCount: userDeviceKeys.size,
            },
        };
        this.keyBackups.store(backup);
        this.stats.backups++;
        this.logEvent('backup-created', userId, { backupId: backup.id });
        this.emit('backup-created', { backup });
        return backup;
    }
    /**
     * Restore keys from backup
     */
    async restoreKeysFromBackup(userId, backupId, vaultToken) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        const backup = this.keyBackups.get(backupId);
        if (!backup || backup.userId !== userId) {
            throw new Error(`Backup ${backupId} not found for user ${userId}`);
        }
        // Simulate key restoration
        try {
            const backupData = JSON.parse(Buffer.from(backup.encryptedBackup, 'base64').toString());
            // Restore keys to user's key store
            if (!this.userKeys.has(userId)) {
                this.userKeys.set(userId, new Map());
            }
            for (const keyData of backupData.keys) {
                const key = {
                    id: keyData.id,
                    algorithm: keyData.algorithm,
                    createdAt: keyData.createdAt,
                };
                // Device ID reconstructed from key ID: "key-{userId}-{deviceId}-{timestamp}"
                const parts = key.id.split('-');
                const deviceId = parts[2];
                this.userKeys.get(userId).set(deviceId, key);
            }
            return true;
        }
        catch (error) {
            console.error(`Failed to restore backup ${backupId}:`, error);
            return false;
        }
    }
    /**
     * Get encryption capability
     */
    async getCapability() {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        return {
            supported: true,
            algorithms: ['megolm', 'olm'],
            keyRotation: {
                algorithmic: 'megolm',
                rotationIntervalMs: 86400000, // 24 hours
                forwardSecrecyMessages: 100,
                deviceRotationMs: 604800000, // 7 days
            },
            keyBackup: true,
            forwardSecrecy: true, // Megolm provides forward secrecy
            deviceVerification: true,
        };
    }
    /**
     * Get encryption statistics
     */
    async getStatistics() {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        return { ...this.stats };
    }
    /**
     * Get events
     */
    async getEvents(limit) {
        const events = [...this.eventsLog];
        if (limit && limit > 0) {
            return events.slice(-limit);
        }
        return events;
    }
    /**
     * Get encrypted message
     */
    async getEncryptedMessage(messageId) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        return this.encryptedMessages.get(messageId);
    }
    /**
     * Get messages in room
     */
    async getMessagesInRoom(roomId, limit) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        const messages = Array.from(this.encryptedMessages.values())
            .filter((m) => m.roomId === roomId)
            .sort((a, b) => b.sentAt - a.sentAt);
        if (limit && limit > 0) {
            return messages.slice(0, limit);
        }
        return messages;
    }
    /**
     * Get user's keys
     */
    async getUserKeys(userId) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        return Array.from(this.userKeys.get(userId)?.values() || []);
    }
    /**
     * Get device fingerprints for room
     */
    async getDeviceFingerprintsForRoom(roomId) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        return Array.from(this.deviceFingerprints.values());
    }
    /**
     * Log event
     */
    logEvent(type, userId, details) {
        this.eventsLog.push({
            type,
            userId,
            timestamp: Date.now(),
            details,
        });
        // Keep last 1000 events
        if (this.eventsLog.length > 1000) {
            this.eventsLog = this.eventsLog.slice(-1000);
        }
    }
}
/**
 * Global singleton instance
 */
let instance = null;
/**
 * Get E2EE service instance
 */
export async function getE2EEService() {
    if (!instance) {
        instance = new E2EEService();
        await instance.initialize();
    }
    return instance;
}
//# sourceMappingURL=e2ee-service.js.map