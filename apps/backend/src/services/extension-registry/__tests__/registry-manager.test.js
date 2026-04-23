#!/usr/bin/env node
// @file        apps/backend/src/services/extension-registry/__tests__/registry-manager.test.ts
// @module      services/extension-registry
// @description Tests for registry manager service
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { RegistryManagerService } from '../registry-manager';
let service;
describe('RegistryManagerService', () => {
    beforeEach(() => {
        service = RegistryManagerService.getInstance();
        service.reset();
    });
    afterEach(() => {
        service.removeAllListeners();
    });
    describe('Extension Registration', () => {
        it('should register extension', () => {
            const ext = service.registerExtension('test.extension', {
                id: 'test.extension',
                name: 'test',
                publisher: 'test-publisher',
                version: '1.0.0',
                displayName: 'Test Extension',
            });
            expect(ext.id).toBe('test.extension');
            expect(ext.version).toBe('1.0.0');
            expect(ext._registeredAt).toBeDefined();
        });
        it('should retrieve registered extension', () => {
            service.registerExtension('test.ext', {
                id: 'test.ext',
                name: 'test',
                publisher: 'org',
                version: '1.0.0',
            });
            const ext = service.getExtension('test.ext');
            expect(ext).toBeDefined();
            expect(ext?.version).toBe('1.0.0');
        });
        it('should get all registered extensions', () => {
            service.registerExtension('ext1', {
                id: 'ext1',
                name: 'ext1',
                publisher: 'pub1',
                version: '1.0.0',
            });
            service.registerExtension('ext2', {
                id: 'ext2',
                name: 'ext2',
                publisher: 'pub2',
                version: '2.0.0',
            });
            const all = service.getAllExtensions();
            expect(all.length).toBe(2);
        });
        it('should track publishers', () => {
            service.registerExtension('ext1', {
                id: 'ext1',
                name: 'ext1',
                publisher: 'publisher1',
                version: '1.0.0',
            });
            service.registerExtension('ext2', {
                id: 'ext2',
                name: 'ext2',
                publisher: 'publisher2',
                version: '1.0.0',
            });
            const stats = service.getStatistics();
            expect(stats.activePublishers.length).toBe(2);
        });
    });
    describe('Blocklist Management', () => {
        it('should block extension', () => {
            const status = service.blockExtension('evil.extension', 'Security vulnerability', 'critical', ['good.alternative']);
            expect(status.blocked).toBe(true);
            expect(status.blockSeverity).toBe('critical');
            expect(status.blockReason).toContain('Security');
        });
        it('should check if extension is blocked', () => {
            service.blockExtension('blocked.ext', 'CVE-2024-1234', 'high');
            expect(service.isBlocked('blocked.ext')).toBe(true);
            expect(service.isBlocked('allowed.ext')).toBe(false);
        });
        it('should unblock extension', () => {
            service.blockExtension('blocked.ext', 'Test', 'medium');
            expect(service.isBlocked('blocked.ext')).toBe(true);
            service.unblockExtension('blocked.ext');
            expect(service.isBlocked('blocked.ext')).toBe(false);
        });
        it('should get blocklist', () => {
            service.blockExtension('ext1', 'Reason 1', 'high');
            service.blockExtension('ext2', 'Reason 2', 'medium');
            const blocklist = service.getBlocklist();
            expect(blocklist.length).toBe(2);
            expect(blocklist.every((b) => b.blocked)).toBe(true);
        });
    });
    describe('Version Pinning', () => {
        beforeEach(() => {
            service.registerExtension('pinned.ext', {
                id: 'pinned.ext',
                name: 'pinned',
                publisher: 'org',
                version: '1.5.0',
            });
        });
        it('should set version pinning', () => {
            const pinning = service.setPinning('pinned.ext', ['1.0.0', '1.5.0'], 'ws-1', 'Tested versions');
            expect(pinning.extensionId).toBe('pinned.ext');
            expect(pinning.allowedVersions.length).toBe(2);
            expect(pinning.workspaceId).toBe('ws-1');
        });
        it('should validate allowed version', () => {
            service.setPinning('pinned.ext', ['1.0.0', '1.5.0'], 'ws-1');
            const validation = service.validateVersion('pinned.ext', '1.5.0', 'ws-1');
            expect(validation.allowed).toBe(true);
        });
        it('should reject disallowed version', () => {
            service.setPinning('pinned.ext', ['1.0.0', '1.5.0'], 'ws-1');
            const validation = service.validateVersion('pinned.ext', '2.0.0', 'ws-1');
            expect(validation.allowed).toBe(false);
            expect(validation.reason).toContain('not in pinned versions');
        });
        it('should match version patterns', () => {
            service.setPinning('pinned.ext', ['1.0.*', '2.*'], 'ws-1');
            expect(service.validateVersion('pinned.ext', '1.0.5', 'ws-1').allowed).toBe(true);
            expect(service.validateVersion('pinned.ext', '1.1.0', 'ws-1').allowed).toBe(false);
            expect(service.validateVersion('pinned.ext', '2.5.10', 'ws-1').allowed).toBe(true);
        });
        it('should allow any version without pinning', () => {
            const validation = service.validateVersion('unpinned.ext', '9.9.9', 'ws-1');
            expect(validation.allowed).toBe(true);
        });
        it('should support global pinning', () => {
            service.setPinning('global.ext', ['1.0.0'], undefined, 'Global policy');
            const validation = service.validateVersion('global.ext', '1.0.0');
            expect(validation.allowed).toBe(true);
        });
    });
    describe('Installation Tracking', () => {
        it('should record installation', () => {
            service.recordInstallation('ext-1');
            service.recordInstallation('ext-1');
            const stats = service.getInstallationStats('ext-1');
            expect(stats.count).toBe(2);
        });
        it('should update blocklist with installation count', () => {
            service.blockExtension('tracked.ext', 'Test', 'medium');
            service.recordInstallation('tracked.ext');
            service.recordInstallation('tracked.ext');
            const blocklist = service.getBlocklist();
            const status = blocklist.find((b) => b.id === 'tracked.ext');
            expect(status?.installationCount).toBe(2);
        });
        it('should track last installation time', () => {
            service.blockExtension('timed.ext', 'Test', 'low');
            service.recordInstallation('timed.ext');
            const stats = service.getInstallationStats('timed.ext');
            expect(stats.lastInstalled).toBeDefined();
            expect(stats.lastInstalled).toBeGreaterThan(0);
        });
    });
    describe('Statistics', () => {
        beforeEach(() => {
            service.registerExtension('internal.ext', {
                id: 'internal.ext',
                name: 'internal',
                publisher: 'kushnircloud.org',
                version: '1.0.0',
            });
            service.registerExtension('external.ext', {
                id: 'external.ext',
                name: 'external',
                publisher: 'external-org',
                version: '1.0.0',
            });
            service.blockExtension('blocked.ext', 'CVE', 'high');
        });
        it('should report internal extension count correctly', () => {
            service.registerExtension('internal.ext', {
                id: 'internal.ext',
                name: 'internal',
                publisher: 'kushnircloud',
                version: '1.0.0',
            });
            service.registerExtension('external.ext', {
                id: 'external.ext',
                name: 'external',
                publisher: 'microsoft',
                version: '1.0.0',
            });
            const stats = service.getStatistics();
            expect(stats.totalExtensions).toBe(2);
            expect(stats.internalExtensions).toBe(1);
        });
        ;
        it('should count total installations', () => {
            service.recordInstallation('internal.ext');
            service.recordInstallation('internal.ext');
            service.recordInstallation('external.ext');
            const stats = service.getStatistics();
            expect(stats.totalInstallations).toBe(3);
        });
        it('should report sync status as healthy', () => {
            service.recordSync();
            const stats = service.getStatistics();
            expect(stats.syncStatus).toBe('healthy');
            expect(stats.lastSync).toBeGreaterThan(0);
        });
    });
    describe('Events', () => {
        it('should emit extension-registered event', async () => {
            const eventPromise = new Promise((resolve) => {
                service.once('extension-registered', (ext) => {
                    expect(ext.id).toBe('test.ext');
                    resolve(null);
                });
            });
            service.registerExtension('test.ext', {
                id: 'test.ext',
                name: 'test',
                publisher: 'pub',
                version: '1.0.0',
            });
            await eventPromise;
        });
        it('should emit extension-blocked event', async () => {
            const eventPromise = new Promise((resolve) => {
                service.once('extension-blocked', (status) => {
                    expect(status.id).toBe('blocked.ext');
                    expect(status.blocked).toBe(true);
                    resolve(null);
                });
            });
            service.blockExtension('blocked.ext', 'Test', 'high');
            await eventPromise;
        });
        it('should emit version-pinned event', async () => {
            const eventPromise = new Promise((resolve) => {
                service.once('version-pinned', (pinning) => {
                    expect(pinning.extensionId).toBe('pinned.ext');
                    resolve(null);
                });
            });
            service.setPinning('pinned.ext', ['1.0.0']);
            await eventPromise;
        });
        it('should emit extension-installed event', async () => {
            const eventPromise = new Promise((resolve) => {
                service.once('extension-installed', (data) => {
                    expect(data.extensionId).toBe('installed.ext');
                    expect(data.count).toBe(1);
                    resolve(null);
                });
            });
            service.recordInstallation('installed.ext');
            await eventPromise;
        });
        it('should emit registry-synced event', async () => {
            const eventPromise = new Promise((resolve) => {
                service.once('registry-synced', (data) => {
                    expect(data.timestamp).toBeGreaterThan(0);
                    resolve(null);
                });
            });
            service.recordSync();
            await eventPromise;
        });
    });
    describe('Singleton Pattern', () => {
        it('should return same instance', () => {
            const instance1 = RegistryManagerService.getInstance();
            const instance2 = RegistryManagerService.getInstance();
            expect(instance1).toBe(instance2);
        });
        it('should share state across instances', () => {
            const instance1 = RegistryManagerService.getInstance();
            instance1.reset();
            instance1.registerExtension('shared.ext', {
                id: 'shared.ext',
                name: 'shared',
                publisher: 'org',
                version: '1.0.0',
            });
            const instance2 = RegistryManagerService.getInstance();
            const ext = instance2.getExtension('shared.ext');
            expect(ext).toBeDefined();
        });
    });
    describe('Integration Scenarios', () => {
        it('should handle complete registry workflow', () => {
            // Register internal extension
            service.registerExtension('internal.ext', {
                id: 'internal.ext',
                name: 'Internal Tool',
                publisher: 'kushnircloud',
                version: '1.0.0',
            });
            // Register and block external extension
            service.registerExtension('external.ext', {
                id: 'external.ext',
                name: 'External Tool',
                publisher: 'external-org',
                version: '1.0.0',
            });
            service.blockExtension('external.ext', 'CVE-2024-1234', 'critical');
            // Register pinned extension
            service.registerExtension('pinned.ext', {
                id: 'pinned.ext',
                name: 'Pinned Tool',
                publisher: 'kushnircloud',
                version: '1.5.0',
            });
            service.setPinning('pinned.ext', ['1.0.0', '1.5.0'], 'ws-prod', 'Production stable versions');
            // Record installations
            service.recordInstallation('internal.ext');
            service.recordInstallation('internal.ext');
            service.recordInstallation('pinned.ext');
            // Sync registry
            service.recordSync();
            // Verify statistics
            const stats = service.getStatistics();
            expect(stats.totalExtensions).toBe(3);
            expect(stats.internalExtensions).toBe(2);
            expect(stats.blockedExtensions).toBe(1);
            expect(stats.totalInstallations).toBe(3);
            expect(stats.syncStatus).toBe('healthy');
        });
        it('should validate version pinning in workflow', () => {
            service.registerExtension('dev.ext', {
                id: 'dev.ext',
                name: 'Dev Tool',
                publisher: 'kushnircloud',
                version: '2.0.0',
            });
            // Pin to specific versions for development
            service.setPinning('dev.ext', ['1.8.0', '1.9.0', '2.0.0'], 'ws-dev');
            // New user in dev workspace can install pinned version
            expect(service.validateVersion('dev.ext', '2.0.0', 'ws-dev').allowed).toBe(true);
            // But cannot install pre-release
            expect(service.validateVersion('dev.ext', '2.1.0-beta', 'ws-dev').allowed).toBe(false);
            // User in different workspace has no restrictions
            expect(service.validateVersion('dev.ext', '99.0.0', 'ws-other').allowed).toBe(true);
        });
    });
});
//# sourceMappingURL=registry-manager.test.js.map