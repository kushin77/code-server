/**
 * @file        apps/backend/src/services/inline-communication/__tests__/integration-example.test.ts
 * @module      collaboration/inline-communication
 * @description Integration tests for inline communication service
 * @owner       Collaboration Team
 * @status      Production - April 23, 2026
 */
import { describe, it, expect, beforeEach } from 'vitest';
import request from 'supertest';
import InlineCommunicationService from '../index';
import { createInlineCommunicationExampleApp } from '../integration-example';
describe('InlineCommunicationService', () => {
    let service;
    beforeEach(() => {
        service = InlineCommunicationService.getInstance();
        service.clearAllThreads();
    });
    describe('Thread Creation', () => {
        it('should create a new comment thread', () => {
            const location = {
                filePath: 'src/main.ts',
                startLine: 10,
                endLine: 20,
                functionName: 'processRequest',
            };
            const thread = service.createThread(location, 'session-1', 'user-1', 'Alice', 'This needs optimization');
            expect(thread).toBeDefined();
            expect(thread.id).toBeTruthy();
            expect(thread.codeLocation).toEqual(location);
            expect(thread.sessionId).toBe('session-1');
            expect(thread.createdBy).toBe('user-1');
            expect(thread.comments).toHaveLength(1);
            expect(thread.comments[0].content).toBe('This needs optimization');
            expect(thread.resolved).toBe(false);
            expect(thread.status).toBe('active');
        });
        it('should extract mentions from initial comment', () => {
            const location = {
                filePath: 'src/api.ts',
                startLine: 50,
                endLine: 60,
            };
            const thread = service.createThread(location, 'session-1', 'user-1', 'Alice', '@bob @carol this needs review');
            expect(thread.comments[0].mentions).toContain('bob');
            expect(thread.comments[0].mentions).toContain('carol');
        });
        it('should emit thread-created event', () => {
            const location = {
                filePath: 'src/test.ts',
                startLine: 1,
                endLine: 5,
            };
            let emittedThread = null;
            service.on('thread-created', (thread) => {
                emittedThread = thread;
            });
            service.createThread(location, 'session-1', 'user-1', 'Alice', 'Test');
            expect(emittedThread).not.toBeNull();
            expect(emittedThread?.codeLocation).toEqual(location);
        });
    });
    describe('Comment Management', () => {
        let threadId;
        let location;
        beforeEach(() => {
            location = {
                filePath: 'src/handler.ts',
                startLine: 100,
                endLine: 120,
                functionName: 'handleRequest',
            };
            const thread = service.createThread(location, 'session-1', 'user-1', 'Alice', 'Initial comment');
            threadId = thread.id;
        });
        it('should add comment to thread', () => {
            const comment = service.addComment(threadId, 'user-2', 'Bob', 'I agree with this');
            expect(comment).toBeDefined();
            expect(comment?.authorId).toBe('user-2');
            expect(comment?.authorName).toBe('Bob');
            expect(comment?.content).toBe('I agree with this');
            const thread = service.getThread(threadId);
            expect(thread.comments).toHaveLength(2);
        });
        it('should extract mentions from added comment', () => {
            const comment = service.addComment(threadId, 'user-2', 'Bob', '@alice @dave need feedback');
            expect(comment?.mentions).toContain('alice');
            expect(comment?.mentions).toContain('dave');
        });
        it('should emit comment-added event', () => {
            let emittedEvent = null;
            service.on('comment-added', (event) => {
                emittedEvent = event;
            });
            service.addComment(threadId, 'user-2', 'Bob', 'Comment');
            expect(emittedEvent).not.toBeNull();
            expect(emittedEvent.threadId).toBe(threadId);
        });
        it('should return null for non-existent thread', () => {
            const comment = service.addComment('fake-id', 'user-2', 'Bob', 'Comment');
            expect(comment).toBeNull();
        });
        it('should update comment content', () => {
            const comment = service.addComment(threadId, 'user-2', 'Bob', 'Old content');
            const commentId = comment.id;
            const updated = service.updateComment(threadId, commentId, 'New content');
            expect(updated?.content).toBe('New content');
            expect(updated?.updatedAt).toBeDefined();
        });
        it('should emit comment-updated event', () => {
            const comment = service.addComment(threadId, 'user-2', 'Bob', 'Content');
            let emittedEvent = null;
            service.on('comment-updated', (event) => {
                emittedEvent = event;
            });
            service.updateComment(threadId, comment.id, 'Updated');
            expect(emittedEvent).not.toBeNull();
        });
    });
    describe('Thread Resolution', () => {
        let threadId;
        beforeEach(() => {
            const location = {
                filePath: 'src/resolve-test.ts',
                startLine: 1,
                endLine: 10,
            };
            const thread = service.createThread(location, 'session-1', 'user-1', 'Alice', 'Needs fixing');
            threadId = thread.id;
        });
        it('should resolve a thread', () => {
            const resolved = service.resolveThread(threadId, 'user-1');
            expect(resolved).not.toBeNull();
            expect(resolved?.resolved).toBe(true);
            expect(resolved?.resolvedBy).toBe('user-1');
            expect(resolved?.resolvedAt).toBeDefined();
            expect(resolved?.status).toBe('resolved');
        });
        it('should emit thread-resolved event', () => {
            let emittedThread = null;
            service.on('thread-resolved', (thread) => {
                emittedThread = thread;
            });
            service.resolveThread(threadId, 'user-1');
            expect(emittedThread).not.toBeNull();
            expect(emittedThread?.resolved).toBe(true);
        });
        it('should unresolve a thread', () => {
            service.resolveThread(threadId, 'user-1');
            const unresolved = service.unresolveThread(threadId);
            expect(unresolved?.resolved).toBe(false);
            expect(unresolved?.resolvedBy).toBeUndefined();
            expect(unresolved?.status).toBe('active');
        });
        it('should emit thread-unresolved event', () => {
            service.resolveThread(threadId, 'user-1');
            let emittedThread = null;
            service.on('thread-unresolved', (thread) => {
                emittedThread = thread;
            });
            service.unresolveThread(threadId);
            expect(emittedThread).not.toBeNull();
            expect(emittedThread?.resolved).toBe(false);
        });
        it('should archive thread when resolved', () => {
            service.resolveThread(threadId, 'user-1');
            const stats = service.getThreadStatistics();
            expect(stats.archived).toBe(1);
        });
    });
    describe('Thread Retrieval', () => {
        beforeEach(() => {
            const location1 = {
                filePath: 'src/file1.ts',
                startLine: 10,
                endLine: 20,
                functionName: 'func1',
            };
            const location2 = {
                filePath: 'src/file1.ts',
                startLine: 30,
                endLine: 40,
                functionName: 'func2',
            };
            const location3 = {
                filePath: 'src/file2.ts',
                startLine: 50,
                endLine: 60,
            };
            service.createThread(location1, 'session-1', 'user-1', 'Alice', 'Thread 1');
            service.createThread(location2, 'session-1', 'user-2', 'Bob', 'Thread 2');
            service.createThread(location3, 'session-1', 'user-1', 'Alice', 'Thread 3');
        });
        it('should get threads at specific location', () => {
            const location = {
                filePath: 'src/file1.ts',
                startLine: 10,
                endLine: 20,
                functionName: 'func1',
            };
            const threads = service.getThreadsForLocation(location);
            expect(threads).toHaveLength(1);
        });
        it('should get all threads in file', () => {
            const threads = service.getThreadsInFile('src/file1.ts');
            expect(threads).toHaveLength(2);
            const threads2 = service.getThreadsInFile('src/file2.ts');
            expect(threads2).toHaveLength(1);
        });
        it('should get all threads', () => {
            const threads = service.getAllThreads();
            expect(threads).toHaveLength(3);
        });
        it('should get thread by ID', () => {
            const allThreads = service.getAllThreads();
            const threadId = allThreads[0].id;
            const thread = service.getThread(threadId);
            expect(thread).not.toBeNull();
            expect(thread?.id).toBe(threadId);
        });
        it('should return null for non-existent thread ID', () => {
            const thread = service.getThread('fake-id');
            expect(thread).toBeNull();
        });
    });
    describe('Code Refactoring', () => {
        it('should relocate threads when code refactors', () => {
            const oldLocation = {
                filePath: 'src/old.ts',
                startLine: 10,
                endLine: 20,
                functionName: 'oldFunc',
            };
            const newLocation = {
                filePath: 'src/new.ts',
                startLine: 50,
                endLine: 60,
                functionName: 'newFunc',
            };
            service.createThread(oldLocation, 'session-1', 'user-1', 'Alice', 'Comment');
            const updated = service.handleCodeRefactor(oldLocation, newLocation);
            expect(updated).toBe(1);
            const threads = service.getThreadsForLocation(newLocation);
            expect(threads).toHaveLength(1);
        });
        it('should emit threads-relocated event', () => {
            const oldLocation = {
                filePath: 'src/old.ts',
                startLine: 1,
                endLine: 10,
            };
            const newLocation = {
                filePath: 'src/new.ts',
                startLine: 20,
                endLine: 30,
            };
            service.createThread(oldLocation, 'session-1', 'user-1', 'Alice', 'Test');
            let emittedEvent = null;
            service.on('threads-relocated', (event) => {
                emittedEvent = event;
            });
            service.handleCodeRefactor(oldLocation, newLocation);
            expect(emittedEvent).not.toBeNull();
            expect(emittedEvent.count).toBe(1);
        });
    });
    describe('Statistics', () => {
        beforeEach(() => {
            service.clearAllThreads();
            // Create 3 threads
            for (let i = 0; i < 3; i++) {
                const location = {
                    filePath: 'src/stats.ts',
                    startLine: i * 10,
                    endLine: i * 10 + 10,
                };
                service.createThread(location, 'session-1', 'user-1', 'Alice', 'Thread ' + i);
            }
            // Add comments to first thread
            const firstThread = service.getAllThreads()[0];
            service.addComment(firstThread.id, 'user-2', 'Bob', 'Reply 1');
            service.addComment(firstThread.id, 'user-3', 'Carol', 'Reply 2');
            // Resolve one thread
            service.resolveThread(service.getAllThreads()[1].id, 'user-1');
        });
        it('should get thread statistics', () => {
            const stats = service.getThreadStatistics();
            expect(stats.total).toBe(3);
            expect(stats.active).toBe(2);
            expect(stats.resolved).toBe(1);
            expect(stats.archived).toBe(1);
            expect(stats.averageCommentCount).toBeGreaterThan(0);
        });
        it('should get user statistics', () => {
            const userStats = service.getUserStatistics('user-1');
            expect(userStats.threadsCreated).toBe(3);
            expect(userStats.threadsResolved).toBe(1);
            expect(userStats.commentsAdded).toBeGreaterThanOrEqual(3);
        });
        it('should count mentions in user statistics', () => {
            service.clearAllThreads(); // Clear before this specific test
            const location = {
                filePath: 'src/mentions.ts',
                startLine: 1,
                endLine: 10,
            };
            const thread = service.createThread(location, 'session-1', 'user-1', 'Alice', '@user-2 check this');
            service.addComment(thread.id, 'user-3', 'Carol', '@user-2 agreed');
            const userStats = service.getUserStatistics('user-2');
            expect(userStats.mentions).toBe(2);
        });
    });
    describe('Search', () => {
        beforeEach(() => {
            const location1 = {
                filePath: 'src/search1.ts',
                startLine: 1,
                endLine: 10,
            };
            const location2 = {
                filePath: 'src/search2.ts',
                startLine: 20,
                endLine: 30,
            };
            const thread1 = service.createThread(location1, 'session-1', 'user-1', 'Alice', 'Bug in authentication');
            const thread2 = service.createThread(location2, 'session-1', 'user-2', 'Bob', 'Performance issue');
            service.addComment(thread1.id, 'user-2', 'Bob', 'Need to fix authentication');
            service.addComment(thread2.id, 'user-1', 'Alice', 'Different performance bug');
        });
        it('should search threads by content', () => {
            const results = service.searchThreads('authentication');
            expect(results.length).toBeGreaterThanOrEqual(1);
            expect(results[0].comments.some((c) => c.content.includes('authentication'))).toBe(true);
        });
        it('should search across all comments', () => {
            const results = service.searchThreads('authentication');
            expect(results.length).toBeGreaterThanOrEqual(1);
        });
        it('should return empty for no matches', () => {
            const results = service.searchThreads('nonexistent_word_xyz');
            expect(results).toHaveLength(0);
        });
    });
    describe('Export/Import', () => {
        beforeEach(() => {
            const location = {
                filePath: 'src/export.ts',
                startLine: 1,
                endLine: 10,
            };
            const thread = service.createThread(location, 'session-1', 'user-1', 'Alice', 'Test');
            service.addComment(thread.id, 'user-2', 'Bob', 'Comment');
        });
        it('should export threads', () => {
            const exported = service.exportThreads();
            expect(exported).toHaveLength(1);
            expect(exported[0].comments).toHaveLength(2);
        });
        it('should import threads', () => {
            const exported = service.exportThreads();
            service.clearAllThreads();
            const count = service.importThreads(exported);
            expect(count).toBe(1);
            const imported = service.getAllThreads();
            expect(imported).toHaveLength(1);
            expect(imported[0].comments).toHaveLength(2);
        });
    });
});
describe('InlineCommunicationService Express Integration', () => {
    let app;
    beforeEach(() => {
        // Clear service state before each test
        const service = InlineCommunicationService.getInstance();
        service.clearAllThreads();
        app = createInlineCommunicationExampleApp();
    });
    describe('REST API Endpoints', () => {
        it('should create thread via POST /threads', async () => {
            const response = await request(app)
                .post('/api/inline-communication/threads')
                .send({
                codeLocation: {
                    filePath: 'src/main.ts',
                    startLine: 10,
                    endLine: 20,
                    functionName: 'processData',
                },
                sessionId: 'session-1',
                authorId: 'user-1',
                authorName: 'Alice',
                comment: 'Needs optimization',
            });
            expect(response.status).toBe(201);
            expect(response.body.id).toBeDefined();
            expect(response.body.comments).toHaveLength(1);
        });
        it('should get thread via GET /threads/:threadId', async () => {
            // Create a thread first
            const createRes = await request(app)
                .post('/api/inline-communication/threads')
                .send({
                codeLocation: { filePath: 'src/test.ts', startLine: 1, endLine: 5 },
                sessionId: 'session-1',
                authorId: 'user-1',
                authorName: 'Alice',
                comment: 'Test',
            });
            const threadId = createRes.body.id;
            // Get the thread
            const getRes = await request(app).get(`/api/inline-communication/threads/${threadId}`);
            expect(getRes.status).toBe(200);
            expect(getRes.body.id).toBe(threadId);
        });
        it('should add comment via POST /threads/:threadId/comments', async () => {
            // Create thread
            const createRes = await request(app)
                .post('/api/inline-communication/threads')
                .send({
                codeLocation: { filePath: 'src/api.ts', startLine: 10, endLine: 20 },
                sessionId: 'session-1',
                authorId: 'user-1',
                authorName: 'Alice',
                comment: 'Initial',
            });
            const threadId = createRes.body.id;
            // Add comment
            const commentRes = await request(app)
                .post(`/api/inline-communication/threads/${threadId}/comments`)
                .send({
                authorId: 'user-2',
                authorName: 'Bob',
                content: 'I agree',
            });
            expect(commentRes.status).toBe(201);
            expect(commentRes.body.content).toBe('I agree');
        });
        it('should resolve thread via POST /threads/:threadId/resolve', async () => {
            // Create and resolve
            const createRes = await request(app)
                .post('/api/inline-communication/threads')
                .send({
                codeLocation: { filePath: 'src/resolve.ts', startLine: 1, endLine: 10 },
                sessionId: 'session-1',
                authorId: 'user-1',
                authorName: 'Alice',
                comment: 'Fix this',
            });
            const threadId = createRes.body.id;
            const resolveRes = await request(app)
                .post(`/api/inline-communication/threads/${threadId}/resolve`)
                .send({ resolvedBy: 'user-1' });
            expect(resolveRes.status).toBe(200);
            expect(resolveRes.body.resolved).toBe(true);
        });
        it('should get statistics via GET /statistics', async () => {
            // Clear service state first
            const service = InlineCommunicationService.getInstance();
            service.clearAllThreads();
            // Create a thread first
            await request(app)
                .post('/api/inline-communication/threads')
                .send({
                codeLocation: { filePath: 'src/stats.ts', startLine: 1, endLine: 10 },
                sessionId: 'session-1',
                authorId: 'user-1',
                authorName: 'Alice',
                comment: 'Test',
            });
            const statsRes = await request(app).get('/api/inline-communication/statistics');
            expect(statsRes.status).toBe(200);
            expect(statsRes.body.total).toBe(1);
            expect(statsRes.body.active).toBe(1);
        });
        it('should search threads via GET /search', async () => {
            // Create thread
            await request(app)
                .post('/api/inline-communication/threads')
                .send({
                codeLocation: { filePath: 'src/search.ts', startLine: 1, endLine: 10 },
                sessionId: 'session-1',
                authorId: 'user-1',
                authorName: 'Alice',
                comment: 'Database performance issue',
            });
            const searchRes = await request(app).get('/api/inline-communication/search?query=database');
            expect(searchRes.status).toBe(200);
            expect(searchRes.body.length).toBeGreaterThan(0);
        });
        it('should handle missing required fields', async () => {
            const response = await request(app)
                .post('/api/inline-communication/threads')
                .send({
                // Missing required fields
                codeLocation: { filePath: 'src/test.ts', startLine: 1, endLine: 5 },
            });
            expect(response.status).toBe(400);
            expect(response.body.error).toBeDefined();
        });
        it('should return 404 for non-existent thread', async () => {
            const response = await request(app).get('/api/inline-communication/threads/fake-id');
            expect(response.status).toBe(404);
            expect(response.body.error).toBeDefined();
        });
    });
});
//# sourceMappingURL=integration-example.test.js.map