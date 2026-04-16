/**
 * IAM Audit Logging and Session Management
 * File: src/node/iam-audit.ts
 * Purpose: Production-grade IAM audit trail and session tracking
 * Status: Ready for integration with oauth2-proxy
 * Date: April 16, 2026
 */

import { Pool, QueryResult } from 'pg';
import crypto from 'crypto';

/**
 * IAM Audit Events
 */
interface AuditEvent {
  userId: string;
  userEmail: string;
  userName?: string;
  action: string; // 'login', 'logout', 'token_refresh', 'mfa_verify', 'role_grant', 'role_revoke', 'resource_access'
  resourceType: string; // 'workspace', 'file', 'setting', 'user', 'role'
  resourceId: string;
  resourceName?: string;
  changes?: Record<string, any>;
  result: 'success' | 'failure';
  resultDetails?: Record<string, any>;
  ipAddress: string;
  userAgent: string;
  sessionId: string;
  duration?: number; // in milliseconds
}

/**
 * Session tracking
 */
interface SessionRecord {
  sessionId: string;
  userId: string;
  userEmail: string;
  createdAt: Date;
  expiresAt: Date;
  lastActivityAt: Date;
  ipAddress: string;
  userAgent: string;
  refreshCount: number;
  revokedAt?: Date;
  revocationReason?: string;
}

/**
 * IAM Audit Logger - Production-grade audit trail
 */
export class IAMAuditLogger {
  private db: Pool;
  private readonly tableName = 'iam_audit_log';

  constructor(dbPool: Pool) {
    this.db = dbPool;
  }

  /**
   * Initialize audit logging tables
   */
  async initialize(): Promise<void> {
    const client = await this.db.connect();
    try {
      // Create main audit log table
      await client.query(`
        CREATE TABLE IF NOT EXISTS ${this.tableName} (
          id BIGSERIAL PRIMARY KEY,
          timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
          user_id VARCHAR(255),
          user_email VARCHAR(255),
          user_name VARCHAR(255),
          action VARCHAR(100) NOT NULL,
          resource_type VARCHAR(100),
          resource_id VARCHAR(255),
          resource_name VARCHAR(255),
          changes JSONB,
          status VARCHAR(20) NOT NULL, -- 'success', 'failure'
          result_details JSONB,
          ip_address INET,
          user_agent TEXT,
          session_id VARCHAR(255),
          duration_ms INTEGER,
          metadata JSONB
        );
      `);

      // Create indexes for common queries
      await client.query(
        `CREATE INDEX IF NOT EXISTS idx_iam_audit_timestamp ON ${this.tableName}(timestamp DESC)`
      );
      await client.query(
        `CREATE INDEX IF NOT EXISTS idx_iam_audit_user_email ON ${this.tableName}(user_email)`
      );
      await client.query(
        `CREATE INDEX IF NOT EXISTS idx_iam_audit_action ON ${this.tableName}(action)`
      );
      await client.query(
        `CREATE INDEX IF NOT EXISTS idx_iam_audit_session ON ${this.tableName}(session_id)`
      );
      await client.query(
        `CREATE INDEX IF NOT EXISTS idx_iam_audit_resource ON ${this.tableName}(resource_type, resource_id)`
      );
      await client.query(
        `CREATE INDEX IF NOT EXISTS idx_iam_audit_composite ON ${this.tableName}(user_email, action, timestamp DESC)`
      );

      // Create sessions table
      await client.query(`
        CREATE TABLE IF NOT EXISTS iam_sessions (
          session_id VARCHAR(255) PRIMARY KEY,
          user_id VARCHAR(255) NOT NULL,
          user_email VARCHAR(255) NOT NULL,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
          expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
          last_activity_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
          ip_address INET,
          user_agent TEXT,
          refresh_count INTEGER DEFAULT 0,
          revoked_at TIMESTAMP WITH TIME ZONE,
          revocation_reason VARCHAR(255),
          token_hashes TEXT[] -- Multiple token hashes for verification
        );
      `);

      // Create token revocation table (for fast lookup)
      await client.query(`
        CREATE TABLE IF NOT EXISTS iam_token_revocation (
          token_hash VARCHAR(64) PRIMARY KEY,
          token_type VARCHAR(50), -- 'access', 'refresh'
          revoked_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
          revoked_by VARCHAR(255),
          reason VARCHAR(255),
          expires_at TIMESTAMP WITH TIME ZONE
        );
      `);

      // Create anomaly detection table
      await client.query(`
        CREATE TABLE IF NOT EXISTS iam_anomalies (
          id BIGSERIAL PRIMARY KEY,
          timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
          user_email VARCHAR(255) NOT NULL,
          anomaly_type VARCHAR(100), -- 'brute_force', 'impossible_travel', 'unusual_location', 'token_misuse'
          severity VARCHAR(50), -- 'low', 'medium', 'high', 'critical'
          details JSONB,
          action_taken VARCHAR(100), -- 'block', 'revoke', 'notify', 'none'
          resolved_at TIMESTAMP WITH TIME ZONE
        );
      `);

      console.log('[IAM-AUDIT] Audit logging tables initialized successfully');
    } finally {
      client.release();
    }
  }

