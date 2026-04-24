#!/usr/bin/env node
/**
 * @file        apps/backend/src/services/collab-debug/collab-debug-service.ts
 * @module      services/collaboration/collab-debug
 * @description Collaborative debugging service with DAP proxy relay
 */

import { EventEmitter } from 'events';
import {
  DebugSession,
  DebugBreakpoint,
  BreakpointLocation,
  ThreadState,
  SetBreakpointRequest,
  SetBreakpointResult,
  ClearBreakpointRequest,
  ClearBreakpointResult,
  ContinueThreadRequest,
  ContinueThreadResult,
  StepThreadRequest,
  StepThreadResult,
  GetVariablesRequest,
  GetVariablesResult,
  SetVariableRequest,
  SetVariableResult,
  EvalExpressionRequest,
  EvalExpressionResult,
  CollaborativeDebugServiceConfig,
  DebugEvent,
  CollaborativeDebugAuditEntry,
  CollaborativeDebugStatistics,
} from './types.js';

/**
 * Collaborative debugging service
 */
export class CollaborativeDebugService extends EventEmitter {
  private static instance: CollaborativeDebugService;

  private config: Required<CollaborativeDebugServiceConfig>;
  private sessions: Map<string, DebugSession>;
  private auditLog: Map<string, CollaborativeDebugAuditEntry[]>;
  private statistics: CollaborativeDebugStatistics;
  private sessionDurations: Map<string, number>; // sessionId -> startTime

  /**
   * Get singleton instance
   */
  static getInstance(config?: Partial<CollaborativeDebugServiceConfig>): CollaborativeDebugService {
    if (!this.instance) {
      this.instance = new CollaborativeDebugService(config);
    }
    return this.instance;
  }

  /**
   * Reset singleton for testing
   */
  static reset(): void {
    this.instance = (undefined as any);
  }

  /**
   * Constructor
   */
  private constructor(config?: Partial<CollaborativeDebugServiceConfig>) {
    super();

    this.config = {
      maxSessions: config?.maxSessions ?? 50,
      maxParticipantsPerSession: config?.maxParticipantsPerSession ?? 10,
      maxBreakpoints: config?.maxBreakpoints ?? 100,
      enableLogpoints: config?.enableLogpoints ?? true,
      enableConditionalBreakpoints: config?.enableConditionalBreakpoints ?? true,
      maxWatchExpressions: config?.maxWatchExpressions ?? 50,
      dapProxyHost: config?.dapProxyHost ?? 'localhost',
      dapProxyPort: config?.dapProxyPort ?? 5005,
      sessionTimeout: config?.sessionTimeout ?? 1800000,
      maxAuditLogSize: config?.maxAuditLogSize ?? 10000,
    };

    this.sessions = new Map();
    this.auditLog = new Map();
    this.sessionDurations = new Map();
    this.statistics = {
      totalSessions: 0,
      activeSessions: 0,
      totalBreakpoints: 0,
      totalSteps: 0,
      totalEvaluations: 0,
      avgParticipantsPerSession: 0,
      avgSessionDuration: 0,
      lastSessionAt: 0,
    };

    this.emit('initialized', { timestamp: Date.now() });
  }

  /**
   * Create debug session
   */
  createDebugSession(
    initiatorUserId: string,
    initiatorUserEmail: string,
    debugSessionId: string,
    isShared: boolean,
    maxParticipants?: number,
    ipAddress: string = 'unknown',
    userAgent: string = 'unknown'
  ): DebugSession {
    if (this.sessions.size >= this.config.maxSessions) {
      throw new Error('Maximum concurrent debug sessions reached');
    }

    const session: DebugSession = {
      id: `dbg-${Date.now()}-${Math.random().toString(16).slice(2)}`,
      debugSessionId,
      initiatorUserId,
      initiatorUserEmail,
      participantUserIds: [],
      createdAt: Date.now(),
      status: 'active',
      breakpoints: new Map(),
      threads: new Map(),
      watchExpressions: [],
      isShared,
      maxParticipants,
    };

    this.sessions.set(session.id, session);
    this.sessionDurations.set(session.id, Date.now());
    this.statistics.totalSessions++;
    this.statistics.activeSessions++;
    this.statistics.lastSessionAt = Date.now();

    this.recordAudit({
      userId: initiatorUserId,
      userEmail: initiatorUserEmail,
      operation: 'debug-session-created',
      status: 'success',
      sessionId: session.id,
      details: { debugSessionId, isShared, maxParticipants },
      ipAddress,
      userAgent,
      timestamp: Date.now(),
    });

    this.emit('debug-session-created', { session, timestamp: Date.now() });

    return session;
  }

