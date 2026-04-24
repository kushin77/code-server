/**
 * @file        apps/backend/src/services/ephemeral-creds/ephemeral-creds-service.ts
 * @module      security/ephemeral-credentials
 * @description Ephemeral credentials service with Vault integration
 */

import { EventEmitter } from 'events';
import { AuditService } from '../audit/audit-service.js';
import {
  EphemeralCredential,
  CredentialRequest,
  RotationEvent,
  RevocationEvent,
  VaultConfig,
  EphemeralCredsStats,
  RotationPolicy,
  EphemeralCredsEvent,
  SessionCredentialBundle,
} from './types.js';

/**
 * In-memory credential storage
 */
class CredentialStorage {
  private credentials = new Map<string, EphemeralCredential>();
  private requests = new Map<string, CredentialRequest>();

  storeCredential(cred: EphemeralCredential): void {
    this.credentials.set(cred.id, cred);
  }

  getCredential(id: string): EphemeralCredential | undefined {
    return this.credentials.get(id);
  }

  getCredentialsBySession(sessionId: string): EphemeralCredential[] {
    return Array.from(this.credentials.values()).filter((c) => c.sessionId === sessionId);
  }

  getCredentialsByUser(userId: string): EphemeralCredential[] {
    return Array.from(this.credentials.values()).filter((c) => c.userId === userId);
  }

  getAllCredentials(): EphemeralCredential[] {
    return Array.from(this.credentials.values());
  }

  storeRequest(req: CredentialRequest): void {
    this.requests.set(req.id, req);
  }

  getRequest(id: string): CredentialRequest | undefined {
    return this.requests.get(id);
  }

  getPendingRequests(): CredentialRequest[] {
    return Array.from(this.requests.values()).filter((r) => r.status === 'pending');
  }

  delete(id: string): boolean {
    return this.credentials.delete(id);
  }
}

/**
 * Ephemeral credentials service with Vault integration
 */
export class EphemeralCredsService extends EventEmitter {
  private isInitialized = false;
  private storage = new CredentialStorage();
  private auditService?: AuditService;
  private rotationPolicy: RotationPolicy = {
    enabled: true,
    rotationIntervalMs: 86400000, // 24 hours
    rotationBefore: 3600000, // 1 hour before expiration
    maxAge: 604800000, // 7 days
    automaticRotation: true,
  };

  // Session -> bundle mapping
  private sessionBundles = new Map<string, SessionCredentialBundle>();

  // Rotation timers
  private rotationTimers = new Map<string, NodeJS.Timeout>();

