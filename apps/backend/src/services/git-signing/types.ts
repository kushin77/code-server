/**
 * @file        apps/backend/src/services/git-signing/types.ts
 * @module      security/git-signing
 * @description Type definitions for Sigstore/Gitsign integration
 */

/**
 * Signature verification status
 */
export type SignatureStatus = 'signed' | 'unsigned' | 'invalid' | 'unknown' | 'trusted' | 'untrusted';

/**
 * Gitsign configuration
 */
export interface GitsignConfig {
  enabled: boolean;
  required: boolean; // Enforce signed commits
  identity: string; // Email or Sigstore identity
  provider: 'sigstore' | 'custom'; // 'sigstore' uses OpenID Connect, 'custom' for enterprise
  timeout: number; // ms to wait for signature
  trustRoot?: string; // Custom trust root URL
  rejectUnsigned: boolean; // Reject push if unsigned commits
}

/**
 * Signature record from git commit
 */
export interface CommitSignature {
  commitHash: string;
  author: {
    name: string;
    email: string;
  };
  timestamp: number;
  signed: boolean;
  status: SignatureStatus;
  signerIdentity?: string; // Sigstore identity (email for OIDC)
  keyId?: string; // Public key fingerprint
  trustLevel?: 'trusted' | 'untrusted' | 'unverified';
  verificationTime?: number; // ms spent verifying
}

/**
 * Batch signature verification result
 */
export interface SignatureBatchResult {
  verified: CommitSignature[];
  failed: Array<{ commitHash: string; reason: string }>;
  totalTime: number;
  successCount: number;
  failureCount: number;
}

/**
 * Signature enforcement policy
 */
export interface SigningPolicy {
  id: string;
  workspaceId: string;
  enabled: boolean;
  enforceAll: boolean; // All commits must be signed
  enforceMainBranch: boolean; // Only enforce on main/master
  allowedIdentities: string[]; // Whitelisted signers
  allowedIssuers?: string[]; // For OIDC (e.g., github.com)
  requiredCertificateChain?: boolean; // Verify cert chain
  createdAt: number;
  updatedAt: number;
}

/**
 * Pre-commit hook configuration for gitsign
 */
export interface PreCommitHookConfig {
  id: string;
  workspaceId: string;
  enabled: boolean;
  hookPath: string;
  gitsignPath: string; // Path to gitsign executable
  config: GitsignConfig;
  environment: Record<string, string>; // Env vars for hook
  createdAt: number;
  updatedAt: number;
}

/**
 * Signature verification result for API response
 */
export interface VerificationResponse {
  success: boolean;
  commits: CommitSignature[];
  policy?: SigningPolicy;
  recommendations?: string[];
  error?: string;
}

/**
 * Statistics for signing compliance
 */
export interface SigningStats {
  totalCommits: number;
  signedCommits: number;
  unsignedCommits: number;
  signedPercentage: number;
  verifiedIdentities: Record<string, number>; // identity -> count
  failedVerifications: number;
  lastVerificationTime?: number;
}

/**
 * Certificate information from Sigstore
 */
export interface SigntoreCertificate {
  issuer: string; // OIDC issuer (e.g., https://github.com)
  subject: string; // OIDC subject (email or gh username)
  identity: string; // Identity from cert
  certPem: string; // PEM-encoded certificate
  keyPem: string; // PEM-encoded public key
  certChain: string[]; // Full cert chain for verification
  expiresAt: number;
}

/**
 * Rekor (transparency log) entry
 */
export interface RekorEntry {
  uuid: string;
  commitHash: string;
  integratedTime: number;
  logIndex: number;
  logId: string;
  verification: {
    inclusionProof?: {
      checkpoint: string;
      hashes: string[];
      leafIndex: number;
      treeSize: number;
    };
    signedEntryTimestamp: string;
  };
}
