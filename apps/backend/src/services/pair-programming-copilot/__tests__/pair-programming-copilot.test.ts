#!/usr/bin/env node
// @file        apps/backend/src/services/pair-programming-copilot/__tests__/pair-programming-copilot.test.ts
// @module      collaboration/pair-programming-copilot
// @description Tests for shared context injection and deduplicated pair copilot suggestions
// @owner       collab-3.2
// @status      active

import { describe, it, expect, beforeEach, vi } from 'vitest';
import { Pool } from 'pg';
import { PairProgrammingAICopilotService } from '../index';

vi.mock('../../../lib/logger', () => ({
  getLogger: vi.fn(() => ({
    info: vi.fn(),
    error: vi.fn(),
    warn: vi.fn(),
    debug: vi.fn(),
  })),
}));

describe('PairProgrammingAICopilotService', () => {
  let service: PairProgrammingAICopilotService;
  let mockPool: Partial<Pool>;
  let mockClient: any;

  beforeEach(() => {
    mockClient = {
      query: vi.fn(),
      release: vi.fn(),
    };

    mockPool = {
      connect: vi.fn(async () => mockClient),
    } as unknown as Pool;

    service = new PairProgrammingAICopilotService(mockPool as Pool);
  });

  it('initializes schema tables', async () => {
    mockClient.query.mockResolvedValue({});

    await service.initialize();

    expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('pair_copilot_context_entries'));
    expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('pair_copilot_suggestions'));
  });

  it('upserts participant edit context', async () => {
    const now = new Date().toISOString();
    mockClient.query.mockResolvedValueOnce({
      rows: [
        {
          id: 'ctx-1',
          session_id: 'session-1',
          user_id: 'alice',
          file_path: 'src/app.ts',
          function_name: 'run',
          edit_summary: 'Refactored function signature',
          cursor_line: 21,
          cursor_column: 5,
          updated_at: now,
        },
      ],
    });

    const contextEntry = await service.upsertContext({
      sessionId: 'session-1',
      userId: 'alice',
      filePath: 'src/app.ts',
      functionName: 'run',
      editSummary: 'Refactored function signature',
      cursorLine: 21,
      cursorColumn: 5,
    });

    expect(contextEntry.id).toBe('ctx-1');
    expect(contextEntry.userId).toBe('alice');
    expect(contextEntry.functionName).toBe('run');
  });

  it('builds shared context grouped by participant', async () => {
    const now = new Date().toISOString();
    mockClient.query.mockResolvedValueOnce({
      rows: [
        {
          id: 'ctx-1',
          session_id: 'session-1',
          user_id: 'alice',
          file_path: 'src/app.ts',
          function_name: 'run',
          edit_summary: 'Refactored function signature',
          cursor_line: 21,
          cursor_column: 5,
          updated_at: now,
        },
        {
          id: 'ctx-2',
          session_id: 'session-1',
          user_id: 'bob',
          file_path: 'src/app.ts',
          function_name: '',
          edit_summary: 'Added null checks',
          cursor_line: 35,
          cursor_column: 1,
          updated_at: now,
        },
      ],
    });

    const shared = await service.getSharedContext('session-1', 'alice');

    expect(shared.sessionId).toBe('session-1');
    expect(shared.participants).toHaveLength(2);
    expect(shared.participants.find((entry) => entry.userId === 'bob')?.edits[0].editSummary).toContain('null checks');
  });

  it('deduplicates repeated suggestions per session', async () => {
    const now = new Date().toISOString();

    mockClient.query
      .mockResolvedValueOnce({
        rows: [
          {
            id: 'ctx-1',
            session_id: 'session-1',
            user_id: 'alice',
            file_path: 'src/app.ts',
            function_name: '',
            edit_summary: 'Refactored imports',
            cursor_line: 10,
            cursor_column: 2,
            updated_at: now,
          },
        ],
      })
      .mockResolvedValueOnce({ rowCount: 1, rows: [{ id: 'suggest-1' }] })
      .mockResolvedValueOnce({
        rows: [
          {
            id: 'ctx-1',
            session_id: 'session-1',
            user_id: 'alice',
            file_path: 'src/app.ts',
            function_name: '',
            edit_summary: 'Refactored imports',
            cursor_line: 10,
            cursor_column: 2,
            updated_at: now,
          },
        ],
      })
      .mockResolvedValueOnce({ rowCount: 0, rows: [] });

    const first = await service.generateSuggestions({
      sessionId: 'session-1',
      requesterId: 'bob',
      prompt: 'Prepare a safe refactor plan',
      maxSuggestions: 1,
    });

    const second = await service.generateSuggestions({
      sessionId: 'session-1',
      requesterId: 'bob',
      prompt: 'Prepare a safe refactor plan',
      maxSuggestions: 1,
    });

    expect(first.suggestions).toHaveLength(1);
    expect(first.suggestions[0].deduplicated).toBe(false);
    expect(second.suggestions).toHaveLength(1);
    expect(second.suggestions[0].deduplicated).toBe(true);
  });
});
