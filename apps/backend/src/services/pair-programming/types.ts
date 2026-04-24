/**
 * Pair Programming AI Copilot Service - Type Definitions
 * @file        apps/backend/src/services/pair-programming/__types/types.ts
 * @module      services/pair-programming
 * @description Type definitions for AI-augmented pair programming with real-time collaboration
 */

import { EventEmitter } from 'events';

/**
 * Pair programming session participant
 */
export interface PairProgrammingParticipant {
  userId: string;
  userEmail: string;
  userName: string;
  role: ParticipantRole;
  joinedAt: number;
  lastActivityAt: number;
  isActive: boolean;
  cursorPosition?: CursorPosition;
  isTyping: boolean;
  focusedFile?: string;
}

/**
 * Participant role in pair programming
 */
export type ParticipantRole = 'driver' | 'navigator' | 'observer';

/**
 * Cursor position
 */
export interface CursorPosition {
  filePath: string;
  line: number;
  column: number;
  timestamp: number;
}

/**
 * Pair programming session
 */
export interface PairProgrammingSession {
  id: string;
  workspaceId: string;
  sessionId: string;
  initiatorId: string;
  initiatorEmail: string;
  initiatorName: string;
  title: string;
  description?: string;
  participants: PairProgrammingParticipant[];
  focusedFile: string;
  createdAt: number;
  updatedAt: number;
  endedAt?: number;
  isActive: boolean;
  aiContext: AIContext;
  suggestions: Map<string, AICodeSuggestion>;
  driverSwitchHistory: DriverSwitch[];
}

/**
 * AI context for pair programming
 */
export interface AIContext {
  currentCode: string;
  recentChanges: CodeChange[];
  relatedFiles: FileReference[];
  projectContext: string;
  conversationHistory: ConversationTurn[];
  lastUpdateAt: number;
}

/**
 * Code change tracking
 */
export interface CodeChange {
  timestamp: number;
  userId: string;
  filePath: string;
  oldContent: string;
  newContent: string;
  description: string;
}

/**
 * File reference in project
 */
export interface FileReference {
  filePath: string;
  content?: string;
  isRelevant: boolean;
  relevanceScore: number;
  relationType: 'import' | 'dependency' | 'similar' | 'context';
}

/**
 * Conversation turn in pair programming
 */
export interface ConversationTurn {
  id: string;
  userId: string;
  userEmail: string;
  userName: string;
  isAI: boolean;
  content: string;
  timestamp: number;
  context?: {
    filePath: string;
    startLine: number;
    endLine: number;
  };
}

/**
 * AI code suggestion
 */
export interface AICodeSuggestion {
  id: string;
  sessionId: string;
  suggestedBy: SuggestionSource;
  timestamp: number;
  filePath: string;
  startLine: number;
  endLine: number;
  originalCode: string;
  suggestedCode: string;
  explanation: string;
  confidence: number;
  category: SuggestionCategory;
  status: 'pending' | 'accepted' | 'rejected' | 'applied';
  appliedAt?: number;
  rejectedAt?: number;
  rejectionReason?: string;
  relatedSuggestions?: string[];
}

/**
 * Suggestion source
 */
export type SuggestionSource = 'ai-copilot' | 'linting' | 'accessibility' | 'performance' | 'security' | 'style';

/**
 * Suggestion category
 */
export type SuggestionCategory =
  | 'refactoring'
  | 'bug-fix'
  | 'optimization'
  | 'completion'
  | 'testing'
  | 'documentation'
  | 'security'
  | 'accessibility';

/**
 * Driver switch record
 */
export interface DriverSwitch {
  timestamp: number;
  previousDriver: string;
  newDriver: string;
  reason?: string;
  durationMs: number;
}

/**
 * Real-time sync message
 */
export interface SyncMessage {
  type: MessageType;
  timestamp: number;
  userId: string;
  userEmail: string;
  data: unknown;
  sessionId: string;
}

/**
 * Message type
 */
