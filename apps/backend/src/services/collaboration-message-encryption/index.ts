#!/usr/bin/env node
// @file        apps/backend/src/services/collaboration-message-encryption/index.ts
// @module      collaboration/message-encryption
// @description Vault-backed encryption helper for collaboration message payloads
// @owner       backend

import { createCipheriv, createDecipheriv, createHash, hkdfSync, randomBytes } from 'node:crypto';

const DEFAULT_ENCRYPTION_INFO = 'code-server:collaboration-message:v1';

export interface CollaborationMessageCipherEnvelope {
  version: 1;
  algorithm: 'aes-256-gcm';
  keyId: string;
  salt: string;
  iv: string;
  ciphertext: string;
  authTag: string;
  metadata: Record<string, unknown>;
}

export interface CollaborationMessageCiphertext {
  body: string;
  keyId: string;
  algorithm: CollaborationMessageCipherEnvelope['algorithm'];
}

export interface CollaborationMessageEncryptionOptions {
  keyMaterial?: string;
  keyId?: string;
  info?: string;
}

function parseKeyMaterial(keyMaterial: string): Buffer {
  const trimmed = keyMaterial.trim();

  if (!trimmed) {
    throw new Error('COLLABORATION_MESSAGE_ENCRYPTION_KEY is required');
  }

  if (/^[0-9a-f]{64}$/i.test(trimmed)) {
    return Buffer.from(trimmed, 'hex');
  }

  const decoded = Buffer.from(trimmed, 'base64');
  if (decoded.length === 32) {
    return decoded;
  }

  if (Buffer.byteLength(trimmed, 'utf8') === 32) {
    return Buffer.from(trimmed, 'utf8');
  }

  throw new Error('COLLABORATION_MESSAGE_ENCRYPTION_KEY must be 32 bytes (hex, base64, or utf8)');
}

function deriveKeyId(keyMaterial: Buffer): string {
  return createHash('sha256').update(keyMaterial).digest('hex').slice(0, 16);
}

function normalizeMetadata(metadata: Record<string, unknown> | undefined): Record<string, unknown> {
  return metadata ? { ...metadata } : {};
}

function deriveMessageKey(masterKey: Buffer, salt: Buffer, info: string): Buffer {
  return Buffer.from(hkdfSync('sha256', masterKey, salt, Buffer.from(info), 32));
}

function encodeEnvelope(envelope: CollaborationMessageCipherEnvelope): string {
  return JSON.stringify(envelope);
}

function decodeEnvelope(body: string): CollaborationMessageCipherEnvelope {
  const parsed = JSON.parse(body) as Partial<CollaborationMessageCipherEnvelope>;

  if (parsed.version !== 1 || parsed.algorithm !== 'aes-256-gcm') {
    throw new Error('Unsupported collaboration message envelope');
  }

  if (!parsed.keyId || !parsed.salt || !parsed.iv || !parsed.ciphertext || !parsed.authTag) {
    throw new Error('Incomplete collaboration message envelope');
  }

  return {
    version: 1,
    algorithm: 'aes-256-gcm',
    keyId: parsed.keyId,
    salt: parsed.salt,
    iv: parsed.iv,
    ciphertext: parsed.ciphertext,
    authTag: parsed.authTag,
    metadata: normalizeMetadata(parsed.metadata),
  };
}

export class CollaborationMessageEncryptionService {
  private readonly masterKey: Buffer;

  private readonly keyId: string;

  private readonly info: string;

  constructor(options: CollaborationMessageEncryptionOptions = {}) {
    const keyMaterial = options.keyMaterial ?? process.env.COLLABORATION_MESSAGE_ENCRYPTION_KEY ?? '';
    this.masterKey = parseKeyMaterial(keyMaterial);
    this.keyId = options.keyId?.trim() || process.env.COLLABORATION_MESSAGE_ENCRYPTION_KEY_ID?.trim() || deriveKeyId(this.masterKey);
    this.info = options.info?.trim() || process.env.COLLABORATION_MESSAGE_ENCRYPTION_INFO?.trim() || DEFAULT_ENCRYPTION_INFO;
  }

  encryptMessage(message: string, metadata: Record<string, unknown> = {}): CollaborationMessageCiphertext {
    const salt = randomBytes(16);
    const iv = randomBytes(12);
    const encryptionKey = deriveMessageKey(this.masterKey, salt, this.info);
    const cipher = createCipheriv('aes-256-gcm', encryptionKey, iv);
    const normalizedMetadata = normalizeMetadata(metadata);
    const aad = Buffer.from(JSON.stringify(normalizedMetadata), 'utf8');

    cipher.setAAD(aad);

    const ciphertext = Buffer.concat([cipher.update(message, 'utf8'), cipher.final()]);
    const envelope: CollaborationMessageCipherEnvelope = {
      version: 1,
      algorithm: 'aes-256-gcm',
      keyId: this.keyId,
      salt: salt.toString('base64'),
      iv: iv.toString('base64'),
      ciphertext: ciphertext.toString('base64'),
      authTag: cipher.getAuthTag().toString('base64'),
      metadata: normalizedMetadata,
    };

    return {
      body: encodeEnvelope(envelope),
      keyId: this.keyId,
      algorithm: envelope.algorithm,
    };
  }

  decryptMessage(body: string): { message: string; metadata: Record<string, unknown>; keyId: string } {
    const envelope = decodeEnvelope(body);

    if (envelope.keyId !== this.keyId) {
      throw new Error('Collaboration message was encrypted with an unknown key id');
    }

    const salt = Buffer.from(envelope.salt, 'base64');
    const iv = Buffer.from(envelope.iv, 'base64');
    const authTag = Buffer.from(envelope.authTag, 'base64');
    const encryptionKey = deriveMessageKey(this.masterKey, salt, this.info);
    const decipher = createDecipheriv('aes-256-gcm', encryptionKey, iv);
    const aad = Buffer.from(JSON.stringify(normalizeMetadata(envelope.metadata)), 'utf8');

    decipher.setAAD(aad);
    decipher.setAuthTag(authTag);

    const plaintext = Buffer.concat([
      decipher.update(Buffer.from(envelope.ciphertext, 'base64')),
      decipher.final(),
    ]).toString('utf8');

    return {
      message: plaintext,
      metadata: normalizeMetadata(envelope.metadata),
      keyId: envelope.keyId,
    };
  }
}
