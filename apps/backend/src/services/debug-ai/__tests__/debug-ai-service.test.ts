/**
 * @file        apps/backend/src/services/debug-ai/__tests__/debug-ai-service.test.ts
 * @module      ai/debug-session
 * @description Debug session AI service comprehensive tests
 */

import { describe, it, expect, beforeEach } from 'vitest';
import {
  DebugAIService,
  getDebugAIService,
} from '../debug-ai-service.js';
import { StackFrame, DebugVariable } from '../types.js';

describe('Debug AI Service', () => {
  let debugService: DebugAIService;

  beforeEach(async () => {
    debugService = new DebugAIService();
    await debugService.initialize();
  });

  describe('Service Initialization', () => {
    it('should initialize successfully', async () => {
      expect(debugService).toBeDefined();
    });

    it('should emit initialized event', async () => {
      return new Promise<void>((resolve) => {
        const service = new DebugAIService();
        service.once('initialized', () => {
          resolve();
        });
        service.initialize();
      });
    });
  });

  describe('Session Management', () => {
    it('should start debug session', async () => {
      await debugService.startSession(
        'session-001',
        'ws-test',
        'typescript',
        'node'
      );

      const session = await debugService.getSession('session-001');
      expect(session).toBeDefined();
      expect(session?.language).toBe('typescript');
      expect(session?.runtime).toBe('node');
      expect(session?.isPaused).toBe(false);
    });

    it('should emit session-started event', async () => {
      return new Promise<void>((resolve) => {
        debugService.once('session-started', ({ sessionId, language }) => {
          expect(sessionId).toBe('session-001');
          expect(language).toBe('python');
          resolve();
        });

        debugService.startSession('session-001', 'ws-test', 'python');
      });
    });

    it('should end session', async () => {
      await debugService.startSession('session-001', 'ws-test', 'typescript');

      return new Promise<void>((resolve) => {
        debugService.once('session-ended', ({ sessionId }) => {
          expect(sessionId).toBe('session-001');
          resolve();
        });

        debugService.endSession('session-001');
      });
    });
  });

  describe('Pause and Resume', () => {
    let sessionId: string;

    beforeEach(async () => {
      sessionId = 'session-001';
      await debugService.startSession(sessionId, 'ws-test', 'typescript');
    });

    it('should update state on pause', async () => {
      const stack: StackFrame[] = [
        {
          id: 1,
          name: 'myFunction',
          source: { name: 'app.ts', path: '/src/app.ts' },
          line: 42,
          column: 10,
        },
      ];

      const variables: DebugVariable[] = [
        {
          name: 'x',
          value: '10',
          type: 'number',
          scope: 'local',
        },
      ];

      await debugService.updateOnPause(
        sessionId,
        'breakpoint',
        stack,
        variables
      );

      const session = await debugService.getSession(sessionId);
      expect(session?.isPaused).toBe(true);
      expect(session?.pauseReason).toBe('breakpoint');
      expect(session?.stackTrace.length).toBe(1);
      expect(session?.variables.length).toBe(1);
    });

    it('should emit session-paused event', async () => {
      const stack: StackFrame[] = [
        {
          id: 1,
          name: 'test',
          source: { name: 'test.ts', path: '/test.ts' },
          line: 10,
        },
      ];

      return new Promise<void>((resolve) => {
        debugService.once('session-paused', ({ reason }) => {
          expect(reason).toBe('exception');
          resolve();
        });

        debugService.updateOnPause(sessionId, 'exception', stack, []);
      });
    });

    it('should update state on resume', async () => {
      const stack: StackFrame[] = [
        {
          id: 1,
          name: 'test',
          source: { name: 'test.ts', path: '/test.ts' },
          line: 10,
        },
      ];

      await debugService.updateOnPause(sessionId, 'step', stack, []);
      await debugService.updateOnResume(sessionId);

      const session = await debugService.getSession(sessionId);
      expect(session?.isPaused).toBe(false);
    });
  });

  describe('Output Tracking', () => {
    let sessionId: string;

    beforeEach(async () => {
      sessionId = 'session-001';
      await debugService.startSession(sessionId, 'ws-test', 'javascript');
    });

    it('should add stdout output', async () => {
      await debugService.addOutput(sessionId, 'stdout', 'Hello World');

      const session = await debugService.getSession(sessionId);
      expect(session?.output.length).toBe(1);
      expect(session?.output[0].category).toBe('stdout');
      expect(session?.output[0].output).toBe('Hello World');
    });

    it('should add stderr output', async () => {
      await debugService.addOutput(
        sessionId,
        'stderr',
        'Error: undefined variable'
      );

      const session = await debugService.getSession(sessionId);
      expect(session?.output.length).toBe(1);
      expect(session?.output[0].category).toBe('stderr');
    });

    it('should track multiple outputs', async () => {
      await debugService.addOutput(sessionId, 'stdout', 'Line 1');
      await debugService.addOutput(sessionId, 'stdout', 'Line 2');
      await debugService.addOutput(sessionId, 'stderr', 'Error');

      const session = await debugService.getSession(sessionId);
      expect(session?.output.length).toBe(3);
    });
  });

  describe('AI Analysis', () => {
    let sessionId: string;

    beforeEach(async () => {
      sessionId = 'session-001';
      await debugService.startSession(sessionId, 'ws-test', 'typescript');

      // Set up a paused state with variables
      const stack: StackFrame[] = [
        {
          id: 1,
          name: 'myFunction',
          source: { name: 'app.ts', path: '/src/app.ts' },
          line: 42,
        },
      ];

      const variables: DebugVariable[] = [
        {
          name: 'result',
          value: 'undefined',
          type: 'any',
          scope: 'local',
        },
        {
          name: 'data',
          value: 'null',
          type: 'object',
          scope: 'local',
        },
      ];

      await debugService.updateOnPause(sessionId, 'breakpoint', stack, variables);
      await debugService.addOutput(sessionId, 'stderr', 'Error: Cannot read property of undefined');
    });

    it('should analyze debug state', async () => {
      const analysisId = await debugService.analyzeDebugState(sessionId);

      expect(analysisId).toMatch(/^analysis-/);

      const analysis = await debugService.getAnalysis(analysisId);
      expect(analysis).toBeDefined();
      expect(analysis?.suspectedCause.description).toBeDefined();
      expect(analysis?.suspectedCause.confidence).toBeGreaterThan(0);
    });

    it('should emit analysis-complete event', async () => {
      return new Promise<void>((resolve) => {
        debugService.once('analysis-complete', ({ sessionId: sid, analysisId }) => {
          expect(sid).toBe(sessionId);
          expect(analysisId).toMatch(/^analysis-/);
          resolve();
        });

        debugService.analyzeDebugState(sessionId);
      });
    });

    it('should identify suspicious variables', async () => {
      const analysisId = await debugService.analyzeDebugState(sessionId);

      const analysis = await debugService.getAnalysis(analysisId);
      expect(analysis?.variableAnalysis.suspiciousVariables.length).toBeGreaterThan(0);
      expect(
        analysis?.variableAnalysis.suspiciousVariables.some(
          (v) => v.name === 'result'
        )
      ).toBe(true);
    });

    it('should suggest fixes', async () => {
      const analysisId = await debugService.analyzeDebugState(sessionId);

      const analysis = await debugService.getAnalysis(analysisId);
      expect(analysis?.suggestedFixes.length).toBeGreaterThan(0);
      expect(analysis?.suggestedFixes[0].title).toBeDefined();
      expect(analysis?.suggestedFixes[0].difficulty).toMatch(
        /easy|medium|hard/
      );
    });

    it('should provide relevant documentation', async () => {
      const analysisId = await debugService.analyzeDebugState(sessionId);

      const analysis = await debugService.getAnalysis(analysisId);
      expect(analysis?.relevantDocs).toBeDefined();
    });

    it('should suggest next debug steps', async () => {
      const analysisId = await debugService.analyzeDebugState(sessionId);

      const analysis = await debugService.getAnalysis(analysisId);
      expect(analysis?.suggestedNextSteps).toBeDefined();
      expect(analysis?.suggestedNextSteps.length).toBeGreaterThan(0);
    });

    it('should analyze with relevant code', async () => {
      const analysisId = await debugService.analyzeDebugState(sessionId, {
        filePath: 'src/app.ts',
        content: 'const x = obj.prop; // Error here',
        startLine: 42,
      });

      const analysis = await debugService.getAnalysis(analysisId);
      expect(analysis?.timestamp).toBeDefined();
    });
  });

  describe('Session History', () => {
    let sessionId: string;

    beforeEach(async () => {
      sessionId = 'session-001';
      await debugService.startSession(sessionId, 'ws-test', 'typescript');
    });

    it('should track session history', async () => {
      const stack: StackFrame[] = [
        {
          id: 1,
          name: 'func1',
          source: { name: 'app.ts', path: '/app.ts' },
          line: 10,
        },
      ];

      // First pause
      await debugService.updateOnPause(sessionId, 'breakpoint', stack, []);
      await debugService.updateOnResume(sessionId);

      // Second pause
      await debugService.updateOnPause(sessionId, 'step', stack, []);

      const history = await debugService.getSessionHistory(sessionId);
      expect(history.length).toBeGreaterThanOrEqual(1);
    });
  });

  describe('Feedback', () => {
    let sessionId: string;
    let analysisId: string;

    beforeEach(async () => {
      sessionId = 'session-001';
      await debugService.startSession(sessionId, 'ws-test', 'typescript');

      const stack: StackFrame[] = [
        {
          id: 1,
          name: 'test',
          source: { name: 'test.ts', path: '/test.ts' },
          line: 10,
        },
      ];

      const variables: DebugVariable[] = [
        { name: 'x', value: 'undefined', type: 'any', scope: 'local' },
      ];

      await debugService.updateOnPause(sessionId, 'breakpoint', stack, variables);
      analysisId = await debugService.analyzeDebugState(sessionId);
    });

    it('should submit feedback', async () => {
      return new Promise<void>((resolve) => {
        debugService.once('feedback-received', (feedback) => {
          expect(feedback.helpfulness).toBe(5);
          expect(feedback.accuracy).toBe(4);
          expect(feedback.correctDiagnosis).toBe(true);
          resolve();
        });

        debugService.submitFeedback(
          analysisId,
          sessionId,
          'user-123',
          5,
          4,
          true,
          'Very helpful'
        );
      });
    });

    it('should mark need for further help if accuracy low', async () => {
      return new Promise<void>((resolve) => {
        debugService.once('feedback-received', (feedback) => {
          expect(feedback.needsFurtherHelp).toBe(true);
          resolve();
        });

        debugService.submitFeedback(
          analysisId,
          sessionId,
          'user-123',
          2,
          2,
          false
        );
      });
    });
  });

  describe('Suggestions', () => {
    let sessionId: string;

    beforeEach(async () => {
      sessionId = 'session-001';
      await debugService.startSession(sessionId, 'ws-test', 'typescript');
    });

    it('should provide suggestions when paused', async () => {
      const stack: StackFrame[] = [
        {
          id: 1,
          name: 'test',
          source: { name: 'test.ts', path: '/test.ts' },
          line: 10,
        },
      ];

      await debugService.updateOnPause(sessionId, 'breakpoint', stack, []);

      const suggestions = await debugService.getSuggestions(sessionId);
      expect(suggestions.length).toBeGreaterThan(0);
    });

    it('should return empty when not paused', async () => {
      const suggestions = await debugService.getSuggestions(sessionId);
      expect(suggestions.length).toBe(0);
    });

    it('should suggest different actions by pause reason', async () => {
      const stack: StackFrame[] = [
        {
          id: 1,
          name: 'test',
          source: { name: 'test.ts', path: '/test.ts' },
          line: 10,
        },
      ];

      // Get exception suggestions
      await debugService.updateOnPause(sessionId, 'exception', stack, []);
      const exceptionSuggestions = await debugService.getSuggestions(sessionId);

      expect(exceptionSuggestions.some((s) => s.includes('error'))).toBe(true);
    });
  });

  describe('Statistics', () => {
    beforeEach(async () => {
      // Create multiple sessions
      for (let i = 0; i < 3; i++) {
        const lang = ['typescript', 'python', 'javascript'][i];
        await debugService.startSession(
          `session-${i}`,
          'ws-stats',
          lang
        );

        const stack: StackFrame[] = [
          {
            id: 1,
            name: 'test',
            source: { name: 'test.ts', path: '/test.ts' },
            line: 10 + i,
          },
        ];

        const reason = ['breakpoint', 'exception', 'step'][i] as any;
        await debugService.updateOnPause(`session-${i}`, reason, stack, []);
      }
    });

    it('should calculate statistics', async () => {
      const stats = await debugService.getStatistics('ws-stats');

      expect(stats.totalSessions).toBe(3);
      expect(stats.activeSessions).toBe(3);
      expect(stats.analysisRuns).toBe(0); // No analyses created yet
    });

    it('should count by language', async () => {
      const stats = await debugService.getStatistics('ws-stats');

      expect(stats.byLanguage['typescript']).toBe(1);
      expect(stats.byLanguage['python']).toBe(1);
      expect(stats.byLanguage['javascript']).toBe(1);
    });

    it('should count by pause reason', async () => {
      const stats = await debugService.getStatistics('ws-stats');

      expect(stats.byPauseReason['breakpoint']).toBeGreaterThanOrEqual(1);
      expect(stats.byPauseReason['exception']).toBeGreaterThanOrEqual(1);
      expect(stats.byPauseReason['step']).toBeGreaterThanOrEqual(1);
    });

    it('should calculate average session duration', async () => {
      const stats = await debugService.getStatistics('ws-stats');

      expect(stats.averageSessionDuration).toBeGreaterThanOrEqual(0);
    });
  });

  describe('Event Emission', () => {
    it('should emit session-started event', async () => {
      return new Promise<void>((resolve) => {
        debugService.once('session-started', (data) => {
          expect(data.sessionId).toBe('session-001');
          resolve();
        });

        debugService.startSession('session-001', 'ws-test', 'typescript');
      });
    });

    it('should emit session-resumed event', async () => {
      const sessionId = 'session-001';
      await debugService.startSession(sessionId, 'ws-test', 'typescript');

      const stack: StackFrame[] = [
        {
          id: 1,
          name: 'test',
          source: { name: 'test.ts', path: '/test.ts' },
          line: 10,
        },
      ];

      await debugService.updateOnPause(sessionId, 'step', stack, []);

      return new Promise<void>((resolve) => {
        debugService.once('session-resumed', ({ sessionId: sid }) => {
          expect(sid).toBe(sessionId);
          resolve();
        });

        debugService.updateOnResume(sessionId);
      });
    });
  });

  describe('Global Singleton', () => {
    it('should return same instance', async () => {
      const service1 = await getDebugAIService();
      const service2 = await getDebugAIService();

      expect(service1).toBe(service2);
    });
  });

  describe('Integration', () => {
    it('should handle complete debug session workflow', async () => {
      const sessionId = 'session-integration';

      // 1. Start session
      await debugService.startSession(sessionId, 'ws-integration', 'typescript', 'node');

      // 2. Hit breakpoint
      const stack: StackFrame[] = [
        {
          id: 1,
          name: 'processData',
          source: { name: 'process.ts', path: '/src/process.ts' },
          line: 42,
          column: 10,
        },
        {
          id: 2,
          name: 'main',
          source: { name: 'main.ts', path: '/src/main.ts' },
          line: 10,
          column: 5,
        },
      ];

      const variables: DebugVariable[] = [
        { name: 'input', value: '{ id: 1 }', type: 'object', scope: 'argument' },
        { name: 'result', value: 'undefined', type: 'any', scope: 'local' },
      ];

      await debugService.updateOnPause(sessionId, 'breakpoint', stack, variables);

      // 3. Add output with error
      await debugService.addOutput(
        sessionId,
        'stderr',
        'Error: Cannot read property of undefined'
      );

      // 4. Analyze
      const analysisId = await debugService.analyzeDebugState(sessionId);
      const analysis = await debugService.getAnalysis(analysisId);

      expect(analysis?.suspectedCause.description).toBeDefined();
      expect(analysis?.suggestedFixes.length).toBeGreaterThan(0);

      // 5. Get suggestions
      const suggestions = await debugService.getSuggestions(sessionId);
      expect(suggestions.length).toBeGreaterThan(0);

      // 6. Resume
      await debugService.updateOnResume(sessionId);

      // 7. Verify state
      const session = await debugService.getSession(sessionId);
      expect(session?.isPaused).toBe(false);

      // 8. End session
      await debugService.endSession(sessionId);

      // 9. Get statistics
      const stats = await debugService.getStatistics('ws-integration');
      expect(stats.totalSessions).toBe(1);
      expect(stats.analysisRuns).toBe(1);
    });
  });
});
