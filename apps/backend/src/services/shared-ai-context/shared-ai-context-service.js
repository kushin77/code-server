/**
 * @file        apps/backend/src/services/shared-ai-context/shared-ai-context-service.ts
 * @module      services/shared-ai-context
 * @description Shared AI Copilot conversation context for collaborative coding
 *
 */
import { EventEmitter } from 'events';
/**
 * Shared AI Copilot Context Service
 * Manages shared conversation contexts between multiple users in a workspace
 */
export class SharedAICopilotContextService extends EventEmitter {
    static getInstance(config) {
        if (!this.instance) {
            this.instance = new SharedAICopilotContextService(config);
        }
        return this.instance;
    }
    static reset() {
        this.instance = undefined;
    }
    constructor(config) {
        super();
        this.conversations = new Map();
        this.auditLogs = new Map();
        this.subscribers = new Map(); // conversationId -> Set of userIds
        this.participantActivity = new Map(); // conversationId -> userId -> activity
        this.config = {
            maxConversationsPerSession: 50,
            maxTurnsPerConversation: 500,
            maxContextTokensPerTurn: 4096,
            maxParticipantsPerConversation: 20,
            conversationIdleTimeout: 3600000, // 1 hour
            enableAutoSummarization: true,
            enableDocumentationExport: true,
            maxAuditLogSize: 1000,
            retentionDays: 30,
            ...config,
        };
        this.emit('initialized', { timestamp: Date.now() });
    }
    startSharedConversation(request, ipAddress, userAgent) {
        try {
            const conversationId = `conv-${request.workspaceId}-${Date.now()}-${Math.random().toString(16).slice(2)}`;
            const conversation = {
                id: conversationId,
                workspaceId: request.workspaceId,
                sessionId: request.sessionId,
                participants: [
                    {
                        userId: request.userId,
                        userName: request.userName,
                        userEmail: request.userEmail,
                        isAI: false,
                    },
                ],
                turns: new Map(),
                createdAt: Date.now(),
                updatedAt: Date.now(),
                isActive: true,
                visibility: request.visibility,
                topic: request.topic,
                tags: [],
            };
            this.conversations.set(conversationId, conversation);
            this.subscribers.set(conversationId, new Set([request.userId]));
            this.participantActivity.set(conversationId, new Map());
            const activity = {
                userId: request.userId,
                userEmail: request.userEmail,
                userName: request.userName,
                joinedAt: Date.now(),
                lastActivityAt: Date.now(),
                turnCount: 0,
                isActive: true,
            };
            this.participantActivity.get(conversationId).set(request.userId, activity);
            if (request.initialMessage) {
                const turnId = `turn-${Date.now()}-${Math.random().toString(16).slice(2)}`;
                const turn = {
                    id: turnId,
                    conversationId,
                    author: {
                        userId: request.userId,
                        userName: request.userName,
                        userEmail: request.userEmail,
                        isAI: false,
                    },
                    content: request.initialMessage,
                    timestamp: Date.now(),
                    followUpCount: 0,
                };
                conversation.turns.set(turnId, turn);
            }
            this.recordAudit({
                timestamp: Date.now(),
                userId: request.userId,
                userEmail: request.userEmail,
                ipAddress,
                userAgent,
                operation: 'start-conversation',
                conversationId,
                status: 'success',
                details: { topic: request.topic, visibility: request.visibility },
            });
            this.emit('conversation-started', {
                conversation,
                timestamp: Date.now(),
            });
            return { success: true, conversationId, conversation };
        }
        catch (error) {
            const errorMsg = error instanceof Error ? error.message : String(error);
            this.recordAudit({
                timestamp: Date.now(),
                userId: request.userId,
                userEmail: request.userEmail,
                ipAddress,
                userAgent,
                operation: 'start-conversation',
                conversationId: '',
                status: 'failure',
                details: { error: errorMsg },
            });
            return { success: false, error: errorMsg };
        }
    }
    addConversationTurn(request, ipAddress, userAgent) {
        try {
            const conversation = this.conversations.get(request.conversationId);
            if (!conversation) {
                throw new Error(`Conversation ${request.conversationId} not found`);
            }
            if (conversation.turns.size >= this.config.maxTurnsPerConversation) {
                throw new Error('Max turns per conversation exceeded');
            }
            const turnId = `turn-${Date.now()}-${Math.random().toString(16).slice(2)}`;
            const turn = {
                id: turnId,
                conversationId: request.conversationId,
                author: {
                    userId: request.userId,
                    userName: request.userName,
                    userEmail: request.userEmail,
                    isAI: request.isAI,
                },
                content: request.content,
                timestamp: Date.now(),
                followUpCount: 0,
            };
            if (request.model) {
                turn.metadata = {
                    model: request.model,
                    temperature: request.temperature || 0.7,
                    maxTokens: request.maxTokens || 2048,
                    tokensUsed: request.tokensUsed || 0,
                    completionTime: request.completionTime || 0,
                    costInCredits: request.costInCredits || 0,
                };
            }
            conversation.turns.set(turnId, turn);
            conversation.updatedAt = Date.now();
            // Update participant activity
            if (!this.participantActivity.has(request.conversationId)) {
                this.participantActivity.set(request.conversationId, new Map());
            }
            const activity = this.participantActivity.get(request.conversationId).get(request.userId) || {
                userId: request.userId,
                userName: request.userName,
                userEmail: request.userEmail,
                joinedAt: Date.now(),
                lastActivityAt: Date.now(),
                turnCount: 0,
                isActive: true,
            };
            activity.lastActivityAt = Date.now();
            activity.turnCount += 1;
            this.participantActivity.get(request.conversationId).set(request.userId, activity);
            // Add author to participants if new
            if (!conversation.participants.find((p) => p.userId === request.userId)) {
                conversation.participants.push({
                    userId: request.userId,
                    userName: request.userName,
                    userEmail: request.userEmail,
                    isAI: request.isAI,
                });
            }
            const broadcastedTo = this.subscribers.get(request.conversationId)?.size || 0;
            this.recordAudit({
                timestamp: Date.now(),
                userId: request.userId,
                userEmail: request.userEmail,
                ipAddress,
                userAgent,
                operation: 'add-turn',
                conversationId: request.conversationId,
                status: 'success',
                details: {
                    turnId,
                    isAI: request.isAI,
                    contentLength: request.content.length,
                    tokensUsed: request.tokensUsed || 0,
                },
            });
            this.emit('turn-added', {
                conversationId: request.conversationId,
                turn,
                timestamp: Date.now(),
            });
            return { success: true, turnId, turn, broadcastedTo };
        }
        catch (error) {
            const errorMsg = error instanceof Error ? error.message : String(error);
            return { success: false, error: errorMsg };
        }
    }
    editConversationTurn(request, ipAddress, userAgent) {
        try {
            const conversation = this.conversations.get(request.conversationId);
            if (!conversation) {
                throw new Error(`Conversation ${request.conversationId} not found`);
            }
            const turn = conversation.turns.get(request.turnId);
            if (!turn) {
                throw new Error(`Turn ${request.turnId} not found`);
            }
            // Initialize edit history
            if (!turn.editHistory) {
                turn.editHistory = [];
            }
            // Record previous version in edit history
            turn.editHistory.push({
                content: turn.content,
                editedAt: turn.editedAt || turn.timestamp,
                editedBy: turn.editedBy || turn.author,
            });
            // Update turn
            turn.content = request.newContent;
            turn.editedAt = Date.now();
            turn.editedBy = {
                userId: request.userId,
                userName: request.userName,
                userEmail: request.userEmail,
                isAI: false,
            };
            conversation.updatedAt = Date.now();
            this.recordAudit({
                timestamp: Date.now(),
                userId: request.userId,
                userEmail: request.userEmail,
                ipAddress,
                userAgent,
                operation: 'edit-turn',
                conversationId: request.conversationId,
                status: 'success',
                details: { turnId: request.turnId, editHistoryLength: turn.editHistory.length },
            });
            this.emit('turn-edited', {
                conversationId: request.conversationId,
                turn,
                timestamp: Date.now(),
            });
            return { success: true, turn };
        }
        catch (error) {
            const errorMsg = error instanceof Error ? error.message : String(error);
            return { success: false, error: errorMsg };
        }
    }
    resolveConversationTurn(request, ipAddress, userAgent) {
        try {
            const conversation = this.conversations.get(request.conversationId);
            if (!conversation) {
                throw new Error(`Conversation ${request.conversationId} not found`);
            }
            const turn = conversation.turns.get(request.turnId);
            if (!turn) {
                throw new Error(`Turn ${request.turnId} not found`);
            }
            turn.isResolved = true;
            conversation.updatedAt = Date.now();
            this.recordAudit({
                timestamp: Date.now(),
                userId: request.userId,
                userEmail: request.userEmail,
                ipAddress,
                userAgent,
                operation: 'resolve-turn',
                conversationId: request.conversationId,
                status: 'success',
            });
            this.emit('turn-resolved', {
                conversationId: request.conversationId,
                turnId: request.turnId,
                timestamp: Date.now(),
            });
            return { success: true };
        }
        catch (error) {
            const errorMsg = error instanceof Error ? error.message : String(error);
            return { success: false, error: errorMsg };
        }
    }
    getConversation(request) {
        try {
            const conversation = this.conversations.get(request.conversationId);
            if (!conversation) {
                throw new Error(`Conversation ${request.conversationId} not found`);
            }
            const turns = Array.from(conversation.turns.values());
            const participants = conversation.participants;
            return {
                success: true,
                conversation,
                turns,
                participants,
            };
        }
        catch (error) {
            const errorMsg = error instanceof Error ? error.message : String(error);
            return { success: false, error: errorMsg };
        }
    }
    injectContextToCopilot(request, ipAddress, userAgent) {
        try {
            const conversation = this.conversations.get(request.conversationId);
            if (!conversation) {
                throw new Error(`Conversation ${request.conversationId} not found`);
            }
            const turnsArray = Array.from(conversation.turns.values());
            const recentTurns = turnsArray.slice(Math.max(0, turnsArray.length - (request.includeRecentTurns || 10)));
            let tokenEstimate = 0;
            for (const turn of recentTurns) {
                tokenEstimate += Math.ceil(turn.content.length / 4);
                if (turn.metadata) {
                    tokenEstimate += turn.metadata.tokensUsed;
                }
            }
            const summary = this.config.enableAutoSummarization
                ? `Conversation with ${conversation.participants.length} participants. ${turnsArray.length} turns. Topics: ${conversation.topic || 'general'}`
                : undefined;
            const injection = {
                conversationId: request.conversationId,
                turns: recentTurns,
                participants: conversation.participants,
                summary: summary || '',
                relevantCode: request.includeCodeContext ? [] : undefined,
                recentActivity: request.includeRecentActivity ? [] : undefined,
            };
            const contextId = `ctx-${Date.now()}-${Math.random().toString(16).slice(2)}`;
            this.recordAudit({
                timestamp: Date.now(),
                userId: request.userId,
                userEmail: request.userEmail,
                ipAddress,
                userAgent,
                operation: 'inject-context',
                conversationId: request.conversationId,
                status: 'success',
                details: {
                    contextId,
                    turnsIncluded: recentTurns.length,
                    tokenEstimate,
                },
            });
            this.emit('context-injected', {
                conversationId: request.conversationId,
                contextId,
                tokenEstimate,
                timestamp: Date.now(),
            });
            return {
                success: true,
                contextId,
                injection,
                tokenEstimate,
            };
        }
        catch (error) {
            const errorMsg = error instanceof Error ? error.message : String(error);
            return { success: false, error: errorMsg };
        }
    }
    listConversations(request) {
        try {
            const conversationsArray = Array.from(this.conversations.values());
            const filtered = conversationsArray.filter((conv) => {
                if (request.workspaceId && conv.workspaceId !== request.workspaceId) {
                    return false;
                }
                return conv.visibility === 'public' || conv.participants.some((p) => p.userEmail === request.userEmail);
            });
            const limit = request.limit || 10;
            const offset = request.offset || 0;
            const paginated = filtered.slice(offset, offset + limit);
            return {
                success: true,
                conversations: paginated,
                count: filtered.length,
                hasMore: offset + limit < filtered.length,
            };
        }
        catch (error) {
            const errorMsg = error instanceof Error ? error.message : String(error);
            return { success: false, error: errorMsg };
        }
    }
    subscribeConversation(request, ipAddress, userAgent) {
        try {
            const conversation = this.conversations.get(request.conversationId);
            if (!conversation) {
                throw new Error(`Conversation ${request.conversationId} not found`);
            }
            if (!this.subscribers.has(request.conversationId)) {
                this.subscribers.set(request.conversationId, new Set());
            }
            this.subscribers.get(request.conversationId).add(request.userId);
            this.emit('user-subscribed', {
                conversationId: request.conversationId,
                userId: request.userId,
                timestamp: Date.now(),
            });
            return { success: true };
        }
        catch (error) {
            return { success: false };
        }
    }
    unsubscribeConversation(request) {
        try {
            const subscribers = this.subscribers.get(request.conversationId);
            if (subscribers) {
                subscribers.delete(request.userId);
            }
            this.emit('user-unsubscribed', {
                conversationId: request.conversationId,
                userId: request.userId,
                timestamp: Date.now(),
            });
            return { success: true };
        }
        catch (error) {
            return { success: false };
        }
    }
    closeConversation(request, ipAddress, userAgent) {
        try {
            const conversation = this.conversations.get(request.conversationId);
            if (!conversation) {
                throw new Error(`Conversation ${request.conversationId} not found`);
            }
            conversation.isActive = false;
            conversation.updatedAt = Date.now();
            this.recordAudit({
                timestamp: Date.now(),
                userId: request.userId,
                userEmail: request.userEmail,
                ipAddress,
                userAgent,
                operation: 'close-conversation',
                conversationId: request.conversationId,
                status: 'success',
            });
            this.emit('conversation-closed', {
                conversationId: request.conversationId,
                timestamp: Date.now(),
            });
            return { success: true };
        }
        catch (error) {
            const errorMsg = error instanceof Error ? error.message : String(error);
            return { success: false, error: errorMsg };
        }
    }
    summarizeConversation(request, ipAddress, userAgent) {
        try {
            const conversation = this.conversations.get(request.conversationId);
            if (!conversation) {
                throw new Error(`Conversation ${request.conversationId} not found`);
            }
            const turns = Array.from(conversation.turns.values());
            const aiTurns = turns.filter((t) => t.author.isAI);
            const userTurns = turns.filter((t) => !t.author.isAI);
            const summary = request.style === 'brief'
                ? `${conversation.topic || 'Untitled'}: ${turns.length} messages, ${conversation.participants.length} participants`
                : request.style === 'detailed'
                    ? `Conversation on ${conversation.topic || 'general'} with ${conversation.participants.length} participants. ${turns.length} total messages: ${userTurns.length} user, ${aiTurns.length} AI.`
                    : `Action items from conversation: 1. Review code changes 2. Test implementation 3. Document findings`;
            const keyPoints = turns
                .filter((t) => !t.author.isAI)
                .slice(-5)
                .map((t) => t.content.substring(0, 100));
            const actionItems = [];
            for (const turn of turns) {
                if (turn.content.toLowerCase().includes('todo') ||
                    turn.content.toLowerCase().includes('action') ||
                    turn.content.toLowerCase().includes('next')) {
                    actionItems.push(turn.content.substring(0, 150));
                }
            }
            return {
                success: true,
                summary,
                keyPoints,
                actionItems,
            };
        }
        catch (error) {
            const errorMsg = error instanceof Error ? error.message : String(error);
            return { success: false, error: errorMsg };
        }
    }
    exportConversation(request, ipAddress, userAgent) {
        try {
            const conversation = this.conversations.get(request.conversationId);
            if (!conversation) {
                throw new Error(`Conversation ${request.conversationId} not found`);
            }
            let content = '';
            if (request.format === 'markdown') {
                content += `# ${conversation.topic || 'Conversation'}\n\n`;
                content += `**Participants**: ${conversation.participants.map((p) => p.userName).join(', ')}\n`;
                content += `**Created**: ${new Date(conversation.createdAt).toISOString()}\n\n`;
                for (const turn of conversation.turns.values()) {
                    const author = turn.author.isAI ? `🤖 ${turn.author.userName}` : `👤 ${turn.author.userName}`;
                    content += `### ${author}\n`;
                    content += `${turn.content}\n\n`;
                }
            }
            else if (request.format === 'json') {
                const exportData = {
                    conversation: {
                        id: conversation.id,
                        topic: conversation.topic,
                        createdAt: conversation.createdAt,
                        updatedAt: conversation.updatedAt,
                        participants: conversation.participants,
                        turns: Array.from(conversation.turns.values()),
                    },
                };
                content = JSON.stringify(exportData, null, 2);
            }
            else if (request.format === 'pdf') {
                content = `PDF Export - ${conversation.topic || 'Conversation'}\n`;
                content += `Participants: ${conversation.participants.map((p) => p.userName).join(', ')}\n`;
                content += `Total turns: ${conversation.turns.size}\n`;
            }
            const documentId = `doc-${Date.now()}-${Math.random().toString(16).slice(2)}`;
            this.recordAudit({
                timestamp: Date.now(),
                userId: request.userId,
                userEmail: request.userEmail,
                ipAddress,
                userAgent,
                operation: 'export-conversation',
                conversationId: request.conversationId,
                status: 'success',
                details: { format: request.format, documentId },
            });
            this.emit('conversation-exported', {
                conversationId: request.conversationId,
                documentId,
                format: request.format,
                timestamp: Date.now(),
            });
            return {
                success: true,
                content,
                documentId,
            };
        }
        catch (error) {
            const errorMsg = error instanceof Error ? error.message : String(error);
            return { success: false, error: errorMsg };
        }
    }
    getAuditLog(userId, limit = 100) {
        const logs = this.auditLogs.get(userId) || [];
        return logs.slice(-limit);
    }
    getStatistics() {
        const conversations = Array.from(this.conversations.values());
        const totalTurns = conversations.reduce((sum, c) => sum + c.turns.size, 0);
        let totalTokensUsed = 0;
        let totalCost = 0;
        let totalResponseTime = 0;
        let responseCount = 0;
        conversations.forEach((conv) => {
            conv.turns.forEach((turn) => {
                if (turn.metadata) {
                    totalTokensUsed += turn.metadata.tokensUsed;
                    totalCost += turn.metadata.costInCredits;
                    totalResponseTime += turn.metadata.completionTime;
                    responseCount += 1;
                }
            });
        });
        const activeConversations = conversations.filter((c) => c.isActive).length;
        const totalParticipants = new Set(conversations.flatMap((c) => c.participants.map((p) => p.userId))).size;
        return {
            totalConversations: conversations.length,
            activeConversations,
            totalTurns,
            averageTurnsPerConversation: conversations.length > 0 ? totalTurns / conversations.length : 0,
            totalParticipants,
            averageParticipantsPerConversation: conversations.length > 0 ? totalParticipants / conversations.length : 0,
            totalAIResponses: responseCount,
            averageResponseTime: responseCount > 0 ? totalResponseTime / responseCount : 0,
            totalTokensUsed,
            averageCostPerConversation: conversations.length > 0 ? totalCost / conversations.length : 0,
            exportedConversations: 0,
        };
    }
    updateConfig(config, userId, ipAddress, userAgent) {
        Object.assign(this.config, config);
        this.recordAudit({
            timestamp: Date.now(),
            userId,
            userEmail: 'system@example.com',
            ipAddress,
            userAgent,
            operation: 'update-config',
            conversationId: '',
            status: 'success',
            details: { config },
        });
        this.emit('config-updated', { config: this.config, timestamp: Date.now() });
    }
    recordAudit(entry) {
        if (!this.auditLogs.has(entry.userId)) {
            this.auditLogs.set(entry.userId, []);
        }
        const logs = this.auditLogs.get(entry.userId);
        logs.push(entry);
        if (logs.length > this.config.maxAuditLogSize) {
            logs.splice(0, logs.length - this.config.maxAuditLogSize);
        }
        this.emit('audit-logged', { entry, timestamp: Date.now() });
    }
    shutdown() {
        this.conversations.clear();
        this.auditLogs.clear();
        this.subscribers.clear();
        this.participantActivity.clear();
        this.emit('shutdown', { timestamp: Date.now() });
    }
}
//# sourceMappingURL=shared-ai-context-service.js.map