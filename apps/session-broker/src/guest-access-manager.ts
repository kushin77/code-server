// @file        apps/session-broker/src/guest-access-manager.ts
// @module      session-management/guest-access
// @description Guest access control and permissions for IDE sessions in KC
//
// Manages guest access tokens, permissions, and session sharing for collaborative work.

import * as winston from 'winston';
import * as crypto from 'crypto';
import { RedisSessionStore, SessionContext } from './redis-session-store';

const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || 'info',
  format: winston.format.json(),
  transports: [new winston.transports.Console()],
});

export enum GuestPermission {
  VIEW = 'view',
  EDIT = 'edit',
  ADMIN = 'admin',
}

export interface GuestAccessToken {
  id: string;
  sessionId: string;
  guestEmail: string;
  permission: GuestPermission;
  createdBy: string;
  createdAt: Date;
  expiresAt: Date;
  isActive: boolean;
  lastAccessedAt?: Date;
  accessCount: number;
}

export interface AccessRevocation {
  guestId: string;
  sessionId: string;
  revokedAt: Date;
  revokedBy: string;
  reason: string;
}

/**
 * Manages guest access to sessions with token-based permissions.
 * Idempotent: safe to grant same access multiple times.
 */
export class GuestAccessManager {
  private tokenStore: Map<string, GuestAccessToken> = new Map();
  private revocationLog: AccessRevocation[] = [];

  constructor(private sessionStore: RedisSessionStore) {}

  /**
   * Generate a guest access token for a session.
   * Idempotent: granting same access twice returns same token with updated expiry.
   */
  async grantAccess(
    sessionId: string,
    guestEmail: string,
    permission: GuestPermission,
    createdBy: string,
    durationHours: number = 24
  ): Promise<GuestAccessToken | null> {
    try {
      const session = await this.sessionStore.getSession(sessionId);
      if (!session) {
        logger.error('Cannot grant access: session not found', { sessionId });
        return null;
      }

      // Check for existing access (idempotent)
      const existingToken = Array.from(this.tokenStore.values()).find(
        t => t.sessionId === sessionId && t.guestEmail === guestEmail && t.isActive
      );

      if (existingToken) {
        // Update expiry for idempotency
        existingToken.expiresAt = new Date(Date.now() + durationHours * 60 * 60 * 1000);
        logger.info('Updated existing guest access token', { sessionId, guestEmail });
        return existingToken;
      }

      // Create new token
      const token: GuestAccessToken = {
        id: this.generateTokenId(),
        sessionId,
        guestEmail,
        permission,
        createdBy,
        createdAt: new Date(),
        expiresAt: new Date(Date.now() + durationHours * 60 * 60 * 1000),
        isActive: true,
        accessCount: 0,
      };

      this.tokenStore.set(token.id, token);
      logger.info('Granted guest access', { sessionId, guestEmail, permission, expiresAt: token.expiresAt });
      return token;
    } catch (error) {
      logger.error('Failed to grant access', { error, sessionId, guestEmail });
      return null;
    }
  }

  /**
   * Verify and track guest access to a session.
   * Updates last accessed time and access count for audit trail.
   */
  async verifyAccess(tokenId: string, sessionId: string): Promise<GuestAccessToken | null> {
    try {
      const token = this.tokenStore.get(tokenId);
      if (!token) {
        logger.warn('Access token not found', { tokenId, sessionId });
        return null;
      }

      if (!token.isActive) {
        logger.warn('Access token is revoked', { tokenId, sessionId });
        return null;
      }

      if (new Date() > token.expiresAt) {
        logger.warn('Access token expired', { tokenId, sessionId, expiresAt: token.expiresAt });
        token.isActive = false;
        return null;
      }

      if (token.sessionId !== sessionId) {
        logger.warn('Token session mismatch', { tokenId, expectedSessionId: sessionId, actualSessionId: token.sessionId });
        return null;
      }

      // Update tracking
      token.lastAccessedAt = new Date();
      token.accessCount++;

      return token;
    } catch (error) {
      logger.error('Failed to verify access', { error, tokenId, sessionId });
      return null;
    }
  }

  /**
   * Revoke guest access to a session.
   * Idempotent: revoking already-revoked access is a no-op.
   */
  async revokeAccess(tokenId: string, sessionId: string, revokedBy: string, reason: string): Promise<boolean> {
    try {
      const token = this.tokenStore.get(tokenId);
      if (!token) {
        logger.info('Token already revoked or not found', { tokenId });
        return true; // Idempotent
      }

      if (token.sessionId !== sessionId) {
        logger.error('Session mismatch on revocation', { tokenId, expectedSessionId: sessionId });
        return false;
      }

      token.isActive = false;
      this.revocationLog.push({
        guestId: token.id,
        sessionId,
        revokedAt: new Date(),
        revokedBy,
        reason,
      });

      logger.info('Revoked guest access', { tokenId, sessionId, reason });
      return true;
    } catch (error) {
      logger.error('Failed to revoke access', { error, tokenId, sessionId });
      return false;
    }
  }

  /**
   * List all active guests for a session.
   */
  async listGuestAccess(sessionId: string): Promise<GuestAccessToken[]> {
    try {
      return Array.from(this.tokenStore.values()).filter(
        t => t.sessionId === sessionId && t.isActive && new Date() <= t.expiresAt
      );
    } catch (error) {
      logger.error('Failed to list guest access', { error, sessionId });
      return [];
    }
  }

  /**
   * Generate audit report for guest access history.
   */
  async getAuditReport(sessionId: string): Promise<{ tokens: GuestAccessToken[]; revocations: AccessRevocation[] }> {
    try {
      const tokens = Array.from(this.tokenStore.values()).filter(t => t.sessionId === sessionId);
      const revocations = this.revocationLog.filter(r => r.sessionId === sessionId);
      return { tokens, revocations };
    } catch (error) {
      logger.error('Failed to generate audit report', { error, sessionId });
      return { tokens: [], revocations: [] };
    }
  }

  private generateTokenId(): string {
    return `guest-${Date.now()}-${crypto.randomBytes(8).toString('hex')}`;
  }
}
