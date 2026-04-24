/**
 * @file        apps/backend/src/services/ephemeral-creds/types.ts
 * @module      security/ephemeral-credentials
 * @description Ephemeral credential type definitions
 */

/**
 * Credential type
 */
export type CredentialType = 'database' | 'cloud' | 'api' | 'git' | 'ssh' | 'oauth';

/**
 * Credential status
 */
export type CredentialStatus =
  | 'requested'
  | 'generating'
  | 'ready'
  | 'rotated'
  | 'revoking'
  | 'revoked'
  | 'expired'
  | 'failed';

/**
 * Cloud provider
 */
export type CloudProvider = 'aws' | 'gcp' | 'azure';

/**
 * Database engine
 */
export type DatabaseEngine = 'postgres' | 'mysql' | 'mongodb' | 'redis';

/**
 * Ephemeral credential
 */
export interface EphemeralCredential {
  id: string;
  sessionId: string;
  userId: string;

  // Credential metadata
  type: CredentialType;
  status: CredentialStatus;
  resourceName: string; // Database name, cloud project, etc.

  // Actual credential (encrypted)
  username?: string;
  password?: string; // Encrypted
  token?: string; // Encrypted
  secretKey?: string; // Encrypted

  // Vault metadata
  vaultPath?: string; // Path in Vault where credential generated
  leaseDuration: number; // Duration in seconds
  renewBefore: number; // Renew before expiration (ms)

  // Lifecycle
  createdAt: number;
  expiresAt: number;
  rotatedAt?: number;
  revokedAt?: number;

  // Usage tracking
  usageCount: number;
  lastUsedAt?: number;

  // Cloud-specific metadata
  provider?: CloudProvider;
  region?: string;
  role?: string; // IAM role for cloud credentials

  // Database-specific metadata
  databaseEngine?: DatabaseEngine;
  permissions?: string[]; // SELECT, INSERT, UPDATE, DELETE
  defaultDatabase?: string;
}

/**
 * Credential request
 */
export interface CredentialRequest {
  id: string;
  sessionId: string;
  userId: string;
  type: CredentialType;
  resourceName: string;
  leaseDuration: number;
  requestedAt: number;
  status: 'pending' | 'approved' | 'denied' | 'fulfilled';
  denialReason?: string;
}

/**
 * Credential rotation event
 */
export interface RotationEvent {
  credentialId: string;
  previousId?: string;
  rotatedAt: number;
  reason: 'scheduled' | 'manual' | 'security-incident';
  duration: number; // Rotation duration in ms
}

/**
 * Credential revocation
 */
export interface RevocationEvent {
  credentialId: string;
  revokedAt: number;
  reason: 'session-ended' | 'manual' | 'expired' | 'security-incident';
  revokeTime: number; // Time to revoke in ms
}

/**
 * Vault configuration
 */
export interface VaultConfig {
  address: string; // Vault server address
  token: string; // Vault authentication token (encrypted)
  namespace?: string;
  authMethod: 'token' | 'oidc' | 'kubernetes';
  databaseMount: string; // Path to database secret engine
  awsMount?: string; // Path to AWS secret engine
  gcpMount?: string; // Path to GCP secret engine
  ttl: number; // Default TTL in seconds
}

/**
 * Lease information
 */
export interface LeaseInfo {
  leaseId: string;
  createdAt: number;
  expiresAt: number;
  renewable: boolean;
  duration: number;
}

/**
 * Ephemeral credentials statistics
 */
export interface EphemeralCredsStats {
  totalCredentials: number;
  activeCredentials: number;
  rotatedCredentials: number;
  revokedCredentials: number;
  expiredCredentials: number;
  failedCredentials: number;

  averageLeaseTime: number; // milliseconds
  averageRotationTime: number; // milliseconds
  averageRevocationTime: number; // milliseconds

  byType: Record<CredentialType, number>;
  byStatus: Record<CredentialStatus, number>;
  byUser: Record<string, number>;
  bySession: Record<string, number>;

  requestsApproved: number;
  requestsDenied: number;
  rotationCount: number;
  revocationCount: number;
}

/**
 * Rotation policy
 */
export interface RotationPolicy {
  enabled: boolean;
  rotationIntervalMs: number; // Default 24 hours
  rotationBefore: number; // Rotate before expiration (ms)
  maxAge: number; // Max age before forced rotation
  automaticRotation: boolean;
}

/**
 * Ephemeral credentials event
 */
export interface EphemeralCredsEvent {
  type:
    | 'credential-requested'
    | 'credential-generated'
    | 'credential-rotated'
    | 'credential-renewed'
    | 'credential-revoked'
    | 'credential-expired'
    | 'credential-failed';
  credentialId: string;
  sessionId: string;
  userId: string;
  timestamp: number;
  details?: Record<string, any>;
}

/**
 * Session credential bundle
 */
export interface SessionCredentialBundle {
  sessionId: string;
  userId: string;
  credentials: EphemeralCredential[];
  createdAt: number;
  expiresAt: number;
  allRevokedAt?: number;
}
