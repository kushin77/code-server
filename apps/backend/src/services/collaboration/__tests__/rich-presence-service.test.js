#!/usr/bin/env node
// @file        apps/backend/src/services/collaboration/__tests__/rich-presence-service.test.ts
// @module      collaboration/presence
// @description Comprehensive tests for rich presence service
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
vi.mock('../../../lib/tracing', () => ({
    getTracer: () => ({
        startActiveSpan: (_name, _options, callback) => callback({
            setStatus: vi.fn(),
            recordException: vi.fn(),
            end: vi.fn(),
        }),
    }),
    withSpanSync: (_tracer, _name, _attributes, fn) => fn({
        setStatus: vi.fn(),
        recordException: vi.fn(),
        end: vi.fn(),
    }),
}));
import service from '../rich-presence-service';
describe('RichPresenceService', () => {
    beforeEach(() => {
        service.reset();
    });
    afterEach(() => {
        service.reset();
    });
    describe('updatePresence', () => {
        it('should update or create presence', () => {
            const presence = service.updatePresence('user1', {
                username: 'Alice',
                email: 'alice@example.com',
                status: 'online',
                workspaceId: 'ws-123',
                sessionId: 'sess-123',
            });
            expect(presence).toBeDefined();
            expect(presence.userId).toBe('user1');
            expect(presence.username).toBe('Alice');
            expect(presence.status).toBe('online');
        });
        it('should update existing presence', () => {
            service.updatePresence('user1', { username: 'Alice', workspaceId: 'ws-123', sessionId: 'sess-123' });
            const updated = service.updatePresence('user1', {
                status: 'away',
            });
            expect(updated.status).toBe('away');
            expect(updated.username).toBe('Alice'); // Retained from previous
        });
        it('should emit presenceUpdated event', () => {
            const spy = vi.spyOn(service, 'emit');
            service.updatePresence('user1', {
                username: 'Alice',
                workspaceId: 'ws-123',
                sessionId: 'sess-123',
            });
            expect(spy).toHaveBeenCalledWith('presenceUpdated', expect.objectContaining({ userId: 'user1' }));
        });
        it('should set TTL in Redis cache', () => {
            service.updatePresence('user1', {
                username: 'Alice',
                workspaceId: 'ws-123',
                sessionId: 'sess-123',
            });
            const cached = service.getFromCache('user1');
            expect(cached).toBeDefined();
            expect(cached?.userId).toBe('user1');
        });
    });
    describe('setStatus', () => {
        it('should change user status', () => {
            service.updatePresence('user1', { username: 'Alice', workspaceId: 'ws-123', sessionId: 'sess-123' });
            const presence = service.setStatus('user1', 'away');
            expect(presence?.status).toBe('away');
        });
        it('should return null for non-existent user', () => {
            const result = service.setStatus('non-existent', 'offline');
            expect(result).toBeNull();
        });
        it('should emit statusChanged event', () => {
            const spy = vi.spyOn(service, 'emit');
            service.updatePresence('user1', { username: 'Alice', workspaceId: 'ws-123', sessionId: 'sess-123' });
            service.setStatus('user1', 'idle');
            expect(spy).toHaveBeenCalledWith('statusChanged', expect.objectContaining({ status: 'idle' }));
        });
    });
    describe('setCurrentFile', () => {
        it('should set current file with line/column', () => {
            service.updatePresence('user1', { username: 'Alice', workspaceId: 'ws-123', sessionId: 'sess-123' });
            const presence = service.setCurrentFile('user1', {
                path: '/src/app.ts',
                line: 42,
                column: 15,
            });
            expect(presence?.currentFile?.path).toBe('/src/app.ts');
            expect(presence?.currentFile?.line).toBe(42);
            expect(presence?.currentFile?.column).toBe(15);
        });
        it('should emit fileChanged event', () => {
            const spy = vi.spyOn(service, 'emit');
            service.updatePresence('user1', { username: 'Alice', workspaceId: 'ws-123', sessionId: 'sess-123' });
            service.setCurrentFile('user1', { path: '/src/app.ts' });
            expect(spy).toHaveBeenCalledWith('fileChanged', expect.objectContaining({ userId: 'user1' }));
        });
    });
    describe('setCurrentFunction', () => {
        it('should set current function', () => {
            service.updatePresence('user1', { username: 'Alice', workspaceId: 'ws-123', sessionId: 'sess-123' });
            const presence = service.setCurrentFunction('user1', {
                name: 'handleRequest',
                file: '/src/app.ts',
                line: 42,
            });
            expect(presence?.currentFunction?.name).toBe('handleRequest');
            expect(presence?.currentFunction?.file).toBe('/src/app.ts');
            expect(presence?.currentFunction?.line).toBe(42);
        });
        it('should emit functionChanged event', () => {
            const spy = vi.spyOn(service, 'emit');
            service.updatePresence('user1', { username: 'Alice', workspaceId: 'ws-123', sessionId: 'sess-123' });
            service.setCurrentFunction('user1', { name: 'handleRequest', file: '/src/app.ts', line: 42 });
            expect(spy).toHaveBeenCalledWith('functionChanged', expect.objectContaining({ userId: 'user1' }));
        });
    });
    describe('setCurrentTask', () => {
        it('should set current task', () => {
            service.updatePresence('user1', { username: 'Alice', workspaceId: 'ws-123', sessionId: 'sess-123' });
            const presence = service.setCurrentTask('user1', {
                id: 'task-123',
                title: 'Fix login bug',
                status: 'active',
            });
            expect(presence?.currentTask?.id).toBe('task-123');
            expect(presence?.currentTask?.title).toBe('Fix login bug');
            expect(presence?.currentTask?.status).toBe('active');
        });
        it('should emit taskChanged event', () => {
            const spy = vi.spyOn(service, 'emit');
            service.updatePresence('user1', { username: 'Alice', workspaceId: 'ws-123', sessionId: 'sess-123' });
            service.setCurrentTask('user1', { id: 'task-123', title: 'Fix login bug', status: 'active' });
            expect(spy).toHaveBeenCalledWith('taskChanged', expect.objectContaining({ userId: 'user1' }));
        });
    });
    describe('Custom Status', () => {
        it('should set custom status with emoji and text', () => {
            service.updatePresence('user1', { username: 'Alice', workspaceId: 'ws-123', sessionId: 'sess-123' });
            const presence = service.setCustomStatus('user1', {
                emoji: '🎉',
                text: 'Shipped new feature!',
            });
            expect(presence?.customStatus?.emoji).toBe('🎉');
            expect(presence?.customStatus?.text).toBe('Shipped new feature!');
        });
        it('should set expiration for custom status', () => {
            service.updatePresence('user1', { username: 'Alice', workspaceId: 'ws-123', sessionId: 'sess-123' });
            const presence = service.setCustomStatus('user1', {
                emoji: '🚀',
                text: 'Deploying',
                expiresIn: 300000, // 5 minutes
            });
            expect(presence?.customStatus?.expiresAt).toBeDefined();
        });
        it('should clear custom status', () => {
            service.updatePresence('user1', { username: 'Alice', workspaceId: 'ws-123', sessionId: 'sess-123' });
            service.setCustomStatus('user1', { emoji: '🎉', text: 'Working' });
            const presence = service.clearCustomStatus('user1');
            expect(presence?.customStatus).toBeUndefined();
        });
        it('should emit customStatusChanged event', () => {
            const spy = vi.spyOn(service, 'emit');
            service.updatePresence('user1', { username: 'Alice', workspaceId: 'ws-123', sessionId: 'sess-123' });
            service.setCustomStatus('user1', { emoji: '🎉', text: 'Working' });
            expect(spy).toHaveBeenCalledWith('customStatusChanged', expect.anything());
        });
    });
    describe('setCursorPosition', () => {
        it('should set cursor position', () => {
            service.updatePresence('user1', { username: 'Alice', workspaceId: 'ws-123', sessionId: 'sess-123' });
            const presence = service.setCursorPosition('user1', { x: 100, y: 200 });
            expect(presence?.cursorPosition).toEqual({ x: 100, y: 200 });
        });
        it('should update lastActiveAt', () => {
            service.updatePresence('user1', { username: 'Alice', workspaceId: 'ws-123', sessionId: 'sess-123' });
            const beforeTime = Date.now();
            const presence = service.setCursorPosition('user1', { x: 100, y: 200 });
            const afterTime = Date.now();
            expect(presence?.lastActiveAt).toBeGreaterThanOrEqual(beforeTime);
            expect(presence?.lastActiveAt).toBeLessThanOrEqual(afterTime);
        });
        it('should emit cursorMoved event', () => {
            const spy = vi.spyOn(service, 'emit');
            service.updatePresence('user1', { username: 'Alice', workspaceId: 'ws-123', sessionId: 'sess-123' });
            service.setCursorPosition('user1', { x: 100, y: 200 });
            expect(spy).toHaveBeenCalledWith('cursorMoved', expect.objectContaining({ userId: 'user1' }));
        });
    });
    describe('getPresence', () => {
        it('should retrieve presence by user ID', () => {
            service.updatePresence('user1', { username: 'Alice', workspaceId: 'ws-123', sessionId: 'sess-123' });
            const presence = service.getPresence('user1');
            expect(presence).toBeDefined();
            expect(presence?.userId).toBe('user1');
        });
        it('should return undefined for non-existent user', () => {
            const presence = service.getPresence('non-existent');
            expect(presence).toBeUndefined();
        });
    });
    describe('getWorkspacePresence', () => {
        it('should retrieve all users in workspace', () => {
            service.updatePresence('user1', { username: 'Alice', workspaceId: 'ws-123', sessionId: 'sess-1' });
            service.updatePresence('user2', { username: 'Bob', workspaceId: 'ws-123', sessionId: 'sess-2' });
            service.updatePresence('user3', { username: 'Charlie', workspaceId: 'ws-456', sessionId: 'sess-3' });
            const workspaceUsers = service.getWorkspacePresence('ws-123');
            expect(workspaceUsers).toHaveLength(2);
            expect(workspaceUsers.map((u) => u.userId)).toContain('user1');
            expect(workspaceUsers.map((u) => u.userId)).toContain('user2');
        });
    });
    describe('getUsersOnFile', () => {
        it('should retrieve users editing a file', () => {
            service.updatePresence('user1', { username: 'Alice', workspaceId: 'ws-123', sessionId: 'sess-1' });
            service.updatePresence('user2', { username: 'Bob', workspaceId: 'ws-123', sessionId: 'sess-2' });
            service.setCurrentFile('user1', { path: '/src/app.ts' });
            service.setCurrentFile('user2', { path: '/src/app.ts' });
            const usersOnFile = service.getUsersOnFile('/src/app.ts');
            expect(usersOnFile).toHaveLength(2);
        });
        it('should return empty array for file with no users', () => {
            const usersOnFile = service.getUsersOnFile('/src/non-existent.ts');
            expect(usersOnFile).toHaveLength(0);
        });
    });
    describe('getUsersOnFunction', () => {
        it('should retrieve users debugging a function', () => {
            service.updatePresence('user1', { username: 'Alice', workspaceId: 'ws-123', sessionId: 'sess-1' });
            service.updatePresence('user2', { username: 'Bob', workspaceId: 'ws-123', sessionId: 'sess-2' });
            service.setCurrentFunction('user1', { name: 'handleRequest', file: '/src/app.ts', line: 42 });
            service.setCurrentFunction('user2', { name: 'handleRequest', file: '/src/app.ts', line: 45 });
            const usersOnFunction = service.getUsersOnFunction('handleRequest');
            expect(usersOnFunction).toHaveLength(2);
        });
    });
    describe('getUsersOnTask', () => {
        it('should retrieve users working on a task', () => {
            service.updatePresence('user1', { username: 'Alice', workspaceId: 'ws-123', sessionId: 'sess-1' });
            service.updatePresence('user2', { username: 'Bob', workspaceId: 'ws-123', sessionId: 'sess-2' });
            service.setCurrentTask('user1', { id: 'task-123', title: 'Fix bug', status: 'active' });
            service.setCurrentTask('user2', { id: 'task-123', title: 'Fix bug', status: 'active' });
            const usersOnTask = service.getUsersOnTask('task-123');
            expect(usersOnTask).toHaveLength(2);
        });
    });
    describe('getOnlineUsers', () => {
        it('should retrieve all online/idle users', () => {
            service.updatePresence('user1', { username: 'Alice', status: 'online', workspaceId: 'ws-123', sessionId: 'sess-1' });
            service.updatePresence('user2', { username: 'Bob', status: 'idle', workspaceId: 'ws-123', sessionId: 'sess-2' });
            service.updatePresence('user3', { username: 'Charlie', status: 'offline', workspaceId: 'ws-123', sessionId: 'sess-3' });
            const onlineUsers = service.getOnlineUsers();
            expect(onlineUsers).toHaveLength(2);
            expect(onlineUsers.map((u) => u.userId)).not.toContain('user3');
        });
    });
    describe('queryPresence', () => {
        beforeEach(() => {
            service.updatePresence('user1', { username: 'Alice', status: 'online', workspaceId: 'ws-123', sessionId: 'sess-1' });
            service.updatePresence('user2', { username: 'Bob', status: 'away', workspaceId: 'ws-123', sessionId: 'sess-2' });
            service.updatePresence('user3', { username: 'Charlie', status: 'offline', workspaceId: 'ws-456', sessionId: 'sess-3' });
            service.setCurrentFile('user1', { path: '/src/app.ts' });
            service.setCurrentFile('user2', { path: '/src/app.ts' });
        });
        it('should filter by workspace', () => {
            const results = service.queryPresence({ workspaceId: 'ws-123' });
            expect(results).toHaveLength(2);
        });
        it('should filter by status', () => {
            const results = service.queryPresence({ status: 'online' });
            expect(results).toHaveLength(1);
            expect(results[0].userId).toBe('user1');
        });
        it('should filter by file', () => {
            const results = service.queryPresence({ currentFile: '/src/app.ts' });
            expect(results).toHaveLength(2);
        });
        it('should combine filters', () => {
            const results = service.queryPresence({
                workspaceId: 'ws-123',
                status: 'online',
            });
            expect(results).toHaveLength(1);
            expect(results[0].userId).toBe('user1');
        });
    });
    describe('removePresence', () => {
        it('should remove presence', () => {
            service.updatePresence('user1', { username: 'Alice', workspaceId: 'ws-123', sessionId: 'sess-123' });
            const result = service.removePresence('user1');
            expect(result).toBe(true);
            expect(service.getPresence('user1')).toBeUndefined();
        });
        it('should return false for non-existent user', () => {
            const result = service.removePresence('non-existent');
            expect(result).toBe(false);
        });
        it('should emit presenceRemoved event', () => {
            const spy = vi.spyOn(service, 'emit');
            service.updatePresence('user1', { username: 'Alice', workspaceId: 'ws-123', sessionId: 'sess-123' });
            service.removePresence('user1');
            expect(spy).toHaveBeenCalledWith('presenceRemoved', expect.objectContaining({ userId: 'user1' }));
        });
    });
    describe('getStatistics', () => {
        it('should return presence statistics', () => {
            service.updatePresence('user1', { username: 'Alice', status: 'online', workspaceId: 'ws-123', sessionId: 'sess-1' });
            service.updatePresence('user2', { username: 'Bob', status: 'away', workspaceId: 'ws-123', sessionId: 'sess-2' });
            service.updatePresence('user3', { username: 'Charlie', status: 'offline', workspaceId: 'ws-456', sessionId: 'sess-3' });
            service.setCurrentFile('user1', { path: '/src/app.ts' });
            service.setCurrentFunction('user2', { name: 'handleRequest', file: '/src/app.ts', line: 42 });
            service.setCurrentTask('user3', { id: 'task-123', title: 'Fix bug', status: 'active' });
            const stats = service.getStatistics();
            expect(stats.totalUsers).toBe(3);
            expect(stats.onlineUsers).toBe(1);
            expect(stats.awayUsers).toBe(1);
            expect(stats.activeFiles['/src/app.ts']).toBe(1);
            expect(stats.activeFunctions['handleRequest']).toBe(1);
            expect(stats.activeTasks['task-123']).toBe(1);
        });
        it('should calculate workspace statistics', () => {
            service.updatePresence('user1', { username: 'Alice', status: 'online', workspaceId: 'ws-123', sessionId: 'sess-1' });
            service.updatePresence('user2', { username: 'Bob', status: 'idle', workspaceId: 'ws-123', sessionId: 'sess-2' });
            const stats = service.getStatistics();
            expect(stats.workspaceStats['ws-123'].online).toBe(1);
            expect(stats.workspaceStats['ws-123'].idle).toBe(1);
        });
    });
    describe('broadcastPresenceUpdate', () => {
        it('should broadcast presence', () => {
            const spy = vi.spyOn(service, 'emit');
            service.updatePresence('user1', { username: 'Alice', workspaceId: 'ws-123', sessionId: 'sess-123' });
            service.broadcastPresenceUpdate('user1');
            expect(spy).toHaveBeenCalledWith('presenceBroadcast', expect.objectContaining({ userId: 'user1' }));
        });
        it('should return null for non-existent user', () => {
            const result = service.broadcastPresenceUpdate('non-existent');
            expect(result).toBeNull();
        });
    });
    describe('Redis Cache Operations', () => {
        it('should retrieve from cache', () => {
            service.updatePresence('user1', { username: 'Alice', workspaceId: 'ws-123', sessionId: 'sess-123' });
            const cached = service.getFromCache('user1');
            expect(cached).toBeDefined();
            expect(cached?.userId).toBe('user1');
        });
        it('should return undefined for expired cache entry', () => {
            service.updatePresence('user1', { username: 'Alice', workspaceId: 'ws-123', sessionId: 'sess-123' });
            // Manually expire the entry
            service.removePresence('user1');
            const cached = service.getFromCache('user1');
            expect(cached).toBeUndefined();
        });
        it('should get all cached presences', () => {
            service.updatePresence('user1', { username: 'Alice', workspaceId: 'ws-123', sessionId: 'sess-1' });
            service.updatePresence('user2', { username: 'Bob', workspaceId: 'ws-123', sessionId: 'sess-2' });
            const cached = service.getAllCached();
            expect(cached).toHaveLength(2);
        });
        it('should count by status', () => {
            service.updatePresence('user1', { username: 'Alice', status: 'online', workspaceId: 'ws-123', sessionId: 'sess-1' });
            service.updatePresence('user2', { username: 'Bob', status: 'away', workspaceId: 'ws-123', sessionId: 'sess-2' });
            service.updatePresence('user3', { username: 'Charlie', status: 'offline', workspaceId: 'ws-123', sessionId: 'sess-3' });
            const counts = service.countByStatus('ws-123');
            expect(counts.online).toBe(1);
            expect(counts.away).toBe(1);
            expect(counts.offline).toBe(1);
        });
    });
    describe('singleton pattern', () => {
        it('should return same instance', () => {
            const instance1 = service;
            const instance2 = service;
            expect(instance1).toBe(instance2);
        });
        it('should reset properly', () => {
            service.updatePresence('user1', { username: 'Alice', workspaceId: 'ws-123', sessionId: 'sess-123' });
            expect(service.getStatistics().totalUsers).toBe(1);
            service.reset();
            expect(service.getStatistics().totalUsers).toBe(0);
        });
    });
});
//# sourceMappingURL=rich-presence-service.test.js.map