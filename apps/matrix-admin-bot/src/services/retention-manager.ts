/**
 * @file        apps/matrix-admin-bot/src/services/retention-manager.ts
 * @module      matrix/admin-bot/services
 * @description Manages retention policies for rooms
 */

import type { MatrixClient } from "matrix-bot-sdk";
import { Pool } from "pg";

export class RetentionManager {
  private pool: Pool;

  constructor(
    private client: MatrixClient,
    databaseUrl: string
  ) {
    this.pool = new Pool({ connectionString: databaseUrl });
  }

  /**
   * Set retention policy for a room
   */
  async setRetention(roomId: string, retentionDays: number): Promise<void> {
    if (retentionDays < 1) {
      throw new Error("Retention days must be at least 1");
    }

    const maxLifetime = retentionDays * 24 * 60 * 60 * 1000; // Convert to milliseconds

    try {
      // Update Synapse room state
      await this.client.sendStateEvent(
        roomId,
        "m.room.retention",
        "",
        {
          max_lifetime: maxLifetime,
        }
      );

      // Store in database for tracking
      await this.pool.query(
        `
        INSERT INTO audit.retention_policies (room_id, retention_days, max_lifetime_ms, set_at)
        VALUES ($1, $2, $3, NOW())
        `,
        [roomId, retentionDays, maxLifetime]
      );
    } catch (error) {
      throw new Error(
        `Failed to set retention policy: ${error instanceof Error ? error.message : "Unknown error"}`
      );
    }
  }

  /**
   * Get current retention policy for a room
   */
  async getRetention(roomId: string): Promise<number | null> {
    try {
      const state = await this.client.getRoomStateEvent(
        roomId,
        "m.room.retention",
        ""
      );

      if (state?.max_lifetime) {
        return Math.ceil(state.max_lifetime / (24 * 60 * 60 * 1000)); // Convert ms back to days
      }
      return null;
    } catch {
      return null;
    }
  }

  /**
   * Initialize retention policy schema if needed
   */
  async initializeSchema(): Promise<void> {
    try {
      await this.pool.query(`
        CREATE TABLE IF NOT EXISTS audit.retention_policies (
          id BIGSERIAL PRIMARY KEY,
          room_id VARCHAR(255) NOT NULL,
          retention_days INT NOT NULL,
          max_lifetime_ms BIGINT NOT NULL,
          set_at TIMESTAMP DEFAULT NOW(),
          set_by VARCHAR(255),
          UNIQUE(room_id)
        );

        CREATE INDEX IF NOT EXISTS idx_retention_room ON audit.retention_policies(room_id);
      `);
    } catch (error) {
      if (!(error instanceof Error) || !error.message.includes("already exists")) {
        throw error;
      }
    }
  }

  /**
   * Close database connection
   */
  async close(): Promise<void> {
    await this.pool.end();
  }
}
