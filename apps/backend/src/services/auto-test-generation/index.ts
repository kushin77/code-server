#!/usr/bin/env node
// @file        apps/backend/src/services/auto-test-generation/index.ts
// @module      collaboration/auto-test-generation
// @description AI-powered Jest test generation from bug fix sessions
// @owner       collab-3.9
// @status      active

import { EventEmitter } from 'events';
import { Pool } from 'pg';
import { getLogger } from '../../lib/logger';

const logger = getLogger('AutoTestGenerationService');

export interface TestSuggestion {
  id: string;
  sessionId: string;
  fileName: string;
  functionName: string;
  testCode: string;
  coverage: number; // 0-100 percentage
  confidence: number; // 0-100 AI confidence
  aiContext: string;
  status: 'pending' | 'accepted' | 'rejected' | 'used';
  rejectionReason?: string;
  createdAt: Date;
  acceptedAt?: Date;
  usedAt?: Date;
}

export interface TestMetrics {
  sessionId: string;
  totalSuggestions: number;
  accepted: number;
  rejected: number;
  used: number;
  avgConfidence: number;
  avgCoverage: number;
}

export interface GenerateTestsRequest {
  sessionId: string;
  changedFiles: string[];
  aiContext: string;
  bugDescription: string;
  fixDescription: string;
}

export class AutoTestGenerationService extends EventEmitter {
  private pool: Pool;
  private initialized = false;

  constructor(pool: Pool) {
    super();
    this.pool = pool;
  }

