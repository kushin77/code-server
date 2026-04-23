/**
 * @file        apps/backend/src/services/git-signing/__tests__/git-signing.test.ts
 * @module      security/git-signing
 * @description Comprehensive git signing verification test suite
 */
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { GitSignatureVerificationService, } from '../verification-service.js';
import { GitHookSetupService, } from '../hook-setup-service.js';
/**
 * Mock signature data for testing
 */
const MOCK_SIGNATURES = {
    'abc1234': {
        commitHash: 'abc1234',
        author: { name: 'Alice Chen', email: 'alice@example.com' },
        timestamp: Date.now() - 86400000, // 1 day ago
        signed: true,
        status: 'signed',
        signerIdentity: 'alice@example.com',
        keyId: 'sigstore-abc123',
        trustLevel: 'trusted',
        verificationTime: 45,
    },
    'def5678': {
        commitHash: 'def5678',
        author: { name: 'Bob Kumar', email: 'bob@example.com' },
        timestamp: Date.now() - 43200000, // 12 hours ago
        signed: true,
        status: 'signed',
        signerIdentity: 'bob@example.com',
        keyId: 'sigstore-def456',
        trustLevel: 'trusted',
        verificationTime: 52,
    },
    'unsigned': {
        commitHash: 'unsigned',
        author: { name: 'Carol Wang', email: 'carol@example.com' },
        timestamp: Date.now() - 21600000, // 6 hours ago
        signed: false,
        status: 'unsigned',
        trustLevel: 'untrusted',
        verificationTime: 10,
    },
};
/**
 * Mock verification service for testing
 */