  /**
   * Get debug session
   */
  getDebugSession(sessionId: string): DebugSession | null {
    return this.sessions.get(sessionId) ?? null;
  }

  /**
   * Join debug session
   */
  joinDebugSession(sessionId: string, userId: string, userEmail: string, ipAddress: string, userAgent: string): boolean {
    const session = this.sessions.get(sessionId);
    if (!session) {
      return false;
    }

    if (!session.isShared) {
      return false;
    }

    if (session.maxParticipants && session.participantUserIds.length >= session.maxParticipants) {
      return false;
    }

    if (!session.participantUserIds.includes(userId)) {
      session.participantUserIds.push(userId);
    }

    this.recordAudit({
      userId,
      userEmail,
      operation: 'participant-joined',
      status: 'success',
      sessionId,
      ipAddress,
      userAgent,
      timestamp: Date.now(),
    });

    this.emit('participant-joined', { sessionId, userId, timestamp: Date.now() });

    return true;
  }

  /**
   * Leave debug session
   */
  leaveDebugSession(sessionId: string, userId: string, userEmail: string, ipAddress: string, userAgent: string): boolean {
    const session = this.sessions.get(sessionId);
    if (!session) {
      return false;
    }

    session.participantUserIds = session.participantUserIds.filter((id) => id !== userId);

    this.recordAudit({
      userId,
      userEmail,
      operation: 'participant-left',
      status: 'success',
      sessionId,
      ipAddress,
      userAgent,
      timestamp: Date.now(),
    });

    this.emit('participant-left', { sessionId, userId, timestamp: Date.now() });

    return true;
  }

  /**
   * Set breakpoint
   */
  setBreakpoint(request: SetBreakpointRequest, sessionId: string, ipAddress: string, userAgent: string): SetBreakpointResult {
    const session = this.sessions.get(sessionId);
    if (!session) {
      return { success: false, breakpointId: '', verified: false, message: 'Session not found' };
    }

    if (session.breakpoints.size >= this.config.maxBreakpoints) {
      return { success: false, breakpointId: '', verified: false, message: 'Maximum breakpoints reached' };
    }

    if (request.condition && !this.config.enableConditionalBreakpoints) {
      return { success: false, breakpointId: '', verified: false, message: 'Conditional breakpoints disabled' };
    }

    const breakpointId = `bp-${Date.now()}-${Math.random().toString(16).slice(2)}`;
    const breakpoint: DebugBreakpoint = {
      id: breakpointId,
      location: request.location,
      condition: request.condition,
      logMessage: request.logMessage,
      enabled: true,
      setByUserId: request.userId,
      setByUserEmail: request.userEmail,
      createdAt: Date.now(),
    };

    session.breakpoints.set(breakpointId, breakpoint);
    this.statistics.totalBreakpoints++;

    this.recordAudit({
      userId: request.userId,
      userEmail: request.userEmail,
      operation: 'breakpoint-set',
      status: 'success',
      sessionId,
      breakpointId,
      details: request,
      ipAddress,
      userAgent,
      timestamp: Date.now(),
    });

    this.emit('breakpoint-set', { breakpoint, sessionId, timestamp: Date.now() });

    return { success: true, breakpointId, verified: true };
  }

  /**
   * Clear breakpoint
   */
  clearBreakpoint(request: ClearBreakpointRequest, sessionId: string, ipAddress: string, userAgent: string): ClearBreakpointResult {
    const session = this.sessions.get(sessionId);
    if (!session) {
      return { success: false, breakpointId: request.breakpointId, message: 'Session not found' };
    }

    const removed = session.breakpoints.delete(request.breakpointId);
    if (!removed) {
      return { success: false, breakpointId: request.breakpointId, message: 'Breakpoint not found' };
    }

    this.recordAudit({
      userId: request.userId,
      userEmail: request.userEmail,
      operation: 'breakpoint-cleared',
      status: 'success',
      sessionId,
      breakpointId: request.breakpointId,
      ipAddress,
      userAgent,
      timestamp: Date.now(),
    });

    this.emit('breakpoint-cleared', { breakpointId: request.breakpointId, sessionId, timestamp: Date.now() });

    return { success: true, breakpointId: request.breakpointId };
  }

