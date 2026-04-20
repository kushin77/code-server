/**
 * @file        apps/matrix-admin-bot/src/services/audit-logger.ts
 * @module      matrix/admin-bot/services
 * @description Immutable audit logging for Matrix events
 */

import { Pool } from "pg";
import crypto from "crypto";

interface AuditEvent {
  eventType: string;
  sender: string;
  roomId?: string;
  command?: string;
  action: string;
  metadata?: Record<string, unknown>;
}

export class AuditLogger {
  private pool: Pool;

  constructor(databaseUrl: string) {
    this.pool = new Pool({ connectionString: databaseUrl });
  }

  /**
   * Log an audit event
   */
  async log(event: AuditEvent): Promise<void> {
    try {
      const contentHash = this.hashContent(JSON.stringify(event));

      await this.pool.query(
        `
        INSERT INTO audit.events (
          timestamp, event_type, sender, room_id, content_hash, action, metadata
        ) VALUES ($1, $2, $3, $4, $5, $6, $7)
        `,
        [
          new Date(),
          event.eventType,
          event.sender,
          event.roomId || null,
          contentHash,
          event.action,
          JSON.stringify(event.metadata || {}),
        ]
      );
    } catch (error) {
      // Don't throw - audit logging should not crash the bot
      console.error("Failed to log audit event:", error);
    }
  }

  /**
   * Initialize audit schema
   */
  async initializeSchema(): Promise<void> {
    try {
      // Create audit schema
      await this.pool.query(`
        CREATE SCHEMA IF NOT EXISTS audit;
      `);

      // Create audit events table (immutable append-only)
      await this.pool.query(`
        CREATE TABLE IF NOT EXISTS audit.events (
          id BIGSERIAL PRIMARY KEY,
          timestamp TIMESTAMP DEFAULT NOW(),
          event_type VARCHAR(255) NOT NULL,
          sender VARCHAR(255) NOT NULL,
          room_id VARCHAR(255),
          content_hash VARCHAR(64),
          action VARCHAR(50),
          metadata JSONB
        );

        CREATE INDEX IF NOT EXISTS idx_audit_timestamp 
          ON audit.events(timestamp DESC);
        CREATE INDEX IF NOT EXISTS idx_audit_room 
          ON audit.events(room_id);
        CREATE INDEX IF NOT EXISTS idx_audit_sender 
          ON audit.events(sender);
        CREATE INDEX IF NOT EXISTS idx_audit_type 
          ON audit.events(event_type);
      `);

      // Create retention policy table
      await this.pool.query(`
        CREATE TABLE IF NOT EXISTS audit.retention_policies (
          id BIGSERIAL PRIMARY KEY,
          room_id VARCHAR(255) NOT NULL UNIQUE,
          retention_days INT NOT NULL,
          max_lifetime_ms BIGINT NOT NULL,
          set_at TIMESTAMP DEFAULT NOW(),
          set_by VARCHAR(255)
        );

        CREATE INDEX IF NOT EXISTS idx_retention_room 
          ON audit.retention_policies(room_id);
      `);

      // Create room templates table
      await this.pool.query(`
        CREATE TABLE IF NOT EXISTS audit.room_templates (
          id BIGSERIAL PRIMARY KEY,
          room_id VARCHAR(255) NOT NULL,
          template_name VARCHAR(255) NOT NULL,
          created_at TIMESTAMP DEFAULT NOW(),
          created_by VARCHAR(255),
          display_name VARCHAR(255),
          topic TEXT
        );

        CREATE INDEX IF NOT EXISTS idx_templates_room 
          ON audit.room_templates(room_id);
        CREATE INDEX IF NOT EXISTS idx_templates_template 
          ON audit.room_templates(template_name);
      `);
    } catch (error) {
      if (error instanceof Error && !error.message.includes("already exists")) {
        throw error;
      }
    }
  }

  /**
   * Query audit logs
   */
  async queryLogs(
    filters?: {
      roomId?: string;
      sender?: string;
      eventType?: string;
      since?: Date;
      limit?: number;
    }
  ): Promise<AuditEvent[]> {
    let query = "SELECT * FROM audit.events WHERE 1=1";
    const params: unknown[] = [];

    if (filters?.roomId) {
      query += ` AND room_id = $${params.length + 1}`;
      params.push(filters.roomId);
    }

    if (filters?.sender) {
      query += ` AND sender = $${params.length + 1}`;
      params.push(filters.sender);
    }

    if (filters?.eventType) {
      query += ` AND event_type = $${params.length + 1}`;
      params.push(filters.eventType);
    }

    if (filters?.since) {
      query += ` AND timestamp >= $${params.length + 1}`;
      params.push(filters.since);
    }

    query += " ORDER BY timestamp DESC";

    if (filters?.limit) {
      query += ` LIMIT $${params.length + 1}`;
      params.push(filters.limit);
    }

    try {
      const result = await this.pool.query(query, params);
      return result.rows;
    } catch (error) {
      console.error("Failed to query audit logs:", error);
      return [];
    }
  }

  /**
   * Archive audit logs older than specified days
   */
  async archiveOldLogs(retentionDays: number): Promise<number> {
    try {
      const date = new Date();
      date.setDate(date.getDate() - retentionDays);

      const result = await this.pool.query(
        `
        DELETE FROM audit.events
        WHERE timestamp < $1
        `,
        [date]
      );

      return result.rowCount || 0;
    } catch (error) {
      console.error("Failed to archive old logs:", error);
      return 0;
    }
  }

  /**
   * Hash content for integrity checking
   */
  private hashContent(content: string): string {
    return crypto.createHash("sha256").update(content).digest("hex");
  }

  /**
   * Close database connection
   */
  async close(): Promise<void> {
    await this.pool.end();
  }
}
