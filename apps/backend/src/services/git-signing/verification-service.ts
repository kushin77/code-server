/**
 * @file        apps/backend/src/services/git-signing/verification-service.ts
 * @module      security/git-signing
 * @description Git signature verification with Sigstore/Gitsign integration
 */

import { spawn } from 'child_process';
import { EventEmitter } from 'events';
import {
  CommitSignature,
  GitsignConfig,
  SignatureBatchResult,
  SigningPolicy,
  SignatureStatus,
  VerificationResponse,
  SigningStats,
} from './types.js';

/**
 * GitSignatureVerificationService: Verify and enforce signed commits
 */
export class GitSignatureVerificationService extends EventEmitter {
  private config: GitsignConfig | null = null;
  private policy: SigningPolicy | null = null;
  private isInitialized = false;
  private verificationCache = new Map<string, CommitSignature>();
  private cacheMaxSize = 1000;
  private cacheTtlMs = 3600000; // 1 hour

  /**
   * Initialize with configuration
   */
  async initialize(config: GitsignConfig, policy?: SigningPolicy): Promise<void> {
    if (this.isInitialized) return;

    this.config = config;
    this.policy = policy || null;
    this.isInitialized = true;

    console.log(
      `[GitSignatureVerificationService] Initialized with provider: ${config.provider}`
    );
    this.emit('initialized', { provider: config.provider });
  }

  /**
   * Verify a single commit signature
   */
  async verifyCommit(commitHash: string): Promise<CommitSignature> {
    if (!this.config) throw new Error('Service not initialized');

    // Check cache first
    const cached = this.verificationCache.get(commitHash);
    if (cached && Date.now() - cached.timestamp < this.cacheTtlMs) {
      console.log(`[GitSignatureVerificationService] Cache hit for ${commitHash}`);
      return cached;
    }

    const startTime = performance.now();

    try {
      // Use gitsign to verify commit
      const signature = await this.verifyWithGitsign(commitHash);

      // Determine trust level
      if (this.policy?.allowedIdentities) {
        signature.trustLevel = this.policy.allowedIdentities.includes(
          signature.signerIdentity || ''
        )
          ? 'trusted'
          : 'untrusted';
      } else {
        signature.trustLevel = signature.signed ? 'unverified' : 'untrusted';
      }

      signature.verificationTime = performance.now() - startTime;

      // Cache the result
      this.cacheSignature(signature);

      console.log(
        `[GitSignatureVerificationService] Verified ${commitHash} in ${signature.verificationTime.toFixed(2)}ms`
      );

      return signature;
    } catch (error) {
      console.error(`[GitSignatureVerificationService] Verification failed:`, error);

      return {
        commitHash,
        author: { name: 'unknown', email: 'unknown' },
        timestamp: Date.now(),
        signed: false,
        status: 'unknown',
        verificationTime: performance.now() - startTime,
      };
    }
  }

  /**
   * Verify multiple commits
   */
  async verifyBatch(commitHashes: string[]): Promise<SignatureBatchResult> {
    if (!this.config) throw new Error('Service not initialized');

    const startTime = performance.now();
    const results: CommitSignature[] = [];
    const failed: Array<{ commitHash: string; reason: string }> = [];

    // Verify in parallel with concurrency limit
    const concurrency = 5;
    for (let i = 0; i < commitHashes.length; i += concurrency) {
      const batch = commitHashes.slice(i, i + concurrency);
      const verifications = await Promise.allSettled(
        batch.map((hash) => this.verifyCommit(hash))
      );

      verifications.forEach((result, idx) => {
        if (result.status === 'fulfilled') {
          results.push(result.value);
        } else {
          failed.push({
            commitHash: batch[idx],
            reason: String(result.reason),
          });
        }
      });
    }

    const totalTime = performance.now() - startTime;

    return {
      verified: results,
      failed,
      totalTime,
      successCount: results.length,
      failureCount: failed.length,
    };
  }

  /**
   * Check if commit is properly signed according to policy
   */
  async checkCompliance(commitHash: string): Promise<boolean> {
    if (!this.policy || !this.policy.enabled) return true;

    const signature = await this.verifyCommit(commitHash);

    // Check enforcement
    if (this.policy.enforceAll && !signature.signed) {
      return false;
    }

    // Check identity whitelist
    if (
      this.policy.allowedIdentities.length > 0 &&
      signature.signed &&
      signature.trustLevel !== 'trusted'
    ) {
      return false;
    }

    return true;
  }