  /**
   * Continue thread
   */
  continueThread(request: ContinueThreadRequest, sessionId: string, ipAddress: string, userAgent: string): ContinueThreadResult {
    const session = this.sessions.get(sessionId);
    if (!session) {
      return { success: false, threadId: request.threadId, allThreadsContinued: false };
    }

    const thread = session.threads.get(request.threadId);
    if (thread) {
      thread.state = 'running';
    }

    this.statistics.totalSteps++;

    this.recordAudit({
      userId: request.userId,
      userEmail: request.userEmail,
      operation: 'thread-continued',
      status: 'success',
      sessionId,
      threadId: request.threadId,
      ipAddress,
      userAgent,
      timestamp: Date.now(),
    });

    this.emit('thread-continued', { threadId: request.threadId, sessionId, timestamp: Date.now() });

    return { success: true, threadId: request.threadId, allThreadsContinued: true };
  }

  /**
   * Step thread
   */
  stepThread(request: StepThreadRequest, sessionId: string, ipAddress: string, userAgent: string): StepThreadResult {
    const session = this.sessions.get(sessionId);
    if (!session) {
      return { success: false, threadId: request.threadId, allThreadsStopped: false };
    }

    const thread = session.threads.get(request.threadId);
    if (thread) {
      // Simulate step execution
      thread.state = 'running';
      setTimeout(() => {
        if (thread) {
          thread.state = 'stopped';
          thread.stoppedReason = 'step';
          thread.stoppedAt = Date.now();
        }
      }, 50 + Math.random() * 50);
    }

    this.statistics.totalSteps++;

    this.recordAudit({
      userId: request.userId,
      userEmail: request.userEmail,
      operation: 'thread-stepped',
      status: 'success',
      sessionId,
      threadId: request.threadId,
      details: { stepType: request.stepType },
      ipAddress,
      userAgent,
      timestamp: Date.now(),
    });

    this.emit('thread-stepped', { threadId: request.threadId, stepType: request.stepType, sessionId, timestamp: Date.now() });

    return { success: true, threadId: request.threadId, allThreadsStopped: true };
  }

  /**
   * Get variables
   */
  getVariables(request: GetVariablesRequest, sessionId: string, ipAddress: string, userAgent: string): GetVariablesResult {
    const session = this.sessions.get(sessionId);
    if (!session) {
      return { success: false, variables: [], message: 'Session not found' };
    }

    const thread = session.threads.get(request.threadId);
    if (!thread) {
      return { success: false, variables: [], message: 'Thread not found' };
    }

    const variables = Array.from(thread.variables.values());

    this.recordAudit({
      userId: request.userId,
      userEmail: request.userEmail,
      operation: 'variable-inspected',
      status: 'success',
      sessionId,
      threadId: request.threadId,
      details: { count: variables.length },
      ipAddress,
      userAgent,
      timestamp: Date.now(),
    });

    this.emit('variables-fetched', { threadId: request.threadId, sessionId, timestamp: Date.now() });

    return { success: true, variables };
  }

  /**
   * Set variable
   */
  setVariable(request: SetVariableRequest, sessionId: string, ipAddress: string, userAgent: string): SetVariableResult {
    const session = this.sessions.get(sessionId);
    if (!session) {
      return { success: false, variableName: request.variableName, newValue: undefined, message: 'Session not found' };
    }

    const thread = session.threads.get(request.threadId);
    if (!thread) {
      return { success: false, variableName: request.variableName, newValue: undefined, message: 'Thread not found' };
    }

    const variable = thread.variables.get(request.variableName);
    if (!variable) {
      return {
        success: false,
        variableName: request.variableName,
        newValue: undefined,
        message: 'Variable not found',
      };
    }

    variable.value = request.newValue;

    this.recordAudit({
      userId: request.userId,
      userEmail: request.userEmail,
      operation: 'thread-stepped',
      status: 'success',
      sessionId,
      threadId: request.threadId,
      details: { variableName: request.variableName, newValue: request.newValue },
      ipAddress,
      userAgent,
      timestamp: Date.now(),
    });

    this.emit('variable-set', {
      threadId: request.threadId,
      variableName: request.variableName,
      newValue: request.newValue,
      sessionId,
      timestamp: Date.now(),
    });

    return { success: true, variableName: request.variableName, newValue: request.newValue };
  }

