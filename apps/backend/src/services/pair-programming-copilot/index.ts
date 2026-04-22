#!/usr/bin/env node
// @file        apps/backend/src/services/pair-programming-copilot/index.ts
// @module      collaboration/pair-programming-copilot
// @description Shared context injection and deduplicated suggestions for pair programming AI copilot
// @owner       collab-3.2
// @status      active

import { createHash, randomUUID } from 'crypto';
import { EventEmitter } from 'events';
import { Pool } from 'pg';
import { getLogger } from '../../lib/logger';

export interface PairCopilotContextUpdateInput {
  sessionId: string;
  userId: string;
  filePath: string;
  functionName?: string | null;
  editSummary: string;
  cursorLine?: number | null;
  cursorColumn?: number | null;
}

export interface PairCopilotContextEntry {
  id: string;
  sessionId: string;
  userId: string;
  filePath: string;
  functionName: string | null;
  editSummary: string;
  cursorLine: number | null;
  cursorColumn: number | null;
  updatedAt: string;
}

export interface SharedParticipantContext {
  userId: string;
  edits: PairCopilotContextEntry[];
}

export interface PairCopilotSharedContext {
  sessionId: string;
  requesterId?: string;
  generatedAt: string;
  participants: SharedParticipantContext[];
}

export interface PairCopilotSuggestion {
  id: string;
  text: string;
  hash: string;
  deduplicated: boolean;
}

export interface PairCopilotSuggestionRequest {
  sessionId: string;
  requesterId: string;
  prompt?: string;
  maxSuggestions?: number;
}

export interface PairCopilotSuggestionResponse {
  sharedContext: PairCopilotSharedContext;
  suggestions: PairCopilotSuggestion[];
}

export class PairProgrammingAICopilotService extends EventEmitter {
  private pool: Pool;
  private logger = getLogger('PairProgrammingAICopilotService');
  private initialized = false;

  constructor(pool: Pool) {
    super();
    this.pool = pool;
  }

  async initialize(): Promise<void> {
    if (this.initialized) {
      return;
    }

    await this.createTables();
    this.initialized = true;
    this.logger.info('Pair programming AI copilot schema initialized');
  }

  private async createTables(): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query(`
        CREATE TABLE IF NOT EXISTS pair_copilot_context_entries (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          session_id TEXT NOT NULL,
          user_id TEXT NOT NULL,
          file_path TEXT NOT NULL,
          function_name TEXT NOT NULL DEFAULT '',
          edit_summary TEXT NOT NULL,
          cursor_line INTEGER,
          cursor_column INTEGER,
          updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
          UNIQUE(session_id, user_id, file_path, function_name)
        )
      `);

      await client.query(`
        CREATE TABLE IF NOT EXISTS pair_copilot_suggestions (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          session_id TEXT NOT NULL,
          requester_id TEXT NOT NULL,
          suggestion_hash TEXT NOT NULL,
          suggestion_text TEXT NOT NULL,
          context_snapshot JSONB NOT NULL,
          created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
          UNIQUE(session_id, suggestion_hash)
        )
      `);

      await client.query(`
        CREATE INDEX IF NOT EXISTS idx_pair_copilot_context_session
          ON pair_copilot_context_entries(session_id, updated_at DESC)
      `);