  /**
   * Get signing compliance statistics
   */
  async getStatistics(commitHashes: string[]): Promise<SigningStats> {
    const result = await this.verifyBatch(commitHashes);
    const signatures = result.verified;

    const signed = signatures.filter((s) => s.signed);
    const identities: Record<string, number> = {};

    signed.forEach((sig) => {
      if (sig.signerIdentity) {
        identities[sig.signerIdentity] = (identities[sig.signerIdentity] || 0) + 1;
      }
    });

    return {
      totalCommits: commitHashes.length,
      signedCommits: signed.length,
      unsignedCommits: commitHashes.length - signed.length,
      signedPercentage: (signed.length / commitHashes.length) * 100,
      verifiedIdentities: identities,
      failedVerifications: result.failureCount,
      lastVerificationTime: Date.now(),
    };
  }

  /**
   * Get current policy
   */
  getPolicy(): SigningPolicy | null {
    return this.policy;
  }

  /**
   * Update policy
   */
  async updatePolicy(policy: SigningPolicy): Promise<void> {
    this.policy = policy;
    console.log(`[GitSignatureVerificationService] Policy updated`);
    this.emit('policy-updated', policy);
  }

  /**
   * Clear cache
   */
  clearCache(): void {
    this.verificationCache.clear();
    console.log('[GitSignatureVerificationService] Cache cleared');
  }

  /**
   * Private: Verify signature using gitsign
   */
  private verifyWithGitsign(commitHash: string): Promise<CommitSignature> {
    return new Promise((resolve, reject) => {
      const gitsignPath = process.env.GITSIGN_PATH || 'gitsign';

      const args = [
        'verify',
        commitHash,
        '--verbose',
        `--identity=${this.config?.identity || ''}`,
      ];

      if (this.config?.trustRoot) {
        args.push(`--trust-root=${this.config.trustRoot}`);
      }

      const timeout = setTimeout(() => {
        process.kill(proc.pid!);
        reject(new Error(`Signature verification timeout after ${this.config?.timeout}ms`));
      }, this.config?.timeout || 30000);

      let stdout = '';
      let stderr = '';

      const proc = spawn(gitsignPath, args, {
        timeout: this.config?.timeout || 30000,
        stdio: ['pipe', 'pipe', 'pipe'],
      });

      proc.stdout?.on('data', (data) => {
        stdout += data.toString();
      });

      proc.stderr?.on('data', (data) => {
        stderr += data.toString();
      });

      proc.on('close', (code) => {
        clearTimeout(timeout);

        const signature: CommitSignature = {
          commitHash,
          author: { name: 'unknown', email: 'unknown' },
          timestamp: Date.now(),
          signed: code === 0,
          status: code === 0 ? 'signed' : 'unsigned',
          keyId: this.extractKeyId(stdout),
          signerIdentity: this.extractIdentity(stdout),
        };

        if (code === 0) {
          resolve(signature);
        } else {
          signature.status = 'invalid';
          resolve(signature);
        }
      });

      proc.on('error', (err) => {
        clearTimeout(timeout);
        reject(err);
      });
    });
  }

  /**
   * Private: Extract key ID from gitsign output
   */
  private extractKeyId(output: string): string | undefined {
    const match = output.match(/KeyID:\s*([a-f0-9]+)/i);
    return match ? match[1] : undefined;
  }

  /**
   * Private: Extract identity from gitsign output
   */
  private extractIdentity(output: string): string | undefined {
    const match = output.match(/Identity:\s*([^\n]+)/i);
    return match ? match[1].trim() : undefined;
  }

  /**
   * Private: Cache signature result with LRU eviction
   */
  private cacheSignature(signature: CommitSignature): void {
    if (this.verificationCache.size >= this.cacheMaxSize) {
      // Remove oldest entry (simple FIFO for simplicity)
      const firstKey = this.verificationCache.keys().next().value;
      this.verificationCache.delete(firstKey);
    }

    this.verificationCache.set(signature.commitHash, signature);
  }
}

/**
 * Global service instance
 */
let serviceInstance: GitSignatureVerificationService | null = null;

/**
 * Get global service instance
 */
export async function getGitSignatureVerificationService(
  config: GitsignConfig,
  policy?: SigningPolicy
): Promise<GitSignatureVerificationService> {
  if (!serviceInstance) {
    serviceInstance = new GitSignatureVerificationService();
    await serviceInstance.initialize(config, policy);
  }
  return serviceInstance;
}