export type MessageType =
  | 'cursor-moved'
  | 'code-changed'
  | 'suggestion-generated'
  | 'driver-changed'
  | 'file-focused'
  | 'ai-response'
  | 'debug-breakpoint'
  | 'test-run-result';

/**
 * AI suggestion request
 */
export interface AISuggestionRequest {
  sessionId: string;
  userId: string;
  userEmail: string;
  userName: string;
  filePath: string;
  code: string;
  lineNumber?: number;
  context: 'general' | 'completion' | 'refactoring' | 'testing' | 'bug-fix' | 'documentation';
  includeExplanation: boolean;
}

/**
 * AI suggestion response
 */
export interface AISuggestionResponse {
  success: boolean;
  suggestion?: AICodeSuggestion;
  suggestions?: AICodeSuggestion[];
  explanation?: string;
  error?: string;
  model?: string;
  tokensUsed?: number;
  costInCredits?: number;
}

/**
 * Session statistics
 */
export interface PairProgrammingStatistics {
  sessionId: string;
  duration: number;
  participantCount: number;
  linesAddedByDriver1: number;
  linesAddedByDriver2: number;
  linesAddedByAI: number;
  totalSuggestions: number;
  acceptedSuggestions: number;
  acceptanceRate: number;
  driverSwitchCount: number;
  averageDriverDuration: number;
  aiResponseTime: number;
  codeQualityImprovement: number;
  estimatedTimesSaved: number;
}

/**
 * Audit entry for pair programming
 */
export interface PairProgrammingAuditEntry {
  timestamp: number;
  userId: string;
  userEmail: string;
  ipAddress: string;
  userAgent: string;
  operation: PairProgrammingOperation;
  sessionId?: string;
  status: 'success' | 'failure';
  details: Map<string, unknown>;
}

/**
 * Operation type
 */
export type PairProgrammingOperation =
  | 'session-created'
  | 'user-joined'
  | 'user-left'
  | 'driver-switched'
  | 'ai-suggestion-generated'
  | 'suggestion-applied'
  | 'code-change'
  | 'session-ended';

/**
 * Service configuration
 */
export interface PairProgrammingConfig {
  maxSessionsPerWorkspace: number;
  maxParticipantsPerSession: number;
  aiSuggestionThrottleMs: number;
  enableRealTimeSync: boolean;
  enableAutoSuggestions: boolean;
  suggestionModel: 'gpt-4' | 'gpt-3.5-turbo' | 'claude-3' | 'local-llama';
  maxSuggestionsPerSession: number;
  suggestionConfidenceThreshold: number;
  enableDriverTracking: boolean;
  enableCodeQualityMetrics: boolean;
  maxAuditLogSize: number;
  retentionDays: number;
}

/**
 * Request to create pair programming session
 */
export interface CreatePairSessionRequest {
  userId: string;
  userEmail: string;
  userName: string;
  workspaceId: string;
  sessionId: string;
  title: string;
  description?: string;
  focusedFile: string;
  inviteeIds?: string[];
  inviteeEmails?: string[];
  autoStartAI?: boolean;
}

/**
 * Result of creating session
 */
export interface CreatePairSessionResult {
  success: boolean;
  sessionId?: string;
  session?: PairProgrammingSession;
  error?: string;
}

/**
 * Request to join session
 */
export interface JoinPairSessionRequest {
  sessionId: string;
  userId: string;
  userEmail: string;
  userName: string;
  role: ParticipantRole;
}

/**
 * Result of joining session
 */
export interface JoinPairSessionResult {
  success: boolean;
  session?: PairProgrammingSession;
  participants?: PairProgrammingParticipant[];
  error?: string;
}

/**
 * Request to get AI suggestion
 */
export interface GetAISuggestionRequest {
  sessionId: string;
  userId: string;
  userEmail: string;
  fileName: string;
  context: string;
  codeSelection?: string;
  suggestionType: 'completion' | 'refactoring' | 'test' | 'doc' | 'general';
}

/**
 * Result of getting AI suggestion
 */
