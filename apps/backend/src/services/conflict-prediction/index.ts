#!/usr/bin/env node
// @file        apps/backend/src/services/conflict-prediction/index.ts
// @module      collaboration/conflict-prediction
// @description ML-powered conflict prediction before merge
// @owner       collab-3.1
// @status      active

import { EventEmitter } from 'events';
import { Router, type Response } from 'express';
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
    for (const edit of this.activeEdits.values()) {
      if (edit.userId !== userId && edit.filePath === filePath && edit.functionName === functionName) {
        await this.triggerConflictAlert(userId, edit.userId, filePath, functionName);
      }
    }
  }

  previewConflicts(userId: string, filePath: string, functionName: string | null): ConflictAlert[] {
    return this.getMatchingEdits(userId, filePath, functionName).map((otherEdit) => ({
      id: Math.random().toString(36).substring(7),
      targetUserId: userId,
      otherUserId: otherEdit.userId,
      filePath,
      functionName,
      riskScore: this.calculateRiskScore(filePath, functionName),
      message: functionName
        ? `Warning: ${otherEdit.userId} is also editing function ${functionName} in ${filePath}`
        : `Warning: ${otherEdit.userId} is also editing ${filePath}`,
    }));
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

  private getMatchingEdits(userId: string, filePath: string, functionName: string | null): ActiveEdit[] {
    return Array.from(this.activeEdits.values()).filter((edit) => {
      return edit.userId !== userId && edit.filePath === filePath && edit.functionName === functionName;
    });
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

function sendError(response: Response, error: unknown): Response {
  const message = error instanceof Error ? error.message : 'Unexpected conflict prediction error';
  return response.status(400).json({ error: message });
}

function requireText(value: unknown): string {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new Error('Missing required field');
  }

  return value.trim();
}

export function initializeConflictPredictionRoutes(pool: Pool) {
  const router = Router();
  const service = new ConflictPredictionService(pool);
  const logger = getLogger('ConflictPredictionRoutes');

  service.initialize().catch((error) => {
    logger.error('Failed to initialize conflict prediction service', { error });
  });

  router.post('/api/conflict-prediction/activity', async (request, response) => {
    try {
      const userId = requireText(request.body?.userId);
      const filePath = requireText(request.body?.filePath);
      const functionName = typeof request.body?.functionName === 'string' && request.body.functionName.trim().length > 0
        ? request.body.functionName.trim()
        : null;

      await service.reportActivity(userId, filePath, functionName);
      response.status(201).json({
        success: true,
        conflicts: service.previewConflicts(userId, filePath, functionName),
      });
    } catch (error) {
      logger.error('Failed to record conflict prediction activity', { error, body: request.body });
      sendError(response, error);
    }
  });

  router.get('/api/conflict-prediction/preview', async (request, response) => {
    try {
      const userId = requireText(request.query.userId);
      const filePath = requireText(request.query.filePath);
      const functionName = typeof request.query.functionName === 'string' && request.query.functionName.trim().length > 0
        ? request.query.functionName.trim()
        : null;

      response.json({
        success: true,
        conflicts: service.previewConflicts(userId, filePath, functionName),
      });
    } catch (error) {
      logger.error('Failed to preview conflict prediction', { error, query: request.query });
      sendError(response, error);
    }
  });

  return router;
}