  async initialize(): Promise<void> {
    if (this.initialized) return;

    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');

      // Test suggestions table
      await client.query(`
        CREATE TABLE IF NOT EXISTS test_suggestions (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          session_id VARCHAR(255) NOT NULL,
          file_name VARCHAR(512) NOT NULL,
          function_name VARCHAR(255),
          test_code TEXT NOT NULL,
          coverage INTEGER CHECK (coverage >= 0 AND coverage <= 100),
          confidence INTEGER CHECK (confidence >= 0 AND confidence <= 100),
          ai_context TEXT,
          status VARCHAR(50) DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'rejected', 'used')),
          rejection_reason TEXT,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          accepted_at TIMESTAMP WITH TIME ZONE,
          used_at TIMESTAMP WITH TIME ZONE,
          CONSTRAINT valid_status CHECK (
            (status = 'pending' AND accepted_at IS NULL) OR
            (status = 'accepted' AND accepted_at IS NOT NULL) OR
            (status = 'rejected' AND rejection_reason IS NOT NULL) OR
            (status = 'used' AND used_at IS NOT NULL)
          )
        );
      `);

      // Session test batch tracking
      await client.query(`
        CREATE TABLE IF NOT EXISTS test_generation_batches (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          session_id VARCHAR(255) NOT NULL UNIQUE,
          bug_description TEXT NOT NULL,
          fix_description TEXT NOT NULL,
          total_suggestions INTEGER DEFAULT 0,
          ai_model VARCHAR(255),
          generated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        );
      `);

      // User feedback on tests
      await client.query(`
        CREATE TABLE IF NOT EXISTS test_feedback (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          suggestion_id UUID NOT NULL REFERENCES test_suggestions(id) ON DELETE CASCADE,
          user_id VARCHAR(255) NOT NULL,
          feedback_type VARCHAR(50) CHECK (feedback_type IN ('helpful', 'incorrect', 'incomplete', 'unclear')),
          comment TEXT,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        );
      `);

      // Test execution results
      await client.query(`
        CREATE TABLE IF NOT EXISTS test_execution_results (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          suggestion_id UUID NOT NULL REFERENCES test_suggestions(id) ON DELETE CASCADE,
          passed BOOLEAN,
          duration_ms INTEGER,
          error_message TEXT,
          execution_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        );
      `);

      // Create indexes
      await client.query('CREATE INDEX IF NOT EXISTS idx_test_suggestions_session ON test_suggestions(session_id)');
      await client.query('CREATE INDEX IF NOT EXISTS idx_test_suggestions_status ON test_suggestions(status)');
      await client.query('CREATE INDEX IF NOT EXISTS idx_test_suggestions_confidence ON test_suggestions(confidence DESC)');
      await client.query('CREATE INDEX IF NOT EXISTS idx_test_feedback_suggestion ON test_feedback(suggestion_id)');
      await client.query('CREATE INDEX IF NOT EXISTS idx_test_execution_suggestion ON test_execution_results(suggestion_id)');

      await client.query('COMMIT');
      this.initialized = true;
      logger.info('AutoTestGenerationService initialized');
    } catch (error) {
      await client.query('ROLLBACK');
      logger.error('Failed to initialize AutoTestGenerationService', { error });
      throw error;
    } finally {
      client.release();
    }
  }

  async generateTestsForSession(request: GenerateTestsRequest, suggestedTests: TestSuggestion[]): Promise<TestSuggestion[]> {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');

      // Create batch record
      await client.query(`
        INSERT INTO test_generation_batches (session_id, bug_description, fix_description, total_suggestions)
        VALUES ($1, $2, $3, $4)
        ON CONFLICT (session_id) DO UPDATE SET total_suggestions = $4
      `, [request.sessionId, request.bugDescription, request.fixDescription, suggestedTests.length]);

      const inserted: TestSuggestion[] = [];
      for (const test of suggestedTests) {
        const result = await client.query(`
          INSERT INTO test_suggestions 
          (session_id, file_name, function_name, test_code, coverage, confidence, ai_context, status, created_at)
          VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NOW())
          RETURNING id, session_id, file_name, function_name, test_code, coverage, confidence, ai_context, status, created_at
        `, [
          request.sessionId,
          test.fileName,
          test.functionName,
          test.testCode,
          test.coverage,
          test.confidence,
          request.aiContext,
          'pending',
        ]);

        inserted.push(this.rowToTestSuggestion(result.rows[0]));
      }

      await client.query('COMMIT');
      this.emit('tests-generated', { sessionId: request.sessionId, count: inserted.length });
      logger.info(`Generated ${inserted.length} test suggestions for session ${request.sessionId}`);
      return inserted;
    } catch (error) {
      await client.query('ROLLBACK');
      logger.error('Failed to generate tests', { sessionId: request.sessionId, error });
      throw error;
    } finally {
      client.release();
    }
  }

  async getTestSuggestion(suggestionId: string): Promise<TestSuggestion | null> {
    const client = await this.pool.connect();
    try {
      const result = await client.query('SELECT * FROM test_suggestions WHERE id = $1', [suggestionId]);
      return result.rows.length ? this.rowToTestSuggestion(result.rows[0]) : null;
    } finally {
      client.release();
    }
  }

  async acceptTestSuggestion(suggestionId: string): Promise<TestSuggestion> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(`
        UPDATE test_suggestions 
        SET status = 'accepted', accepted_at = NOW()
        WHERE id = $1
        RETURNING *
      `, [suggestionId]);

      if (!result.rows.length) {
        throw new Error(`Test suggestion ${suggestionId} not found`);
      }

      const suggestion = this.rowToTestSuggestion(result.rows[0]);
      this.emit('test-accepted', { suggestionId, sessionId: suggestion.sessionId });
      return suggestion;
    } finally {
      client.release();
    }
  }

  async rejectTestSuggestion(suggestionId: string, reason: string): Promise<TestSuggestion> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(`
        UPDATE test_suggestions 
        SET status = 'rejected', rejection_reason = $2
        WHERE id = $1
        RETURNING *
      `, [suggestionId, reason]);

      if (!result.rows.length) {
        throw new Error(`Test suggestion ${suggestionId} not found`);
      }

      const suggestion = this.rowToTestSuggestion(result.rows[0]);
      this.emit('test-rejected', { suggestionId, reason });
      return suggestion;
    } finally {
      client.release();
    }
  }

  async getSessionTestSuggestions(sessionId: string, status?: string): Promise<TestSuggestion[]> {
    const client = await this.pool.connect();
    try {
      let query = 'SELECT * FROM test_suggestions WHERE session_id = $1';
      const params: any[] = [sessionId];

      if (status) {
        query += ' AND status = $2';
        params.push(status);
      }

      query += ' ORDER BY confidence DESC, created_at DESC';
      const result = await client.query(query, params);
      return result.rows.map(row => this.rowToTestSuggestion(row));
    } finally {
      client.release();
    }
  }

  async markTestAsUsed(suggestionId: string): Promise<TestSuggestion> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(`
        UPDATE test_suggestions 
        SET status = 'used', used_at = NOW()
        WHERE id = $1
        RETURNING *
      `, [suggestionId]);

      if (!result.rows.length) {
        throw new Error(`Test suggestion ${suggestionId} not found`);
      }

      const suggestion = this.rowToTestSuggestion(result.rows[0]);
      this.emit('test-used', { suggestionId, sessionId: suggestion.sessionId });
      return suggestion;
    } finally {
      client.release();
    }
  }

  async recordTestExecution(suggestionId: string, passed: boolean, durationMs: number, errorMessage?: string): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query(`
        INSERT INTO test_execution_results (suggestion_id, passed, duration_ms, error_message)
        VALUES ($1, $2, $3, $4)
      `, [suggestionId, passed, durationMs, errorMessage || null]);

      this.emit('test-executed', { suggestionId, passed, durationMs });
    } finally {
      client.release();
    }
  }

  async getTestMetrics(sessionId: string): Promise<TestMetrics> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(`
        SELECT 
          COUNT(*) as total,
          SUM(CASE WHEN status = 'accepted' THEN 1 ELSE 0 END) as accepted,
          SUM(CASE WHEN status = 'rejected' THEN 1 ELSE 0 END) as rejected,
          SUM(CASE WHEN status = 'used' THEN 1 ELSE 0 END) as used,
          ROUND(AVG(confidence)::numeric, 2) as avg_confidence,
          ROUND(AVG(coverage)::numeric, 2) as avg_coverage
        FROM test_suggestions
        WHERE session_id = $1
      `, [sessionId]);

      const row = result.rows[0];
      return {
        sessionId,
        totalSuggestions: parseInt(row.total) || 0,
        accepted: parseInt(row.accepted) || 0,
        rejected: parseInt(row.rejected) || 0,
        used: parseInt(row.used) || 0,
        avgConfidence: parseFloat(row.avg_confidence) || 0,
        avgCoverage: parseFloat(row.avg_coverage) || 0,
      };
    } finally {
      client.release();
    }
  }

  async addFeedback(suggestionId: string, userId: string, feedbackType: 'helpful' | 'incorrect' | 'incomplete' | 'unclear', comment?: string): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query(`
        INSERT INTO test_feedback (suggestion_id, user_id, feedback_type, comment)
        VALUES ($1, $2, $3, $4)
      `, [suggestionId, userId, feedbackType, comment || null]);

      this.emit('feedback-recorded', { suggestionId, feedbackType });
    } finally {
      client.release();
    }
  }

  private rowToTestSuggestion(row: any): TestSuggestion {
    return {
      id: row.id,
      sessionId: row.session_id,
      fileName: row.file_name,
      functionName: row.function_name,
      testCode: row.test_code,
      coverage: row.coverage,
      confidence: row.confidence,
      aiContext: row.ai_context,
      status: row.status,
      rejectionReason: row.rejection_reason,
      createdAt: row.created_at,
      acceptedAt: row.accepted_at,
      usedAt: row.used_at,
    };
  }
}
