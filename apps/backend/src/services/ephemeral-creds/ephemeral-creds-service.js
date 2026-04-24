/**
 * @file        apps/backend/src/services/ephemeral-creds/ephemeral-creds-service.ts
 * @module      security/ephemeral-credentials
 * @description Ephemeral credentials service with Vault integration
 */
import { EventEmitter } from 'events';
/**
 * In-memory credential storage
 */
class CredentialStorage {
    constructor() {
        this.credentials = new Map();
        this.requests = new Map();
    }
    storeCredential(cred) {
        this.credentials.set(cred.id, cred);
    }
    getCredential(id) {
        return this.credentials.get(id);
    }
    getCredentialsBySession(sessionId) {
        return Array.from(this.credentials.values()).filter((c) => c.sessionId === sessionId);
    }
    getCredentialsByUser(userId) {
        return Array.from(this.credentials.values()).filter((c) => c.userId === userId);
    }
    getAllCredentials() {
        return Array.from(this.credentials.values());
    }
    storeRequest(req) {
        this.requests.set(req.id, req);
    }
    getRequest(id) {
        return this.requests.get(id);
    }
    getPendingRequests() {
        return Array.from(this.requests.values()).filter((r) => r.status === 'pending');
    }
    delete(id) {
        return this.credentials.delete(id);
    }
}
/**
 * Ephemeral credentials service with Vault integration
 */
