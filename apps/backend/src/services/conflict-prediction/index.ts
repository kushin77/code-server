#!/usr/bin/env node
// @file        apps/backend/src/services/conflict-prediction/index.ts
// @module      collaboration/conflict-prediction
// @description ML-powered conflict prediction before merge
// @owner       collab-3.1
// @status      active

import { EventEmitter } from 'events';
import { Pool } from 'pg';
import { getLogger } from '../../lib/logger';

export interface ActiveEdit {
  userId: string;
  filePath: string;
  functionName: string | null;
  timestamp: number;
}

export interface ConflictAlert {
  id: string;
  targetUserId: string;
  otherUserId: string;
  filePath: string;
  functionName: string | null;
  riskScore: number;
  message: string;
}

export class ConflictPredictionService extends EventEmitter {
  private logger = getLogger('ConflictPredictionService');
  private pool: Pool;
  private activeEdits: Map<string, ActiveEdit> = new Map();

  constructor(pool: Pool) {
    super();
    this.pool = pool;
  }

  async initialize(): Promise<void> {
    await this.createTables();
    this.startCleanupInterval();
  }

  private async createTables(): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query(`
        CREATE TABLE IF NOT EXISTS conflict_logs (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id1 VARCHAR(255) NOT NULL,
          user_id2 VARCHAR(255) NOT NULL,
          file_path VARCHAR(512) NOT NULL,
          function_name VARCHAR(255),
          risk_score INTEGER NOT NULL,
          created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      `);
      await client.query(`CREATE INDEX IF NOT EXISTS idx_conflict_logs_file ON conflict_logs(file_path, function_name)`);
    } finally {
      client.release();
    }
  }

  /**
   * Record that a user is actively editing a file/function
   */
  async reportActivity(userId: string, filePath: string, functionName: string | null): Promise<void> {
    const key = `${userId}:${filePath}:${functionName || ''}`;
    this.activeEdits.set(key, { userId, filePath, functionName, timestamp: Date.now() });

    // Check for overlaps with other users
    for (const [otherKey, edit] of this.activeEdits.entries()) {
      if (edit.userId !== userId && edit.filePath === filePath && edit.functionName === functionName) {
        await this.triggerConflictAlert(userId, edit.userId, filePath, functionName);
      }
    }
  }

  private async triggerConflictAlert(
    userId1: string,
    userId2: string,
    filePath: string,
    functionName: string | null
  ): Promise<void> {
    const riskScore = this.calculateRiskScore(filePath, functionName);
    const message = functionName 
      ? `Warning: ${userId2} is also editing function ${functionName} in ${filePath}`
      : `Warning: ${userId2} is also editing ${filePath}`;

    const alert: ConflictAlert = {
      id: Math.random().toString(36).substring(7),
      targetUserId: userId1,
      otherUserId: userId2,
      filePath,
      functionName,
      riskScore,
      message
    };

    this.emit('conflict-detected', alert);
    this.logger.warn(`Conflict predicted between ${userId1} and ${userId2} on ${filePath}#${functionName || ''} (Score: ${riskScore})`);
    
    // Log persistent record
    const client = await this.pool.connect();
    try {
      await client.query(
        'INSERT INTO conflict_logs (user_id1, user_id2, file_path, function_name, risk_score) VALUES ($1, $2, $3, $4, $5)',
        [userId1, userId2, filePath, functionName, riskScore]
      );
    } finally {
      client.release();
    }
  }

  private calculateRiskScore(filePath: string, functionName: string | null): number {
    // Simple heuristic: function level hits are riskier (90) than file level (50)
    return functionName ? 90 : 50;
  }

  private startCleanupInterval(): void {
    // Purge edits older than 5 minutes
    setInterval(() => {
      const now = Date.now();
      for (const [key, edit] of this.activeEdits.entries()) {
        if (now - edit.timestamp > 300000) {
          this.activeEdits.delete(key);
        }
      }
    }, 60000);
  }
}
