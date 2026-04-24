// @file        apps/backend/src/services/ai-context/index.ts
// @module      ai/shared-context
// @description Shared AI Copilot context service enabling multi-user session context

import { EventEmitter } from 'events';
import { Pool } from 'pg';
import Redis from 'ioredis';
import { AuditService } from '../audit/audit-service.js';
import {
  AIContextSnapshot,
  AIContextShare,
  AIContextConfig,
} from './types.js';

/**
 * Shared AI context service managing collaborative AI session context
 * - Snapshots file context + conversation history
 * - Shares context between collaborators in real-time
 * - Maintains context TTL and expiration
 * - Emits events for context updates
 */
export class SharedAIContextService extends EventEmitter {
  private config: AIContextConfig;
  private pool: Pool;
  private redis: Redis;
  private auditService?: AuditService;
  private contexts: Map<string, AIContextSnapshot> = new Map();
  private shares: Map<string, AIContextShare[]> = new Map();

  constructor(config: AIContextConfig, pool: Pool, redis: Redis, auditService?: AuditService) {
    super();
    this.config = config;
    this.pool = pool;
    this.redis = redis;
    this.auditService = auditService;

    if (!config.workspaceId) {
      throw new Error('Workspace ID required for shared AI context');
    }
  }

  /**
   * Create a new AI context snapshot
   */
  async createContext(
    userId: string,
    sessionId: string,
    fileContext: AIContextSnapshot['fileContext'],
    conversation: AIContextSnapshot['recentConversation']
  ): Promise<AIContextSnapshot> {
    const contextId = `ctx-${Date.now()}-${Math.random().toString(36).substring(7)}`;
    const ttlMs = (this.config.ttlMinutes || 30) * 60 * 1000;

    const context: AIContextSnapshot = {
      id: contextId,
      workspaceId: this.config.workspaceId,
      userId,
      sessionId,
      fileContext,
      recentConversation: conversation,
      sharedWith: [],
      createdAt: new Date(),
      expiresAt: new Date(Date.now() + ttlMs),
    };

    this.contexts.set(contextId, context);

    // SOC2: Audit context creation
    this.auditService?.emit({
      userId,
      action: 'CREATE',
      resource: 'AIContextSnapshot',
      resourceId: contextId,
      metadata: {
        workspaceId: this.config.workspaceId,
        sessionId,
        fileCount: fileContext.length,
        conversationLength: conversation.length,
      },
    });

    this.emit('context_created', context);
    return context;
  }

  /**
   * Share context with another user
   */
  async shareContext(
    contextId: string,
    sharedBy: string,
    sharedWith: string,
    canModify: boolean = false
  ): Promise<AIContextShare> {
    const context = this.contexts.get(contextId);
    if (!context) {
      throw new Error(`Context ${contextId} not found`);
    }

    if (!context.sharedWith.includes(sharedWith)) {
      context.sharedWith.push(sharedWith);
    }

    const share: AIContextShare = {
      contextId,
      sharedWith,
      sharedBy,
      sharedAt: new Date(),
      canModify,
    };

    const shares = this.shares.get(contextId) || [];
    shares.push(share);
    this.shares.set(contextId, shares);

    // SOC2: Audit context share
    this.auditService?.emit({
      userId: sharedBy,
      action: 'UPDATE',
      resource: 'AIContextSnapshot',
      resourceId: contextId,
      metadata: {
        event: 'context_shared',
        sharedWith,
        canModify,
      },
    });

    this.emit('context_shared', share);
    return share;
  }

  /**
   * Update context with new conversation
   */
  async updateContext(
    contextId: string,
    userId: string,
    newMessages: AIContextSnapshot['recentConversation']
  ): Promise<AIContextSnapshot> {
    const context = this.contexts.get(contextId);
    if (!context) {
      throw new Error(`Context ${contextId} not found`);
    }

    if (context.expiresAt < new Date()) {
      throw new Error(`Context ${contextId} has expired`);
    }

    context.recentConversation.push(...newMessages);

    // SOC2: Audit context update
    this.auditService?.emit({
      userId,
      action: 'UPDATE',
      resource: 'AIContextSnapshot',
      resourceId: contextId,
      metadata: {
        messageCount: newMessages.length,
      },
    });

    this.emit('context_updated', context);
    return context;
  }

  /**
   * Revoke context access
   */
  async revokeContext(contextId: string, revokedBy: string): Promise<void> {
    const context = this.contexts.get(contextId);
    if (!context) {
      throw new Error(`Context ${contextId} not found`);
    }

    context.sharedWith = [];

    // SOC2: Audit context revocation
    this.auditService?.emit({
      userId: revokedBy,
      action: 'DELETE',
      resource: 'AIContextSnapshot',
      resourceId: contextId,
      metadata: {
        reason: 'access_revoked',
      },
    });

    this.emit('context_revoked', context);
  }

  /**
   * Get context with access check
   */
  async getContext(contextId: string, userId: string): Promise<AIContextSnapshot | null> {
    const context = this.contexts.get(contextId);
    if (!context) {
      return null;
    }

    if (context.expiresAt < new Date()) {
      this.contexts.delete(contextId);
      return null;
    }

    const hasAccess = context.userId === userId || context.sharedWith.includes(userId);
    if (!hasAccess) {
      throw new Error('Access denied to context');
    }

    // SOC2: Audit context access
    this.auditService?.emit({
      userId,
      action: 'READ',
      resource: 'AIContextSnapshot',
      resourceId: contextId,
      metadata: {
        isOwner: context.userId === userId,
      },
    });

    return context;
  }

  /**
   * Get user's accessible contexts
   */
  getUserContexts(userId: string): AIContextSnapshot[] {
    return Array.from(this.contexts.values()).filter(ctx => {
      if (ctx.expiresAt < new Date()) return false;
      return ctx.userId === userId || ctx.sharedWith.includes(userId);
    });
  }

  /**
   * Clean expired contexts
   */
  async cleanExpiredContexts(): Promise<number> {
    const now = new Date();
    let count = 0;

    for (const [id, ctx] of this.contexts.entries()) {
      if (ctx.expiresAt < now) {
        this.contexts.delete(id);
        this.shares.delete(id);
        count++;
      }
    }

    return count;
  }
}

export { AIContextSnapshot, AIContextShare, AIContextConfig };