  /**
   * Eval expression
   */
  evalExpression(request: EvalExpressionRequest, sessionId: string, ipAddress: string, userAgent: string): EvalExpressionResult {
    const session = this.sessions.get(sessionId);
    if (!session) {
      return { success: false, result: undefined, type: 'error', message: 'Session not found' };
    }

    // Simulate simple expression evaluation
    let result: unknown = null;
    let resultType = 'unknown';

    try {
      // Simple expression evaluation (in production would use DAP relay)
      if (request.expression === 'true') {
        result = true;
        resultType = 'boolean';
      } else if (request.expression === 'false') {
        result = false;
        resultType = 'boolean';
      } else if (/^\d+$/.test(request.expression)) {
        result = parseInt(request.expression, 10);
        resultType = 'number';
      } else {
        result = request.expression;
        resultType = 'string';
      }

      this.statistics.totalEvaluations++;

      this.recordAudit({
        userId: request.userId,
        userEmail: request.userEmail,
        operation: 'expression-evaluated',
        status: 'success',
        sessionId,
        threadId: request.threadId,
        details: { expression: request.expression, context: request.context },
        ipAddress,
        userAgent,
        timestamp: Date.now(),
      });

      this.emit('expression-evaluated', {
        threadId: request.threadId,
        expression: request.expression,
        result,
        sessionId,
        timestamp: Date.now(),
      });

      return { success: true, result, type: resultType };
    } catch (error) {
      return {
        success: false,
        result: undefined,
        type: 'error',
        message: error instanceof Error ? error.message : 'Evaluation failed',
      };
    }
  }

  /**
   * Terminate debug session
   */
  terminateDebugSession(sessionId: string, userId: string, userEmail: string, ipAddress: string, userAgent: string): boolean {
    const session = this.sessions.get(sessionId);
    if (!session) {
      return false;
    }

    session.status = 'terminated';

    // Calculate session duration
    const startTime = this.sessionDurations.get(sessionId) ?? Date.now();
    const duration = Date.now() - startTime;
    const prevDuration = this.statistics.avgSessionDuration;
    this.statistics.avgSessionDuration =
      (prevDuration * (this.statistics.totalSessions - 1) + duration) / this.statistics.totalSessions;
    this.statistics.activeSessions--;

    this.sessionDurations.delete(sessionId);
    this.sessions.delete(sessionId);

    this.recordAudit({
      userId,
      userEmail,
      operation: 'debug-session-terminated',
      status: 'success',
      sessionId,
      ipAddress,
      userAgent,
      timestamp: Date.now(),
    });

    this.emit('debug-session-terminated', { sessionId, timestamp: Date.now() });

    return true;
  }

  /**
   * Get audit log
   */
  getAuditLog(userId: string): CollaborativeDebugAuditEntry[] {
    return this.auditLog.get(userId) ?? [];
  }

  /**
   * Get statistics
   */
  getStatistics(): CollaborativeDebugStatistics {
    return {
      ...this.statistics,
      avgParticipantsPerSession:
        this.statistics.totalSessions > 0
          ? Array.from(this.sessions.values()).reduce((sum, s) => sum + s.participantUserIds.length, 0) /
            this.statistics.totalSessions
          : 0,
    };
  }

  /**
   * Update configuration
   */
  updateConfig(config: Partial<CollaborativeDebugServiceConfig>, userId: string, ipAddress: string, userAgent: string): void {
    Object.assign(this.config, config);

    this.recordAudit({
      userId,
      userEmail: '',
      operation: 'debug-session-created',
      status: 'success',
      details: config,
      ipAddress,
      userAgent,
      timestamp: Date.now(),
    });

    this.emit('config-updated', { config: this.config, timestamp: Date.now() });
  }

  /**
   * Shutdown service
   */
  shutdown(): void {
    this.sessions.clear();
    this.auditLog.clear();
    this.sessionDurations.clear();
    this.emit('shutdown', { timestamp: Date.now() });
  }

  /**
   * Record audit entry
   */
  private recordAudit(entry: CollaborativeDebugAuditEntry): void {
    if (!this.auditLog.has(entry.userId)) {
      this.auditLog.set(entry.userId, []);
    }

    const log = this.auditLog.get(entry.userId)!;
    log.push(entry);

    // Limit audit log size
    if (log.length > this.config.maxAuditLogSize) {
      log.splice(0, log.length - this.config.maxAuditLogSize);
    }

    this.emit('audit-logged', { entry, timestamp: Date.now() });
  }
}
