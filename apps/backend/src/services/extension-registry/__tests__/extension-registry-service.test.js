import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { ExtensionRegistryService } from '../extension-registry-service.js';
describe('Extension Registry Service', () => {
    let service;
    // Helper: Create mock manifest
    function createManifest(name = 'test-ext', publisher = 'test-pub', version = '1.0.0') {
        return {
            name,
            displayName: `${name} Display`,
            version,
            publisher,
            description: 'Test extension',
            author: 'Test Author',
            engines: { vscode: '^1.75.0' },
            categories: ['Other'],
            keywords: ['test'],
        };
    }
    beforeEach(async () => {
        service = new ExtensionRegistryService();
        await service.initialize();
    });
    afterEach(async () => {
        await service.shutdown();
    });
    describe('Initialization', () => {
        it('should initialize successfully', async () => {
            expect(service).toBeDefined();
            const stats = await service.getStatistics();
            expect(stats.totalExtensions).toBe(0);
        });
        it('should not initialize twice', async () => {
            await service.initialize();
            expect(service).toBeDefined();
        });
        it('should emit initialized event', async () => {
            return new Promise((resolve) => {
                const svc = new ExtensionRegistryService();
                svc.once('initialized', () => {
                    svc.shutdown().then(() => resolve());
                });
                svc.initialize();
            });
        });
    });
    describe('Extension Publishing', () => {
        it('should publish extension', async () => {
            const manifest = createManifest();
            const buffer = Buffer.from('mock vsix content');
            const pkg = await service.publishExtension(manifest, buffer, 'test-user', 'private');
            expect(pkg.name).toBe('test-ext');
            expect(pkg.publisher).toBe('test-pub');
            expect(pkg.version).toBe('1.0.0');
            expect(pkg.fileSize).toBe(buffer.length);
            expect(pkg.checksum).toBeDefined();
        });
        it('should create registry entry', async () => {
            const manifest = createManifest();
            const buffer = Buffer.from('mock vsix content');
            await service.publishExtension(manifest, buffer, 'test-user', 'private');
            const entry = await service.getExtension('test-pub.test-ext');
            expect(entry).toBeDefined();
            expect(entry?.name).toBe('test-ext');
            expect(entry?.versions.length).toBe(1);
        });
        it('should handle multiple versions', async () => {
            const buffer = Buffer.from('mock vsix content');
            const v1 = createManifest('ext', 'pub', '1.0.0');
            await service.publishExtension(v1, buffer, 'test-user', 'private');
            const v2 = createManifest('ext', 'pub', '1.1.0');
            await service.publishExtension(v2, buffer, 'test-user', 'private');
            const v3 = createManifest('ext', 'pub', '2.0.0');
            await service.publishExtension(v3, buffer, 'test-user', 'private');
            const entry = await service.getExtension('pub.ext');
            expect(entry?.versions.length).toBe(3);
        });
        it('should emit extension-published event', async () => {
            return new Promise((resolve) => {
                service.once('extension-published', ({ extensionId, version }) => {
                    expect(extensionId).toBe('test-pub.test-ext');
                    expect(version).toBe('1.0.0');
                    resolve();
                });
                const manifest = createManifest();
                const buffer = Buffer.from('mock vsix content');
                service.publishExtension(manifest, buffer, 'test-user', 'private');
            });
        });
        it('should reject missing manifest fields', async () => {
            const manifest = { name: 'test', publisher: 'test' };
            const buffer = Buffer.from('mock vsix content');
            await expect(service.publishExtension(manifest, buffer, 'test-user', 'private')).rejects.toThrow('Invalid manifest');
        });
        it('should reject oversized files', async () => {
            const manifest = createManifest();
            const largeBuffer = Buffer.alloc(200000000); // 200MB
            await expect(service.publishExtension(manifest, largeBuffer, 'test-user', 'private')).rejects.toThrow('exceeds maximum size');
        });
    });
    describe('Extension Retrieval', () => {
        it('should get extension by ID', async () => {
            const manifest = createManifest();
            const buffer = Buffer.from('mock vsix content');
            await service.publishExtension(manifest, buffer, 'test-user', 'private');
            const entry = await service.getExtension('test-pub.test-ext');
            expect(entry).toBeDefined();
            expect(entry?.name).toBe('test-ext');
        });
        it('should return undefined for non-existent extension', async () => {
            const result = await service.getExtension('non-existent.ext');
            expect(result).toBeUndefined();
        });
        it('should get specific version', async () => {
            const m1 = createManifest('ext', 'pub', '1.0.0');
            const m2 = createManifest('ext', 'pub', '2.0.0');
            const buffer = Buffer.from('mock vsix content');
            await service.publishExtension(m1, buffer, 'test-user', 'private');
            await service.publishExtension(m2, buffer, 'test-user', 'private');
            const version = await service.getExtensionVersion('pub.ext', '1.0.0');
            expect(version?.version).toBe('1.0.0');
        });
        it('should get latest version', async () => {
            const m1 = createManifest('ext', 'pub', '1.0.0');
            const m2 = createManifest('ext', 'pub', '2.0.0');
            const buffer = Buffer.from('mock vsix content');
            await service.publishExtension(m1, buffer, 'test-user', 'private');
            await service.publishExtension(m2, buffer, 'test-user', 'private');
            const latest = await service.getLatestVersion('pub.ext');
            expect(latest?.version).toBe('2.0.0');
        });
        it('should cache extensions', async () => {
            const manifest = createManifest();
            const buffer = Buffer.from('mock vsix content');
            await service.publishExtension(manifest, buffer, 'test-user', 'private');
            const first = await service.getExtension('test-pub.test-ext');
            const second = await service.getExtension('test-pub.test-ext');
            expect(first).toEqual(second);
        });
    });
    describe('Extension Query/Search', () => {
        beforeEach(async () => {
            const buffer = Buffer.from('mock vsix content');
            const m1 = createManifest('auth', 'corp', '1.0.0');
            m1.description = 'Authentication extension';
            m1.categories = ['Security'];
            m1.keywords = ['auth', 'oauth'];
            await service.publishExtension(m1, buffer, 'user1', 'private');
            const m2 = createManifest('debug', 'corp', '1.0.0');
            m2.description = 'Debugging tools';
            m2.categories = ['Debuggers'];
            m2.keywords = ['debug', 'test'];
            await service.publishExtension(m2, buffer, 'user2', 'internal');
            const m3 = createManifest('theme', 'other', '1.0.0');
            m3.description = 'Color theme extension';
            m3.categories = ['Themes'];
            m3.keywords = ['theme', 'colors'];
            await service.publishExtension(m3, buffer, 'user3', 'public');
        });
        it('should query all extensions', async () => {
            const result = await service.queryExtensions({});
            expect(result.entries.length).toBe(3);
            expect(result.totalCount).toBe(3);
        });
        it('should filter by scope', async () => {
            const result = await service.queryExtensions({ scope: 'private' });
            expect(result.entries.length).toBe(1);
            expect(result.entries[0].scope).toBe('private');
        });
        it('should filter by publisher', async () => {
            const result = await service.queryExtensions({ publisher: 'corp' });
            expect(result.entries.length).toBe(2);
            expect(result.entries.every((e) => e.publisher === 'corp')).toBe(true);
        });
        it('should search by name', async () => {
            const result = await service.queryExtensions({ search: 'auth' });
            expect(result.entries.length).toBeGreaterThan(0);
            expect(result.entries.some((e) => e.name === 'auth')).toBe(true);
        });
        it('should filter by category', async () => {
            const result = await service.queryExtensions({ tag: 'auth' });
            expect(result.entries.length).toBeGreaterThan(0);
        });
        it('should sort by name', async () => {
            const result = await service.queryExtensions({ sort: 'name' });
            const names = result.entries.map((e) => e.displayName);
            for (let i = 1; i < names.length; i++) {
                expect(names[i - 1].localeCompare(names[i])).toBeLessThanOrEqual(0);
            }
        });
        it('should paginate results', async () => {
            const page1 = await service.queryExtensions({ limit: 2, offset: 0 });
            expect(page1.entries.length).toBe(2);
            expect(page1.hasMore).toBe(true);
            const page2 = await service.queryExtensions({ limit: 2, offset: 2 });
            expect(page2.entries.length).toBe(1);
            expect(page2.hasMore).toBe(false);
        });
    });
    describe('Installation', () => {
        it('should install extension', async () => {
            const manifest = createManifest();
            const buffer = Buffer.from('mock vsix content');
            await service.publishExtension(manifest, buffer, 'test-user', 'private');
            const result = await service.installExtension('test-pub.test-ext', 'user-alice');
            expect(result.extensionId).toBe('test-pub.test-ext');
            expect(result.version).toBe('1.0.0');
            expect(result.status).toBe('downloaded');
        });
        it('should install specific version', async () => {
            const m1 = createManifest('ext', 'pub', '1.0.0');
            const m2 = createManifest('ext', 'pub', '2.0.0');
            const buffer = Buffer.from('mock vsix content');
            await service.publishExtension(m1, buffer, 'test-user', 'private');
            await service.publishExtension(m2, buffer, 'test-user', 'private');
            const result = await service.installExtension('pub.ext', 'user-alice', undefined, '1.0.0');
            expect(result.version).toBe('1.0.0');
        });
        it('should reject non-existent extension', async () => {
            await expect(service.installExtension('non-existent.ext', 'user-alice')).rejects.toThrow('Extension not found');
        });
        it('should emit extension-installed event', async () => {
            return new Promise((resolve) => {
                service.once('extension-installed', ({ extensionId, version }) => {
                    expect(extensionId).toBe('test-pub.test-ext');
                    expect(version).toBe('1.0.0');
                    resolve();
                });
                const manifest = createManifest();
                const buffer = Buffer.from('mock vsix content');
                service.publishExtension(manifest, buffer, 'test-user', 'private')
                    .then(() => service.installExtension('test-pub.test-ext', 'user-alice'));
            });
        });
        it('should increment install count', async () => {
            const manifest = createManifest();
            const buffer = Buffer.from('mock vsix content');
            await service.publishExtension(manifest, buffer, 'test-user', 'private');
            await service.installExtension('test-pub.test-ext', 'user-alice');
            await service.installExtension('test-pub.test-ext', 'user-bob');
            const entry = await service.getExtension('test-pub.test-ext');
            expect(entry?.installCount).toBe(2);
        });
    });
    describe('Version Pinning', () => {
        beforeEach(async () => {
            const m1 = createManifest('ext', 'pub', '1.0.0');
            const m2 = createManifest('ext', 'pub', '2.0.0');
            const buffer = Buffer.from('mock vsix content');
            await service.publishExtension(m1, buffer, 'test-user', 'private');
            await service.publishExtension(m2, buffer, 'test-user', 'private');
        });
        it('should pin version', async () => {
            const pin = await service.pinVersion('pub.ext', '1.0.0', 'organization', 'Stable release', 'admin-user');
            expect(pin.extensionId).toBe('pub.ext');
            expect(pin.pinnedVersion).toBe('1.0.0');
            expect(pin.scope).toBe('organization');
        });
        it('should emit version-pinned event', async () => {
            return new Promise((resolve) => {
                service.once('version-pinned', ({ extensionId, pinnedVersion }) => {
                    expect(extensionId).toBe('pub.ext');
                    expect(pinnedVersion).toBe('1.0.0');
                    resolve();
                });
                service.pinVersion('pub.ext', '1.0.0', 'organization', 'Stable', 'admin');
            });
        });
        it('should get version pins', async () => {
            await service.pinVersion('pub.ext', '1.0.0', 'organization', 'Stable', 'admin');
            const pins = await service.getVersionPins('pub.ext');
            expect(pins.length).toBe(1);
            expect(pins[0].pinnedVersion).toBe('1.0.0');
        });
        it('should unpin version', async () => {
            await service.pinVersion('pub.ext', '1.0.0', 'organization', 'Stable', 'admin');
            await service.unpinVersion('pub.ext');
            const pins = await service.getVersionPins('pub.ext');
            expect(pins.length).toBe(0);
        });
        it('should enforce pinned version on install', async () => {
            await service.pinVersion('pub.ext', '1.0.0', 'organization', 'Stable', 'admin');
            const result = await service.installExtension('pub.ext', 'user-alice');
            expect(result.version).toBe('1.0.0');
        });
        it('should emit version-unpinned event', async () => {
            return new Promise((resolve) => {
                service.once('version-unpinned', ({ extensionId }) => {
                    expect(extensionId).toBe('pub.ext');
                    resolve();
                });
                service.pinVersion('pub.ext', '1.0.0', 'organization', 'Stable', 'admin')
                    .then(() => service.unpinVersion('pub.ext'));
            });
        });
    });
    describe('Blocklist', () => {
        beforeEach(async () => {
            const manifest = createManifest();
            const buffer = Buffer.from('mock vsix content');
            await service.publishExtension(manifest, buffer, 'test-user', 'private');
        });
        it('should blocklist extension', async () => {
            const entry = await service.blocklistExtension('test-pub.test-ext', 'security', 'critical', 'Contains malware', 'admin-user');
            expect(entry.extensionId).toBe('test-pub.test-ext');
            expect(entry.reason).toBe('security');
            expect(entry.severity).toBe('critical');
        });
        it('should check if blocklisted', async () => {
            await service.blocklistExtension('test-pub.test-ext', 'security', 'critical', 'Contains malware', 'admin-user');
            const isBlocked = await service.isBlocklisted('test-pub.test-ext');
            expect(isBlocked).toBe(true);
        });
        it('should reject installation of blocklisted extension', async () => {
            await service.blocklistExtension('test-pub.test-ext', 'security', 'critical', 'Contains malware', 'admin-user');
            await expect(service.installExtension('test-pub.test-ext', 'user-alice')).rejects.toThrow('blocklisted');
        });
        it('should unblock extension', async () => {
            await service.blocklistExtension('test-pub.test-ext', 'security', 'critical', 'Contains malware', 'admin-user');
            await service.unblocklistExtension('test-pub.test-ext');
            const isBlocked = await service.isBlocklisted('test-pub.test-ext');
            expect(isBlocked).toBe(false);
        });
        it('should emit extension-blocklisted event', async () => {
            return new Promise((resolve) => {
                service.once('extension-blocklisted', ({ extensionId }) => {
                    expect(extensionId).toBe('test-pub.test-ext');
                    resolve();
                });
                service.blocklistExtension('test-pub.test-ext', 'security', 'critical', 'Contains malware', 'admin-user');
            });
        });
        it('should emit extension-unblocklisted event', async () => {
            return new Promise((resolve) => {
                service.once('extension-unblocklisted', ({ extensionId }) => {
                    expect(extensionId).toBe('test-pub.test-ext');
                    resolve();
                });
                service.blocklistExtension('test-pub.test-ext', 'security', 'critical', 'Contains malware', 'admin-user')
                    .then(() => service.unblocklistExtension('test-pub.test-ext'));
            });
        });
        it('should get blocklist entries', async () => {
            await service.blocklistExtension('test-pub.test-ext', 'security', 'critical', 'Contains malware', 'admin-user');
            const entries = await service.getBlocklistEntries();
            expect(entries.length).toBeGreaterThan(0);
        });
    });
    describe('Statistics', () => {
        it('should track total extensions', async () => {
            const buffer = Buffer.from('mock vsix content');
            const m1 = createManifest('ext1', 'pub', '1.0.0');
            const m2 = createManifest('ext2', 'pub', '1.0.0');
            await service.publishExtension(m1, buffer, 'test-user', 'private');
            await service.publishExtension(m2, buffer, 'test-user', 'private');
            const stats = await service.getStatistics();
            expect(stats.totalExtensions).toBe(2);
        });
        it('should track extensions by scope', async () => {
            const buffer = Buffer.from('mock vsix content');
            const m1 = createManifest('ext1', 'pub', '1.0.0');
            const m2 = createManifest('ext2', 'pub', '1.0.0');
            await service.publishExtension(m1, buffer, 'test-user', 'private');
            await service.publishExtension(m2, buffer, 'test-user', 'internal');
            const stats = await service.getStatistics();
            expect(stats.extensionsByScope['private']).toBe(1);
            expect(stats.extensionsByScope['internal']).toBe(1);
        });
        it('should track total versions', async () => {
            const buffer = Buffer.from('mock vsix content');
            const m1 = createManifest('ext', 'pub', '1.0.0');
            const m2 = createManifest('ext', 'pub', '2.0.0');
            await service.publishExtension(m1, buffer, 'test-user', 'private');
            await service.publishExtension(m2, buffer, 'test-user', 'private');
            const stats = await service.getStatistics();
            expect(stats.totalVersions).toBe(2);
        });
        it('should track install count', async () => {
            const manifest = createManifest();
            const buffer = Buffer.from('mock vsix content');
            await service.publishExtension(manifest, buffer, 'test-user', 'private');
            await service.installExtension('test-pub.test-ext', 'user-alice');
            await service.installExtension('test-pub.test-ext', 'user-bob');
            const stats = await service.getStatistics();
            expect(stats.totalInstalls).toBe(2);
        });
    });
    describe('Deletion', () => {
        it('should delete extension', async () => {
            const manifest = createManifest();
            const buffer = Buffer.from('mock vsix content');
            await service.publishExtension(manifest, buffer, 'test-user', 'private');
            await service.deleteExtension('test-pub.test-ext');
            const result = await service.getExtension('test-pub.test-ext');
            expect(result).toBeUndefined();
        });
        it('should emit extension-deleted event', async () => {
            return new Promise((resolve) => {
                service.once('extension-deleted', ({ extensionId }) => {
                    expect(extensionId).toBe('test-pub.test-ext');
                    resolve();
                });
                const manifest = createManifest();
                const buffer = Buffer.from('mock vsix content');
                service.publishExtension(manifest, buffer, 'test-user', 'private')
                    .then(() => service.deleteExtension('test-pub.test-ext'));
            });
        });
    });
    describe('Shutdown', () => {
        it('should shutdown gracefully', async () => {
            const svc = new ExtensionRegistryService();
            await svc.initialize();
            const manifest = createManifest();
            const buffer = Buffer.from('mock vsix content');
            await svc.publishExtension(manifest, buffer, 'test-user', 'private');
            await svc.shutdown();
            expect(true).toBe(true);
        });
    });
    describe('Singleton Pattern', () => {
        it('should use singleton instance', () => {
            const instance1 = ExtensionRegistryService.getInstance();
            const instance2 = ExtensionRegistryService.getInstance();
            expect(instance1).toBe(instance2);
        });
    });
    describe('Integration', () => {
        it('should handle complete extension lifecycle', async () => {
            // 1. Publish
            const manifest = createManifest();
            const buffer = Buffer.from('mock vsix content');
            const pkg = await service.publishExtension(manifest, buffer, 'test-user', 'private');
            expect(pkg).toBeDefined();
            // 2. Query
            const result = await service.queryExtensions({ search: 'test-ext' });
            expect(result.entries.length).toBeGreaterThan(0);
            // 3. Install
            const installed = await service.installExtension('test-pub.test-ext', 'user-alice');
            expect(installed.status).toBe('downloaded');
            // 4. Pin version
            const pin = await service.pinVersion('test-pub.test-ext', '1.0.0', 'organization', 'Stable', 'admin');
            expect(pin).toBeDefined();
            // 5. Get stats
            const stats = await service.getStatistics();
            expect(stats.totalExtensions).toBe(1);
            expect(stats.totalInstalls).toBeGreaterThan(0);
            // 6. Unpin
            await service.unpinVersion('test-pub.test-ext');
            const pins = await service.getVersionPins('test-pub.test-ext');
            expect(pins.length).toBe(0);
            // 7. Delete
            await service.deleteExtension('test-pub.test-ext');
            const deleted = await service.getExtension('test-pub.test-ext');
            expect(deleted).toBeUndefined();
        });
        it('should manage multiple extensions', async () => {
            const buffer = Buffer.from('mock vsix content');
            const m1 = createManifest('auth', 'corp', '1.0.0');
            const m2 = createManifest('debug', 'corp', '1.0.0');
            const m3 = createManifest('theme', 'other', '1.0.0');
            await service.publishExtension(m1, buffer, 'user1', 'private');
            await service.publishExtension(m2, buffer, 'user2', 'internal');
            await service.publishExtension(m3, buffer, 'user3', 'public');
            const allExts = await service.getAllExtensions();
            expect(allExts.length).toBe(3);
            const corpExts = await service.queryExtensions({ publisher: 'corp' });
            expect(corpExts.entries.length).toBe(2);
            const stats = await service.getStatistics();
            expect(stats.totalExtensions).toBe(3);
            expect(stats.extensionsByPublisher['corp']).toBe(2);
            expect(stats.extensionsByPublisher['other']).toBe(1);
        });
    });
});
//# sourceMappingURL=extension-registry-service.test.js.map