  /**
   * Log an audit event
   */
  async logEvent(event: AuditEvent): Promise<void> {
    try {
      await this.db.query(
        `INSERT INTO ${this.tableName} 
        (user_id, user_email, user_name, action, resource_type, resource_id, 
         resource_name, changes, status, result_details, ip_address, user_agent, 
         session_id, duration_ms, metadata)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15)`,
        [
          event.userId,
          event.userEmail,
          event.userName || null,
          event.action,
          event.resourceType || null,
          event.resourceId || null,
          event.resourceName || null,
          event.changes ? JSON.stringify(event.changes) : null,
          event.result,
          event.resultDetails ? JSON.stringify(event.resultDetails) : null,
          event.ipAddress,
          event.userAgent,
          event.sessionId,
          event.duration || null,
          JSON.stringify({
            timestamp: new Date().toISOString(),
          }),
        ]
      );
    } catch (error) {
      console.error('[IAM-AUDIT] Error logging event:', error);
      // Don't throw - audit logging failure shouldn't break app
    }
  }

  /**
   * Get user's recent activity (last N events)
   */
  async getUserActivity(userEmail: string, limit: number = 50): Promise<any[]> {
    const result = await this.db.query(
      `SELECT * FROM ${this.tableName} 
       WHERE user_email = $1 
       ORDER BY timestamp DESC 
       LIMIT $2`,
      [userEmail, limit]
    );
    return result.rows;
  }

  /**
   * Detect failed login attempts (potential brute force)
   */
  async detectBruteForce(userEmail: string, timeWindowMinutes: number = 15): Promise<number> {
    const result = await this.db.query(
      `SELECT COUNT(*) as failed_attempts FROM ${this.tableName}
       WHERE user_email = $1 
       AND action = 'login'
       AND status = 'failure'
       AND timestamp > NOW() - INTERVAL '${timeWindowMinutes} minutes'`,
      [userEmail]
    );
    return parseInt(result.rows[0]?.failed_attempts || 0, 10);
  }

  /**
   * Log anomaly
   */
  async logAnomaly(
    userEmail: string,
    anomalyType: string,
    severity: 'low' | 'medium' | 'high' | 'critical',
    details: Record<string, any>,
    actionTaken: string = 'notify'
  ): Promise<void> {
    try {
      await this.db.query(
        `INSERT INTO iam_anomalies (user_email, anomaly_type, severity, details, action_taken)
         VALUES ($1, $2, $3, $4, $5)`,
        [userEmail, anomalyType, severity, JSON.stringify(details), actionTaken]
      );
    } catch (error) {
      console.error('[IAM-AUDIT] Error logging anomaly:', error);
    }
  }
}

/**
 * Session Manager - Production-grade session tracking
 */
export class SessionManager {
  private db: Pool;
  private readonly tableName = 'iam_sessions';

  constructor(dbPool: Pool) {
    this.db = dbPool;
  }