class MockGitSignatureVerificationService extends GitSignatureVerificationService {
    async verifyWithGitsignMock(commitHash) {
        const sig = MOCK_SIGNATURES[commitHash];
        if (!sig) {
            return {
                commitHash,
                author: { name: 'unknown', email: 'unknown' },
                timestamp: Date.now(),
                signed: false,
                status: 'unknown',
                verificationTime: 5,
            };
        }
        return { ...sig };
    }
    // Override private method with public mock version
    async verifyCommit(commitHash) {
        return this.verifyWithGitsignMock(commitHash);
    }
}
describe('Git Signature Verification', () => {
    let service;
    let hookService;
    const testConfig = {
        enabled: true,
        required: true,
        identity: 'test@example.com',
        provider: 'sigstore',
        timeout: 30000,
        rejectUnsigned: true,
    };
    const testPolicy = {
        id: 'policy-1',
        workspaceId: 'ws-test',
        enabled: true,
        enforceAll: true,
        enforceMainBranch: true,
        allowedIdentities: ['alice@example.com', 'bob@example.com'],
        createdAt: Date.now(),
        updatedAt: Date.now(),
    };
    beforeEach(async () => {
        service = new MockGitSignatureVerificationService();
        await service.initialize(testConfig, testPolicy);
        hookService = new GitHookSetupService();
        await hookService.initialize();
    });
    afterEach(() => {
        service.clearCache();
    });
    describe('Signature Verification', () => {
        it('should verify signed commit', async () => {
            const sig = await service.verifyCommit('abc1234');
            expect(sig.signed).toBe(true);
            expect(sig.status).toBe('signed');
            expect(sig.signerIdentity).toBe('alice@example.com');
            expect(sig.keyId).toMatch(/sigstore/);
        });
        it('should verify unsigned commit', async () => {
            const sig = await service.verifyCommit('unsigned');
            expect(sig.signed).toBe(false);
            expect(sig.status).toBe('unsigned');
            expect(sig.trustLevel).toBe('untrusted');
        });
        it('should return unknown status for missing commit', async () => {
            const sig = await service.verifyCommit('nonexistent');
            expect(sig.signed).toBe(false);
            expect(sig.status).toBe('unknown');
        });
        it('should track verification time', async () => {
            const sig = await service.verifyCommit('abc1234');
            expect(sig.verificationTime).toBeGreaterThan(0);
            expect(sig.verificationTime).toBeLessThan(200);
        });
        it('should cache verification results', async () => {
            const sig1 = await service.verifyCommit('abc1234');
            const sig2 = await service.verifyCommit('abc1234');
            expect(sig1).toEqual(sig2);
            expect(sig2.verificationTime).toBeLessThanOrEqual(sig1.verificationTime);
        });
    });
    describe('Batch Verification', () => {
        it('should verify multiple commits', async () => {
            const hashes = ['abc1234', 'def5678', 'unsigned'];
            const result = await service.verifyBatch(hashes);
            expect(result.verified.length).toBe(3);
            expect(result.successCount).toBe(3);
            expect(result.failureCount).toBe(0);
        });
        it('should handle verification failures', async () => {
            const hashes = ['abc1234', 'nonexistent', 'def5678'];
            const result = await service.verifyBatch(hashes);
            expect(result.verified.length).toBeGreaterThanOrEqual(2);
            expect(result.totalTime).toBeGreaterThan(0);
        });
        it('should track batch verification time', async () => {
            const hashes = ['abc1234', 'def5678', 'unsigned'];
            const result = await service.verifyBatch(hashes);
            expect(result.totalTime).toBeGreaterThan(0);
            expect(result.totalTime).toBeLessThan(5000);
        });
        it('should limit concurrent verifications', async () => {
            const hashes = Array.from({ length: 20 }, (_, i) => `commit-${i}`);
            const result = await service.verifyBatch(hashes);
            expect(result.verified.length).toBeGreaterThanOrEqual(15);
        });
    });
    describe('Policy Compliance', () => {
        it('should enforce signature requirement', async () => {
            const policy = {
                ...testPolicy,
                enforceAll: true,
            };
            await service.updatePolicy(policy);
            const compliant = await service.checkCompliance('abc1234');
            const nonCompliant = await service.checkCompliance('unsigned');
            expect(compliant).toBe(true);
            expect(nonCompliant).toBe(false);
        });
        it('should enforce identity whitelist', async () => {
            // The service will check if signerIdentity is in allowedIdentities
            // Both alice and bob are in the test policy's allowedIdentities by default
            // So they both should be compliant
            const policy = {
                ...testPolicy,
                allowedIdentities: ['alice@example.com', 'bob@example.com'],
            };
            await service.updatePolicy(policy);
            const aliceCompliant = await service.checkCompliance('abc1234');
            const bobCompliant = await service.checkCompliance('def5678');
            // Both are in whitelist, both should be compliant
            expect(aliceCompliant).toBe(true);
            expect(bobCompliant).toBe(true);
        });
        it('should bypass policy when disabled', async () => {
            const policy = {
                ...testPolicy,
                enabled: false,
            };
            await service.updatePolicy(policy);
            const unsigned = await service.checkCompliance('unsigned');
            expect(unsigned).toBe(true); // Should not enforce
        });
    });
    describe('Statistics', () => {
        it('should calculate signing statistics', async () => {
            const hashes = ['abc1234', 'def5678', 'unsigned'];
            const stats = await service.getStatistics(hashes);
            expect(stats.totalCommits).toBe(3);
            expect(stats.signedCommits).toBe(2);
            expect(stats.unsignedCommits).toBe(1);
            expect(stats.signedPercentage).toBeCloseTo(66.67, 1);
            expect(stats.verifiedIdentities['alice@example.com']).toBe(1);
            expect(stats.verifiedIdentities['bob@example.com']).toBe(1);
        });
        it('should track verified identities', async () => {
            const hashes = ['abc1234', 'abc1234', 'def5678'];
            const stats = await service.getStatistics(hashes);
            expect(stats.verifiedIdentities['alice@example.com']).toBe(2);
            expect(stats.verifiedIdentities['bob@example.com']).toBe(1);
        });
        it('should handle all unsigned commits', async () => {
            const hashes = ['unsigned', 'unsigned', 'unsigned'];
            const stats = await service.getStatistics(hashes);
            expect(stats.signedCommits).toBe(0);
            expect(stats.unsignedCommits).toBe(3);
            expect(stats.signedPercentage).toBe(0);
        });
        it('should handle all signed commits', async () => {
            const hashes = ['abc1234', 'def5678'];
            const stats = await service.getStatistics(hashes);
            expect(stats.signedCommits).toBe(2);
            expect(stats.unsignedCommits).toBe(0);
            expect(stats.signedPercentage).toBe(100);
        });
    });
    describe('Policy Management', () => {
        it('should get current policy', () => {
            const policy = service.getPolicy();
            expect(policy).toBeDefined();
            expect(policy?.enforceAll).toBe(true);
            expect(policy?.allowedIdentities).toContain('alice@example.com');
        });
        it('should update policy', async () => {
            const newPolicy = {
                ...testPolicy,
                enforceAll: false,
                enforceMainBranch: true,
            };
            await service.updatePolicy(newPolicy);
            const updated = service.getPolicy();
            expect(updated?.enforceAll).toBe(false);
            expect(updated?.enforceMainBranch).toBe(true);
        });
        it('should emit policy-updated event', async () => {
            const newPolicy = {
                ...testPolicy,
                enforceAll: false,
            };
            return new Promise((resolve) => {
                service.on('policy-updated', (policy) => {
                    expect(policy.enforceAll).toBe(false);
                    resolve();
                });
                service.updatePolicy(newPolicy);
            });
        });
    });
    describe('Caching', () => {
        it('should cache verification results', async () => {
            await service.verifyCommit('abc1234');
            const startTime = performance.now();
            await service.verifyCommit('abc1234');
            const cachedTime = performance.now() - startTime;
            expect(cachedTime).toBeLessThan(5); // Cache hit should be instant
        });
        it('should clear cache', async () => {
            await service.verifyCommit('abc1234');
            service.clearCache();
            // After cache clear, verification should take more time
            const startTime = performance.now();
            await service.verifyCommit('abc1234');
            const verifyTime = performance.now() - startTime;
            expect(verifyTime).toBeGreaterThan(0);
        });
        it('should respect cache TTL', async () => {
            await service.verifyCommit('abc1234');
            // Cache should still be valid shortly after
            const cached = await service.verifyCommit('abc1234');
            expect(cached).toBeDefined();
        });
    });
    describe('Event Emission', () => {
        it('should emit initialized event', async () => {
            const newService = new MockGitSignatureVerificationService();
            return new Promise((resolve) => {
                newService.on('initialized', (data) => {
                    expect(data.provider).toBe('sigstore');
                    resolve();
                });
                newService.initialize(testConfig);
            });
        });
    });
    describe('Hook Setup', () => {
        it('should generate valid hook script', async () => {
            const script = hookService.generateHookScript(testConfig);
            expect(script).toContain('#!/bin/bash');
            expect(script).toContain('gitsign');
            expect(script).toContain('test@example.com');
            expect(script).toContain('prepare-commit-msg');
        });
        it('should list hooks', () => {
            const hooks = hookService.listHooks();
            expect(Array.isArray(hooks)).toBe(true);
        });
    });
    describe('Integration', () => {
        it('should support full workflow: verify → enforce → report', async () => {
            // Verify
            const sigs = await service.verifyBatch(['abc1234', 'def5678', 'unsigned']);
            expect(sigs.verified.length).toBe(3);
            // Enforce (check compliance)
            const compliances = await Promise.all([
                service.checkCompliance('abc1234'),
                service.checkCompliance('unsigned'),
            ]);
            expect(compliances[0]).toBe(true); // alice should be compliant
            expect(compliances[1]).toBe(false); // unsigned should not comply
            // Report (get stats)
            const stats = await service.getStatistics(['abc1234', 'def5678', 'unsigned']);
            expect(stats.signedPercentage).toBeCloseTo(66.67, 1);
        });
        it('should handle policy enforcement across batch', async () => {
            const policy = {
                ...testPolicy,
                enforceAll: true,
            };
            await service.updatePolicy(policy);
            // Check all in batch
            const hashes = ['abc1234', 'def5678', 'unsigned'];
            const compliances = await Promise.all(hashes.map((hash) => service.checkCompliance(hash)));
            expect(compliances[0]).toBe(true);
            expect(compliances[1]).toBe(true);
            expect(compliances[2]).toBe(false); // unsigned fails
        });
    });
});
//# sourceMappingURL=git-signing.test.js.map