#!/usr/bin/env node
// @file        apps/backend/src/services/debugging/__tests__/debug-session-ai-service.test.ts
// @module      services/debugging
// @description Tests for debug session AI service

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import service, { DebugSessionAIService, Breakpoint, VariableValue, StackFrame } from '../debug-session-ai-service';

describe('DebugSessionAIService', () => {
  beforeEach(() => {
    service.reset();
    service.removeAllListeners();
  });

  afterEach(() => {
    service.reset();
    service.removeAllListeners();
  });

  describe('Session Management', () => {
    it('should be a singleton', () => {
      const instance1 = DebugSessionAIService.getInstance();
      const instance2 = DebugSessionAIService.getInstance();
      expect(instance1).toBe(instance2);
    });

    it('should start a new debug session', () => {
      const session = service.startSession('user1', 'ws-123', 'sess-123', 'node');
      expect(session.id).toBeDefined();
      expect(session.userId).toBe('user1');
      expect(session.workspaceId).toBe('ws-123');
      expect(session.type).toBe('node');
      expect(session.state).toBe('running');
    });

    it('should retrieve a debug session', () => {
      const created = service.startSession('user1', 'ws-123', 'sess-123', 'node');
      const retrieved = service.getSession(created.id);
      expect(retrieved).toBe(created);
    });

    it('should stop a debug session', () => {
      const session = service.startSession('user1', 'ws-123', 'sess-123', 'node');
      const stopped = service.stopSession(session.id);
      expect(stopped?.state).toBe('stopped');
      expect(stopped?.stoppedAt).toBeDefined();
    });

    it('should list active sessions in a workspace', () => {
      service.startSession('user1', 'ws-123', 'sess-1', 'node');
      service.startSession('user1', 'ws-123', 'sess-2', 'python');
      const session3 = service.startSession('user1', 'ws-456', 'sess-3', 'go');

      const activeSessions = service.listSessions('ws-123');
      expect(activeSessions).toHaveLength(2);
      expect(activeSessions.every((s) => s.workspaceId === 'ws-123')).toBe(true);
    });

    it('should not list stopped sessions', () => {
      const session1 = service.startSession('user1', 'ws-123', 'sess-1', 'node');
      const session2 = service.startSession('user1', 'ws-123', 'sess-2', 'python');
      service.stopSession(session1.id);

      const activeSessions = service.listSessions('ws-123');
      expect(activeSessions).toHaveLength(1);
      expect(activeSessions[0].id).toBe(session2.id);
    });
  });

  describe('Breakpoint Management', () => {
    it('should set a breakpoint', () => {
      const session = service.startSession('user1', 'ws-123', 'sess-123', 'node');
      const breakpoint: Breakpoint = {
        id: 'bp-1',
        file: '/src/app.ts',
        line: 42,
        column: 10,
        verified: true,
      };

      const updated = service.setBreakpoint(session.id, breakpoint);
      expect(updated?.breakpoints.get('bp-1')).toBe(breakpoint);
    });

    it('should handle multiple breakpoints', () => {
      const session = service.startSession('user1', 'ws-123', 'sess-123', 'node');

      const bp1: Breakpoint = { id: 'bp-1', file: '/src/app.ts', line: 10, verified: true };
      const bp2: Breakpoint = { id: 'bp-2', file: '/src/utils.ts', line: 20, verified: true };
      const bp3: Breakpoint = { id: 'bp-3', file: '/src/app.ts', line: 30, verified: true };

      service.setBreakpoint(session.id, bp1);
      service.setBreakpoint(session.id, bp2);
      service.setBreakpoint(session.id, bp3);

      const retrieved = service.getSession(session.id);
      expect(retrieved?.breakpoints.size).toBe(3);
    });

    it('should remove a breakpoint', () => {
      const session = service.startSession('user1', 'ws-123', 'sess-123', 'node');
      const breakpoint: Breakpoint = {
        id: 'bp-1',
        file: '/src/app.ts',
        line: 42,
        verified: true,
      };

      service.setBreakpoint(session.id, breakpoint);
      service.removeBreakpoint(session.id, 'bp-1');

      const retrieved = service.getSession(session.id);
      expect(retrieved?.breakpoints.get('bp-1')).toBeUndefined();
    });

    it('should update breakpoint with hit count', () => {
      const session = service.startSession('user1', 'ws-123', 'sess-123', 'node');
      const breakpoint: Breakpoint = {
        id: 'bp-1',
        file: '/src/app.ts',
        line: 42,
        verified: true,
        hitCount: 0,
      };

      service.setBreakpoint(session.id, breakpoint);
      const updated: Breakpoint = { ...breakpoint, hitCount: 5 };
      service.setBreakpoint(session.id, updated);

      const retrieved = service.getSession(session.id);
      expect(retrieved?.breakpoints.get('bp-1')?.hitCount).toBe(5);
    });
  });

  describe('Session State Management', () => {
    it('should update session state to paused', () => {
      const session = service.startSession('user1', 'ws-123', 'sess-123', 'node');
      const updated = service.updateSessionState(session.id, 'paused');
      expect(updated?.state).toBe('paused');
    });

    it('should update session state to running', () => {
      const session = service.startSession('user1', 'ws-123', 'sess-123', 'node');
      service.updateSessionState(session.id, 'paused');
      const updated = service.updateSessionState(session.id, 'running');
      expect(updated?.state).toBe('running');
    });

    it('should update session state to stopped', () => {
      const session = service.startSession('user1', 'ws-123', 'sess-123', 'node');
      const updated = service.updateSessionState(session.id, 'stopped');
      expect(updated?.state).toBe('stopped');
    });
  });

  describe('Variable Capture', () => {
    it('should capture variables at breakpoint', () => {
      const session = service.startSession('user1', 'ws-123', 'sess-123', 'node');
      const breakpoint: Breakpoint = { id: 'bp-1', file: '/src/app.ts', line: 42, verified: true };
      service.setBreakpoint(session.id, breakpoint);

      const variables: VariableValue[] = [
        { name: 'x', value: '10', type: 'number' },
        { name: 'y', value: '20', type: 'number' },
      ];

      const updated = service.captureVariables(session.id, 'bp-1', variables);
      expect(updated?.variables).toHaveLength(2);
      expect(updated?.variables[0].name).toBe('x');
    });

    it('should store current breakpoint when capturing variables', () => {
      const session = service.startSession('user1', 'ws-123', 'sess-123', 'node');
      const breakpoint: Breakpoint = { id: 'bp-1', file: '/src/app.ts', line: 42, verified: true };
      service.setBreakpoint(session.id, breakpoint);

      const variables: VariableValue[] = [{ name: 'x', value: '10', type: 'number' }];
      service.captureVariables(session.id, 'bp-1', variables);

      const retrieved = service.getSession(session.id);
      expect(retrieved?.currentBreakpoint?.id).toBe('bp-1');
    });

    it('should maintain issue history', () => {
      const session = service.startSession('user1', 'ws-123', 'sess-123', 'node');
      const bp: Breakpoint = { id: 'bp-1', file: '/src/app.ts', line: 42, verified: true };
      service.setBreakpoint(session.id, bp);

      const vars1: VariableValue[] = [{ name: 'x', value: '1', type: 'number' }];
      const vars2: VariableValue[] = [{ name: 'x', value: '2', type: 'number' }];

      service.captureVariables(session.id, 'bp-1', vars1);
      service.captureVariables(session.id, 'bp-1', vars2);

      const retrieved = service.getSession(session.id);
      expect(retrieved?.issueHistory).toHaveLength(2);
    });

    it('should limit history to 100 items', () => {
      const session = service.startSession('user1', 'ws-123', 'sess-123', 'node');
      const bp: Breakpoint = { id: 'bp-1', file: '/src/app.ts', line: 42, verified: true };
      service.setBreakpoint(session.id, bp);

      for (let i = 0; i < 150; i++) {
        const vars: VariableValue[] = [{ name: 'x', value: String(i), type: 'number' }];
        service.captureVariables(session.id, 'bp-1', vars);
      }

      const retrieved = service.getSession(session.id);
      expect(retrieved?.issueHistory.length).toBeLessThanOrEqual(100);
    });
  });

  describe('Stack Frame Capture', () => {
    it('should capture stack frames', () => {
      const session = service.startSession('user1', 'ws-123', 'sess-123', 'node');
      const frames: StackFrame[] = [
        { id: 1, name: 'main', file: '/src/app.ts', line: 42 },
        { id: 2, name: 'handleRequest', file: '/src/routes/handler.ts', line: 10 },
        { id: 3, name: 'processData', file: '/src/utils.ts', line: 50 },
      ];

      const updated = service.captureStackFrames(session.id, frames);
      expect(updated?.stackFrames).toHaveLength(3);
      expect(updated?.stackFrames[0].name).toBe('main');
    });

    it('should handle deep stack frames', () => {
      const session = service.startSession('user1', 'ws-123', 'sess-123', 'node');
      const frames: StackFrame[] = [];
      for (let i = 0; i < 60; i++) {
        frames.push({
          id: i,
          name: `frame${i}`,
          file: '/src/app.ts',
          line: i,
        });
      }

      service.captureStackFrames(session.id, frames);
      const retrieved = service.getSession(session.id);
      expect(retrieved?.stackFrames).toHaveLength(60);
    });
  });

  describe('Root Cause Analysis', () => {
    it('should analyze root cause', () => {
      const session = service.startSession('user1', 'ws-123', 'sess-123', 'node');
      const bp: Breakpoint = { id: 'bp-1', file: '/src/app.ts', line: 42, verified: true };
      service.setBreakpoint(session.id, bp);

      const variables: VariableValue[] = [{ name: 'x', value: 'null', type: 'null' }];
      service.captureVariables(session.id, 'bp-1', variables);
      service.captureStackFrames(session.id, [{ id: 1, name: 'main', file: '/src/app.ts', line: 42 }]);

      const analysis = service.analyzeRootCause(session.id);
      expect(analysis).toBeDefined();
      expect(analysis?.likely.length).toBeGreaterThan(0);
      expect(analysis?.confidence).toBeGreaterThan(0);
    });

    it('should detect null/undefined variables', () => {
      const session = service.startSession('user1', 'ws-123', 'sess-123', 'node');
      const bp: Breakpoint = { id: 'bp-1', file: '/src/app.ts', line: 42, verified: true };
      service.setBreakpoint(session.id, bp);

      const variables: VariableValue[] = [
        { name: 'user', value: 'null', type: 'object' },
        { name: 'name', value: 'undefined', type: 'string' },
      ];
      service.captureVariables(session.id, 'bp-1', variables);
      service.captureStackFrames(session.id, [{ id: 1, name: 'main', file: '/src/app.ts', line: 42 }]);

      const analysis = service.analyzeRootCause(session.id);
      expect(analysis?.likely.some((c) => c.includes('Null'))).toBe(true);
    });

    it('should detect type mismatches', () => {
      const session = service.startSession('user1', 'ws-123', 'sess-123', 'node');
      const bp: Breakpoint = { id: 'bp-1', file: '/src/app.ts', line: 42, verified: true };
      service.setBreakpoint(session.id, bp);

      const variables: VariableValue[] = [
        { name: 'value', value: 'unknown', type: 'any' },
        { name: 'data', value: 'unknown', type: 'unknown' },
      ];
      service.captureVariables(session.id, 'bp-1', variables);
      service.captureStackFrames(session.id, [{ id: 1, name: 'main', file: '/src/app.ts', line: 42 }]);

      const analysis = service.analyzeRootCause(session.id);
      expect(analysis?.likely.some((c) => c.includes('Type'))).toBe(true);
    });

    it('should detect stack overflow potential', () => {
      const session = service.startSession('user1', 'ws-123', 'sess-123', 'node');
      const bp: Breakpoint = { id: 'bp-1', file: '/src/app.ts', line: 42, verified: true };
      service.setBreakpoint(session.id, bp);

      service.captureVariables(session.id, 'bp-1', [{ name: 'x', value: '1', type: 'number' }]);

      // Create deep stack frames
      const frames: StackFrame[] = [];
      for (let i = 0; i < 60; i++) {
        frames.push({
          id: i,
          name: `recursiveFunc`,
          file: '/src/app.ts',
          line: 42,
        });
      }
      service.captureStackFrames(session.id, frames);

      const analysis = service.analyzeRootCause(session.id);
      expect(analysis?.likely.some((c) => c.includes('Stack overflow'))).toBe(true);
    });

    it('should detect repeated breakpoints', () => {
      const session = service.startSession('user1', 'ws-123', 'sess-123', 'node');
      const bp: Breakpoint = { id: 'bp-1', file: '/src/app.ts', line: 42, verified: true };
      service.setBreakpoint(session.id, bp);

      // Capture multiple times at same breakpoint
      for (let i = 0; i < 6; i++) {
        service.captureVariables(session.id, 'bp-1', [{ name: 'x', value: String(i), type: 'number' }]);
      }
      service.captureStackFrames(session.id, [{ id: 1, name: 'main', file: '/src/app.ts', line: 42 }]);

      const analysis = service.analyzeRootCause(session.id);
      expect(analysis?.likely.some((c) => c.includes('Infinite'))).toBe(true);
    });

    it('should store analysis in session', () => {
      const session = service.startSession('user1', 'ws-123', 'sess-123', 'node');
      const bp: Breakpoint = { id: 'bp-1', file: '/src/app.ts', line: 42, verified: true };
      service.setBreakpoint(session.id, bp);

      service.captureVariables(session.id, 'bp-1', [{ name: 'x', value: 'null', type: 'null' }]);
      service.captureStackFrames(session.id, [{ id: 1, name: 'main', file: '/src/app.ts', line: 42 }]);
      service.analyzeRootCause(session.id);

      const retrieved = service.getSession(session.id);
      expect(retrieved?.rootCauseAnalysis).toBeDefined();
      expect(retrieved?.lastAnalyzedAt).toBeDefined();
    });
  });

  describe('Fix Suggestions', () => {
    it('should generate fix suggestions', () => {
      const session = service.startSession('user1', 'ws-123', 'sess-123', 'node');
      const bp: Breakpoint = { id: 'bp-1', file: '/src/app.ts', line: 42, verified: true };
      service.setBreakpoint(session.id, bp);

      service.captureVariables(session.id, 'bp-1', [{ name: 'x', value: 'null', type: 'null' }]);
      service.captureStackFrames(session.id, [{ id: 1, name: 'main', file: '/src/app.ts', line: 42 }]);

      const suggestions = service.generateFixSuggestions(session.id);
      expect(suggestions.length).toBeGreaterThan(0);
      expect(suggestions[0].approach).toBeDefined();
      expect(suggestions[0].severity).toBeDefined();
    });

    it('should suggest null checks', () => {
      const session = service.startSession('user1', 'ws-123', 'sess-123', 'node');
      const bp: Breakpoint = { id: 'bp-1', file: '/src/app.ts', line: 42, verified: true };
      service.setBreakpoint(session.id, bp);

      service.captureVariables(session.id, 'bp-1', [
        { name: 'user', value: 'null', type: 'object' },
        { name: 'email', value: 'null', type: 'string' },
      ]);
      service.captureStackFrames(session.id, [{ id: 1, name: 'main', file: '/src/app.ts', line: 42 }]);

      const suggestions = service.generateFixSuggestions(session.id);
      expect(suggestions.some((s) => s.approach.includes('null'))).toBe(true);
    });

    it('should suggest type validation', () => {
      const session = service.startSession('user1', 'ws-123', 'sess-123', 'node');
      const bp: Breakpoint = { id: 'bp-1', file: '/src/app.ts', line: 42, verified: true };
      service.setBreakpoint(session.id, bp);

      service.captureVariables(session.id, 'bp-1', [{ name: 'value', value: 'unknown', type: 'any' }]);
      service.captureStackFrames(session.id, [{ id: 1, name: 'main', file: '/src/app.ts', line: 42 }]);

      const suggestions = service.generateFixSuggestions(session.id);
      expect(suggestions.some((s) => s.approach.includes('type'))).toBe(true);
    });

    it('should store suggestions in session', () => {
      const session = service.startSession('user1', 'ws-123', 'sess-123', 'node');
      const bp: Breakpoint = { id: 'bp-1', file: '/src/app.ts', line: 42, verified: true };
      service.setBreakpoint(session.id, bp);

      service.captureVariables(session.id, 'bp-1', [{ name: 'x', value: 'null', type: 'null' }]);
      service.captureStackFrames(session.id, [{ id: 1, name: 'main', file: '/src/app.ts', line: 42 }]);
      service.generateFixSuggestions(session.id);

      const retrieved = service.getSession(session.id);
      expect(retrieved?.fixSuggestions.length).toBeGreaterThan(0);
    });
  });

  describe('Documentation Suggestions', () => {
    it('should get relevant documentation', () => {
      const session = service.startSession('user1', 'ws-123', 'sess-123', 'node');
      const bp: Breakpoint = { id: 'bp-1', file: '/src/app.ts', line: 42, verified: true };
      service.setBreakpoint(session.id, bp);

      service.captureVariables(session.id, 'bp-1', [{ name: 'x', value: 'null', type: 'null' }]);
      service.captureStackFrames(session.id, [{ id: 1, name: 'main', file: '/src/app.ts', line: 42 }]);
      service.generateFixSuggestions(session.id);

      const docs = service.getRelevantDocs(session.id);
      expect(docs.length).toBeGreaterThan(0);
      expect(docs[0]).toContain('https://');
    });

    it('should include docs from fix suggestions', () => {
      const session = service.startSession('user1', 'ws-123', 'sess-123', 'node');
      const bp: Breakpoint = { id: 'bp-1', file: '/src/app.ts', line: 42, verified: true };
      service.setBreakpoint(session.id, bp);

      service.captureVariables(session.id, 'bp-1', [{ name: 'x', value: 'null', type: 'null' }]);
      service.captureStackFrames(session.id, [{ id: 1, name: 'main', file: '/src/app.ts', line: 42 }]);
      service.generateFixSuggestions(session.id);

      const docs = service.getRelevantDocs(session.id);
      expect(docs.some((d) => d.includes('nullish'))).toBe(true);
    });
  });

  describe('Event Emission', () => {
    it('should emit sessionStarted event', async () => {
      return new Promise<void>((resolve) => {
        service.on('sessionStarted', (session) => {
          expect(session.id).toBeDefined();
          resolve();
        });

        service.startSession('user1', 'ws-123', 'sess-123', 'node');
      });
    });

    it('should emit breakpointSet event', async () => {
      const session = service.startSession('user1', 'ws-123', 'sess-123', 'node');

      return new Promise<void>((resolve) => {
        service.on('breakpointSet', (sess, bp) => {
          expect(bp.id).toBe('bp-1');
          resolve();
        });

        const breakpoint: Breakpoint = { id: 'bp-1', file: '/src/app.ts', line: 42, verified: true };
        service.setBreakpoint(session.id, breakpoint);
      });
    });

    it('should emit variablesCaptured event', async () => {
      const session = service.startSession('user1', 'ws-123', 'sess-123', 'node');
      const bp: Breakpoint = { id: 'bp-1', file: '/src/app.ts', line: 42, verified: true };
      service.setBreakpoint(session.id, bp);

      return new Promise<void>((resolve) => {
        service.on('variablesCaptured', (sess, vars) => {
          expect(vars).toHaveLength(1);
          resolve();
        });

        const variables: VariableValue[] = [{ name: 'x', value: '10', type: 'number' }];
        service.captureVariables(session.id, 'bp-1', variables);
      });
    });
  });

  describe('Statistics', () => {
    it('should return session statistics', () => {
      service.startSession('user1', 'ws-123', 'sess-1', 'node');
      service.startSession('user1', 'ws-123', 'sess-2', 'python');

      const stats = service.getStatistics();
      expect(stats.totalSessions).toBe(2);
      expect(stats.activeSessions).toBe(2);
    });

    it('should calculate average session duration', () => {
      const session1 = service.startSession('user1', 'ws-123', 'sess-1', 'node');
      service.stopSession(session1.id);

      const stats = service.getStatistics();
      expect(stats.averageSessionDuration).toBeGreaterThanOrEqual(0);
    });

    it('should identify most common language', () => {
      service.startSession('user1', 'ws-123', 'sess-1', 'node');
      service.startSession('user1', 'ws-123', 'sess-2', 'node');
      service.startSession('user1', 'ws-123', 'sess-3', 'python');

      const stats = service.getStatistics();
      expect(stats.mostCommonLanguage).toBe('node');
    });
  });

  describe('Edge Cases', () => {
    it('should handle non-existent session', () => {
      const result = service.getSession('non-existent');
      expect(result).toBeUndefined();
    });

    it('should handle empty variables list', () => {
      const session = service.startSession('user1', 'ws-123', 'sess-123', 'node');
      const bp: Breakpoint = { id: 'bp-1', file: '/src/app.ts', line: 42, verified: true };
      service.setBreakpoint(session.id, bp);

      const updated = service.captureVariables(session.id, 'bp-1', []);
      expect(updated?.variables).toHaveLength(0);
    });

    it('should handle empty stack frames', () => {
      const session = service.startSession('user1', 'ws-123', 'sess-123', 'node');
      const updated = service.captureStackFrames(session.id, []);
      expect(updated?.stackFrames).toHaveLength(0);
    });
  });
});
