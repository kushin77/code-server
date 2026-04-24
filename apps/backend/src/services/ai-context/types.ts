// @file        apps/backend/src/services/ai-context/types.ts
// @module      ai/shared-context
// @description Shared AI context types

export interface AIContextSnapshot {
  id: string;
  workspaceId: string;
  userId: string;
  sessionId: string;
  fileContext: {
    path: string;
    language: string;
    content: string;
    selectionStart?: number;
    selectionEnd?: number;
  }[];
  recentConversation: {
    role: 'user' | 'assistant';
    content: string;
    timestamp: Date;
  }[];
  sharedWith: string[];
  createdAt: Date;
  expiresAt: Date;
}

export interface AIContextConfig {
  workspaceId: string;
  maxContextSize?: number;
  ttlMinutes?: number;
}

export interface AIContextShare {
  contextId: string;
  sharedWith: string;
  sharedBy: string;
  sharedAt: Date;
  canModify: boolean;
}
