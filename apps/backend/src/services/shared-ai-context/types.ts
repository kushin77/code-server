/**
 * @file        apps/backend/src/services/shared-ai-context/types.ts
 * @module      services/shared-ai-context
 * @description Shared AI Copilot conversation context for collaborative coding
 *
 */

/**
 * Author information for conversation turns
 */
export interface ConversationAuthor {
  userId: string;
  userName: string;
  userEmail: string;
  isAI: boolean;
}

/**
 * AI turn metadata with model information
 */
export interface AITurnMetadata {
  model: string;
  temperature: number;
  maxTokens: number;
  tokensUsed: number;
  completionTime: number; // milliseconds
  costInCredits: number;
}

/**
 * Conversation turn (message)
 */
export interface ConversationTurn {
  id: string;
  conversationId: string;
  author: ConversationAuthor;
  content: string;
  timestamp: number;
  editedAt?: number;
  editedBy?: ConversationAuthor;
  editHistory?: {
    content: string;
    editedAt: number;
    editedBy: ConversationAuthor;
  }[];
  reactionCounts?: Record<string, number>;
  isResolved?: boolean;
  followUpCount: number;
  metadata?: AITurnMetadata;
}

/**
 * Shared conversation context
 */
export interface SharedConversation {
  id: string;
  workspaceId: string;
  sessionId: string;
  participants: ConversationAuthor[];
  turns: Map<string, ConversationTurn>;
  createdAt: number;
  updatedAt: number;
  isActive: boolean;
  visibility: 'private' | 'team' | 'public';
  topic?: string;
  tags: string[];
  summary?: string;
  documentationId?: string;
}

/**
 * Context injection data for Copilot
 */
export interface AIContextInjection {
  conversationId: string;
  turns: ConversationTurn[];
  participants: ConversationAuthor[];
  summary: string;
  relevantCode?: {
    filePath: string;
    lineStart: number;
    lineEnd: number;
    snippet: string;
    language: string;
  }[];
  recentActivity?: {
    timestamp: number;
    action: string;
    user: ConversationAuthor;
  }[];
}

/**
 * Request to start a shared conversation
 */
export interface StartSharedConversationRequest {
  userId: string;
  userEmail: string;
  userName: string;
  workspaceId: string;
  sessionId: string;
  topic?: string;
  visibility: 'private' | 'team' | 'public';
  initialMessage?: string;
  participantIds?: string[];
}

/**
 * Result of starting shared conversation
 */
export interface StartSharedConversationResult {
  success: boolean;
  conversationId?: string;
  conversation?: SharedConversation;
  error?: string;
}

/**
 * Request to add turn to conversation
 */
export interface AddConversationTurnRequest {
  conversationId: string;
  userId: string;
  userEmail: string;
  userName: string;
  isAI: boolean;
  content: string;
  model?: string;
  temperature?: number;
  maxTokens?: number;
  tokensUsed?: number;
  completionTime?: number;
  costInCredits?: number;
}

/**
 * Result of adding turn
 */
export interface AddConversationTurnResult {
  success: boolean;
  turnId?: string;
  turn?: ConversationTurn;
  broadcastedTo?: number; // Number of connected participants notified
  error?: string;
}

/**
 * Request to edit a turn
 */
export interface EditConversationTurnRequest {
  conversationId: string;
  turnId: string;
  userId: string;
  userEmail: string;
  userName: string;
  newContent: string;
}

/**
 * Result of editing turn
 */
export interface EditConversationTurnResult {
  success: boolean;
  turn?: ConversationTurn;
  error?: string;
}

/**
 * Request to mark turn as resolved
 */
export interface ResolveConversationTurnRequest {
  conversationId: string;
  turnId: string;
  userId: string;
  userEmail: string;
}

/**
 * Request to get conversation
 */
export interface GetConversationRequest {
  conversationId: string;
  includeMetadata?: boolean;
}

/**
 * Result of getting conversation
 */
export interface GetConversationResult {
  success: boolean;
  conversation?: SharedConversation;
  turns?: ConversationTurn[];
  participants?: ConversationAuthor[];
  error?: string;
}

/**
 * Request to add context to Copilot
 */
export interface InjectContextToCopilotRequest {
  conversationId: string;
  userId: string;
  userEmail: string;
  includeRecentTurns?: number; // Last N turns (default: 10)
  includeCodeContext?: boolean;
  includeRecentActivity?: boolean;
}

/**
 * Result of injecting context
 */
