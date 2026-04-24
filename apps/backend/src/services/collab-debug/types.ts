#!/usr/bin/env node
/**
 * @file        apps/backend/src/services/collab-debug/types.ts
 * @module      services/collaboration/collab-debug
 * @description Type definitions for collaborative debugging service
 */

/**
 * Breakpoint location
 */
export interface BreakpointLocation {
  filePath: string;
  line: number;
  column?: number;
}

/**
 * Debug breakpoint
 */
export interface DebugBreakpoint {
  id: string;
  location: BreakpointLocation;
  condition?: string; // Optional condition
  logMessage?: string; // Logpoint message
  enabled: boolean;
  setByUserId: string;
  setByUserEmail: string;
  createdAt: number;
}

/**
 * Variable value
 */
export interface VariableValue {
  name: string;
  value: unknown;
  type: string;
  expandable: boolean;
  referenceId?: string;
}

/**
 * Stack frame
 */
export interface StackFrame {
  id: string;
  source: string;
  function: string;
  line: number;
  column: number;
}

/**
 * Debug thread state
 */
export interface ThreadState {
  threadId: string;
  state: 'stopped' | 'running' | 'exited';
  stoppedReason?: 'breakpoint' | 'step' | 'pause' | 'exception' | 'goto' | 'function breakpoint' | 'instruction breakpoint';
  stackTrace: StackFrame[];
  variables: Map<string, VariableValue>;
  stoppedAt?: number;
}

/**
 * Debug session
 */
export interface DebugSession {
  id: string;
  debugSessionId: string; // DAP session ID
  initiatorUserId: string;
  initiatorUserEmail: string;
  participantUserIds: string[]; // Other collaborative debuggers
  createdAt: number;
  status: 'active' | 'paused' | 'terminated';
  breakpoints: Map<string, DebugBreakpoint>;
  threads: Map<string, ThreadState>;
  watchExpressions: string[];
  isShared: boolean;
  maxParticipants?: number;
}

/**
 * Set breakpoint request
 */
export interface SetBreakpointRequest {
  userId: string;
  userEmail: string;
  location: BreakpointLocation;
  condition?: string;
  logMessage?: string;
}

/**
 * Set breakpoint result
 */
export interface SetBreakpointResult {
  success: boolean;
  breakpointId: string;
  verified: boolean;
  message?: string;
}

/**
 * Clear breakpoint request
 */
export interface ClearBreakpointRequest {
  userId: string;
  userEmail: string;
  breakpointId: string;
}

/**
 * Clear breakpoint result
 */
export interface ClearBreakpointResult {
  success: boolean;
  breakpointId: string;
  message?: string;
}

/**
 * Continue thread request
 */
export interface ContinueThreadRequest {
  userId: string;
  userEmail: string;
  threadId: string;
}

/**
 * Continue thread result
 */
export interface ContinueThreadResult {
  success: boolean;
  threadId: string;
  allThreadsContinued: boolean;
}

/**
 * Step thread request
 */
export interface StepThreadRequest {
  userId: string;
  userEmail: string;
  threadId: string;
  stepType: 'in' | 'over' | 'out';
}

/**
 * Step thread result
 */
export interface StepThreadResult {
  success: boolean;
  threadId: string;
  allThreadsStopped: boolean;
}

/**
 * Get variables request
 */
export interface GetVariablesRequest {
  userId: string;
  userEmail: string;
  threadId: string;
  referenceId?: string;
}

/**
 * Get variables result
 */
export interface GetVariablesResult {
  success: boolean;
  variables: VariableValue[];
  message?: string;
}

/**
 * Set variable request
 */
export interface SetVariableRequest {
  userId: string;
  userEmail: string;
  variableName: string;
  newValue: unknown;
  threadId: string;
}

/**
 * Set variable result
 */
export interface SetVariableResult {
  success: boolean;
  variableName: string;
  newValue: unknown;
  message?: string;
}

/**
 * Eval expression request
 */
export interface EvalExpressionRequest {
  userId: string;
  userEmail: string;
  expression: string;
  threadId: string;
  context?: 'watch' | 'repl' | 'hover';
}

/**
 * Eval expression result
 */
export interface EvalExpressionResult {
  success: boolean;
  result: unknown;
  type: string;
  message?: string;
}

/**
 * Collaborative debug service configuration
 */
export interface CollaborativeDebugServiceConfig {
  maxSessions?: number; // Default 50
  maxParticipantsPerSession?: number; // Default 10
  maxBreakpoints?: number; // Default 100
  enableLogpoints?: boolean; // Default true
  enableConditionalBreakpoints?: boolean; // Default true
  maxWatchExpressions?: number; // Default 50
  dapProxyHost?: string; // Default localhost
  dapProxyPort?: number; // Default 5005
  sessionTimeout?: number; // Default 1800000 (30 min)
  maxAuditLogSize?: number; // Default 10000
}

/**
 * Debug event types
 */
export type DebugEventType =
  | 'stopped'
  | 'continued'
  | 'thread'
  | 'output'
  | 'module'
  | 'loadedSource'
  | 'processEvent'
  | 'capabilities'
  | 'memory';

/**
 * Debug event
 */
export interface DebugEvent {
  eventType: DebugEventType;
  sessionId: string;
  threadId?: string;
  data?: Record<string, unknown>;
  timestamp: number;
}

/**
 * Collaborative debug audit entry
 */
export interface CollaborativeDebugAuditEntry {
  userId: string;
  userEmail: string;
  operation:
    | 'debug-session-created'
    | 'debug-session-terminated'
    | 'breakpoint-set'
    | 'breakpoint-cleared'
    | 'thread-continued'
    | 'thread-stepped'
    | 'variable-inspected'
    | 'expression-evaluated'
    | 'participant-joined'
    | 'participant-left';
  status: 'success' | 'failure';
  sessionId?: string;
  breakpointId?: string;
  threadId?: string;
  details?: Record<string, unknown>;
  ipAddress: string;
  userAgent: string;
  timestamp: number;
}

/**
 * Collaborative debug statistics
 */
export interface CollaborativeDebugStatistics {
  totalSessions: number;
  activeSessions: number;
  totalBreakpoints: number;
  totalSteps: number;
  totalEvaluations: number;
  avgParticipantsPerSession: number;
  avgSessionDuration: number; // ms
  lastSessionAt: number;
}
