/**
 * @file        apps/backend/src/services/debug-ai/types.ts
 * @module      ai/debug-session
 * @description Debug session AI analysis type definitions
 */

/**
 * Breakpoint state
 */
export interface Breakpoint {
  id: string;
  filePath: string;
  lineNumber: number;
  column?: number;
  condition?: string;
  hitCount?: number;
  enabled: boolean;
  logMessage?: string;
}

/**
 * Variable in debug context
 */
export interface DebugVariable {
  name: string;
  value: string;
  type: string;
  variablesReference?: number; // For nested objects
  scope: 'local' | 'global' | 'argument' | 'parameter';
  frameId?: number;
}

/**
 * Stack frame
 */
export interface StackFrame {
  id: number;
  name: string; // Function name
  source: {
    name: string; // File name
    path: string; // File path
  };
  line: number;
  column?: number;
  endLine?: number;
  endColumn?: number;
  canRestart?: boolean;
  instructionPointerReference?: string;
  moduleId?: string | number;
}

/**
 * Debug session state snapshot
 */
export interface DebugSessionState {
  sessionId: string;
  workspaceId: string;
  createdAt: number;

  // Execution state
  isPaused: boolean;
  pauseReason?: 'breakpoint' | 'step' | 'pause' | 'entry' | 'exception' | 'goto' | 'function breakpoint' | 'data breakpoint';
  pausedAt?: number;

  // Stack and variables
  stackTrace: StackFrame[];
  variables: DebugVariable[];
  activeFrameId?: number;

  // Breakpoints
  breakpoints: Breakpoint[];

  // Program output
  output: Array<{
    category: 'stdout' | 'stderr' | 'console' | 'telemetry';
    output: string;
    source?: string;
    variablesReference?: number;
    group?: string;
    line?: number;
    column?: number;
    variables?: DebugVariable[];
  }>;

  // Metadata
  language: string; // 'typescript', 'python', 'javascript', etc.
  runtime?: string; // 'node', 'python', 'browser', etc.
  debuggerVersion?: string;
}

/**
 * Analysis context for AI
 */
export interface DebugAnalysisContext {
  state: DebugSessionState;
  history: DebugSessionState[]; // Previous states for trend analysis
  relevantCode?: {
    filePath: string;
    lineNumber: number;
    startLine: number;
    endLine: number;
    content: string;
  };
  relatedErrors?: Array<{
    timestamp: number;
    message: string;
    stack?: string;
  }>;
}

/**
 * AI analysis result
 */
export interface DebugAIAnalysis {
  sessionId: string;
  analysisId: string;
  timestamp: number;

  // Root cause analysis
  suspectedCause: {
    confidence: number; // 0-1
    description: string;
    evidence: string[]; // Why we think this is the cause
  };

  // Fix suggestions
  suggestedFixes: Array<{
    title: string;
    description: string;
    codeChanges?: Array<{
      filePath: string;
      lineNumber: number;
      oldCode: string;
      newCode: string;
      explanation: string;
    }>;
    difficulty: 'easy' | 'medium' | 'hard';
    estimatedTime: number; // Minutes
  }>;

  // Relevant documentation
  relevantDocs: Array<{
    title: string;
    url: string;
    relevance: number; // 0-1
    excerpt?: string;
  }>;

  // Variable analysis
  variableAnalysis: {
    suspiciousVariables: Array<{
      name: string;
      reason: string;
      suggestedValues?: string[];
    }>;
    uninitializedVariables: string[];
    unexpectedTypes: Array<{
      variable: string;
      expectedType: string;
      actualType: string;
    }>;
  };

  // Common patterns
  commonPatterns: Array<{
    pattern: string;
    frequency: number; // How many times seen
    hasOccurred: boolean; // Does it apply here
    fix?: string;
  }>;

  // Next debug steps
  suggestedNextSteps: string[];

  // Metadata
  model: string; // 'gpt-4', 'claude', etc.
  processingTime: number; // ms
}

/**
 * Debug session event
 */
export interface DebugSessionEvent {
  type:
    | 'paused'
    | 'resumed'
    | 'breakpoint-hit'
    | 'exception'
    | 'analysis-requested'
    | 'analysis-complete'
    | 'suggestion-accepted'
    | 'output-received';
  sessionId: string;
  timestamp: number;
  data?: Record<string, any>;
}

/**
 * Debug statistics
 */
export interface DebugStats {
  totalSessions: number;
  activeSessions: number;
  averageSessionDuration: number; // ms
  analysisRuns: number;
  suggestedFixesGenerated: number;
  fixesApplied: number;
  applyRate: number; // % of suggestions applied
  averageResolutionTime: number; // ms from pause to resume
  commonCauses: Record<string, number>; // Frequency by cause type
  byLanguage: Record<string, number>;
  byPauseReason: Record<string, number>;
}

/**
 * User feedback on analysis
 */
export interface AnalysisFeedback {
  analysisId: string;
  sessionId: string;
  timestamp: number;
  userId: string;

  // Ratings
  helpfulness: number; // 1-5
  accuracy: number; // 1-5
  correctDiagnosis: boolean; // Was root cause correct
  appliedSuggestions: number; // How many fixes did user apply

  // Comments
  comment?: string;

  // Follow-up
  needsFurtherHelp: boolean;
  followUpQuestion?: string;
}