export interface InjectContextToCopilotResult {
  success: boolean;
  contextId?: string;
  injection?: AIContextInjection;
  tokenEstimate?: number;
  error?: string;
}

/**
 * Request to list conversations for user
 */
export interface ListConversationsRequest {
  userId: string;
  userEmail: string;
  workspaceId?: string;
  limit?: number;
  offset?: number;
}

/**
 * Result of listing conversations
 */
export interface ListConversationsResult {
  success: boolean;
  conversations?: SharedConversation[];
  count?: number;
  hasMore?: boolean;
  error?: string;
}

/**
 * Request to subscribe to conversation updates
 */
export interface SubscribeConversationRequest {
  conversationId: string;
  userId: string;
  userEmail: string;
}

/**
 * Request to unsubscribe from conversation
 */
export interface UnsubscribeConversationRequest {
  conversationId: string;
  userId: string;
  userEmail: string;
}

/**
 * Request to close conversation
 */
export interface CloseConversationRequest {
  conversationId: string;
  userId: string;
  userEmail: string;
}

/**
 * Result of closing conversation
 */
export interface CloseConversationResult {
  success: boolean;
  error?: string;
}

/**
 * Request to summarize conversation
 */
export interface SummarizeConversationRequest {
  conversationId: string;
  userId: string;
  userEmail: string;
  style?: 'brief' | 'detailed' | 'actionable';
}

/**
 * Result of summarizing
 */
export interface SummarizeConversationResult {
  success: boolean;
  summary?: string;
  keyPoints?: string[];
  actionItems?: string[];
  error?: string;
}

/**
 * Request to export conversation
 */
export interface ExportConversationRequest {
  conversationId: string;
  userId: string;
  userEmail: string;
  format: 'markdown' | 'json' | 'pdf';
  includeMetadata?: boolean;
}

/**
 * Result of exporting
 */
export interface ExportConversationResult {
  success: boolean;
  content?: string;
  documentId?: string;
  error?: string;
}

/**
 * Audit entry for shared context operations
 */
export interface SharedContextAuditEntry {
  timestamp: number;
  userId: string;
  userEmail: string;
  ipAddress: string;
  userAgent: string;
  operation: 'start-conversation' | 'add-turn' | 'edit-turn' | 'resolve-turn' | 'close-conversation' | 'inject-context' | 'export-conversation' | 'update-config';
  conversationId: string;
  status: 'success' | 'failure';
  details?: Record<string, any>;
}

/**
 * Service configuration
 */
export interface SharedAICopilotContextConfig {
  maxConversationsPerSession?: number;
  maxTurnsPerConversation?: number;
  maxContextTokensPerTurn?: number;
  maxParticipantsPerConversation?: number;
  conversationIdleTimeout?: number; // milliseconds
  enableAutoSummarization?: boolean;
  enableDocumentationExport?: boolean;
  maxAuditLogSize?: number;
  retentionDays?: number;
}

/**
 * Statistics for shared AI context service
 */
export interface SharedContextStatistics {
  totalConversations: number;
  activeConversations: number;
  totalTurns: number;
  averageTurnsPerConversation: number;
  totalParticipants: number;
  averageParticipantsPerConversation: number;
  totalAIResponses: number;
  averageResponseTime: number; // milliseconds
  totalTokensUsed: number;
  averageCostPerConversation: number;
  exportedConversations: number;
}

/**
 * Participant activity in shared context
 */
export interface ParticipantActivity {
  userId: string;
  userEmail: string;
  userName: string;
  joinedAt: number;
  lastActivityAt: number;
  turnCount: number;
  isActive: boolean;
  cursorPosition?: {
    x: number;
    y: number;
    timestamp: number;
  };
}

/**
 * Conversation metadata
 */
export interface ConversationMetadata {
  conversationId: string;
  workspaceId: string;
  sessionId: string;
  createdAt: number;
  updatedAt: number;
  totalTurns: number;
  totalTokensUsed: number;
  totalCost: number;
  averageResponseTime: number;
  isResolved: boolean;
  resolvedAt?: number;
  documentationId?: string;
  documentationUrl?: string;
  createdBy: ConversationAuthor;
  participants: ParticipantActivity[];
}

/**
 * Context injection result with metadata
 */
export interface ContextInjectionWithMetadata {
  injection: AIContextInjection;
  metadata: ConversationMetadata;
  relevanceScore?: number; // 0-100
  estimatedTokenCost?: number;
}