export class EphemeralCredsService extends EventEmitter {
    constructor(auditService) {
        super();
        this.isInitialized = false;
        this.storage = new CredentialStorage();
        this.rotationPolicy = {
            enabled: true,
            rotationIntervalMs: 86400000, // 24 hours
            rotationBefore: 3600000, // 1 hour before expiration
            maxAge: 604800000, // 7 days
            automaticRotation: true,
        };
        // Session -> bundle mapping
        this.sessionBundles = new Map();
        // Rotation timers
        this.rotationTimers = new Map();
        // Statistics
        this.stats = {
            totalCredentials: 0,
            activeCredentials: 0,
            rotatedCredentials: 0,
            revokedCredentials: 0,
            expiredCredentials: 0,
            failedCredentials: 0,
            averageLeaseTime: 0,
            averageRotationTime: 0,
            averageRevocationTime: 0,
            byType: {},
            byStatus: {},
            byUser: {},
            bySession: {},
            requestsApproved: 0,
            requestsDenied: 0,
            rotationCount: 0,
            revocationCount: 0,
        };
        // Events log
        this.eventsLog = [];
        this.auditService = auditService;
    }
    /**
     * Initialize service
     */
    async initialize() {
        if (this.isInitialized)
            return;
        this.isInitialized = true;
        console.log('[EphemeralCredsService] Initialized');
        this.emit('initialized');
    }
    /**
     * Request credential
     */
    async requestCredential(sessionId, userId, type, resourceName, leaseDuration = 3600 // 1 hour default
    ) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        const request = {
            id: `creq-${userId}-${Date.now()}`,
            sessionId,
            userId,
            type,
            resourceName,
            leaseDuration,
            requestedAt: Date.now(),
            status: 'pending',
        };
        this.storage.storeRequest(request);
        if (this.auditService) {
            this.auditService.emit({
                userId,
                action: 'create',
                resourceType: 'credential-request',
                resource: `credential-request:${request.id}`,
                metadata: {
                    sessionId,
                    type,
                    resourceName,
                    leaseDuration,
                    requestId: request.id,
                },
                reason: 'SOC2: Ephemeral credential request creation',
            });
        }
        this.logEvent('credential-requested', {
            credentialId: request.id,
            sessionId,
            userId,
            type,
            resourceName,
        });
        this.emit('credential-requested', { request });
        return request;
    }
    /**
     * Fulfill credential request
     */
    async fulfillCredential(requestId, leaseDuration) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        const request = this.storage.getRequest(requestId);
        if (!request)
            throw new Error(`Request ${requestId} not found`);
        request.status = 'approved';
        this.stats.requestsApproved++;
        // Simulate Vault credential generation
        const credential = {
            id: `cred-${request.userId}-${Date.now()}`,
            sessionId: request.sessionId,
            userId: request.userId,
            type: request.type,
            status: 'ready',
            resourceName: request.resourceName,
            // Simulate credential values (would come from Vault)
            username: `${request.type}_user_${Date.now()}`,
            password: `encrypted_password_${request.type}`,
            token: `token_${request.type}_${Date.now()}`,
            vaultPath: `/secret/${request.userId}/${request.type}/${request.resourceName}`,
            leaseDuration: leaseDuration || request.leaseDuration,
            renewBefore: 300000, // Renew 5 min before expiration
            createdAt: Date.now(),
            expiresAt: Date.now() + (leaseDuration || request.leaseDuration) * 1000,
            usageCount: 0,
        };
        this.storage.storeCredential(credential);
        // Add to session bundle - get or create
        let bundle = this.sessionBundles.get(request.sessionId);
        if (!bundle) {
            bundle = {
                sessionId: request.sessionId,
                userId: request.userId,
                credentials: [],
                createdAt: Date.now(),
                expiresAt: credential.expiresAt,
            };
            this.sessionBundles.set(request.sessionId, bundle);
        }
        // Add credential to bundle
        bundle.credentials.push(credential);
        // Update expiration if this credential expires later
        if (credential.expiresAt > bundle.expiresAt) {
            bundle.expiresAt = credential.expiresAt;
        }
        // Schedule rotation if policy enabled
        if (this.rotationPolicy.automaticRotation) {
            this.scheduleRotation(credential.id);
        }
        this.stats.totalCredentials++;
        this.stats.activeCredentials++;
        this.updateStats();
        this.logEvent('credential-generated', {
            credentialId: credential.id,
            sessionId: request.sessionId,
            userId: request.userId,
            type: request.type,
        });
        if (this.auditService) {
            this.auditService.emit({
                userId: request.userId,
                action: 'create',
                resourceType: 'ephemeral-credential',
                resource: `credential:${credential.id}`,
                metadata: {
                    sessionId: request.sessionId,
                    type: request.type,
                    resourceName: request.resourceName,
                    leaseDuration: credential.leaseDuration,
                    expiresAt: credential.expiresAt,
                    vaultPath: credential.vaultPath,
                },
                reason: 'SOC2: Ephemeral credential issuance from Vault',
            });
        }
        this.emit('credential-generated', { credential });
        return credential;
    }
    /**
     * Get credential
     */
    async getCredential(credentialId) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        const cred = this.storage.getCredential(credentialId);
        if (cred) {
            cred.usageCount++;
            cred.lastUsedAt = Date.now();
        }
        return cred;
    }
    /**
     * Get credentials for session
     */
    async getSessionCredentials(sessionId) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        return this.storage.getCredentialsBySession(sessionId);
    }
    /**
     * Rotate credential
     */
    async rotateCredential(credentialId) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        const oldCred = this.storage.getCredential(credentialId);
        if (!oldCred)
            throw new Error(`Credential ${credentialId} not found`);
        const startTime = Date.now();
        // Create new credential with same properties
        const newCred = {
            ...oldCred,
            id: `cred-${oldCred.userId}-rotated-${Date.now()}`,
            password: `encrypted_password_rotated_${Date.now()}`,
            token: `token_rotated_${Date.now()}`,
            createdAt: Date.now(),
            expiresAt: Date.now() + oldCred.leaseDuration * 1000,
            rotatedAt: Date.now(),
            usageCount: 0,
            lastUsedAt: undefined,
        };
        this.storage.storeCredential(newCred);
        // Mark old credential status as rotated
        oldCred.status = 'rotated';
        const rotationTime = Date.now() - startTime;
        this.stats.rotationCount++;
        this.stats.averageRotationTime =
            (this.stats.averageRotationTime * (this.stats.rotationCount - 1) + rotationTime) /
                this.stats.rotationCount;
        const rotationEvent = {
            credentialId: newCred.id,
            previousId: credentialId,
            rotatedAt: Date.now(),
            reason: 'scheduled',
            duration: rotationTime,
        };
        // Schedule rotation of new credential
        if (this.rotationPolicy.automaticRotation) {
            this.scheduleRotation(newCred.id);
        }
        this.logEvent('credential-rotated', {
            credentialId: newCred.id,
            sessionId: newCred.sessionId,
            userId: newCred.userId,
            type: newCred.type,
        });
        if (this.auditService) {
            this.auditService.emit({
                userId: oldCred.userId,
                action: 'update',
                resourceType: 'ephemeral-credential',
                resource: `credential:${newCred.id}`,
                metadata: {
                    sessionId: newCred.sessionId,
                    type: newCred.type,
                    previousCredentialId: credentialId,
                    newCredentialId: newCred.id,
                    rotatedAt: Date.now(),
                    rotationTime,
                },
                reason: 'SOC2: Ephemeral credential rotation',
            });
        }
        this.emit('credential-rotated', { newCred, oldCred, rotationEvent });
        return newCred;
    }
    /**
     * Revoke credential
     */
    async revokeCredential(credentialId, reason = 'manual') {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        const cred = this.storage.getCredential(credentialId);
        if (!cred)
            throw new Error(`Credential ${credentialId} not found`);
        const startTime = Date.now();
        // Simulate revocation via Vault
        cred.status = 'revoked';
        cred.revokedAt = Date.now();
        const revocationTime = Date.now() - startTime;
        this.stats.revocationCount++;
        this.stats.activeCredentials = Math.max(0, this.stats.activeCredentials - 1);
        this.stats.revokedCredentials++;
        this.stats.averageRevocationTime =
            (this.stats.averageRevocationTime * (this.stats.revocationCount - 1) + revocationTime) /
                this.stats.revocationCount;
        // Clear rotation timer
        const timer = this.rotationTimers.get(credentialId);
        if (timer) {
            clearTimeout(timer);
            this.rotationTimers.delete(credentialId);
        }
        const revocationEvent = {
            credentialId,
            revokedAt: Date.now(),
            reason: reason,
            revokeTime: revocationTime,
        };
        this.logEvent('credential-revoked', {
            credentialId,
            sessionId: cred.sessionId,
            userId: cred.userId,
            type: cred.type,
        });
        if (this.auditService) {
            this.auditService.emit({
                userId: cred.userId,
                action: 'delete',
                resourceType: 'ephemeral-credential',
                resource: `credential:${credentialId}`,
                metadata: {
                    sessionId: cred.sessionId,
                    type: cred.type,
                    resourceName: cred.resourceName,
                    reason: reason,
                    revokedAt: Date.now(),
                    revocationTime,
                },
                reason: 'SOC2: Ephemeral credential revocation',
            });
        }
        this.emit('credential-revoked', { cred, revocationEvent });
    }
    /**
     * Revoke session credentials
     */
    async revokeSessionCredentials(sessionId) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        const creds = this.storage.getCredentialsBySession(sessionId);
        for (const cred of creds) {
            if (cred.status !== 'revoked') {
                await this.revokeCredential(cred.id, 'session-ended');
            }
        }
        const bundle = this.sessionBundles.get(sessionId);
        if (bundle) {
            bundle.allRevokedAt = Date.now();
        }
        if (this.auditService && creds.length > 0) {
            this.auditService.emit({
                userId: creds[0]?.userId || 'system',
                action: 'delete',
                resourceType: 'session-credential-bundle',
                resource: `session:${sessionId}`,
                metadata: {
                    sessionId,
                    revokedCount: creds.length,
                    credentialTypes: [...new Set(creds.map((c) => c.type))],
                    reason: 'session-ended',
                },
                reason: 'SOC2: Session credentials revoked on session termination',
            });
        }
        this.emit('session-credentials-revoked', { sessionId, revokedCount: creds.length });
    }
    /**
     * Schedule automatic rotation
     */
    scheduleRotation(credentialId) {
        const cred = this.storage.getCredential(credentialId);
        if (!cred)
            return;
        // Calculate delay: rotate X minutes before expiration
        const expiresInMs = cred.expiresAt - Date.now();
        const rotateInMs = expiresInMs - this.rotationPolicy.rotationBefore;
        if (rotateInMs > 0) {
            const timer = setTimeout(async () => {
                try {
                    await this.rotateCredential(credentialId);
                }
                catch (error) {
                    console.error(`Failed to rotate credential ${credentialId}:`, error);
                    this.stats.failedCredentials++;
                }
            }, rotateInMs);
            this.rotationTimers.set(credentialId, timer);
        }
    }
    /**
     * Get statistics
     */
    async getStatistics() {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        return { ...this.stats };
    }
    /**
     * Get rotation policy
     */
    async getRotationPolicy() {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        return { ...this.rotationPolicy };
    }
    /**
     * Set rotation policy
     */
    async setRotationPolicy(policy) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        this.rotationPolicy = { ...this.rotationPolicy, ...policy };
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
     * Get session bundle
     */
    async getSessionBundle(sessionId) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        return this.sessionBundles.get(sessionId);
    }
    /**
     * Deny credential request
     */
    async denyRequest(requestId, reason) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        const request = this.storage.getRequest(requestId);
        if (!request)
            throw new Error(`Request ${requestId} not found`);
        request.status = 'denied';
        request.denialReason = reason;
        this.stats.requestsDenied++;
        this.emit('request-denied', { request });
    }
    /**
     * Log event
     */
    logEvent(type, details) {
        this.eventsLog.push({
            type,
            timestamp: Date.now(),
            ...details,
        });
        // Keep last 1000 events
        if (this.eventsLog.length > 1000) {
            this.eventsLog = this.eventsLog.slice(-1000);
        }
    }
    /**
     * Update statistics
     */
    updateStats() {
        const allCreds = this.storage.getAllCredentials();
        // Count by type
        this.stats.byType = {};
        this.stats.byStatus = {};
        this.stats.byUser = {};
        this.stats.bySession = {};
        for (const cred of allCreds) {
            this.stats.byType[cred.type] = (this.stats.byType[cred.type] || 0) + 1;
            this.stats.byStatus[cred.status] = (this.stats.byStatus[cred.status] || 0) + 1;
            this.stats.byUser[cred.userId] = (this.stats.byUser[cred.userId] || 0) + 1;
            this.stats.bySession[cred.sessionId] = (this.stats.bySession[cred.sessionId] || 0) + 1;
        }
        // Calculate averages
        const activeCredsWithLease = allCreds.filter((c) => c.leaseDuration);
        if (activeCredsWithLease.length > 0) {
            this.stats.averageLeaseTime =
                activeCredsWithLease.reduce((sum, c) => sum + c.leaseDuration, 0) /
                    activeCredsWithLease.length;
        }
        // Recalculate active count
        this.stats.activeCredentials = allCreds.filter((c) => c.status === 'ready' && c.expiresAt > Date.now()).length;
        this.stats.expiredCredentials = allCreds.filter((c) => c.status !== 'revoked' && c.expiresAt <= Date.now()).length;
    }
}
/**
 * Global singleton instance
 */
let instance = null;
/**
 * Get ephemeral credentials service instance
 */
export async function getEphemeralCredsService() {
    if (!instance) {
        instance = new EphemeralCredsService();
        await instance.initialize();
    }
    return instance;
}
//# sourceMappingURL=ephemeral-creds-service.js.map