  // Statistics
  private stats: EphemeralCredsStats = {
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
  private eventsLog: EphemeralCredsEvent[] = [];

  constructor(auditService?: AuditService) {
    super();
    this.auditService = auditService;
  }

  /**
   * Initialize service
   */
  async initialize(): Promise<void> {
    if (this.isInitialized) return;
    this.isInitialized = true;

    console.log('[EphemeralCredsService] Initialized');
    this.emit('initialized');
  }

  /**
   * Request credential
   */
  async requestCredential(
    sessionId: string,
    userId: string,
    type: EphemeralCredential['type'],
    resourceName: string,
    leaseDuration: number = 3600 // 1 hour default
  ): Promise<CredentialRequest> {
    if (!this.isInitialized) throw new Error('Service not initialized');

    const request: CredentialRequest = {
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
  async fulfillCredential(
    requestId: string,
    leaseDuration?: number
  ): Promise<EphemeralCredential> {
    if (!this.isInitialized) throw new Error('Service not initialized');

    const request = this.storage.getRequest(requestId);
    if (!request) throw new Error(`Request ${requestId} not found`);

    request.status = 'approved';
    this.stats.requestsApproved++;

    // Simulate Vault credential generation
    const credential: EphemeralCredential = {
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
  async getCredential(credentialId: string): Promise<EphemeralCredential | undefined> {
    if (!this.isInitialized) throw new Error('Service not initialized');

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
  async getSessionCredentials(sessionId: string): Promise<EphemeralCredential[]> {
    if (!this.isInitialized) throw new Error('Service not initialized');

    return this.storage.getCredentialsBySession(sessionId);
  }

  /**
   * Rotate credential
   */
  async rotateCredential(credentialId: string): Promise<EphemeralCredential> {
    if (!this.isInitialized) throw new Error('Service not initialized');

    const oldCred = this.storage.getCredential(credentialId);
    if (!oldCred) throw new Error(`Credential ${credentialId} not found`);

    const startTime = Date.now();

    // Create new credential with same properties
    const newCred: EphemeralCredential = {
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

    const rotationEvent: RotationEvent = {
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
  async revokeCredential(credentialId: string, reason: string = 'manual'): Promise<void> {
    if (!this.isInitialized) throw new Error('Service not initialized');

    const cred = this.storage.getCredential(credentialId);
    if (!cred) throw new Error(`Credential ${credentialId} not found`);

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

    const revocationEvent: RevocationEvent = {
      credentialId,
      revokedAt: Date.now(),
      reason: reason as any,
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
  async revokeSessionCredentials(sessionId: string): Promise<void> {
    if (!this.isInitialized) throw new Error('Service not initialized');

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
  private scheduleRotation(credentialId: string): void {
    const cred = this.storage.getCredential(credentialId);
    if (!cred) return;

    // Calculate delay: rotate X minutes before expiration
    const expiresInMs = cred.expiresAt - Date.now();
    const rotateInMs = expiresInMs - this.rotationPolicy.rotationBefore;

    if (rotateInMs > 0) {
      const timer = setTimeout(async () => {
        try {
          await this.rotateCredential(credentialId);
        } catch (error) {
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
  async getStatistics(): Promise<EphemeralCredsStats> {
    if (!this.isInitialized) throw new Error('Service not initialized');

    return { ...this.stats };
  }

  /**
   * Get rotation policy
   */
  async getRotationPolicy(): Promise<RotationPolicy> {
    if (!this.isInitialized) throw new Error('Service not initialized');

    return { ...this.rotationPolicy };
  }

  /**
   * Set rotation policy
   */
  async setRotationPolicy(policy: Partial<RotationPolicy>): Promise<void> {
    if (!this.isInitialized) throw new Error('Service not initialized');

    this.rotationPolicy = { ...this.rotationPolicy, ...policy };
  }

  /**
   * Get events
   */
  async getEvents(limit?: number): Promise<EphemeralCredsEvent[]> {
    const events = [...this.eventsLog];
    if (limit && limit > 0) {
      return events.slice(-limit);
    }
    return events;
  }

  /**
   * Get session bundle
   */
  async getSessionBundle(sessionId: string): Promise<SessionCredentialBundle | undefined> {
    if (!this.isInitialized) throw new Error('Service not initialized');

    return this.sessionBundles.get(sessionId);
  }

  /**
   * Deny credential request
   */
  async denyRequest(requestId: string, reason: string): Promise<void> {
    if (!this.isInitialized) throw new Error('Service not initialized');

    const request = this.storage.getRequest(requestId);
    if (!request) throw new Error(`Request ${requestId} not found`);

    request.status = 'denied';
    request.denialReason = reason;
    this.stats.requestsDenied++;

    this.emit('request-denied', { request });
  }

  /**
   * Log event
   */
  private logEvent(
    type: EphemeralCredsEvent['type'],
    details: Record<string, any>
  ): void {
    this.eventsLog.push({
      type,
      timestamp: Date.now(),
      ...details,
    } as EphemeralCredsEvent);

    // Keep last 1000 events
    if (this.eventsLog.length > 1000) {
      this.eventsLog = this.eventsLog.slice(-1000);
    }
  }

  /**
   * Update statistics
   */
  private updateStats(): void {
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
    this.stats.activeCredentials = allCreds.filter(
      (c) => c.status === 'ready' && c.expiresAt > Date.now()
    ).length;
    this.stats.expiredCredentials = allCreds.filter(
      (c) => c.status !== 'revoked' && c.expiresAt <= Date.now()
    ).length;
  }
}

/**
 * Global singleton instance
 */
let instance: EphemeralCredsService | null = null;

/**
 * Get ephemeral credentials service instance
 */
export async function getEphemeralCredsService(): Promise<EphemeralCredsService> {
  if (!instance) {
    instance = new EphemeralCredsService();
    await instance.initialize();
  }
  return instance;
}
