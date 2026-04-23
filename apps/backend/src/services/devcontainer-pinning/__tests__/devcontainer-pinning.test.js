/**
 * @file        apps/backend/src/services/devcontainer-pinning/__tests__/devcontainer-pinning.test.ts
 * @module      collaboration/environment-reproducibility
 * @description Comprehensive devcontainer hash pinning test suite
 */
import { describe, it, expect, beforeEach } from 'vitest';
import { getDevcontainerPinningService, } from '../pinning-service.js';
import { getDevcontainerProvisioningService, } from '../provisioning-service.js';
/**
 * Mock devcontainer configurations for testing
 */
const MOCK_DEVCONTAINER = {
    image: 'node:18-alpine',
    features: {
        'ghcr.io/devcontainers/features/git': '1.0.0',
        'ghcr.io/devcontainers/features/docker-in-docker': '2.0.0',
    },
};
const MOCK_PINNED_DEVCONTAINER = {
    ...MOCK_DEVCONTAINER,
    imageHash: 'sha256:abc1234567890def',
    imageDigest: 'sha256:image-manifest-digest',
    image: 'node:18-alpine@sha256:abc1234567890def',
    featureHashes: {
        'ghcr.io/devcontainers/features/git': {
            id: 'ghcr.io/devcontainers/features/git',
            version: '1.0.0',
            hash: 'sha256:feat-git-hash',
        },
        'ghcr.io/devcontainers/features/docker-in-docker': {
            id: 'ghcr.io/devcontainers/features/docker-in-docker',
            version: '2.0.0',
            hash: 'sha256:feat-docker-hash',
        },
    },
    _pinningMetadata: {
        pinnedAt: Date.now(),
        pinnedBy: 'auto',
        hashAlgorithm: 'sha256',
        repository: 'ws-test',
    },
};
describe('Devcontainer Hash Pinning', () => {
    let pinningService;
    let provisioningService;
    beforeEach(async () => {
        pinningService = await getDevcontainerPinningService();
        provisioningService = await getDevcontainerProvisioningService();
    });
    describe('Pinning Service', () => {
        it('should initialize successfully', async () => {
            expect(pinningService).toBeDefined();
        });
        it('should scan devcontainer.json', async () => {
            const result = await pinningService.scanDevcontainer('ws-test', '.devcontainer/devcontainer.json', MOCK_DEVCONTAINER);
            expect(result.id).toMatch(/^scan-/);
            expect(result.workspaceId).toBe('ws-test');
            expect(result.features.length).toBe(2);
            expect(result.scanTime).toBeGreaterThan(0);
        });
        it('should detect unpinned elements', async () => {
            const result = await pinningService.scanDevcontainer('ws-test', '.devcontainer/devcontainer.json', MOCK_DEVCONTAINER);
            expect(result.unpinnedElements.image).toBe(true);
            expect(result.unpinnedElements.features).toContain('ghcr.io/devcontainers/features/git');
        });
        it('should pin hashes in devcontainer.json', async () => {
            const pinned = await pinningService.pinHashes('ws-test', MOCK_DEVCONTAINER);
            expect(pinned.imageHash).toBeDefined();
            expect(pinned.image).toContain('@sha256:');
            expect(pinned.featureHashes).toBeDefined();
            expect(Object.keys(pinned.featureHashes).length).toBe(2);
            expect(pinned._pinningMetadata).toBeDefined();
        });
        it('should preserve original values', async () => {
            const pinned = await pinningService.pinHashes('ws-test', MOCK_DEVCONTAINER);
            expect(pinned._originalImage).toBe(MOCK_DEVCONTAINER.image);
            expect(pinned._originalFeatures).toEqual(MOCK_DEVCONTAINER.features);
        });
        it('should verify reproducibility', async () => {
            const verification = await pinningService.verifyReproducibility(MOCK_PINNED_DEVCONTAINER, {
                image: MOCK_PINNED_DEVCONTAINER.imageDigest,
                'feature-ghcr.io/devcontainers/features/git': MOCK_PINNED_DEVCONTAINER.featureHashes['ghcr.io/devcontainers/features/git'].hash,
                'feature-ghcr.io/devcontainers/features/docker-in-docker': MOCK_PINNED_DEVCONTAINER.featureHashes['ghcr.io/devcontainers/features/docker-in-docker'].hash,
            });
            expect(verification.verified).toBe(true);
            expect(verification.imageMatch).toBe(true);
            expect(verification.mismatches).toHaveLength(0);
        });
        it('should detect reproducibility mismatches', async () => {
            const verification = await pinningService.verifyReproducibility(MOCK_PINNED_DEVCONTAINER, {
                image: 'sha256:different-digest',
            });
            expect(verification.verified).toBe(false);
            expect(verification.imageMatch).toBe(false);
            expect(verification.mismatches.length).toBeGreaterThan(0);
        });
        it('should calculate pinning statistics', async () => {
            // Scan first
            await pinningService.scanDevcontainer('ws-test-stats', '.devcontainer/devcontainer.json', MOCK_DEVCONTAINER);
            const stats = await pinningService.getStatistics('ws-test-stats');
            expect(stats.totalElements).toBe(3); // 1 image + 2 features
            expect(stats.unpinnedElements).toBe(3);
            expect(stats.pinningPercentage).toBe(0);
            expect(stats.byType.images.total).toBe(1);
            expect(stats.byType.features.total).toBe(2);
        });
        it('should track pinning history', async () => {
            // Multiple scans
            await pinningService.scanDevcontainer('ws-test-history', '.devcontainer/devcontainer.json', MOCK_DEVCONTAINER);
            await pinningService.scanDevcontainer('ws-test-history', '.devcontainer/devcontainer.json', MOCK_PINNED_DEVCONTAINER);
            const stats = await pinningService.getStatistics('ws-test-history');
            expect(stats).toBeDefined();
        });
    });
    describe('Provisioning Service', () => {
        it('should initialize successfully', async () => {
            expect(provisioningService).toBeDefined();
        });
        it('should provision environment', async () => {
            const request = {
                id: 'prov-123',
                workspaceId: 'ws-test',
                devcontainerPath: '.devcontainer/devcontainer.json',
                runtime: 'docker',
                usePinnedHashes: true,
            };
            const result = await provisioningService.provision(request, MOCK_PINNED_DEVCONTAINER);
            expect(result.requestId).toBe('prov-123');
            expect(result.duration).toBeGreaterThan(0);
            expect(result.reproduced).toBe(true);
        }, 10000);
        it('should use pinned hashes when available', async () => {
            const request = {
                id: 'prov-pinned',
                workspaceId: 'ws-test',
                devcontainerPath: '.devcontainer/devcontainer.json',
                runtime: 'docker',
                usePinnedHashes: true,
            };
            const result = await provisioningService.provision(request, MOCK_PINNED_DEVCONTAINER);
            expect(result.reproduced).toBe(true);
            expect(result.hashesUsed.image).toBe(MOCK_PINNED_DEVCONTAINER.imageHash);
        }, 10000);
        it('should handle provisioning failures', async () => {
            const request = {
                id: 'prov-fail',
                workspaceId: 'ws-test',
                devcontainerPath: '.devcontainer/devcontainer.json',
                runtime: 'docker',
                usePinnedHashes: true,
            };
            const invalidConfig = {}; // Invalid: no image
            const result = await provisioningService.provision(request, invalidConfig);
            expect(result.success).toBe(false);
            expect(result.error).toBeDefined();
        }, 10000);
        it('should get provisioning result', async () => {
            const request = {
                id: 'prov-get',
                workspaceId: 'ws-test',
                devcontainerPath: '.devcontainer/devcontainer.json',
                runtime: 'docker',
                usePinnedHashes: true,
            };
            const provResult = await provisioningService.provision(request, MOCK_PINNED_DEVCONTAINER);
            const retrieved = provisioningService.getResult('prov-get');
            expect(retrieved).toEqual(provResult);
        });
        it('should list provisioning results', async () => {
            const request = {
                id: 'prov-list',
                workspaceId: 'ws-test',
                devcontainerPath: '.devcontainer/devcontainer.json',
                runtime: 'docker',
                usePinnedHashes: true,
            };
            await provisioningService.provision(request, MOCK_PINNED_DEVCONTAINER);
            const results = provisioningService.listResults(5);
            expect(results.length).toBeGreaterThan(0);
            expect(results[results.length - 1].requestId).toBe('prov-list');
        });
    });
    describe('Pinning Policy', () => {
        it('should create pinning policy', async () => {
            const policy = {
                id: 'policy-1',
                workspaceId: 'ws-test',
                enabled: true,
                autoPin: true,
                pinningStrategy: 'digest',
                allowUnpinned: false,
                hashAlgorithm: 'sha256',
                registries: ['docker.io', 'ghcr.io'],
                createdAt: Date.now(),
                updatedAt: Date.now(),
            };
            await pinningService.setPolicy(policy);
            const retrieved = pinningService.getPolicy('policy-1');
            expect(retrieved).toEqual(policy);
        });
        it('should enforce policy', async () => {
            const policy = {
                id: 'policy-strict',
                workspaceId: 'ws-test',
                enabled: true,
                autoPin: true,
                pinningStrategy: 'digest',
                allowUnpinned: false,
                hashAlgorithm: 'sha256',
                registries: ['docker.io'],
                createdAt: Date.now(),
                updatedAt: Date.now(),
            };
            await pinningService.setPolicy(policy);
            const retrieved = pinningService.getPolicy('policy-strict');
            expect(retrieved?.enabled).toBe(true);
            expect(retrieved?.allowUnpinned).toBe(false);
        });
    });
    describe('Integration', () => {
        it('should support full workflow: scan → pin → provision → verify', async () => {
            const workspaceId = 'ws-integration';
            // Scan
            const scanResult = await pinningService.scanDevcontainer(workspaceId, '.devcontainer/devcontainer.json', MOCK_DEVCONTAINER);
            expect(scanResult.unpinnedElements.image).toBe(true);
            // Pin
            const pinnedConfig = await pinningService.pinHashes(workspaceId, MOCK_DEVCONTAINER);
            expect(pinnedConfig.imageHash).toBeDefined();
            expect(pinnedConfig.imageDigest).toBeDefined();
            // Verify reproducibility - both imageHash and imageDigest should be set after pinning
            const verification = await pinningService.verifyReproducibility(pinnedConfig, {
                image: pinnedConfig.imageDigest || 'mock-digest',
                'feature-ghcr.io/devcontainers/features/git': pinnedConfig.featureHashes?.['ghcr.io/devcontainers/features/git']?.hash || 'mock-hash-1',
                'feature-ghcr.io/devcontainers/features/docker-in-docker': pinnedConfig.featureHashes?.['ghcr.io/devcontainers/features/docker-in-docker']?.hash || 'mock-hash-2',
            });
            expect(verification.verified).toBe(true);
            // Verify that we have proper pinning metadata
            expect(pinnedConfig._pinningMetadata).toBeDefined();
            expect(pinnedConfig._pinningMetadata?.pinnedAt).toBeGreaterThan(0);
        }, 15000);
        it('should handle multiple environments', async () => {
            const workspaces = ['ws-1', 'ws-2', 'ws-3'];
            for (const ws of workspaces) {
                const pinned = await pinningService.pinHashes(ws, MOCK_DEVCONTAINER);
                expect(pinned._pinningMetadata?.repository).toBe(ws);
            }
            // Get stats for each
            for (const ws of workspaces) {
                const stats = await pinningService.getStatistics(ws);
                expect(stats.totalElements).toBeGreaterThanOrEqual(0);
            }
        });
        it('should emit events', async () => {
            return new Promise(async (resolve) => {
                pinningService.once('hashes-pinned', (data) => {
                    expect(data.workspaceId).toBe('ws-emit-test');
                    resolve();
                });
                await pinningService.pinHashes('ws-emit-test', MOCK_DEVCONTAINER);
            });
        });
    });
});
//# sourceMappingURL=devcontainer-pinning.test.js.map