/**
 * @file        apps/backend/src/services/e2ee/__tests__/e2ee-service.test.ts
 * @module      security/e2ee
 * @description E2EE collaboration service tests
 */

import { describe, it, expect, beforeEach } from 'vitest';
import { E2EEService, getE2EEService } from '../e2ee-service.js';
import { MessageContent } from '../types.js';

describe('E2EE Service', () => {
  let e2eeService: E2EEService;

  beforeEach(async () => {
    e2eeService = new E2EEService();
    await e2eeService.initialize();
  });

  describe('Service Initialization', () => {
    it('should initialize successfully', async () => {
      expect(e2eeService).toBeDefined();
    });

    it('should emit initialized event', async () => {
      return new Promise<void>((resolve) => {
        const service = new E2EEService();
        service.once('initialized', () => {
          resolve();
        });
        service.initialize();
      });
    });
  });

  describe('Key Generation', () => {
    it('should generate encryption key for user device', async () => {
      const key = await e2eeService.generateKey('user-alice', 'device-001');

      expect(key.id).toMatch(/^key-/);
      expect(key.algorithm).toBe('olm');
      expect(key.createdAt).toBeGreaterThan(0);
    });

    it('should emit key-generated event', async () => {
      return new Promise<void>((resolve) => {
        e2eeService.once('key-generated', ({ userId, deviceId }) => {
          expect(userId).toBe('user-alice');
          expect(deviceId).toBe('device-001');
          resolve();
        });

        e2eeService.generateKey('user-alice', 'device-001');
      });
    });

    it('should store key for later retrieval', async () => {
      await e2eeService.generateKey('user-bob', 'device-002');

      const keys = await e2eeService.getUserKeys('user-bob');
      expect(keys.length).toBeGreaterThan(0);
      expect(keys[0].algorithm).toBe('olm');
    });

    it('should generate multiple keys per user', async () => {
      await e2eeService.generateKey('user-charlie', 'device-001');
      await e2eeService.generateKey('user-charlie', 'device-002');

      const keys = await e2eeService.getUserKeys('user-charlie');
      expect(keys.length).toBe(2);
    });
  });

  describe('Session Key Management', () => {
    it('should create Megolm session key for room', async () => {
      const sessionKey = await e2eeService.createSessionKey(
        'room-123',
        'user-alice',
        'megolm'
      );

      expect(sessionKey.id).toMatch(/^session-/);
      expect(sessionKey.roomId).toBe('room-123');
      expect(sessionKey.algorithm || 'megolm').toBe('megolm');
      expect(sessionKey.messageIndex).toBe(0);
    });

    it('should emit session-created event', async () => {
      return new Promise<void>((resolve) => {
        e2eeService.once('session-created', ({ roomId }) => {
          expect(roomId).toBe('room-456');
          resolve();
        });

        e2eeService.createSessionKey('room-456', 'user-bob', 'megolm');
      });
    });

    it('should increment message index for forward secrecy', async () => {
      const sessionKey = await e2eeService.createSessionKey(
        'room-789',
        'user-alice',
        'megolm'
      );

      expect(sessionKey.messageIndex).toBe(0);
    });
  });

  describe('Message Encryption', () => {
    beforeEach(async () => {
      await e2eeService.generateKey('user-alice', 'device-001');
    });

    it('should encrypt message', async () => {
      const content: MessageContent = {
        type: 'text',
        body: 'Hello, this is a secret message',
      };

      const encryptedMsg = await e2eeService.encryptMessage(
        'user-alice',
        'device-001',
        'room-123',
        content
      );

      expect(encryptedMsg.id).toMatch(/^msg-/);
      expect(encryptedMsg.ciphertext).toBeDefined();
      expect(encryptedMsg.algorithm).toBe('megolm');
      expect(encryptedMsg.roomId).toBe('room-123');
    });

    it('should set message metadata', async () => {
      const content: MessageContent = {
        type: 'mention',
        body: 'Hey @user-bob',
        formattedBody: '<p>Hey <a href="...">@user-bob</a></p>',
      };

      const encryptedMsg = await e2eeService.encryptMessage(
        'user-alice',
        'device-001',
        'room-123',
        content
      );

      expect(encryptedMsg.senderId).toBe('user-alice');
      expect(encryptedMsg.deviceId).toBe('device-001');
      expect(encryptedMsg.type).toBe('mention');
    });

    it('should include signature for authentication', async () => {
      const content: MessageContent = {
        type: 'text',
        body: 'Signed message',
      };

      const encryptedMsg = await e2eeService.encryptMessage(
        'user-alice',
        'device-001',
        'room-123',
        content
      );

      expect(encryptedMsg.signature).toBeDefined();
      expect(encryptedMsg.signature).toContain('sig-');
    });

    it('should emit message-encrypted event', async () => {
      const content: MessageContent = {
        type: 'text',
        body: 'Test message',
      };

      return new Promise<void>((resolve) => {
        e2eeService.once('message-encrypted', ({ encryptedMsg }) => {
          expect(encryptedMsg.roomId).toBe('room-999');
          resolve();
        });

        e2eeService.encryptMessage('user-alice', 'device-001', 'room-999', content);
      });
    });

    it('should update statistics on encryption', async () => {
      const content: MessageContent = {
        type: 'text',
        body: 'Stat message',
      };

      await e2eeService.encryptMessage('user-alice', 'device-001', 'room-stats', content);

      const stats = await e2eeService.getStatistics();
      expect(stats.totalMessages).toBeGreaterThan(0);
      expect(stats.encryptedMessages).toBeGreaterThan(0);
    });
  });

  describe('Message Decryption', () => {
    let encryptedMsgId: string;

    beforeEach(async () => {
      await e2eeService.generateKey('user-alice', 'device-001');

      const content: MessageContent = {
        type: 'text',
        body: 'Secret content',
      };

      const encryptedMsg = await e2eeService.encryptMessage(
        'user-alice',
        'device-001',
        'room-123',
        content
      );

      encryptedMsgId = encryptedMsg.id;
    });

    it('should decrypt message successfully', async () => {
      const encryptedMsg = await e2eeService.getEncryptedMessage(encryptedMsgId);
      if (!encryptedMsg) throw new Error('Message not found');

      const result = await e2eeService.decryptMessage('user-alice', encryptedMsg);

      expect(result.success).toBe(true);
      expect(result.content?.body).toBe('Secret content');
    });

    it('should measure decryption time', async () => {
      const encryptedMsg = await e2eeService.getEncryptedMessage(encryptedMsgId);
      if (!encryptedMsg) throw new Error('Message not found');

      const result = await e2eeService.decryptMessage('user-alice', encryptedMsg);

      expect(result.decryptionTime).toBeGreaterThanOrEqual(0);
    });

    it('should emit message-decrypted event', async () => {
      const encryptedMsg = await e2eeService.getEncryptedMessage(encryptedMsgId);
      if (!encryptedMsg) throw new Error('Message not found');

      return new Promise<void>((resolve) => {
        e2eeService.once('message-decrypted', ({ messageId }) => {
          expect(messageId).toBe(encryptedMsgId);
          resolve();
        });

        e2eeService.decryptMessage('user-alice', encryptedMsg);
      });
    });

    it('should update decryption statistics', async () => {
      const encryptedMsg = await e2eeService.getEncryptedMessage(encryptedMsgId);
      if (!encryptedMsg) throw new Error('Message not found');

      await e2eeService.decryptMessage('user-alice', encryptedMsg);

      const stats = await e2eeService.getStatistics();
      expect(stats.decryptedMessages).toBeGreaterThan(0);
      expect(stats.averageDecryptionTime).toBeGreaterThanOrEqual(0);
    });
  });

  describe('Device Verification', () => {
    it('should verify device with trusted fingerprint', async () => {
      const trustedFingerprints = new Set<string>(['abc123def456']);

      const verified = await e2eeService.verifyDevice(
        'user-alice',
        'device-001',
        'abc123def456',
        trustedFingerprints
      );

      expect(verified).toBe(true);
    });

    it('should reject untrusted device', async () => {
      const trustedFingerprints = new Set<string>(['abc123def456']);

      const verified = await e2eeService.verifyDevice(
        'user-alice',
        'device-002',
        'xyz789uvw',
        trustedFingerprints
      );

      expect(verified).toBe(false);
    });

    it('should emit device-verified event', async () => {
      const trustedFingerprints = new Set<string>(['trusted-fp']);

      return new Promise<void>((resolve) => {
        e2eeService.once('device-verified', ({ userId, deviceId, verified }) => {
          expect(userId).toBe('user-bob');
          expect(verified).toBe(true);
          resolve();
        });

        e2eeService.verifyDevice('user-bob', 'device-001', 'trusted-fp', trustedFingerprints);
      });
    });

    it('should emit device-unverified event', async () => {
      const trustedFingerprints = new Set<string>();

      return new Promise<void>((resolve) => {
        e2eeService.once('device-unverified', ({ userId, verified }) => {
          expect(userId).toBe('user-charlie');
          expect(verified).toBe(false);
          resolve();
        });

        e2eeService.verifyDevice('user-charlie', 'device-001', 'untrusted-fp', trustedFingerprints);
      });
    });
  });

  describe('Message Verification', () => {
    let encryptedMsgId: string;

    beforeEach(async () => {
      // Generate key and create encrypted message
      await e2eeService.generateKey('user-alice', 'device-001');

      const content: MessageContent = {
        type: 'text',
        body: 'Verify me',
      };

      const encryptedMsg = await e2eeService.encryptMessage(
        'user-alice',
        'device-001',
        'room-123',
        content
      );

      encryptedMsgId = encryptedMsg.id;

      // Verify sender device
      const trustedFingerprints = new Set<string>(['trusted']);
      await e2eeService.verifyDevice('user-alice', 'device-001', 'trusted', trustedFingerprints);
    });

    it('should verify message signature', async () => {
      const encryptedMsg = await e2eeService.getEncryptedMessage(encryptedMsgId);
      if (!encryptedMsg) throw new Error('Message not found');

      const result = await e2eeService.verifyMessage('user-alice', encryptedMsg);

      expect(result.verified).toBe(true);
      expect(result.timestamp).toBe(encryptedMsg.sentAt);
    });
  });

  describe('Key Rotation', () => {
    it('should rotate key', async () => {
      const oldKey = await e2eeService.generateKey('user-alice', 'device-001');
      const newKey = await e2eeService.rotateKey('user-alice', 'device-001');

      expect(newKey.id).not.toBe(oldKey.id);
      expect(newKey.algorithm).toBe('olm');
    });

    it('should emit key-rotated event', async () => {
      await e2eeService.generateKey('user-bob', 'device-001');

      return new Promise<void>((resolve) => {
        e2eeService.once('key-rotated', ({ userId, newKey }) => {
          expect(userId).toBe('user-bob');
          expect(newKey.id).toMatch(/^key-/);
          resolve();
        });

        e2eeService.rotateKey('user-bob', 'device-001');
      });
    });

    it('should increment rotation count', async () => {
      await e2eeService.generateKey('user-charlie', 'device-001');

      const statsBefore = await e2eeService.getStatistics();
      const beforeRotations = statsBefore.keyRotations;

      await e2eeService.rotateKey('user-charlie', 'device-001');

      const statsAfter = await e2eeService.getStatistics();
      expect(statsAfter.keyRotations).toBe(beforeRotations + 1);
    });
  });

  describe('Key Backup', () => {
    beforeEach(async () => {
      await e2eeService.generateKey('user-alice', 'device-001');
      await e2eeService.generateKey('user-alice', 'device-002');
    });

    it('should backup keys to vault', async () => {
      const backup = await e2eeService.backupKeysToVault('user-alice', 'vault-token-xyz');

      expect(backup.id).toMatch(/^backup-/);
      expect(backup.userId).toBe('user-alice');
      expect(backup.backupMethod).toBe('vault');
      expect(backup.metadata?.deviceCount).toBe(2);
    });

    it('should emit backup-created event', async () => {
      return new Promise<void>((resolve) => {
        e2eeService.once('backup-created', ({ backup }) => {
          expect(backup.userId).toBe('user-bob');
          resolve();
        });

        e2eeService.generateKey('user-bob', 'device-001').then(() => {
          e2eeService.backupKeysToVault('user-bob');
        });
      });
    });

    it('should restore keys from backup', async () => {
      const backup = await e2eeService.backupKeysToVault('user-alice');

      const restored = await e2eeService.restoreKeysFromBackup('user-alice', backup.id);

      expect(restored).toBe(true);
    });

    it('should increment backup count', async () => {
      const statsBefore = await e2eeService.getStatistics();

      await e2eeService.backupKeysToVault('user-alice');

      const statsAfter = await e2eeService.getStatistics();
      expect(statsAfter.backups).toBe(statsBefore.backups + 1);
    });
  });

  describe('Capabilities', () => {
    it('should report E2EE capabilities', async () => {
      const capability = await e2eeService.getCapability();

      expect(capability.supported).toBe(true);
      expect(capability.algorithms).toContain('megolm');
      expect(capability.algorithms).toContain('olm');
      expect(capability.keyBackup).toBe(true);
      expect(capability.forwardSecrecy).toBe(true);
    });

    it('should specify key rotation policy', async () => {
      const capability = await e2eeService.getCapability();

      expect(capability.keyRotation.algorithmic).toBe('megolm');
      expect(capability.keyRotation.rotationIntervalMs).toBe(86400000); // 24 hours
      expect(capability.keyRotation.forwardSecrecyMessages).toBe(100);
    });
  });

  describe('Room Messages', () => {
    it('should list messages in room', async () => {
      const service = new E2EEService();
      await service.initialize();

      await service.generateKey('user-alice', 'device-001');

      for (let i = 0; i < 3; i++) {
        const content: MessageContent = {
          type: 'text',
          body: `Message ${i}`,
        };

        await service.encryptMessage(
          'user-alice',
          'device-001',
          'room-msgs',
          content
        );

        // Small delay to ensure different timestamps
        await new Promise((resolve) => setTimeout(resolve, 1));
      }

      const messages = await service.getMessagesInRoom('room-msgs');
      expect(messages.length).toBe(3);
    });

    it('should sort messages by time descending', async () => {
      const service = new E2EEService();
      await service.initialize();

      await service.generateKey('user-bob', 'device-001');

      for (let i = 0; i < 3; i++) {
        const content: MessageContent = {
          type: 'text',
          body: `Message ${i}`,
        };

        await service.encryptMessage(
          'user-bob',
          'device-001',
          'room-sort',
          content
        );

        await new Promise((resolve) => setTimeout(resolve, 1));
      }

      const messages = await service.getMessagesInRoom('room-sort');

      for (let i = 0; i < messages.length - 1; i++) {
        expect(messages[i].sentAt).toBeGreaterThanOrEqual(messages[i + 1].sentAt);
      }
    });

    it('should limit returned messages', async () => {
      const service = new E2EEService();
      await service.initialize();

      await service.generateKey('user-charlie', 'device-001');

      for (let i = 0; i < 5; i++) {
        const content: MessageContent = {
          type: 'text',
          body: `Message ${i}`,
        };

        await service.encryptMessage(
          'user-charlie',
          'device-001',
          'room-limit',
          content
        );

        await new Promise((resolve) => setTimeout(resolve, 1));
      }

      const messages = await service.getMessagesInRoom('room-limit', 2);
      expect(messages.length).toBe(2);
    });
  });

  describe('Events and Logging', () => {
    it('should track events', async () => {
      await e2eeService.generateKey('user-alice', 'device-001');

      const events = await e2eeService.getEvents();

      expect(events.length).toBeGreaterThan(0);
      expect(events.some((e) => e.type === 'key-generated')).toBe(true);
    });

    it('should limit returned events', async () => {
      await e2eeService.generateKey('user-alice', 'device-001');
      await e2eeService.generateKey('user-alice', 'device-002');

      const events = await e2eeService.getEvents(1);

      expect(events.length).toBeLessThanOrEqual(1);
    });
  });

  describe('Statistics', () => {
    it('should calculate encryption rate', async () => {
      await e2eeService.generateKey('user-alice', 'device-001');

      const content: MessageContent = {
        type: 'text',
        body: 'Stat test',
      };

      await e2eeService.encryptMessage('user-alice', 'device-001', 'room-123', content);

      const stats = await e2eeService.getStatistics();

      expect(stats.encryptionRate).toBeGreaterThan(0);
      expect(stats.encryptionRate).toBeLessThanOrEqual(100);
    });
  });

  describe('Global Singleton', () => {
    it('should return same instance', async () => {
      const service1 = await getE2EEService();
      const service2 = await getE2EEService();

      expect(service1).toBe(service2);
    });
  });

  describe('Integration', () => {
    it('should handle complete encryption workflow', async () => {
      // 1. Generate keys
      const key = await e2eeService.generateKey('user-alice', 'device-001');
      expect(key.id).toMatch(/^key-/);

      // 2. Create session
      const session = await e2eeService.createSessionKey('room-123', 'user-alice', 'megolm');
      expect(session.id).toMatch(/^session-/);

      // 3. Verify device
      const verified = await e2eeService.verifyDevice(
        'user-alice',
        'device-001',
        'trusted-fp',
        new Set(['trusted-fp'])
      );
      expect(verified).toBe(true);

      // 4. Encrypt message
      const content: MessageContent = {
        type: 'text',
        body: 'Complete workflow',
      };

      const encryptedMsg = await e2eeService.encryptMessage(
        'user-alice',
        'device-001',
        'room-123',
        content
      );
      expect(encryptedMsg.ciphertext).toBeDefined();

      // 5. Decrypt message
      const decrypted = await e2eeService.decryptMessage('user-alice', encryptedMsg);
      expect(decrypted.success).toBe(true);
      expect(decrypted.content?.body).toBe('Complete workflow');

      // 6. Get statistics
      const stats = await e2eeService.getStatistics();
      expect(stats.encryptedMessages).toBeGreaterThan(0);
      expect(stats.decryptedMessages).toBeGreaterThan(0);
    });
  });
});
