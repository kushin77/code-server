/**
 * @file        apps/backend/src/services/e2ee/types.ts
 * @module      security/e2ee
 * @description End-to-end encryption type definitions for collaboration messages
 */

/**
 * Encryption algorithm
 */
export type EncryptionAlgorithm = 'megolm' | 'olm';

/**
 * Message content type
 */
export type MessageContentType =
  | 'text'
  | 'mention'
  | 'edit'
  | 'delete'
  | 'reaction'
  | 'thread-reply';

/**
 * Encryption key material
 */
export interface EncryptionKey {
  id: string; // Key ID
  algorithm: EncryptionAlgorithm;
  publicKey?: string; // For key exchange
  createdAt: number;
  rotatedAt?: number; // When last rotated
  expiresAt?: number; // Optional expiration
}

/**
 * Session key (for Megolm)
 */
export interface SessionKey {
  id: string;
  roomId: string;
  createdAt: number;
  messageIndex: number; // Forward secrecy: index of first message in session
  creatorUserId: string;
}

/**
 * Device fingerprint
 */
export interface DeviceFingerprint {
  userId: string;
  deviceId: string;
  fingerprint: string; // Curve25519 key
  ed25519Key: string; // Ed25519 signing key
  verified: boolean;
  verifiedAt?: number;
  lastSeen: number;
}

/**
 * Encrypted message
 */
export interface EncryptedMessage {
  id: string;
  roomId: string; // Collaboration room
  senderId: string;
  sentAt: number;

  // Encryption metadata
  algorithm: EncryptionAlgorithm;
  senderKey: string; // Curve25519 key
  ciphertext: string; // Base64-encoded encrypted content
  sessionId: string; // Megolm session ID

  // Message content (encrypted, decrypted locally only)
  type: MessageContentType;
  encryptedContent?: string; // For temporary client-side storage

  // Authentication
  signature?: string; // Ed25519 signature
  deviceId?: string; // Sender device ID

  // Metadata
  unencryptedMetadata?: {
    mentions?: string[]; // User IDs (unencrypted for notifications)
    reactions?: Record<string, number>; // emoji -> count (unencrypted)
  };
}

/**
 * Decrypted message content
 */
export interface MessageContent {
  type: MessageContentType;
  body: string;
  formattedBody?: string; // HTML or markdown
  relatesTo?: {
    eventId: string;
    relType: 'reply' | 'annotation';
  };
}

/**
 * Encryption context
 */
export interface EncryptionContext {
  userId: string;
  deviceId: string;
  roomId: string;
  sessionKey: SessionKey;
  deviceKeys: Map<string, DeviceFingerprint>;
  algorithm: EncryptionAlgorithm;
}

/**
 * Key rotation policy
 */
export interface KeyRotationPolicy {
  algorithmic: EncryptionAlgorithm;
  rotationIntervalMs: number; // Default 24 hours
  forwardSecrecyMessages: number; // Rotate after N messages
  deviceRotationMs?: number; // Per-device key rotation
}

/**
 * Key backup configuration
 */
export interface KeyBackup {
  id: string;
  userId: string;
  createdAt: number;
  lastBackupAt?: number;
  version: number;
  backupMethod: 'vault' | 'password'; // Vault or password-based
  encryptedBackup: string; // Encrypted backup data
  metadata?: {
    deviceCount?: number;
    keyCount?: number;
  };
}

/**
 * E2EE capability
 */
export interface E2EECapability {
  supported: boolean;
  algorithms: EncryptionAlgorithm[];
  keyRotation: KeyRotationPolicy;
  keyBackup: boolean;
  forwardSecrecy: boolean; // Megolm property
  deviceVerification: boolean;
}

/**
 * Encryption event
 */
export interface E2EEEvent {
  type:
    | 'key-generated'
    | 'session-created'
    | 'key-rotated'
    | 'backup-created'
    | 'device-verified'
    | 'device-unverified'
    | 'message-encrypted'
    | 'message-decrypted';
  userId: string;
  timestamp: number;
  details?: Record<string, any>;
}

/**
 * Encryption statistics
 */
export interface E2EEStats {
  totalMessages: number;
  encryptedMessages: number;
  decryptedMessages: number;
  failedDecryptions: number;
  averageDecryptionTime: number; // ms
  keyRotations: number;
  backups: number;
  verifiedDevices: number;
  unverifiedDevices: number;
  encryptionRate: number; // % of messages encrypted
}

/**
 * Message authentication result
 */
export interface AuthenticationResult {
  verified: boolean;
  fromDevice: string;
  timestamp: number;
  error?: string;
}

/**
 * Decryption attempt result
 */
export interface DecryptionResult {
  success: boolean;
  content?: MessageContent;
  decryptionTime: number; // ms
  algorithm: EncryptionAlgorithm;
  error?: string;
  recoverable: boolean; // Can be decrypted with key recovery
}
