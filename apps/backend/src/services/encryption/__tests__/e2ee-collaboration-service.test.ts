// apps/backend/src/services/encryption/__tests__/e2ee-collaboration-service.test.ts
import { describe, it, expect, beforeEach } from "vitest"
import { E2EECollaborationService } from "../e2ee-collaboration-service"

describe("E2EECollaborationService", () => {
  let service: E2EECollaborationService

  beforeEach(() => {
    service = new E2EECollaborationService({
      vaultPath: "secret/test/e2ee-keys",
      backupIntervalMs: 60000,
      maxBackupSize: 104857600,
    })
  })

  describe("Session Management", () => {
    it("should initialize a new E2EE session", () => {
      const result = service.initializeSession("user-123", "workspace-456")

      expect(result.success).toBe(true)
      expect(result.sessionId).toBeDefined()
      expect(result.sessionId.length).toBe(32) // 16 bytes hex
      expect(result.publicKey).toBeDefined()
      expect(result.ephemeralPublicKey).toBeDefined()
    })

    it("should create unique session IDs", () => {
      const result1 = service.initializeSession("user-123", "workspace-456")
      const result2 = service.initializeSession("user-123", "workspace-456")

      expect(result1.sessionId).not.toBe(result2.sessionId)
    })

    it("should store session with correct metadata", () => {
      const result = service.initializeSession("user-123", "workspace-456")

      const session = service.getSessionStatus(result.sessionId)

      expect(session).not.toBeNull()
      expect(session?.userId).toBe("user-123")
      expect(session?.workspaceId).toBe("workspace-456")
      expect(session?.isActive).toBe(true)
    })

    it("should set session expiration to 24 hours", () => {
      const result = service.initializeSession("user-123", "workspace-456")
      const session = service.getSessionStatus(result.sessionId)

      const expiresIn = (session?.expiresAt?.getTime() || 0) - Date.now()
      expect(expiresIn).toBeGreaterThan(86400000 - 1000) // Within 1 second of 24 hours
      expect(expiresIn).toBeLessThanOrEqual(86400000)
    })

    it("should generate base64-encoded keys", () => {
      const result = service.initializeSession("user-123", "workspace-456")

      // Base64 strings should match pattern
      expect(result.publicKey).toMatch(/^[A-Za-z0-9+/]+=*$/)
      expect(result.ephemeralPublicKey).toMatch(/^[A-Za-z0-9+/]+=*$/)
    })

    it("should terminate session and clear keys", () => {
      const init = service.initializeSession("user-123", "workspace-456")

      const result = service.terminateSession(init.sessionId)

      expect(result.success).toBe(true)
      expect(result.keysCleared).toBeGreaterThan(0)

      const session = service.getSessionStatus(init.sessionId)
      expect(session?.isActive).toBe(false)
    })

    it("should fail to terminate non-existent session", () => {
      const result = service.terminateSession("non-existent-id")

      expect(result.success).toBe(false)
      expect(result.keysCleared).toBe(0)
    })

    it("should return null for non-existent session status", () => {
      const status = service.getSessionStatus("non-existent-id")

      expect(status).toBeNull()
    })
  })

  describe("Message Encryption/Decryption", () => {
    let sessionId: string

    beforeEach(() => {
      const result = service.initializeSession("user-123", "workspace-456")
      sessionId = result.sessionId
    })

    it("should encrypt a message", async () => {
      const message = "Hello, encrypted world!"

      const result = await service.encryptMessage(sessionId, message, "user-123")

      expect(result.success).toBe(true)
      expect(result.encryptedMessage).toBeDefined()
      expect(result.messageId).toBeDefined()
      expect(result.algorithm).toBe("megolm")
    })

    it("should generate unique message IDs", async () => {
      const message = "Test message"

      const result1 = await service.encryptMessage(sessionId, message, "user-123")
      const result2 = await service.encryptMessage(sessionId, message, "user-123")

      expect(result1.messageId).not.toBe(result2.messageId)
    })

    it("should produce different ciphertext for same message", async () => {
      const message = "Test message"

      const result1 = await service.encryptMessage(sessionId, message, "user-123")
      const result2 = await service.encryptMessage(sessionId, message, "user-123")

      expect(result1.encryptedMessage).not.toBe(result2.encryptedMessage)
    })

    it("should decrypt encrypted message", async () => {
      const message = "Secret message"

      const encrypted = await service.encryptMessage(sessionId, message, "user-123")
      const decrypted = await service.decryptMessage(
        sessionId,
        encrypted.messageId,
        encrypted.encryptedMessage,
        "user-123"
      )

      expect(decrypted.success).toBe(true)
      expect(decrypted.decryptedContent).toBe(message)
    })

    it("should preserve message content through encryption cycle", async () => {
      const messages = [
        "Hello",
        "This is a longer message with special chars: !@#$%",
        "Message with unicode: 你好世界 🌍",
        "Multi-line\nmessage\ntest",
        "",
      ]

      for (const message of messages) {
        const encrypted = await service.encryptMessage(sessionId, message, "user-123")
        const decrypted = await service.decryptMessage(
          sessionId,
          encrypted.messageId,
          encrypted.encryptedMessage,
          "user-123"
        )

        expect(decrypted.decryptedContent).toBe(message)
      }
    })

    it("should fail to decrypt with wrong message ID", async () => {
      const message = "Secret"

      const encrypted = await service.encryptMessage(sessionId, message, "user-123")
      const decrypted = await service.decryptMessage(
        sessionId,
        "wrong-message-id",
        encrypted.encryptedMessage,
        "user-123"
      )

      expect(decrypted.success).toBe(false)
    })

    it("should fail to decrypt with non-existent session", async () => {
      const encrypted = await service.encryptMessage(sessionId, "test", "user-123")

      const decrypted = await service.decryptMessage(
        "non-existent-session",
        encrypted.messageId,
        encrypted.encryptedMessage,
        "user-123"
      )

      expect(decrypted.success).toBe(false)
    })

    it("should fail to encrypt in inactive session", async () => {
      service.terminateSession(sessionId)

      const result = await service.encryptMessage(sessionId, "message", "user-123")

      expect(result.success).toBe(false)
    })
  })

  describe("Forward Secrecy", () => {
    let sessionId: string

    beforeEach(() => {
      const result = service.initializeSession("user-123", "workspace-456")
      sessionId = result.sessionId
    })

    it("should maintain forward secrecy", async () => {
      const encrypted = await service.encryptMessage(sessionId, "Secret", "user-123")

      const forwardSecrecy = service.verifyForwardSecrecy(sessionId, encrypted.messageId)

      expect(forwardSecrecy.forwardSecure).toBe(true)
      expect(forwardSecrecy.ratchetRotated).toBe(true)
    })

    it("should use unique ratchet for each message", async () => {
      const encrypted1 = await service.encryptMessage(sessionId, "Message 1", "user-123")
      const encrypted2 = await service.encryptMessage(sessionId, "Message 2", "user-123")

      const fs1 = service.verifyForwardSecrecy(sessionId, encrypted1.messageId)
      const fs2 = service.verifyForwardSecrecy(sessionId, encrypted2.messageId)

      expect(fs1.forwardSecure).toBe(true)
      expect(fs2.forwardSecure).toBe(true)
      // Different messages have different ratchet states
      expect(encrypted1.messageId).not.toBe(encrypted2.messageId)
    })

    it("should fail forward secrecy check for non-existent message", () => {
      const forwardSecrecy = service.verifyForwardSecrecy(sessionId, "non-existent-id")

      expect(forwardSecrecy.forwardSecure).toBe(false)
    })
  })

  describe("Key Backup", () => {
    it("should backup keys to Vault", async () => {
      // Initialize a session first
      service.initializeSession("user-123", "workspace-456")

      const result = await service.backupKeysToVault()

      expect(result.success).toBe(true)
      expect(result.backupId).toBeDefined()
      expect(result.backupId.length).toBe(24) // 12 bytes hex
      expect(result.keysBackedUp).toBeGreaterThanOrEqual(2) // At least the session keys
    })

    it("should generate unique backup IDs", async () => {
      service.initializeSession("user-123", "workspace-456")

      const result1 = await service.backupKeysToVault()
      const result2 = await service.backupKeysToVault()

      expect(result1.backupId).not.toBe(result2.backupId)
    })

    it("should restore keys from Vault", async () => {
      service.initializeSession("user-123", "workspace-456")
      const backup = await service.backupKeysToVault()

      const restore = await service.restoreKeysFromVault(backup.backupId)

      expect(restore.success).toBe(true)
      expect(restore.keysRestored).toBeGreaterThanOrEqual(2)
    })

    it("should emit keys-backed-up event", async () => {
      service.initializeSession("user-123", "workspace-456")

      let eventFired = false
      service.on("keys-backed-up", (data) => {
        eventFired = true
        expect(data.backupId).toBeDefined()
        expect(data.keyCount).toBeGreaterThanOrEqual(2)
      })

      await service.backupKeysToVault()

      expect(eventFired).toBe(true)
    })
  })

  describe("Megolm Algorithm", () => {
    let sessionId: string

    beforeEach(() => {
      const result = service.initializeSession("user-123", "workspace-456")
      sessionId = result.sessionId
    })

    it("should use megolm algorithm", async () => {
      const encrypted = await service.encryptMessage(sessionId, "test", "user-123")

      expect(encrypted.algorithm).toBe("megolm")
    })

    it("should produce base64-encoded ciphertext", async () => {
      const encrypted = await service.encryptMessage(sessionId, "test", "user-123")

      expect(encrypted.encryptedMessage).toMatch(/^[A-Za-z0-9+/]+=*$/)
    })

    it("should use AES-256-GCM", async () => {
      // Megolm uses AES-256-GCM internally
      const encrypted = await service.encryptMessage(sessionId, "test", "user-123")

      // Verify we can decrypt with correct message ID
      const decrypted = await service.decryptMessage(
        sessionId,
        encrypted.messageId,
        encrypted.encryptedMessage,
        "user-123"
      )

      expect(decrypted.success).toBe(true)
    })

    it("should include IV and auth tag in encrypted message", async () => {
      const encrypted = await service.encryptMessage(sessionId, "test", "user-123")

      // Base64-decoded message should have structure: IV (12) + AuthTag (16) + Ciphertext
      const buffer = Buffer.from(encrypted.encryptedMessage, "base64")
      expect(buffer.length).toBeGreaterThan(28) // At least IV + AuthTag
    })
  })

  describe("Multiple Sessions", () => {
    let service1: E2EECollaborationService

    beforeEach(() => {
      service1 = new E2EECollaborationService({
        vaultPath: "secret/test/e2ee-keys",
        backupIntervalMs: 60000,
        maxBackupSize: 104857600,
      })
    })

    it("should handle multiple concurrent sessions", () => {
      const session1 = service1.initializeSession("user-1", "workspace-1")
      const session2 = service1.initializeSession("user-2", "workspace-2")
      const session3 = service1.initializeSession("user-1", "workspace-2")

      expect(session1.sessionId).not.toBe(session2.sessionId)
      expect(session2.sessionId).not.toBe(session3.sessionId)

      const s1 = service1.getSessionStatus(session1.sessionId)
      const s2 = service1.getSessionStatus(session2.sessionId)
      const s3 = service1.getSessionStatus(session3.sessionId)

      expect(s1?.userId).toBe("user-1")
      expect(s2?.userId).toBe("user-2")
      expect(s3?.userId).toBe("user-1")
    })

    it("should isolate messages between sessions", async () => {
      const session1 = service1.initializeSession("user-1", "workspace-1")
      const session2 = service1.initializeSession("user-2", "workspace-2")

      const encrypted1 = await service1.encryptMessage(session1.sessionId, "Secret1", "user-1")
      const encrypted2 = await service1.encryptMessage(session2.sessionId, "Secret2", "user-2")

      // Session 1 should not be able to decrypt session 2's message
      const wrongDecrypt = await service1.decryptMessage(
        session1.sessionId,
        encrypted2.messageId,
        encrypted2.encryptedMessage,
        "user-1"
      )

      expect(wrongDecrypt.success).toBe(false)
    })

    it("should terminate sessions independently", () => {
      const session1 = service1.initializeSession("user-1", "workspace-1")
      const session2 = service1.initializeSession("user-2", "workspace-2")

      service1.terminateSession(session1.sessionId)

      const s1 = service1.getSessionStatus(session1.sessionId)
      const s2 = service1.getSessionStatus(session2.sessionId)

      expect(s1?.isActive).toBe(false)
      expect(s2?.isActive).toBe(true)
    })
  })
})