      await client.query(`
        CREATE INDEX IF NOT EXISTS idx_pair_copilot_suggestions_session
          ON pair_copilot_suggestions(session_id, created_at DESC)
      `);
    } finally {
      client.release();
    }
  }

  async upsertContext(input: PairCopilotContextUpdateInput): Promise<PairCopilotContextEntry> {
    this.requireText(input.sessionId, 'sessionId');
    this.requireText(input.userId, 'userId');
    this.requireText(input.filePath, 'filePath');
    this.requireText(input.editSummary, 'editSummary');

    const normalizedFunctionName = (input.functionName || '').trim();

    const client = await this.pool.connect();
    try {
      const result = await client.query(
        `
          INSERT INTO pair_copilot_context_entries (
            session_id,
            user_id,
            file_path,
            function_name,
            edit_summary,
            cursor_line,
            cursor_column,
            updated_at
          )
          VALUES ($1, $2, $3, $4, $5, $6, $7, NOW())
          ON CONFLICT (session_id, user_id, file_path, function_name)
          DO UPDATE SET
            edit_summary = EXCLUDED.edit_summary,
            cursor_line = EXCLUDED.cursor_line,
            cursor_column = EXCLUDED.cursor_column,
            updated_at = NOW()
          RETURNING
            id,
            session_id,
            user_id,
            file_path,
            function_name,
            edit_summary,
            cursor_line,
            cursor_column,
            updated_at
        `,
        [
          input.sessionId.trim(),
          input.userId.trim(),
          input.filePath.trim(),
          normalizedFunctionName,
          input.editSummary.trim(),
          input.cursorLine ?? null,
          input.cursorColumn ?? null,
        ]
      );

      const entry = this.mapContextRow(result.rows[0]);
      this.emit('context-updated', entry);
      return entry;
    } finally {
      client.release();
    }
  }

  async getSharedContext(sessionId: string, requesterId?: string): Promise<PairCopilotSharedContext> {
    this.requireText(sessionId, 'sessionId');

    const client = await this.pool.connect();
    try {
      const result = await client.query(
        `
          SELECT
            id,
            session_id,
            user_id,
            file_path,
            function_name,
            edit_summary,
            cursor_line,
            cursor_column,
            updated_at
          FROM pair_copilot_context_entries
          WHERE session_id = $1
          ORDER BY updated_at DESC
        `,
        [sessionId.trim()]
      );

      const grouped = new Map<string, PairCopilotContextEntry[]>();
      for (const row of result.rows) {
        const entry = this.mapContextRow(row);
        const list = grouped.get(entry.userId) ?? [];
        list.push(entry);
        grouped.set(entry.userId, list);
      }

      const participants: SharedParticipantContext[] = Array.from(grouped.entries()).map(([userId, edits]) => ({
        userId,
        edits,
      }));

      return {
        sessionId: sessionId.trim(),
        requesterId: requesterId?.trim() || undefined,
        generatedAt: new Date().toISOString(),
        participants,
      };
    } finally {
      client.release();
    }
  }

  async generateSuggestions(input: PairCopilotSuggestionRequest): Promise<PairCopilotSuggestionResponse> {
    this.requireText(input.sessionId, 'sessionId');
    this.requireText(input.requesterId, 'requesterId');

    const sharedContext = await this.getSharedContext(input.sessionId, input.requesterId);
    const maxSuggestions = input.maxSuggestions && input.maxSuggestions > 0 ? input.maxSuggestions : 5;
    const candidates = this.buildCandidateSuggestions(sharedContext, input.prompt, maxSuggestions);

    const client = await this.pool.connect();
    try {
      const suggestions: PairCopilotSuggestion[] = [];
      for (const suggestionText of candidates) {
        const suggestionHash = this.computeSuggestionHash(input.sessionId, suggestionText);
        const insertResult = await client.query(
          `
            INSERT INTO pair_copilot_suggestions (
              session_id,
              requester_id,
              suggestion_hash,
              suggestion_text,
              context_snapshot
            )
            VALUES ($1, $2, $3, $4, $5)
            ON CONFLICT (session_id, suggestion_hash)
            DO NOTHING
            RETURNING id
          `,
          [
            input.sessionId.trim(),
            input.requesterId.trim(),
            suggestionHash,
            suggestionText,
            JSON.stringify(sharedContext),
          ]
        );

        const deduplicated = insertResult.rowCount === 0;
        suggestions.push({
          id: deduplicated ? randomUUID() : insertResult.rows[0].id,
          text: suggestionText,
          hash: suggestionHash,
          deduplicated,
        });
      }

      this.emit('suggestions-generated', {
        sessionId: input.sessionId.trim(),
        requesterId: input.requesterId.trim(),
        count: suggestions.length,
      });

      return {
        sharedContext,
        suggestions,
      };
    } finally {
      client.release();
    }
  }

  private buildCandidateSuggestions(
    sharedContext: PairCopilotSharedContext,
    prompt: string | undefined,
    maxSuggestions: number
  ): string[] {
    const candidates: string[] = [];

    if (prompt && prompt.trim().length > 0) {
      candidates.push(`Align on pair objective before coding: ${prompt.trim().slice(0, 180)}`);
    }

    const fileEditors = new Map<string, Set<string>>();
    for (const participant of sharedContext.participants) {
      for (const edit of participant.edits) {
        const editors = fileEditors.get(edit.filePath) ?? new Set<string>();
        editors.add(participant.userId);
        fileEditors.set(edit.filePath, editors);
      }
    }

    for (const [filePath, editors] of fileEditors.entries()) {
      if (editors.size > 1) {
        const users = Array.from(editors).join(', ');
        candidates.push(`Coordinate edits on ${filePath} before commit. Active editors: ${users}.`);
      }
    }

    for (const participant of sharedContext.participants) {
      const latestEdit = participant.edits[0];
      if (!latestEdit) {
        continue;
      }

      const functionSuffix = latestEdit.functionName ? `#${latestEdit.functionName}` : '';
      candidates.push(
        `Ask ${participant.userId} to summarize intent for ${latestEdit.filePath}${functionSuffix}: ${latestEdit.editSummary}`
      );
    }

    const deduplicated: string[] = [];
    const seen = new Set<string>();
    for (const candidate of candidates) {
      if (!seen.has(candidate)) {
        seen.add(candidate);
        deduplicated.push(candidate);
      }
      if (deduplicated.length >= maxSuggestions) {
        break;
      }
    }

    return deduplicated;
  }

  private computeSuggestionHash(sessionId: string, suggestionText: string): string {
    return createHash('sha256').update(`${sessionId.trim()}::${suggestionText}`).digest('hex');
  }

  private mapContextRow(row: any): PairCopilotContextEntry {
    const functionName = typeof row.function_name === 'string' && row.function_name.length > 0 ? row.function_name : null;
    return {
      id: row.id,
      sessionId: row.session_id,
      userId: row.user_id,
      filePath: row.file_path,
      functionName,
      editSummary: row.edit_summary,
      cursorLine: row.cursor_line ?? null,
      cursorColumn: row.cursor_column ?? null,
      updatedAt: new Date(row.updated_at).toISOString(),
    };
  }

  private requireText(value: string | undefined, field: string): void {
    if (!value || value.trim().length === 0) {
      throw new Error(`Missing required field: ${field}`);
    }
  }
}
