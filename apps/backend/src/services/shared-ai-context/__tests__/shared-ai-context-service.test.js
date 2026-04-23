/**
 * Shared AI Copilot Context Service Tests
 */
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { SharedAICopilotContextService } from '../shared-ai-context-service.js';
describe('SharedAICopilotContextService', () => {
    let service;
    beforeEach(() => {
        SharedAICopilotContextService.reset();
        service = SharedAICopilotContextService.getInstance();
    });
    afterEach(() => {
        service.shutdown();
    });
    describe('Initialization', () => {
        it('should create singleton instance', () => {
            const instance1 = SharedAICopilotContextService.getInstance();
            const instance2 = SharedAICopilotContextService.getInstance();
            expect(instance1).toBe(instance2);
        });
        it('should emit initialized event', () => {
            SharedAICopilotContextService.reset();
            const svc = SharedAICopilotContextService.getInstance();
            expect(svc).toBeDefined();
        });
    });
    describe('Conversation Creation', () => {
        it('should start shared conversation', () => {
            const result = service.startSharedConversation({
                userId: 'user-1',
                userEmail: 'user1@example.com',
                userName: 'Alice',
                workspaceId: 'ws-1',
                sessionId: 'session-1',
                visibility: 'private',
                topic: 'Authentication flow',
            }, '192.168.1.1', 'Mozilla/5.0');
            expect(result.success).toBe(true);
            expect(result.conversationId).toBeDefined();
            expect(result.conversation).toBeDefined();
            expect(result.conversation?.topic).toBe('Authentication flow');
        });
        it('should emit conversation-started event', () => {
            return new Promise((resolve) => {
                service.once('conversation-started', (data) => {
                    expect(data.conversation).toBeDefined();
                    expect(data.conversation.topic).toBe('Database design');
                    resolve();
                });
                service.startSharedConversation({
                    userId: 'user-2',
                    userEmail: 'user2@example.com',
                    userName: 'Bob',
                    workspaceId: 'ws-2',
                    sessionId: 'session-2',
                    visibility: 'team',
                    topic: 'Database design',
                }, '192.168.1.1', 'Mozilla/5.0');
            });
        });
        it('should include initial message in conversation', () => {
            const result = service.startSharedConversation({
                userId: 'user-3',
                userEmail: 'user3@example.com',
                userName: 'Charlie',
                workspaceId: 'ws-3',
                sessionId: 'session-3',
                visibility: 'private',
                initialMessage: 'How should we structure this API?',
            }, '192.168.1.1', 'Mozilla/5.0');
            expect(result.conversation?.turns.size).toBe(1);
            const turns = Array.from(result.conversation.turns.values());
            expect(turns[0].content).toBe('How should we structure this API?');
        });
        it('should generate unique conversation IDs', () => {
            const result1 = service.startSharedConversation({
                userId: 'user-4',
                userEmail: 'user4@example.com',
                userName: 'David',
                workspaceId: 'ws-4',
                sessionId: 'session-4',
                visibility: 'public',
            }, '192.168.1.1', 'Mozilla/5.0');
            const result2 = service.startSharedConversation({
                userId: 'user-5',
                userEmail: 'user5@example.com',
                userName: 'Eve',
                workspaceId: 'ws-4',
                sessionId: 'session-5',
                visibility: 'public',
            }, '192.168.1.1', 'Mozilla/5.0');
            expect(result1.conversationId).not.toBe(result2.conversationId);
        });
    });
    describe('Adding Conversation Turns', () => {
        it('should add turn to conversation', () => {
            const startResult = service.startSharedConversation({
                userId: 'user-6',
                userEmail: 'user6@example.com',
                userName: 'Frank',
                workspaceId: 'ws-6',
                sessionId: 'session-6',
                visibility: 'private',
            }, '192.168.1.1', 'Mozilla/5.0');
            const turnResult = service.addConversationTurn({
                conversationId: startResult.conversationId,
                userId: 'user-6',
                userEmail: 'user6@example.com',
                userName: 'Frank',
                isAI: false,
                content: 'Let me think about this',
            }, '192.168.1.1', 'Mozilla/5.0');
            expect(turnResult.success).toBe(true);
            expect(turnResult.turnId).toBeDefined();
            expect(turnResult.turn?.content).toBe('Let me think about this');
        });
        it('should emit turn-added event', () => {
            return new Promise((resolve) => {
                const startResult = service.startSharedConversation({
                    userId: 'user-7',
                    userEmail: 'user7@example.com',
                    userName: 'Grace',
                    workspaceId: 'ws-7',
                    sessionId: 'session-7',
                    visibility: 'private',
                }, '192.168.1.1', 'Mozilla/5.0');
                service.once('turn-added', (data) => {
                    expect(data.turn).toBeDefined();
                    expect(data.turn.author.isAI).toBe(true);
                    resolve();
                });
                service.addConversationTurn({
                    conversationId: startResult.conversationId,
                    userId: 'ai-bot',
                    userEmail: 'ai@example.com',
                    userName: 'AI Assistant',
                    isAI: true,
                    content: 'Consider using microservices architecture',
                    model: 'gpt-4',
                    temperature: 0.7,
                    maxTokens: 2048,
                    tokensUsed: 150,
                    completionTime: 450,
                    costInCredits: 0.003,
                }, '192.168.1.1', 'Mozilla/5.0');
            });
        });
        it('should track tokens used in AI turns', () => {
            const startResult = service.startSharedConversation({
                userId: 'user-8',
                userEmail: 'user8@example.com',
                userName: 'Henry',
                workspaceId: 'ws-8',
                sessionId: 'session-8',
                visibility: 'private',
            }, '192.168.1.1', 'Mozilla/5.0');
            const turnResult = service.addConversationTurn({
                conversationId: startResult.conversationId,
                userId: 'ai-bot',
                userEmail: 'ai@example.com',
                userName: 'AI',
                isAI: true,
                content: 'Response text',
                model: 'gpt-4',
                tokensUsed: 250,
                costInCredits: 0.005,
            }, '192.168.1.1', 'Mozilla/5.0');
            expect(turnResult.turn?.metadata?.tokensUsed).toBe(250);
            expect(turnResult.turn?.metadata?.costInCredits).toBe(0.005);
        });
        it('should track participant activity', () => {
            const startResult = service.startSharedConversation({
                userId: 'user-9',
                userEmail: 'user9@example.com',
                userName: 'Ivy',
                workspaceId: 'ws-9',
                sessionId: 'session-9',
                visibility: 'private',
            }, '192.168.1.1', 'Mozilla/5.0');
            service.addConversationTurn({
                conversationId: startResult.conversationId,
                userId: 'user-9',
                userEmail: 'user9@example.com',
                userName: 'Ivy',
                isAI: false,
                content: 'First message',
            }, '192.168.1.1', 'Mozilla/5.0');
            const conv = service.getConversation({
                conversationId: startResult.conversationId,
            });
            expect(conv.conversation?.participants.length).toBeGreaterThan(0);
        });
    });
    describe('Editing Conversation Turns', () => {
        it('should edit turn content', () => {
            const startResult = service.startSharedConversation({
                userId: 'user-10',
                userEmail: 'user10@example.com',
                userName: 'Jack',
                workspaceId: 'ws-10',
                sessionId: 'session-10',
                visibility: 'private',
            }, '192.168.1.1', 'Mozilla/5.0');
            const turnResult = service.addConversationTurn({
                conversationId: startResult.conversationId,
                userId: 'user-10',
                userEmail: 'user10@example.com',
                userName: 'Jack',
                isAI: false,
                content: 'Original content',
            }, '192.168.1.1', 'Mozilla/5.0');
            const editResult = service.editConversationTurn({
                conversationId: startResult.conversationId,
                turnId: turnResult.turnId,
                userId: 'user-10',
                userEmail: 'user10@example.com',
                userName: 'Jack',
                newContent: 'Updated content',
            }, '192.168.1.1', 'Mozilla/5.0');
            expect(editResult.success).toBe(true);
            expect(editResult.turn?.content).toBe('Updated content');
            expect(editResult.turn?.editHistory).toBeDefined();
            expect(editResult.turn?.editHistory?.length).toBe(1);
        });
        it('should emit turn-edited event', () => {
            return new Promise((resolve) => {
                const startResult = service.startSharedConversation({
                    userId: 'user-11',
                    userEmail: 'user11@example.com',
                    userName: 'Karen',
                    workspaceId: 'ws-11',
                    sessionId: 'session-11',
                    visibility: 'private',
                }, '192.168.1.1', 'Mozilla/5.0');
                const turnResult = service.addConversationTurn({
                    conversationId: startResult.conversationId,
                    userId: 'user-11',
                    userEmail: 'user11@example.com',
                    userName: 'Karen',
                    isAI: false,
                    content: 'Initial message',
                }, '192.168.1.1', 'Mozilla/5.0');
                service.once('turn-edited', (data) => {
                    expect(data.turn.id).toBe(turnResult.turnId);
                    resolve();
                });
                service.editConversationTurn({
                    conversationId: startResult.conversationId,
                    turnId: turnResult.turnId,
                    userId: 'user-11',
                    userEmail: 'user11@example.com',
                    userName: 'Karen',
                    newContent: 'Revised message',
                }, '192.168.1.1', 'Mozilla/5.0');
            });
        });
    });
    describe('Resolving Conversation Turns', () => {
        it('should resolve turn', () => {
            const startResult = service.startSharedConversation({
                userId: 'user-12',
                userEmail: 'user12@example.com',
                userName: 'Leo',
                workspaceId: 'ws-12',
                sessionId: 'session-12',
                visibility: 'private',
            }, '192.168.1.1', 'Mozilla/5.0');
            const turnResult = service.addConversationTurn({
                conversationId: startResult.conversationId,
                userId: 'user-12',
                userEmail: 'user12@example.com',
                userName: 'Leo',
                isAI: false,
                content: 'Question about the design',
            }, '192.168.1.1', 'Mozilla/5.0');
            const resolveResult = service.resolveConversationTurn({
                conversationId: startResult.conversationId,
                turnId: turnResult.turnId,
                userId: 'user-12',
                userEmail: 'user12@example.com',
            }, '192.168.1.1', 'Mozilla/5.0');
            expect(resolveResult.success).toBe(true);
            const conv = service.getConversation({
                conversationId: startResult.conversationId,
            });
            const turn = Array.from(conv.conversation.turns.values()).find((t) => t.id === turnResult.turnId);
            expect(turn?.isResolved).toBe(true);
        });
        it('should emit turn-resolved event', () => {
            return new Promise((resolve) => {
                const startResult = service.startSharedConversation({
                    userId: 'user-13',
                    userEmail: 'user13@example.com',
                    userName: 'Maria',
                    workspaceId: 'ws-13',
                    sessionId: 'session-13',
                    visibility: 'private',
                }, '192.168.1.1', 'Mozilla/5.0');
                const turnResult = service.addConversationTurn({
                    conversationId: startResult.conversationId,
                    userId: 'user-13',
                    userEmail: 'user13@example.com',
                    userName: 'Maria',
                    isAI: false,
                    content: 'Need clarification',
                }, '192.168.1.1', 'Mozilla/5.0');
                service.once('turn-resolved', (data) => {
                    expect(data.turnId).toBe(turnResult.turnId);
                    resolve();
                });
                service.resolveConversationTurn({
                    conversationId: startResult.conversationId,
                    turnId: turnResult.turnId,
                    userId: 'user-13',
                    userEmail: 'user13@example.com',
                }, '192.168.1.1', 'Mozilla/5.0');
            });
        });
    });
    describe('Context Injection', () => {
        it('should inject context to Copilot', () => {
            const startResult = service.startSharedConversation({
                userId: 'user-14',
                userEmail: 'user14@example.com',
                userName: 'Noah',
                workspaceId: 'ws-14',
                sessionId: 'session-14',
                visibility: 'private',
            }, '192.168.1.1', 'Mozilla/5.0');
            service.addConversationTurn({
                conversationId: startResult.conversationId,
                userId: 'user-14',
                userEmail: 'user14@example.com',
                userName: 'Noah',
                isAI: false,
                content: 'First question',
            }, '192.168.1.1', 'Mozilla/5.0');
            const injectResult = service.injectContextToCopilot({
                conversationId: startResult.conversationId,
                userId: 'user-14',
                userEmail: 'user14@example.com',
            }, '192.168.1.1', 'Mozilla/5.0');
            expect(injectResult.success).toBe(true);
            expect(injectResult.contextId).toBeDefined();
            expect(injectResult.injection).toBeDefined();
            expect(injectResult.tokenEstimate).toBeGreaterThan(0);
        });
        it('should emit context-injected event', () => {
            return new Promise((resolve) => {
                const startResult = service.startSharedConversation({
                    userId: 'user-15',
                    userEmail: 'user15@example.com',
                    userName: 'Olivia',
                    workspaceId: 'ws-15',
                    sessionId: 'session-15',
                    visibility: 'private',
                }, '192.168.1.1', 'Mozilla/5.0');
                service.once('context-injected', (data) => {
                    expect(data.contextId).toBeDefined();
                    expect(data.tokenEstimate).toBeGreaterThanOrEqual(0);
                    resolve();
                });
                service.injectContextToCopilot({
                    conversationId: startResult.conversationId,
                    userId: 'user-15',
                    userEmail: 'user15@example.com',
                }, '192.168.1.1', 'Mozilla/5.0');
            });
        });
    });
    describe('Conversation Retrieval', () => {
        it('should get conversation', () => {
            const startResult = service.startSharedConversation({
                userId: 'user-16',
                userEmail: 'user16@example.com',
                userName: 'Peter',
                workspaceId: 'ws-16',
                sessionId: 'session-16',
                visibility: 'private',
            }, '192.168.1.1', 'Mozilla/5.0');
            const getResult = service.getConversation({
                conversationId: startResult.conversationId,
            });
            expect(getResult.success).toBe(true);
            expect(getResult.conversation).toBeDefined();
            expect(getResult.participants).toBeDefined();
        });
        it('should list conversations', () => {
            service.startSharedConversation({
                userId: 'user-17',
                userEmail: 'user17@example.com',
                userName: 'Quinn',
                workspaceId: 'ws-17',
                sessionId: 'session-17',
                visibility: 'public',
            }, '192.168.1.1', 'Mozilla/5.0');
            const listResult = service.listConversations({
                userId: 'user-17',
                userEmail: 'user17@example.com',
            });
            expect(listResult.success).toBe(true);
            expect(listResult.conversations).toBeDefined();
            expect(listResult.count).toBeGreaterThan(0);
        });
    });
    describe('Subscription Management', () => {
        it('should subscribe to conversation', () => {
            const startResult = service.startSharedConversation({
                userId: 'user-18',
                userEmail: 'user18@example.com',
                userName: 'Rachel',
                workspaceId: 'ws-18',
                sessionId: 'session-18',
                visibility: 'private',
            }, '192.168.1.1', 'Mozilla/5.0');
            const subResult = service.subscribeConversation({
                userId: 'user-19',
                userEmail: 'user19@example.com',
                conversationId: startResult.conversationId,
            }, '192.168.1.1', 'Mozilla/5.0');
            expect(subResult.success).toBe(true);
        });
        it('should unsubscribe from conversation', () => {
            const startResult = service.startSharedConversation({
                userId: 'user-20',
                userEmail: 'user20@example.com',
                userName: 'Samuel',
                workspaceId: 'ws-20',
                sessionId: 'session-20',
                visibility: 'private',
            }, '192.168.1.1', 'Mozilla/5.0');
            service.subscribeConversation({
                userId: 'user-20',
                userEmail: 'user20@example.com',
                conversationId: startResult.conversationId,
            }, '192.168.1.1', 'Mozilla/5.0');
            const unsubResult = service.unsubscribeConversation({
                userId: 'user-20',
                userEmail: 'user20@example.com',
                conversationId: startResult.conversationId,
            });
            expect(unsubResult.success).toBe(true);
        });
    });
    describe('Conversation Closing', () => {
        it('should close conversation', () => {
            const startResult = service.startSharedConversation({
                userId: 'user-21',
                userEmail: 'user21@example.com',
                userName: 'Tina',
                workspaceId: 'ws-21',
                sessionId: 'session-21',
                visibility: 'private',
            }, '192.168.1.1', 'Mozilla/5.0');
            const closeResult = service.closeConversation({
                userId: 'user-21',
                userEmail: 'user21@example.com',
                conversationId: startResult.conversationId,
            }, '192.168.1.1', 'Mozilla/5.0');
            expect(closeResult.success).toBe(true);
            const conv = service.getConversation({
                conversationId: startResult.conversationId,
            });
            expect(conv.conversation?.isActive).toBe(false);
        });
        it('should emit conversation-closed event', () => {
            return new Promise((resolve) => {
                const startResult = service.startSharedConversation({
                    userId: 'user-22',
                    userEmail: 'user22@example.com',
                    userName: 'Ulysses',
                    workspaceId: 'ws-22',
                    sessionId: 'session-22',
                    visibility: 'private',
                }, '192.168.1.1', 'Mozilla/5.0');
                service.once('conversation-closed', (data) => {
                    expect(data.conversationId).toBe(startResult.conversationId);
                    resolve();
                });
                service.closeConversation({
                    userId: 'user-22',
                    userEmail: 'user22@example.com',
                    conversationId: startResult.conversationId,
                }, '192.168.1.1', 'Mozilla/5.0');
            });
        });
    });
    describe('Summarization', () => {
        it('should summarize conversation', () => {
            const startResult = service.startSharedConversation({
                userId: 'user-23',
                userEmail: 'user23@example.com',
                userName: 'Violet',
                workspaceId: 'ws-23',
                sessionId: 'session-23',
                visibility: 'private',
                topic: 'API design',
            }, '192.168.1.1', 'Mozilla/5.0');
            service.addConversationTurn({
                conversationId: startResult.conversationId,
                userId: 'user-23',
                userEmail: 'user23@example.com',
                userName: 'Violet',
                isAI: false,
                content: 'How should we handle error codes?',
            }, '192.168.1.1', 'Mozilla/5.0');
            const summaryResult = service.summarizeConversation({
                conversationId: startResult.conversationId,
                userId: 'user-23',
                userEmail: 'user23@example.com',
                style: 'detailed',
            }, '192.168.1.1', 'Mozilla/5.0');
            expect(summaryResult.success).toBe(true);
            expect(summaryResult.summary).toBeDefined();
        });
    });
    describe('Export', () => {
        it('should export conversation as markdown', () => {
            const startResult = service.startSharedConversation({
                userId: 'user-24',
                userEmail: 'user24@example.com',
                userName: 'Walter',
                workspaceId: 'ws-24',
                sessionId: 'session-24',
                visibility: 'private',
                topic: 'Testing strategy',
            }, '192.168.1.1', 'Mozilla/5.0');
            const exportResult = service.exportConversation({
                conversationId: startResult.conversationId,
                userId: 'user-24',
                userEmail: 'user24@example.com',
                format: 'markdown',
            }, '192.168.1.1', 'Mozilla/5.0');
            expect(exportResult.success).toBe(true);
            expect(exportResult.content).toBeDefined();
            expect(exportResult.documentId).toBeDefined();
        });
        it('should export conversation as JSON', () => {
            const startResult = service.startSharedConversation({
                userId: 'user-25',
                userEmail: 'user25@example.com',
                userName: 'Xander',
                workspaceId: 'ws-25',
                sessionId: 'session-25',
                visibility: 'private',
            }, '192.168.1.1', 'Mozilla/5.0');
            const exportResult = service.exportConversation({
                conversationId: startResult.conversationId,
                userId: 'user-25',
                userEmail: 'user25@example.com',
                format: 'json',
            }, '192.168.1.1', 'Mozilla/5.0');
            expect(exportResult.success).toBe(true);
            expect(exportResult.content).toContain('conversation');
        });
    });
    describe('Audit Logging', () => {
        it('should record audit entry', () => {
            service.startSharedConversation({
                userId: 'user-26',
                userEmail: 'user26@example.com',
                userName: 'Yvonne',
                workspaceId: 'ws-26',
                sessionId: 'session-26',
                visibility: 'private',
            }, '192.168.1.1', 'Mozilla/5.0');
            const audit = service.getAuditLog('user-26');
            expect(audit.length).toBeGreaterThan(0);
            expect(audit[0].operation).toBe('start-conversation');
        });
        it('should emit audit-logged event', () => {
            return new Promise((resolve) => {
                service.once('audit-logged', (data) => {
                    expect(data.entry).toBeDefined();
                    resolve();
                });
                service.startSharedConversation({
                    userId: 'user-27',
                    userEmail: 'user27@example.com',
                    userName: 'Zoe',
                    workspaceId: 'ws-27',
                    sessionId: 'session-27',
                    visibility: 'private',
                }, '192.168.1.1', 'Mozilla/5.0');
            });
        });
    });
    describe('Statistics', () => {
        it('should get service statistics', () => {
            service.startSharedConversation({
                userId: 'user-28',
                userEmail: 'user28@example.com',
                userName: 'Aaron',
                workspaceId: 'ws-28',
                sessionId: 'session-28',
                visibility: 'private',
            }, '192.168.1.1', 'Mozilla/5.0');
            const stats = service.getStatistics();
            expect(stats.totalConversations).toBeGreaterThan(0);
            expect(stats.activeConversations).toBeGreaterThanOrEqual(0);
        });
    });
    describe('Configuration', () => {
        it('should update configuration', () => {
            service.updateConfig({ maxConversationsPerSession: 100 }, 'user-29', '192.168.1.1', 'Mozilla/5.0');
            expect(service['config'].maxConversationsPerSession).toBe(100);
        });
        it('should emit config-updated event', () => {
            return new Promise((resolve) => {
                service.once('config-updated', (data) => {
                    expect(data.config).toBeDefined();
                    resolve();
                });
                service.updateConfig({ maxTurnsPerConversation: 1000 }, 'user-30', '192.168.1.1', 'Mozilla/5.0');
            });
        });
    });
    describe('Shutdown', () => {
        it('should shutdown service', () => {
            const result = service.startSharedConversation({
                userId: 'user-31',
                userEmail: 'user31@example.com',
                userName: 'Bella',
                workspaceId: 'ws-31',
                sessionId: 'session-31',
                visibility: 'private',
            }, '192.168.1.1', 'Mozilla/5.0');
            service.shutdown();
            const getResult = service.getConversation({
                conversationId: result.conversationId,
            });
            expect(getResult.success).toBe(false);
        });
        it('should emit shutdown event', () => {
            return new Promise((resolve) => {
                service.once('shutdown', (data) => {
                    expect(data.timestamp).toBeDefined();
                    resolve();
                });
                service.shutdown();
            });
        });
    });
});
//# sourceMappingURL=shared-ai-context-service.test.js.map