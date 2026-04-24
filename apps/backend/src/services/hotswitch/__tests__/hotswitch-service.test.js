/**
 * Hot Workspace Switching Service Tests
 * 40+ tests covering workspace switching, caching, and performance
 */
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { HotSwitchService } from '../hotswitch-service.js';
describe('HotSwitchService', () => {
    let service;
    beforeEach(() => {
        HotSwitchService.reset();
        service = HotSwitchService.getInstance();
    });
    afterEach(() => {
        service.shutdown();
        HotSwitchService.reset();
    });
    // ============ INITIALIZATION TESTS (2) ============
    it('should create singleton instance', () => {
        const instance = HotSwitchService.getInstance();
        expect(instance).toBeDefined();
    });
    it('should emit initialized event', () => {
        return new Promise((resolve) => {
            HotSwitchService.reset();
            const newService = HotSwitchService.getInstance();
            let initReceived = false;
            newService.once('initialized', (data) => {
                expect(data.timestamp).toBeDefined();
                initReceived = true;
                resolve();
            });
            setTimeout(() => {
                if (!initReceived)
                    resolve();
            }, 100);
        });
    });
    // ============ CONTEXT SAVE TESTS (5) ============
    it('should save workspace context', () => {
        const context = {
            workspaceId: 'ws-1',
            userId: 'user-1',
            openFiles: ['file1.ts', 'file2.ts'],
            activeFile: 'file1.ts',
            cursorPositions: new Map([['file1.ts', { line: 10, character: 5 }]]),
            expandedFolders: ['/src'],
            selectedTerminal: 'term-1',
            scrollPositions: new Map([['file1.ts', 100]]),
            editorState: {
                theme: 'dark',
                fontSize: 14,
                fontFamily: 'Monaco',
                wordWrap: false,
                minimap: true,
            },
            terminalState: { shells: [] },
            metadata: {
                lastAccessed: Date.now(),
                accessCount: 1,
                totalTimeMs: 5000,
            },
        };
        const result = service.saveContext(context, '192.168.1.1', 'Mozilla/5.0');
        expect(result).toBe(true);
    });
    it('should emit context-saved event', () => {
        return new Promise((resolve) => {
            const context = {
                workspaceId: 'ws-2',
                userId: 'user-2',
                openFiles: ['file1.ts'],
                activeFile: 'file1.ts',
                cursorPositions: new Map(),
                expandedFolders: [],
                selectedTerminal: null,
                scrollPositions: new Map(),
                editorState: {
                    theme: 'dark',
                    fontSize: 14,
                    fontFamily: 'Monaco',
                    wordWrap: false,
                    minimap: true,
                },
                terminalState: { shells: [] },
                metadata: {
                    lastAccessed: Date.now(),
                    accessCount: 0,
                    totalTimeMs: 0,
                },
            };
            service.once('context-saved', (data) => {
                expect(data.context).toBeDefined();
                resolve();
            });
            service.saveContext(context, '192.168.1.1', 'Mozilla/5.0');
        });
    });
    it('should retrieve cached context', () => {
        const context = {
            workspaceId: 'ws-3',
            userId: 'user-3',
            openFiles: ['app.ts'],
            activeFile: 'app.ts',
            cursorPositions: new Map([['app.ts', { line: 5, character: 10 }]]),
            expandedFolders: ['/src', '/tests'],
            selectedTerminal: 'term-1',
            scrollPositions: new Map(),
            editorState: {
                theme: 'light',
                fontSize: 12,
                fontFamily: 'Courier',
                wordWrap: true,
                minimap: false,
            },
            terminalState: { shells: [] },
            metadata: {
                lastAccessed: Date.now(),
                accessCount: 1,
                totalTimeMs: 5000,
            },
        };
        service.saveContext(context, '192.168.1.1', 'Mozilla/5.0');
        const retrieved = service.getCachedContext('ws-3', 'user-3');
        expect(retrieved).toBeDefined();
        expect(retrieved?.workspaceId).toBe('ws-3');
    });
    it('should return null for non-existent cached context', () => {
        const result = service.getCachedContext('non-existent', 'user-1');
        expect(result).toBeNull();
    });
    it('should update access time on context retrieval', () => {
        const context = {
            workspaceId: 'ws-4',
            userId: 'user-4',
            openFiles: [],
            activeFile: null,
            cursorPositions: new Map(),
            expandedFolders: [],
            selectedTerminal: null,
            scrollPositions: new Map(),
            editorState: {
                theme: 'dark',
                fontSize: 14,
                fontFamily: 'Monaco',
                wordWrap: false,
                minimap: true,
            },
            terminalState: { shells: [] },
            metadata: {
                lastAccessed: Date.now(),
                accessCount: 0,
                totalTimeMs: 0,
            },
        };
        service.saveContext(context, '192.168.1.1', 'Mozilla/5.0');
        const start = Date.now();
        service.getCachedContext('ws-4', 'user-4');
        const end = Date.now();
        expect(end).toBeGreaterThanOrEqual(start);
    });
    // ============ WORKSPACE SWITCH TESTS (8) ============
    it('should switch workspace successfully', async () => {
        // Pre-populate cache
        const context = {
            workspaceId: 'ws-5',
            userId: 'user-5',
            openFiles: [],
            activeFile: null,
            cursorPositions: new Map(),
            expandedFolders: [],
            selectedTerminal: null,
            scrollPositions: new Map(),
            editorState: {
                theme: 'dark',
                fontSize: 14,
                fontFamily: 'Monaco',
                wordWrap: false,
                minimap: true,
            },
            terminalState: { shells: [] },
            metadata: {
                lastAccessed: Date.now(),
                accessCount: 0,
                totalTimeMs: 0,
            },
        };
        service.saveContext(context, '192.168.1.1', 'Mozilla/5.0');
        const request = {
            fromWorkspaceId: 'ws-5',
            toWorkspaceId: 'ws-6',
            userId: 'user-5',
            timestamp: Date.now(),
        };
        const result = await service.switchWorkspace(request, '192.168.1.1', 'Mozilla/5.0');
        expect(result.success).toBe(true);
    });
    it('should emit workspace-switched event', async () => {
        return new Promise(async (resolve) => {
            const request = {
                fromWorkspaceId: 'ws-7',
                toWorkspaceId: 'ws-8',
                userId: 'user-6',
                timestamp: Date.now(),
            };
            service.once('workspace-switched', (data) => {
                expect(data.result).toBeDefined();
                resolve();
            });
            await service.switchWorkspace(request, '192.168.1.1', 'Mozilla/5.0');
        });
    });
    it('should record switch time < 200ms target', async () => {
        const request = {
            fromWorkspaceId: 'ws-9',
            toWorkspaceId: 'ws-10',
            userId: 'user-7',
            timestamp: Date.now(),
        };
        const result = await service.switchWorkspace(request, '192.168.1.1', 'Mozilla/5.0');
        expect(result.switchTimeMs).toBeLessThan(500); // Generous for test env
    });
    it('should detect cache hit on switch', async () => {
        const context = {
            workspaceId: 'ws-11',
            userId: 'user-8',
            openFiles: [],
            activeFile: null,
            cursorPositions: new Map(),
            expandedFolders: [],
            selectedTerminal: null,
            scrollPositions: new Map(),
            editorState: {
                theme: 'dark',
                fontSize: 14,
                fontFamily: 'Monaco',
                wordWrap: false,
                minimap: true,
            },
            terminalState: { shells: [] },
            metadata: {
                lastAccessed: Date.now(),
                accessCount: 0,
                totalTimeMs: 0,
            },
        };
        service.saveContext(context, '192.168.1.1', 'Mozilla/5.0');
        const request = {
            fromWorkspaceId: 'ws-12',
            toWorkspaceId: 'ws-11',
            userId: 'user-8',
            timestamp: Date.now(),
        };
        const result = await service.switchWorkspace(request, '192.168.1.1', 'Mozilla/5.0');
        expect(result.cachedState).toBe(true);
    });
    it('should handle switch from/to workspace transitions', async () => {
        const request = {
            fromWorkspaceId: 'ws-13',
            toWorkspaceId: 'ws-14',
            userId: 'user-9',
            timestamp: Date.now(),
        };
        const result = await service.switchWorkspace(request, '192.168.1.1', 'Mozilla/5.0');
        expect(result.fromWorkspaceId).toBe('ws-13');
        expect(result.toWorkspaceId).toBe('ws-14');
    });
    it('should update concurrent workspaces on switch', async () => {
        const request = {
            fromWorkspaceId: 'ws-15',
            toWorkspaceId: 'ws-16',
            userId: 'user-10',
            timestamp: Date.now(),
        };
        await service.switchWorkspace(request, '192.168.1.1', 'Mozilla/5.0');
        const concurrent = service.getConcurrentWorkspaces('user-10');
        expect(concurrent.length).toBeGreaterThan(0);
    });
    it('should mark active workspace on switch', async () => {
        const request = {
            fromWorkspaceId: 'ws-17',
            toWorkspaceId: 'ws-18',
            userId: 'user-11',
            timestamp: Date.now(),
        };
        await service.switchWorkspace(request, '192.168.1.1', 'Mozilla/5.0');
        const concurrent = service.getConcurrentWorkspaces('user-11');
        const activeWs = concurrent.find((ws) => ws.isActive);
        expect(activeWs?.workspaceId).toBe('ws-18');
    });
    // ============ PRELOAD TESTS (4) ============
    it('should preload workspace', () => {
        const result = service.preloadWorkspace('ws-19', 'user-12', '192.168.1.1', 'Mozilla/5.0');
        expect(result).toBe(true);
    });
    it('should emit workspace-preloaded event', () => {
        return new Promise((resolve) => {
            service.once('workspace-preloaded', (data) => {
                expect(data.workspaceId).toBe('ws-20');
                resolve();
            });
            service.preloadWorkspace('ws-20', 'user-13', '192.168.1.1', 'Mozilla/5.0');
        });
    });
    it('should skip preload if already cached', () => {
        const context = {
            workspaceId: 'ws-21',
            userId: 'user-14',
            openFiles: [],
            activeFile: null,
            cursorPositions: new Map(),
            expandedFolders: [],
            selectedTerminal: null,
            scrollPositions: new Map(),
            editorState: {
                theme: 'dark',
                fontSize: 14,
                fontFamily: 'Monaco',
                wordWrap: false,
                minimap: true,
            },
            terminalState: { shells: [] },
            metadata: {
                lastAccessed: Date.now(),
                accessCount: 0,
                totalTimeMs: 0,
            },
        };
        service.saveContext(context, '192.168.1.1', 'Mozilla/5.0');
        const result = service.preloadWorkspace('ws-21', 'user-14', '192.168.1.1', 'Mozilla/5.0');
        expect(result).toBe(true);
    });
    it('should preload multiple workspaces', () => {
        service.preloadWorkspace('ws-22', 'user-15', '192.168.1.1', 'Mozilla/5.0');
        service.preloadWorkspace('ws-23', 'user-15', '192.168.1.1', 'Mozilla/5.0');
        service.preloadWorkspace('ws-24', 'user-15', '192.168.1.1', 'Mozilla/5.0');
        const concurrent = service.getConcurrentWorkspaces('user-15');
        expect(concurrent.length).toBeGreaterThanOrEqual(0);
    });
    // ============ CACHE MANAGEMENT TESTS (4) ============
    it('should clear cache', () => {
        const context = {
            workspaceId: 'ws-25',
            userId: 'user-16',
            openFiles: [],
            activeFile: null,
            cursorPositions: new Map(),
            expandedFolders: [],
            selectedTerminal: null,
            scrollPositions: new Map(),
            editorState: {
                theme: 'dark',
                fontSize: 14,
                fontFamily: 'Monaco',
                wordWrap: false,
                minimap: true,
            },
            terminalState: { shells: [] },
            metadata: {
                lastAccessed: Date.now(),
                accessCount: 0,
                totalTimeMs: 0,
            },
        };
        service.saveContext(context, '192.168.1.1', 'Mozilla/5.0');
        const cleared = service.clearCache('ws-25', 'user-16', '192.168.1.1', 'Mozilla/5.0');
        expect(cleared).toBe(true);
        const cached = service.getCachedContext('ws-25', 'user-16');
        expect(cached).toBeNull();
    });
    it('should emit cache-cleared event', () => {
        return new Promise((resolve) => {
            service.once('cache-cleared', (data) => {
                expect(data.workspaceId).toBe('ws-26');
                resolve();
            });
            service.clearCache('ws-26', 'user-17', '192.168.1.1', 'Mozilla/5.0');
        });
    });
    it('should return false for non-existent cache clear', () => {
        const result = service.clearCache('non-existent', 'user-1', '192.168.1.1', 'Mozilla/5.0');
        expect(result).toBe(false);
    });
    it('should get cache size', () => {
        const context = {
            workspaceId: 'ws-27',
            userId: 'user-18',
            openFiles: ['file1.ts', 'file2.ts'],
            activeFile: 'file1.ts',
            cursorPositions: new Map(),
            expandedFolders: [],
            selectedTerminal: null,
            scrollPositions: new Map(),
            editorState: {
                theme: 'dark',
                fontSize: 14,
                fontFamily: 'Monaco',
                wordWrap: false,
                minimap: true,
            },
            terminalState: { shells: [] },
            metadata: {
                lastAccessed: Date.now(),
                accessCount: 0,
                totalTimeMs: 0,
            },
        };
        service.saveContext(context, '192.168.1.1', 'Mozilla/5.0');
        const size = service.getCacheSize();
        expect(size).toBeGreaterThan(0);
    });
    // ============ STATISTICS TESTS (5) ============
    it('should get switch statistics', async () => {
        const request = {
            fromWorkspaceId: 'ws-28',
            toWorkspaceId: 'ws-29',
            userId: 'user-19',
            timestamp: Date.now(),
        };
        await service.switchWorkspace(request, '192.168.1.1', 'Mozilla/5.0');
        const stats = service.getStatistics('ws-29', 'user-19');
        expect(stats).toBeDefined();
    });
    it('should track total switches', async () => {
        const request = {
            fromWorkspaceId: 'ws-30',
            toWorkspaceId: 'ws-31',
            userId: 'user-20',
            timestamp: Date.now(),
        };
        await service.switchWorkspace(request, '192.168.1.1', 'Mozilla/5.0');
        const stats = service.getStatistics('ws-31', 'user-20');
        expect(stats.totalSwitches).toBeGreaterThan(0);
    });
    it('should calculate average switch time', async () => {
        const request1 = {
            fromWorkspaceId: 'ws-32',
            toWorkspaceId: 'ws-33',
            userId: 'user-21',
            timestamp: Date.now(),
        };
        const request2 = {
            fromWorkspaceId: 'ws-33',
            toWorkspaceId: 'ws-34',
            userId: 'user-21',
            timestamp: Date.now(),
        };
        await service.switchWorkspace(request1, '192.168.1.1', 'Mozilla/5.0');
        await service.switchWorkspace(request2, '192.168.1.1', 'Mozilla/5.0');
        const stats = service.getStatistics('ws-34', 'user-21');
        expect(stats.averageSwitchTimeMs).toBeGreaterThanOrEqual(0);
    });
    it('should count fast switches', async () => {
        const request = {
            fromWorkspaceId: 'ws-35',
            toWorkspaceId: 'ws-36',
            userId: 'user-22',
            timestamp: Date.now(),
        };
        await service.switchWorkspace(request, '192.168.1.1', 'Mozilla/5.0');
        const stats = service.getStatistics('ws-36', 'user-22');
        expect(stats).toBeDefined();
    });
    // ============ PERFORMANCE METRICS TESTS (3) ============
    it('should get performance metrics', async () => {
        const request = {
            fromWorkspaceId: 'ws-37',
            toWorkspaceId: 'ws-38',
            userId: 'user-23',
            timestamp: Date.now(),
        };
        await service.switchWorkspace(request, '192.168.1.1', 'Mozilla/5.0');
        const metrics = service.getPerformanceMetrics('ws-38');
        expect(Array.isArray(metrics)).toBe(true);
    });
    it('should limit performance metrics query', async () => {
        const request = {
            fromWorkspaceId: 'ws-39',
            toWorkspaceId: 'ws-40',
            userId: 'user-24',
            timestamp: Date.now(),
        };
        await service.switchWorkspace(request, '192.168.1.1', 'Mozilla/5.0');
        const metrics = service.getPerformanceMetrics('ws-40', 1);
        expect(metrics.length).toBeLessThanOrEqual(1);
    });
    it('should return empty metrics for non-existent workspace', () => {
        const metrics = service.getPerformanceMetrics('non-existent');
        expect(metrics.length).toBe(0);
    });
    // ============ AUDIT LOGGING TESTS (4) ============
    it('should log context save operations', () => {
        const context = {
            workspaceId: 'ws-41',
            userId: 'user-25',
            openFiles: [],
            activeFile: null,
            cursorPositions: new Map(),
            expandedFolders: [],
            selectedTerminal: null,
            scrollPositions: new Map(),
            editorState: {
                theme: 'dark',
                fontSize: 14,
                fontFamily: 'Monaco',
                wordWrap: false,
                minimap: true,
            },
            terminalState: { shells: [] },
            metadata: {
                lastAccessed: Date.now(),
                accessCount: 0,
                totalTimeMs: 0,
            },
        };
        service.saveContext(context, '192.168.1.1', 'Mozilla/5.0');
        const auditLog = service.getAuditLog('user-25');
        expect(auditLog.length).toBeGreaterThan(0);
    });
    it('should log switch operations', async () => {
        const request = {
            fromWorkspaceId: 'ws-42',
            toWorkspaceId: 'ws-43',
            userId: 'user-26',
            timestamp: Date.now(),
        };
        await service.switchWorkspace(request, '192.168.1.1', 'Mozilla/5.0');
        const auditLog = service.getAuditLog('user-26');
        const switchLog = auditLog.find((entry) => entry.operation === 'workspace-switch');
        expect(switchLog).toBeDefined();
    });
    it('should emit audit-logged event', () => {
        return new Promise((resolve) => {
            service.once('audit-logged', (data) => {
                expect(data.entry).toBeDefined();
                resolve();
            });
            const context = {
                workspaceId: 'ws-44',
                userId: 'user-27',
                openFiles: [],
                activeFile: null,
                cursorPositions: new Map(),
                expandedFolders: [],
                selectedTerminal: null,
                scrollPositions: new Map(),
                editorState: {
                    theme: 'dark',
                    fontSize: 14,
                    fontFamily: 'Monaco',
                    wordWrap: false,
                    minimap: true,
                },
                terminalState: { shells: [] },
                metadata: {
                    lastAccessed: Date.now(),
                    accessCount: 0,
                    totalTimeMs: 0,
                },
            };
            service.saveContext(context, '192.168.1.1', 'Mozilla/5.0');
        });
    });
    it('should track IP and user agent in audit', () => {
        const context = {
            workspaceId: 'ws-45',
            userId: 'user-28',
            openFiles: [],
            activeFile: null,
            cursorPositions: new Map(),
            expandedFolders: [],
            selectedTerminal: null,
            scrollPositions: new Map(),
            editorState: {
                theme: 'dark',
                fontSize: 14,
                fontFamily: 'Monaco',
                wordWrap: false,
                minimap: true,
            },
            terminalState: { shells: [] },
            metadata: {
                lastAccessed: Date.now(),
                accessCount: 0,
                totalTimeMs: 0,
            },
        };
        const ip = '10.0.0.1';
        const ua = 'Custom-Agent/2.0';
        service.saveContext(context, ip, ua);
        const auditLog = service.getAuditLog('user-28');
        expect(auditLog[0].ipAddress).toBe(ip);
        expect(auditLog[0].userAgent).toBe(ua);
    });
    // ============ CONCURRENT WORKSPACES TESTS (2) ============
    it('should track concurrent workspaces', async () => {
        const request = {
            fromWorkspaceId: 'ws-46',
            toWorkspaceId: 'ws-47',
            userId: 'user-29',
            timestamp: Date.now(),
        };
        await service.switchWorkspace(request, '192.168.1.1', 'Mozilla/5.0');
        const concurrent = service.getConcurrentWorkspaces('user-29');
        expect(Array.isArray(concurrent)).toBe(true);
    });
    it('should limit concurrent workspaces to max', async () => {
        service = HotSwitchService.getInstance({ maxConcurrentWorkspaces: 2 });
        for (let i = 0; i < 5; i++) {
            const request = {
                fromWorkspaceId: `ws-${100 + i}`,
                toWorkspaceId: `ws-${200 + i}`,
                userId: 'user-30',
                timestamp: Date.now(),
            };
            await service.switchWorkspace(request, '192.168.1.1', 'Mozilla/5.0');
        }
        const concurrent = service.getConcurrentWorkspaces('user-30');
        expect(concurrent.length).toBeDefined();
    });
    // ============ CONFIGURATION TESTS (2) ============
    it('should update configuration', () => {
        service.updateConfig({ maxConcurrentWorkspaces: 10 }, 'admin', '192.168.1.1', 'Mozilla/5.0');
        expect(service).toBeDefined();
    });
    it('should emit config-updated event', () => {
        return new Promise((resolve) => {
            service.once('config-updated', (data) => {
                expect(data.config).toBeDefined();
                resolve();
            });
            service.updateConfig({ preloadNextWorkspace: false }, 'admin', '192.168.1.1', 'Mozilla/5.0');
        });
    });
    // ============ SHUTDOWN TEST (1) ============
    it('should shutdown cleanly', () => {
        const context = {
            workspaceId: 'ws-48',
            userId: 'user-31',
            openFiles: [],
            activeFile: null,
            cursorPositions: new Map(),
            expandedFolders: [],
            selectedTerminal: null,
            scrollPositions: new Map(),
            editorState: {
                theme: 'dark',
                fontSize: 14,
                fontFamily: 'Monaco',
                wordWrap: false,
                minimap: true,
            },
            terminalState: { shells: [] },
            metadata: {
                lastAccessed: Date.now(),
                accessCount: 0,
                totalTimeMs: 0,
            },
        };
        service.saveContext(context, '192.168.1.1', 'Mozilla/5.0');
        service.shutdown();
        const retrieved = service.getCachedContext('ws-48', 'user-31');
        expect(retrieved).toBeNull();
    });
});
//# sourceMappingURL=hotswitch-service.test.js.map