  /**
   * Create new session
   */
  async createSession(
    userId: string,
    userEmail: string,
    ipAddress: string,
    userAgent: string,
    expirationMinutes: number = 1440 // 24 hours
  ): Promise<SessionRecord> {
    const sessionId = this.generateSessionId();
    const now = new Date();
    const expiresAt = new Date(now.getTime() + expirationMinutes * 60 * 1000);

    await this.db.query(
      `INSERT INTO ${this.tableName} 
       (session_id, user_id, user_email, created_at, expires_at, last_activity_at, ip_address, user_agent)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
      [sessionId, userId, userEmail, now, expiresAt, now, ipAddress, userAgent]
    );

    return {
      sessionId,
      userId,
      userEmail,
      createdAt: now,
      expiresAt,
      lastActivityAt: now,
      ipAddress,
      userAgent,
      refreshCount: 0,
    };
  }

  /**
   * Update session activity
   */
  async updateSessionActivity(sessionId: string): Promise<void> {
    await this.db.query(
      `UPDATE ${this.tableName} 
       SET last_activity_at = CURRENT_TIMESTAMP
       WHERE session_id = $1`,
      [sessionId]
    );
  }

  /**
   * Refresh session (extend expiration)
   */
  async refreshSession(
    sessionId: string,
    expirationMinutes: number = 1440
  ): Promise<Date> {
    const newExpiresAt = new Date(Date.now() + expirationMinutes * 60 * 1000);

    const result = await this.db.query(
      `UPDATE ${this.tableName} 
       SET expires_at = $1, refresh_count = refresh_count + 1
       WHERE session_id = $2
       RETURNING expires_at`,
      [newExpiresAt, sessionId]
    );

    if (result.rows.length === 0) {
      throw new Error('Session not found');
    }

    return result.rows[0].expires_at;
  }

  /**
   * Revoke session
   */
  async revokeSession(
    sessionId: string,
    reason: string,
    revokedBy: string
  ): Promise<void> {
    await this.db.query(
      `UPDATE ${this.tableName} 
       SET revoked_at = CURRENT_TIMESTAMP, revocation_reason = $1
       WHERE session_id = $2`,
      [reason, sessionId]
    );
  }

  /**
   * Get session
   */
  async getSession(sessionId: string): Promise<SessionRecord | null> {
    const result = await this.db.query(
      `SELECT * FROM ${this.tableName} 
       WHERE session_id = $1 
       AND revoked_at IS NULL
       AND expires_at > CURRENT_TIMESTAMP`,
      [sessionId]
    );

    if (result.rows.length === 0) {
      return null;
    }

    const row = result.rows[0];
    return {
      sessionId: row.session_id,
      userId: row.user_id,
      userEmail: row.user_email,
      createdAt: row.created_at,
      expiresAt: row.expires_at,
      lastActivityAt: row.last_activity_at,
      ipAddress: row.ip_address,
      userAgent: row.user_agent,
      refreshCount: row.refresh_count,
      revokedAt: row.revoked_at,
      revocationReason: row.revocation_reason,
    };
  }

  /**
   * Get user's active sessions
   */
  async getUserActiveSessions(userEmail: string): Promise<SessionRecord[]> {
    const result = await this.db.query(
      `SELECT * FROM ${this.tableName} 
       WHERE user_email = $1 
       AND revoked_at IS NULL
       AND expires_at > CURRENT_TIMESTAMP
       ORDER BY created_at DESC`,
      [userEmail]
    );

    return result.rows.map((row) => ({
      sessionId: row.session_id,
      userId: row.user_id,
      userEmail: row.user_email,
      createdAt: row.created_at,
      expiresAt: row.expires_at,
      lastActivityAt: row.last_activity_at,
      ipAddress: row.ip_address,
      userAgent: row.user_agent,
      refreshCount: row.refresh_count,
      revokedAt: row.revoked_at,
      revocationReason: row.revocation_reason,
    }));
  }

  /**
   * Revoke all user sessions
   */
  async revokeAllUserSessions(userEmail: string, reason: string): Promise<number> {
    const result = await this.db.query(
      `UPDATE ${this.tableName} 
       SET revoked_at = CURRENT_TIMESTAMP, revocation_reason = $1
       WHERE user_email = $2 AND revoked_at IS NULL`,
      [reason, userEmail]
    );

    return result.rowCount || 0;
  }

  /**
   * Cleanup expired sessions (run periodically)
   */
  async cleanupExpiredSessions(): Promise<number> {
    const result = await this.db.query(
      `DELETE FROM ${this.tableName} 
       WHERE expires_at < CURRENT_TIMESTAMP 
       AND revoked_at IS NOT NULL`
    );

    return result.rowCount || 0;
  }

  private generateSessionId(): string {
    return crypto.randomBytes(32).toString('hex');
  }
}

/**
 * Token Revocation Manager
 */
export class TokenRevocationManager {
  private db: Pool;
  private revocationCache: Set<string> = new Set();

  constructor(dbPool: Pool) {
    this.db = dbPool;
  }

  /**
   * Hash token for storage (never store plaintext tokens)
   */
  hashToken(token: string): string {
    return crypto.createHash('sha256').update(token).digest('hex');
  }

  /**
   * Revoke token
   */
  async revokeToken(
    token: string,
    tokenType: string,
    revokedBy: string,
    reason: string
  ): Promise<void> {
    const tokenHash = this.hashToken(token);

    await this.db.query(
      `INSERT INTO iam_token_revocation (token_hash, token_type, revoked_by, reason, expires_at)
       VALUES ($1, $2, $3, $4, NOW() + INTERVAL '24 hours')
       ON CONFLICT (token_hash) DO NOTHING`,
      [tokenHash, tokenType, revokedBy, reason]
    );

    // Update cache
    this.revocationCache.add(tokenHash);
  }

  /**
   * Check if token is revoked (fast lookup)
   */
  async isTokenRevoked(token: string): Promise<boolean> {
    const tokenHash = this.hashToken(token);

    // Check cache first
    if (this.revocationCache.has(tokenHash)) {
      return true;
    }

    // Check database
    const result = await this.db.query(
      `SELECT 1 FROM iam_token_revocation WHERE token_hash = $1`,
      [tokenHash]
    );

    return result.rows.length > 0;
  }

  /**
   * Cleanup expired revocations
   */
  async cleanupExpiredRevocations(): Promise<number> {
    const result = await this.db.query(
      `DELETE FROM iam_token_revocation WHERE expires_at < CURRENT_TIMESTAMP`
    );

    return result.rowCount || 0;
  }
}

// Export for integration with code-server
export default {
  IAMAuditLogger,
  SessionManager,
  TokenRevocationManager,
};
