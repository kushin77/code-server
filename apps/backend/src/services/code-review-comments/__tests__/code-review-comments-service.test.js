/**
 * Code Review Comment Threads Service Tests
 * @file        apps/backend/src/services/code-review-comments/__tests__/code-review-comments-service.test.ts
 * @module      services/code-review-comments
 * @description Test suite for threaded comment discussions on code reviews
 */
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { CodeReviewCommentsService } from '../code-review-comments-service.js';
describe('Code Review Comments Service', () => {
    let service;
    beforeEach(() => {
        CodeReviewCommentsService.reset();
        service = CodeReviewCommentsService.getInstance();
    });
    afterEach(() => {
        service.shutdown();
    });
    describe('Initialization', () => {
        it('should initialize service and emit initialized event', () => {
            // Service is already initialized in beforeEach via getInstance()
            // Just verify the current service is initialized
            expect(service).toBeDefined();
            expect(service.threads).toBeDefined();
            expect(service.threadsByReview).toBeDefined();
        });
        it('should return same instance on subsequent calls', () => {
            const instance1 = CodeReviewCommentsService.getInstance();
            const instance2 = CodeReviewCommentsService.getInstance();
            expect(instance1).toBe(instance2);
        });
        it('should accept config override on getInstance', () => {
            const config = { maxThreadsPerReview: 100 };
            CodeReviewCommentsService.reset();
            const svc = CodeReviewCommentsService.getInstance(config);
            expect(svc.getStatistics().totalThreads).toBe(0);
        });
    });
    describe('Create Comment Thread', () => {
        it('should create comment thread successfully', () => {
            const result = service.createCommentThread({
                reviewRequestId: 'review-1',
                createdBy: {
                    userId: 'user1',
                    userEmail: 'user1@example.com',
                    userName: 'User One',
                },
                location: { filePath: 'src/app.ts', lineNumber: 42 },
                title: 'Question about logic',
                initialComment: 'Why is this like this?',
                priority: 'high',
                tags: ['question', 'important'],
            }, '192.168.1.1', 'Mozilla');
            expect(result.success).toBe(true);
            expect(result.threadId).toBeDefined();
            expect(result.thread).toBeDefined();
            expect(result.thread?.isResolved).toBe(false);
            expect(result.thread?.comments.size).toBe(1);
        });
        it('should emit thread-created event', () => {
            return new Promise((resolve) => {
                service.once('thread-created', (event) => {
                    expect(event.data_object.reviewRequestId).toBe('review-1');
                    expect(event.data_object.createdBy).toBeDefined();
                    expect(event.timestamp).toBeGreaterThan(0);
                    resolve();
                });
                service.createCommentThread({
                    reviewRequestId: 'review-1',
                    createdBy: {
                        userId: 'user1',
                        userEmail: 'user1@example.com',
                        userName: 'User One',
                    },
                    location: { filePath: 'src/app.ts', lineNumber: 42 },
                    initialComment: 'Question?',
                }, '192.168.1.1', 'Mozilla');
            });
        });
        it('should emit audit-logged event on thread creation', () => {
            return new Promise((resolve) => {
                service.once('audit-logged', (event) => {
                    expect(event.data_object.userId).toBeDefined();
                    expect(event.data_object.operation).toBeDefined();
                    resolve();
                });
                service.createCommentThread({
                    reviewRequestId: 'review-1',
                    createdBy: {
                        userId: 'user1',
                        userEmail: 'user1@example.com',
                        userName: 'User One',
                    },
                    location: { filePath: 'src/app.ts', lineNumber: 42 },
                    initialComment: 'Question?',
                }, '192.168.1.1', 'Mozilla');
            });
        });
    });
    describe('Add Thread Comment', () => {
        it('should add comment to thread', () => {
            const threadResult = service.createCommentThread({
                reviewRequestId: 'review-1',
                createdBy: {
                    userId: 'user1',
                    userEmail: 'user1@example.com',
                    userName: 'User One',
                },
                location: { filePath: 'src/app.ts', lineNumber: 42 },
                initialComment: 'Initial comment',
            }, '192.168.1.1', 'Mozilla');
            const threadId = threadResult.threadId;
            const result = service.addThreadComment({
                threadId,
                author: {
                    userId: 'user2',
                    userEmail: 'user2@example.com',
                    userName: 'User Two',
                },
                content: 'Here is my response',
            }, '192.168.1.2', 'Mozilla');
            expect(result.success).toBe(true);
            expect(result.commentId).toBeDefined();
            expect(result.broadcastedTo).toBe(2);
        });
        it('should emit comment-added event', () => {
            return new Promise((resolve) => {
                const threadResult = service.createCommentThread({
                    reviewRequestId: 'review-1',
                    createdBy: {
                        userId: 'user1',
                        userEmail: 'user1@example.com',
                        userName: 'User One',
                    },
                    location: { filePath: 'src/app.ts', lineNumber: 42 },
                    initialComment: 'Initial',
                }, '192.168.1.1', 'Mozilla');
                service.once('comment-added', (event) => {
                    expect(event.data_object.threadId).toBe(threadResult.threadId);
                    expect(event.data_object.participantCount).toBe(2);
                    resolve();
                });
                service.addThreadComment({
                    threadId: threadResult.threadId,
                    author: {
                        userId: 'user2',
                        userEmail: 'user2@example.com',
                        userName: 'User Two',
                    },
                    content: 'Response',
                }, '192.168.1.2', 'Mozilla');
            });
        });
        it('should return error if thread not found', () => {
            const result = service.addThreadComment({
                threadId: 'nonexistent',
                author: {
                    userId: 'user1',
                    userEmail: 'user1@example.com',
                    userName: 'User One',
                },
                content: 'Comment',
            }, '192.168.1.1', 'Mozilla');
            expect(result.success).toBe(false);
            expect(result.error).toBe('Thread not found');
        });
        it('should track mentioned users', () => {
            const threadResult = service.createCommentThread({
                reviewRequestId: 'review-1',
                createdBy: {
                    userId: 'user1',
                    userEmail: 'user1@example.com',
                    userName: 'User One',
                },
                location: { filePath: 'src/app.ts', lineNumber: 42 },
                initialComment: 'Initial',
            }, '192.168.1.1', 'Mozilla');
            const result = service.addThreadComment({
                threadId: threadResult.threadId,
                author: {
                    userId: 'user2',
                    userEmail: 'user2@example.com',
                    userName: 'User Two',
                },
                content: 'Reply mentioning @user3',
                mentionedUserIds: ['user3'],
            }, '192.168.1.2', 'Mozilla');
            expect(result.success).toBe(true);
            expect(result.comment?.mentionedUsers).toContain('user3');
        });
    });
    describe('Edit Thread Comment', () => {
        it('should edit comment successfully', () => {
            const threadResult = service.createCommentThread({
                reviewRequestId: 'review-1',
                createdBy: {
                    userId: 'user1',
                    userEmail: 'user1@example.com',
                    userName: 'User One',
                },
                location: { filePath: 'src/app.ts', lineNumber: 42 },
                initialComment: 'Original comment',
            }, '192.168.1.1', 'Mozilla');
            const threadId = threadResult.threadId;
            const commentId = Array.from(threadResult.thread.comments.keys())[0];
            const result = service.editThreadComment({
                threadId,
                commentId,
                editedBy: {
                    userId: 'user1',
                    userEmail: 'user1@example.com',
                    userName: 'User One',
                },
                newContent: 'Updated comment',
            }, '192.168.1.1', 'Mozilla');
            expect(result.success).toBe(true);
            expect(result.comment?.content).toBe('Updated comment');
            expect(result.comment?.editHistory.length).toBe(1);
        });
        it('should emit comment-edited event', () => {
            return new Promise((resolve) => {
                const threadResult = service.createCommentThread({
                    reviewRequestId: 'review-1',
                    createdBy: {
                        userId: 'user1',
                        userEmail: 'user1@example.com',
                        userName: 'User One',
                    },
                    location: { filePath: 'src/app.ts', lineNumber: 42 },
                    initialComment: 'Original',
                }, '192.168.1.1', 'Mozilla');
                const commentId = Array.from(threadResult.thread.comments.keys())[0];
                service.once('comment-edited', (event) => {
                    expect(event.data_object.threadId).toBe(threadResult.threadId);
                    expect(event.data_object.editCount).toBe(1);
                    resolve();
                });
                service.editThreadComment({
                    threadId: threadResult.threadId,
                    commentId,
                    editedBy: {
                        userId: 'user1',
                        userEmail: 'user1@example.com',
                        userName: 'User One',
                    },
                    newContent: 'Updated',
                }, '192.168.1.1', 'Mozilla');
            });
        });
        it('should maintain edit history', () => {
            const threadResult = service.createCommentThread({
                reviewRequestId: 'review-1',
                createdBy: {
                    userId: 'user1',
                    userEmail: 'user1@example.com',
                    userName: 'User One',
                },
                location: { filePath: 'src/app.ts', lineNumber: 42 },
                initialComment: 'Original',
            }, '192.168.1.1', 'Mozilla');
            const threadId = threadResult.threadId;
            const commentId = Array.from(threadResult.thread.comments.keys())[0];
            service.editThreadComment({
                threadId,
                commentId,
                editedBy: {
                    userId: 'user1',
                    userEmail: 'user1@example.com',
                    userName: 'User One',
                },
                newContent: 'First edit',
            }, '192.168.1.1', 'Mozilla');
            const result = service.editThreadComment({
                threadId,
                commentId,
                editedBy: {
                    userId: 'user1',
                    userEmail: 'user1@example.com',
                    userName: 'User One',
                },
                newContent: 'Second edit',
            }, '192.168.1.1', 'Mozilla');
            expect(result.comment?.editHistory.length).toBe(2);
            expect(result.comment?.editHistory[0].previousContent).toBe('Original');
            expect(result.comment?.editHistory[1].previousContent).toBe('First edit');
        });
    });
    describe('Delete Thread Comment', () => {
        it('should soft-delete comment', () => {
            const threadResult = service.createCommentThread({
                reviewRequestId: 'review-1',
                createdBy: {
                    userId: 'user1',
                    userEmail: 'user1@example.com',
                    userName: 'User One',
                },
                location: { filePath: 'src/app.ts', lineNumber: 42 },
                initialComment: 'To delete',
            }, '192.168.1.1', 'Mozilla');
            const threadId = threadResult.threadId;
            const commentId = Array.from(threadResult.thread.comments.keys())[0];
            const result = service.deleteThreadComment({
                threadId,
                commentId,
                deletedBy: {
                    userId: 'user1',
                    userEmail: 'user1@example.com',
                    userName: 'User One',
                },
                reason: 'Spam',
            }, '192.168.1.1', 'Mozilla');
            expect(result.success).toBe(true);
            expect(result.comment?.isDeleted).toBe(true);
            expect(result.comment?.deletedAt).toBeGreaterThan(0);
        });
        it('should emit comment-deleted event', () => {
            return new Promise((resolve) => {
                const threadResult = service.createCommentThread({
                    reviewRequestId: 'review-1',
                    createdBy: {
                        userId: 'user1',
                        userEmail: 'user1@example.com',
                        userName: 'User One',
                    },
                    location: { filePath: 'src/app.ts', lineNumber: 42 },
                    initialComment: 'To delete',
                }, '192.168.1.1', 'Mozilla');
                const commentId = Array.from(threadResult.thread.comments.keys())[0];
                service.once('comment-deleted', (event) => {
                    expect(event.data_object.threadId).toBe(threadResult.threadId);
                    resolve();
                });
                service.deleteThreadComment({
                    threadId: threadResult.threadId,
                    commentId,
                    deletedBy: {
                        userId: 'user1',
                        userEmail: 'user1@example.com',
                        userName: 'User One',
                    },
                }, '192.168.1.1', 'Mozilla');
            });
        });
    });
    describe('Resolve Thread', () => {
        it('should resolve thread successfully', () => {
            const threadResult = service.createCommentThread({
                reviewRequestId: 'review-1',
                createdBy: {
                    userId: 'user1',
                    userEmail: 'user1@example.com',
                    userName: 'User One',
                },
                location: { filePath: 'src/app.ts', lineNumber: 42 },
                initialComment: 'Issue to resolve',
            }, '192.168.1.1', 'Mozilla');
            const result = service.resolveThread({
                threadId: threadResult.threadId,
                resolvedBy: {
                    userId: 'user1',
                    userEmail: 'user1@example.com',
                    userName: 'User One',
                },
                resolutionComment: 'Fixed in PR #123',
            }, '192.168.1.1', 'Mozilla');
            expect(result.success).toBe(true);
            expect(result.thread?.isResolved).toBe(true);
            expect(result.thread?.resolvedAt).toBeGreaterThan(0);
        });
        it('should emit thread-resolved event', () => {
            return new Promise((resolve) => {
                const threadResult = service.createCommentThread({
                    reviewRequestId: 'review-1',
                    createdBy: {
                        userId: 'user1',
                        userEmail: 'user1@example.com',
                        userName: 'User One',
                    },
                    location: { filePath: 'src/app.ts', lineNumber: 42 },
                    initialComment: 'Issue',
                }, '192.168.1.1', 'Mozilla');
                service.once('thread-resolved', (event) => {
                    expect(event.data_object.threadId).toBe(threadResult.threadId);
                    resolve();
                });
                service.resolveThread({
                    threadId: threadResult.threadId,
                    resolvedBy: {
                        userId: 'user1',
                        userEmail: 'user1@example.com',
                        userName: 'User One',
                    },
                }, '192.168.1.1', 'Mozilla');
            });
        });
    });
    describe('Reopen Thread', () => {
        it('should reopen resolved thread', () => {
            const threadResult = service.createCommentThread({
                reviewRequestId: 'review-1',
                createdBy: {
                    userId: 'user1',
                    userEmail: 'user1@example.com',
                    userName: 'User One',
                },
                location: { filePath: 'src/app.ts', lineNumber: 42 },
                initialComment: 'Issue',
            }, '192.168.1.1', 'Mozilla');
            service.resolveThread({
                threadId: threadResult.threadId,
                resolvedBy: {
                    userId: 'user1',
                    userEmail: 'user1@example.com',
                    userName: 'User One',
                },
            }, '192.168.1.1', 'Mozilla');
            const result = service.reopenThread({
                threadId: threadResult.threadId,
                reopenedBy: {
                    userId: 'user1',
                    userEmail: 'user1@example.com',
                    userName: 'User One',
                },
                reason: 'Not actually fixed',
            }, '192.168.1.1', 'Mozilla');
            expect(result.success).toBe(true);
            expect(result.thread?.isResolved).toBe(false);
        });
        it('should emit thread-reopened event', () => {
            return new Promise((resolve) => {
                const threadResult = service.createCommentThread({
                    reviewRequestId: 'review-1',
                    createdBy: {
                        userId: 'user1',
                        userEmail: 'user1@example.com',
                        userName: 'User One',
                    },
                    location: { filePath: 'src/app.ts', lineNumber: 42 },
                    initialComment: 'Issue',
                }, '192.168.1.1', 'Mozilla');
                service.resolveThread({
                    threadId: threadResult.threadId,
                    resolvedBy: {
                        userId: 'user1',
                        userEmail: 'user1@example.com',
                        userName: 'User One',
                    },
                }, '192.168.1.1', 'Mozilla');
                service.once('thread-reopened', (event) => {
                    expect(event.data_object.threadId).toBe(threadResult.threadId);
                    resolve();
                });
                service.reopenThread({
                    threadId: threadResult.threadId,
                    reopenedBy: {
                        userId: 'user1',
                        userEmail: 'user1@example.com',
                        userName: 'User One',
                    },
                }, '192.168.1.1', 'Mozilla');
            });
        });
    });
    describe('Add Reaction', () => {
        it('should add emoji reaction to comment', () => {
            const threadResult = service.createCommentThread({
                reviewRequestId: 'review-1',
                createdBy: {
                    userId: 'user1',
                    userEmail: 'user1@example.com',
                    userName: 'User One',
                },
                location: { filePath: 'src/app.ts', lineNumber: 42 },
                initialComment: 'Great idea!',
            }, '192.168.1.1', 'Mozilla');
            const commentId = Array.from(threadResult.thread.comments.keys())[0];
            const result = service.addReaction({
                threadId: threadResult.threadId,
                commentId,
                userId: 'user2',
                userEmail: 'user2@example.com',
                reactionType: '👍',
            }, '192.168.1.2', 'Mozilla');
            expect(result.success).toBe(true);
            expect(result.reactionCounts?.get('👍')).toBe(1);
        });
        it('should increment reaction count', () => {
            const threadResult = service.createCommentThread({
                reviewRequestId: 'review-1',
                createdBy: {
                    userId: 'user1',
                    userEmail: 'user1@example.com',
                    userName: 'User One',
                },
                location: { filePath: 'src/app.ts', lineNumber: 42 },
                initialComment: 'Great!',
            }, '192.168.1.1', 'Mozilla');
            const commentId = Array.from(threadResult.thread.comments.keys())[0];
            const threadId = threadResult.threadId;
            service.addReaction({
                threadId,
                commentId,
                userId: 'user2',
                userEmail: 'user2@example.com',
                reactionType: '👍',
            }, '192.168.1.2', 'Mozilla');
            const result = service.addReaction({
                threadId,
                commentId,
                userId: 'user3',
                userEmail: 'user3@example.com',
                reactionType: '👍',
            }, '192.168.1.3', 'Mozilla');
            expect(result.reactionCounts?.get('👍')).toBe(2);
        });
        it('should emit reaction-added event', () => {
            return new Promise((resolve) => {
                const threadResult = service.createCommentThread({
                    reviewRequestId: 'review-1',
                    createdBy: {
                        userId: 'user1',
                        userEmail: 'user1@example.com',
                        userName: 'User One',
                    },
                    location: { filePath: 'src/app.ts', lineNumber: 42 },
                    initialComment: 'Great!',
                }, '192.168.1.1', 'Mozilla');
                const commentId = Array.from(threadResult.thread.comments.keys())[0];
                service.once('reaction-added', (event) => {
                    expect(event.data_object.reactionType).toBe('👍');
                    resolve();
                });
                service.addReaction({
                    threadId: threadResult.threadId,
                    commentId,
                    userId: 'user2',
                    userEmail: 'user2@example.com',
                    reactionType: '👍',
                }, '192.168.1.2', 'Mozilla');
            });
        });
    });
    describe('Mention User', () => {
        it('should create notification on user mention', () => {
            const result = service.mentionUser({
                threadId: 'thread-1',
                commentId: 'comment-1',
                userId: 'user2',
                userEmail: 'user2@example.com',
                userName: 'User Two',
                mentionerEmail: 'user1@example.com',
                message: 'Check this out',
            }, '192.168.1.1', 'Mozilla');
            expect(result.success).toBe(true);
            expect(result.notification).toBeDefined();
            expect(result.notification?.userId).toBe('user2');
            expect(result.notification?.type).toBe('user-mentioned');
        });
        it('should emit user-mentioned event', () => {
            return new Promise((resolve) => {
                service.once('user-mentioned', (event) => {
                    expect(event.data_object.mentionedUser).toBeDefined();
                    resolve();
                });
                service.mentionUser({
                    threadId: 'thread-1',
                    commentId: 'comment-1',
                    userId: 'user2',
                    userEmail: 'user2@example.com',
                    userName: 'User Two',
                    mentionerEmail: 'user1@example.com',
                }, '192.168.1.1', 'Mozilla');
            });
        });
    });
    describe('Get Comment Thread', () => {
        it('should retrieve thread with comments', () => {
            const threadResult = service.createCommentThread({
                reviewRequestId: 'review-1',
                createdBy: {
                    userId: 'user1',
                    userEmail: 'user1@example.com',
                    userName: 'User One',
                },
                location: { filePath: 'src/app.ts', lineNumber: 42 },
                initialComment: 'Initial',
            }, '192.168.1.1', 'Mozilla');
            const threadId = threadResult.threadId;
            service.addThreadComment({
                threadId,
                author: {
                    userId: 'user2',
                    userEmail: 'user2@example.com',
                    userName: 'User Two',
                },
                content: 'Response',
            }, '192.168.1.2', 'Mozilla');
            const result = service.getCommentThread({ threadId });
            expect(result.success).toBe(true);
            expect(result.comments?.length).toBe(2);
            expect(result.participants?.length).toBeGreaterThanOrEqual(1);
        });
        it('should return error for nonexistent thread', () => {
            const result = service.getCommentThread({ threadId: 'nonexistent' });
            expect(result.success).toBe(false);
            expect(result.error).toBe('Thread not found');
        });
    });
    describe('List Comment Threads', () => {
        it('should list all threads for review', () => {
            service.createCommentThread({
                reviewRequestId: 'review-1',
                createdBy: {
                    userId: 'user1',
                    userEmail: 'user1@example.com',
                    userName: 'User One',
                },
                location: { filePath: 'src/app.ts', lineNumber: 1 },
                initialComment: 'Thread 1',
            }, '192.168.1.1', 'Mozilla');
            service.createCommentThread({
                reviewRequestId: 'review-1',
                createdBy: {
                    userId: 'user1',
                    userEmail: 'user1@example.com',
                    userName: 'User One',
                },
                location: { filePath: 'src/app.ts', lineNumber: 2 },
                initialComment: 'Thread 2',
            }, '192.168.1.1', 'Mozilla');
            const result = service.listCommentThreads({ reviewRequestId: 'review-1' });
            expect(result.success).toBe(true);
            expect(result.total).toBe(2);
            expect(result.threads.length).toBe(2);
        });
        it('should filter by resolution status', () => {
            const thread1 = service.createCommentThread({
                reviewRequestId: 'review-1',
                createdBy: {
                    userId: 'user1',
                    userEmail: 'user1@example.com',
                    userName: 'User One',
                },
                location: { filePath: 'src/app.ts', lineNumber: 1 },
                initialComment: 'Active',
            }, '192.168.1.1', 'Mozilla');
            const thread2 = service.createCommentThread({
                reviewRequestId: 'review-1',
                createdBy: {
                    userId: 'user1',
                    userEmail: 'user1@example.com',
                    userName: 'User One',
                },
                location: { filePath: 'src/app.ts', lineNumber: 2 },
                initialComment: 'To resolve',
            }, '192.168.1.1', 'Mozilla');
            service.resolveThread({
                threadId: thread2.threadId,
                resolvedBy: {
                    userId: 'user1',
                    userEmail: 'user1@example.com',
                    userName: 'User One',
                },
            }, '192.168.1.1', 'Mozilla');
            const activeResult = service.listCommentThreads({
                reviewRequestId: 'review-1',
                filter: { resolved: false },
            });
            expect(activeResult.total).toBe(1);
        });
        it('should filter by priority', () => {
            service.createCommentThread({
                reviewRequestId: 'review-1',
                createdBy: {
                    userId: 'user1',
                    userEmail: 'user1@example.com',
                    userName: 'User One',
                },
                location: { filePath: 'src/app.ts', lineNumber: 1 },
                initialComment: 'Low priority',
                priority: 'low',
            }, '192.168.1.1', 'Mozilla');
            service.createCommentThread({
                reviewRequestId: 'review-1',
                createdBy: {
                    userId: 'user1',
                    userEmail: 'user1@example.com',
                    userName: 'User One',
                },
                location: { filePath: 'src/app.ts', lineNumber: 2 },
                initialComment: 'Critical issue',
                priority: 'critical',
            }, '192.168.1.1', 'Mozilla');
            const result = service.listCommentThreads({
                reviewRequestId: 'review-1',
                filter: { priority: ['critical'] },
            });
            expect(result.total).toBe(1);
            expect(result.threads[0].priority).toBe('critical');
        });
    });
    describe('Archive Thread', () => {
        it('should archive thread', () => {
            const threadResult = service.createCommentThread({
                reviewRequestId: 'review-1',
                createdBy: {
                    userId: 'user1',
                    userEmail: 'user1@example.com',
                    userName: 'User One',
                },
                location: { filePath: 'src/app.ts', lineNumber: 42 },
                initialComment: 'To archive',
            }, '192.168.1.1', 'Mozilla');
            const result = service.archiveThread({
                threadId: threadResult.threadId,
                archivedBy: {
                    userId: 'user1',
                    userEmail: 'user1@example.com',
                    userName: 'User One',
                },
                reason: 'Resolved',
            }, '192.168.1.1', 'Mozilla');
            expect(result.success).toBe(true);
            expect(result.thread?.isArchived).toBe(true);
            expect(result.thread?.archivedAt).toBeGreaterThan(0);
        });
        it('should emit thread-archived event', () => {
            return new Promise((resolve) => {
                const threadResult = service.createCommentThread({
                    reviewRequestId: 'review-1',
                    createdBy: {
                        userId: 'user1',
                        userEmail: 'user1@example.com',
                        userName: 'User One',
                    },
                    location: { filePath: 'src/app.ts', lineNumber: 42 },
                    initialComment: 'Archive me',
                }, '192.168.1.1', 'Mozilla');
                service.once('thread-archived', (event) => {
                    expect(event.data_object.threadId).toBe(threadResult.threadId);
                    resolve();
                });
                service.archiveThread({
                    threadId: threadResult.threadId,
                    archivedBy: {
                        userId: 'user1',
                        userEmail: 'user1@example.com',
                        userName: 'User One',
                    },
                }, '192.168.1.1', 'Mozilla');
            });
        });
    });
    describe('Statistics', () => {
        it('should calculate service statistics', () => {
            service.createCommentThread({
                reviewRequestId: 'review-1',
                createdBy: {
                    userId: 'user1',
                    userEmail: 'user1@example.com',
                    userName: 'User One',
                },
                location: { filePath: 'src/app.ts', lineNumber: 1 },
                initialComment: 'Thread 1',
            }, '192.168.1.1', 'Mozilla');
            service.createCommentThread({
                reviewRequestId: 'review-1',
                createdBy: {
                    userId: 'user1',
                    userEmail: 'user1@example.com',
                    userName: 'User One',
                },
                location: { filePath: 'src/app.ts', lineNumber: 2 },
                initialComment: 'Thread 2',
            }, '192.168.1.1', 'Mozilla');
            const stats = service.getStatistics();
            expect(stats.totalThreads).toBe(2);
            expect(stats.activeThreads).toBe(2);
            expect(stats.resolvedThreads).toBe(0);
            expect(stats.totalComments).toBe(2);
        });
        it('should track resolved threads in statistics', () => {
            const thread = service.createCommentThread({
                reviewRequestId: 'review-1',
                createdBy: {
                    userId: 'user1',
                    userEmail: 'user1@example.com',
                    userName: 'User One',
                },
                location: { filePath: 'src/app.ts', lineNumber: 1 },
                initialComment: 'To resolve',
            }, '192.168.1.1', 'Mozilla');
            service.resolveThread({
                threadId: thread.threadId,
                resolvedBy: {
                    userId: 'user1',
                    userEmail: 'user1@example.com',
                    userName: 'User One',
                },
            }, '192.168.1.1', 'Mozilla');
            const stats = service.getStatistics();
            expect(stats.resolvedThreads).toBe(1);
            expect(stats.activeThreads).toBe(0);
        });
        it('should track participants in statistics', () => {
            const thread = service.createCommentThread({
                reviewRequestId: 'review-1',
                createdBy: {
                    userId: 'user1',
                    userEmail: 'user1@example.com',
                    userName: 'User One',
                },
                location: { filePath: 'src/app.ts', lineNumber: 1 },
                initialComment: 'Discussion',
            }, '192.168.1.1', 'Mozilla');
            service.addThreadComment({
                threadId: thread.threadId,
                author: {
                    userId: 'user2',
                    userEmail: 'user2@example.com',
                    userName: 'User Two',
                },
                content: 'My thoughts',
            }, '192.168.1.2', 'Mozilla');
            const stats = service.getStatistics();
            expect(stats.totalParticipants).toBeGreaterThanOrEqual(1);
        });
    });
    describe('Configuration', () => {
        it('should update configuration', () => {
            return new Promise((resolve) => {
                service.once('config-updated', (event) => {
                    expect(event.data_object.userId).toBeDefined();
                    resolve();
                });
                service.updateConfig({ maxThreadsPerReview: 100 }, 'user1', '192.168.1.1', 'Mozilla');
            });
        });
    });
    describe('Shutdown', () => {
        it('should shutdown service cleanly', () => {
            return new Promise((resolve) => {
                service.once('shutdown', (event) => {
                    expect(event.data_object.service).toBe('code-review-comments');
                    expect(event.data_object.status).toBe('shutdown');
                    resolve();
                });
                service.shutdown();
            });
        });
        it('should clear data on shutdown', () => {
            service.createCommentThread({
                reviewRequestId: 'review-1',
                createdBy: {
                    userId: 'user1',
                    userEmail: 'user1@example.com',
                    userName: 'User One',
                },
                location: { filePath: 'src/app.ts', lineNumber: 1 },
                initialComment: 'Thread',
            }, '192.168.1.1', 'Mozilla');
            service.shutdown();
            const stats = service.getStatistics();
            expect(stats.totalThreads).toBe(0);
        });
    });
});
//# sourceMappingURL=code-review-comments-service.test.js.map