export interface GetAISuggestionResult {
  success: boolean;
  suggestion?: AICodeSuggestion;
  alternatives?: AICodeSuggestion[];
  explanation?: string;
  model?: string;
  responseTime?: number;
  costInCredits?: number;
  error?: string;
}

/**
 * Request to apply suggestion
 */
export interface ApplySuggestionRequest {
  sessionId: string;
  suggestionId: string;
  userId: string;
  userEmail: string;
  filePath: string;
}

/**
 * Result of applying suggestion
 */
export interface ApplySuggestionResult {
  success: boolean;
  suggestion?: AICodeSuggestion;
  linesAdded?: number;
  linesModified?: number;
  error?: string;
}

/**
 * Request to switch driver
 */
export interface SwitchDriverRequest {
  sessionId: string;
  newDriverId: string;
  newDriverEmail: string;
  newDriverName: string;
  currentUserId: string;
  reason?: string;
}

/**
 * Result of switching driver
 */
export interface SwitchDriverResult {
  success: boolean;
  driverSwitch?: DriverSwitch;
  session?: PairProgrammingSession;
  error?: string;
}

/**
 * Request to end session
 */
export interface EndPairSessionRequest {
  sessionId: string;
  userId: string;
  userEmail: string;
  finalNotes?: string;
}

/**
 * Result of ending session
 */
export interface EndPairSessionResult {
  success: boolean;
  session?: PairProgrammingSession;
  statistics?: PairProgrammingStatistics;
  error?: string;
}

/**
 * Request to get session
 */
export interface GetPairSessionRequest {
  sessionId: string;
}

/**
 * Result of getting session
 */
export interface GetPairSessionResult {
  success: boolean;
  session?: PairProgrammingSession;
  participants?: PairProgrammingParticipant[];
  suggestions?: AICodeSuggestion[];
  error?: string;
}

/**
 * Request to list sessions
 */
export interface ListPairSessionsRequest {
  userId: string;
  userEmail: string;
  filter?: {
    status?: 'active' | 'ended';
    role?: ParticipantRole[];
  };
  limit?: number;
  offset?: number;
}

/**
 * Result of listing sessions
 */
export interface ListPairSessionsResult {
  success: boolean;
  sessions: PairProgrammingSession[];
  count: number;
  total: number;
  error?: string;
}

/**
 * Pair programming statistics
 */
export interface PairProgrammingServiceStatistics {
  totalSessions: number;
  activeSessions: number;
  totalParticipants: number;
  totalSuggestions: number;
  acceptedSuggestions: number;
  averageAcceptanceRate: number;
  averageSessionDuration: number;
  averageParticipantsPerSession: number;
  totalLinesOfCodeChanged: number;
  totalLinesAddedByAI: number;
  aiAverageResponseTime: number;
  totalTokensUsed: number;
  estimatedTotalTimeSaved: number;
}

/**
 * Service interface
 */
export interface IPairProgrammingService extends EventEmitter {
  createPairSession(
    request: CreatePairSessionRequest,
    ipAddress: string,
    userAgent: string
  ): CreatePairSessionResult;

  joinPairSession(
    request: JoinPairSessionRequest,
    ipAddress: string,
    userAgent: string
  ): JoinPairSessionResult;

  getAISuggestion(
    request: GetAISuggestionRequest,
    ipAddress: string,
    userAgent: string
  ): GetAISuggestionResult;

  applySuggestion(
    request: ApplySuggestionRequest,
    ipAddress: string,
    userAgent: string
  ): ApplySuggestionResult;

  switchDriver(
    request: SwitchDriverRequest,
    ipAddress: string,
    userAgent: string
  ): SwitchDriverResult;

  endPairSession(
    request: EndPairSessionRequest,
    ipAddress: string,
    userAgent: string
  ): EndPairSessionResult;

  getPairSession(request: GetPairSessionRequest): GetPairSessionResult;

  listPairSessions(
    request: ListPairSessionsRequest
  ): ListPairSessionsResult;

  getStatistics(): PairProgrammingServiceStatistics;

  updateConfig(
    config: Partial<PairProgrammingConfig>,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): void;

  shutdown(): void;
}
