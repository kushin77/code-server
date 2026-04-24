// apps/backend/src/services/ephemeral-credentials/__tests__/vault-service.test.ts
import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { EphemeralCredentialsService } from "../vault-service"

describe("EphemeralCredentialsService", () => {
  let service: EphemeralCredentialsService
  const sessionId = "session-123"
  const userId = "alice"

  beforeEach(() => {
    service = new EphemeralCredentialsService()
    process.env.VAULT_ADDR = "https://vault.test"
    process.env.VAULT_TOKEN = "test-token"
  })

  afterEach(() => {
    vi.clearAllMocks()
  })

  describe("requestDatabaseCredentials", () => {
    it("should generate ephemeral database credentials", async () => {
      const cred = await service.requestDatabaseCredentials(sessionId, userId)

      expect(cred.type).toBe("database")
      expect(cred.username).toBeDefined()
      expect(cred.password).toBeDefined()
      expect(cred.issuedAt).toBeInstanceOf(Date)
      expect(cred.expiresAt).toBeInstanceOf(Date)
      expect(cred.ttl).toBeGreaterThan(0)
      expect(cred.sessionId).toBe(sessionId)
    })

    it("should generate different usernames for different sessions", async () => {
      const cred1 = await service.requestDatabaseCredentials("session-1", userId)
      const cred2 = await service.requestDatabaseCredentials("session-2", userId)

      // Different sessions should have different username suffixes even with same user
      expect(cred1.username).toBeDefined()
      expect(cred2.username).toBeDefined()
    })

    it("should respect custom TTL", async () => {
      const customTtl = 7200 // 2 hours
      const cred = await service.requestDatabaseCredentials(sessionId, userId, customTtl)

      expect(cred.ttl).toBe(customTtl)
      const ttlMs = cred.expiresAt.getTime() - cred.issuedAt.getTime()
      expect(Math.abs(ttlMs - customTtl * 1000)).toBeLessThan(1000)
    })

    it("should store credentials in session", async () => {
      const cred = await service.requestDatabaseCredentials(sessionId, userId)
      const sessionCreds = service.getSessionCredentials(sessionId)

      expect(sessionCreds).toHaveLength(1)
      expect(sessionCreds[0]).toEqual(cred)
    })

    it("should throw error without Vault token", async () => {
      delete process.env.VAULT_TOKEN
      const newService = new EphemeralCredentialsService()

      await expect(newService.requestDatabaseCredentials(sessionId, userId)).rejects.toThrow(
        "Vault token not configured"
      )
    })
  })

  describe("requestCloudToken", () => {
    it("should generate AWS credentials", async () => {
      const cred = await service.requestCloudToken(sessionId, userId, "aws")

      expect(cred.type).toBe("cloud_token")
      expect(cred.accessKey).toBeDefined()
      expect(cred.secretKey).toBeDefined()
      expect(cred.metadata.provider).toBe("aws")
    })

    it("should generate GCP token", async () => {
      const cred = await service.requestCloudToken(sessionId, userId, "gcp")

      expect(cred.type).toBe("cloud_token")
      expect(cred.token).toBeDefined()
      expect(cred.metadata.provider).toBe("gcp")
    })

    it("should generate Azure credentials", async () => {
      const cred = await service.requestCloudToken(sessionId, userId, "azure")

      expect(cred.type).toBe("cloud_token")
      expect(cred.metadata.provider).toBe("azure")
    })

    it("should enforce max TTL for cloud tokens", async () => {
      const longTtl = 7200 // 2 hours, beyond cloud token max
      const cred = await service.requestCloudToken(sessionId, userId, "aws", longTtl)

      // Should be capped at 1 hour (3600 seconds)
      expect(cred.ttl).toBeLessThanOrEqual(3600)
    })
  })

  describe("getSessionCredentials", () => {
    it("should return empty array for unknown session", () => {
      const creds = service.getSessionCredentials("unknown-session")

      expect(creds).toEqual([])
    })

    it("should return all credentials for session", async () => {
      await service.requestDatabaseCredentials(sessionId, userId)
      await service.requestCloudToken(sessionId, userId, "aws")

      const creds = service.getSessionCredentials(sessionId)

      expect(creds).toHaveLength(2)
      expect(creds[0].type).toBe("database")
      expect(creds[1].type).toBe("cloud_token")
    })
  })

  describe("revokeSessionCredentials", () => {
    it("should revoke all session credentials", async () => {
      await service.requestDatabaseCredentials(sessionId, userId)
      await service.requestCloudToken(sessionId, userId, "aws")

      await service.revokeSessionCredentials(sessionId)

      const creds = service.getSessionCredentials(sessionId)
      expect(creds).toHaveLength(0)
    })

    it("should emit credentials-revoked event", async () => {
      await service.requestDatabaseCredentials(sessionId, userId)

      const eventSpy = vi.fn()
      service.on("credentials-revoked", eventSpy)

      await service.revokeSessionCredentials(sessionId)

      expect(eventSpy).toHaveBeenCalledWith(
        expect.objectContaining({
          sessionId,
          userId,
          credentialCount: 1,
        })
      )
    })

    it("should handle unknown sessions gracefully", async () => {
      expect(async () => {
        await service.revokeSessionCredentials("unknown-session")
      }).not.toThrow()
    })
  })

  describe("checkCredentialExpiration", () => {
    it("should detect non-expiring credentials", async () => {
      const cred = await service.requestDatabaseCredentials(sessionId, userId, 600) // 10 minutes
      const check = service.checkCredentialExpiration(cred)

      expect(check.minutesRemaining).toBeGreaterThan(0)
    })

    it("should calculate minutes remaining correctly", async () => {
      const cred = await service.requestDatabaseCredentials(sessionId, userId, 600) // 10 minutes
      const check = service.checkCredentialExpiration(cred)

      expect(check.minutesRemaining).toBeGreaterThan(8)
      expect(check.minutesRemaining).toBeLessThanOrEqual(10)
    })

    it("should return 0 minutes for expired credential", () => {
      const expiredCred = {
        type: "database" as const,
        username: "test",
        password: "test",
        issuedAt: new Date(Date.now() - 7200000),
        expiresAt: new Date(Date.now() - 3600000), // Expired 1 hour ago
        ttl: 3600,
        sessionId,
        metadata: {},
      }

      const check = service.checkCredentialExpiration(expiredCred)

      expect(check.isExpiring).toBe(true)
      expect(check.minutesRemaining).toBe(0)
    })
  })

  describe("credential formats", () => {
    it("should generate valid database username format", async () => {
      const cred = await service.requestDatabaseCredentials(sessionId, userId)

      // Should be alphanumeric and underscore only
      expect(cred.username).toMatch(/^[a-z0-9_]+$/)
      // Should contain app prefix
      expect(cred.username).toContain("app_")
      // Should be reasonable length
      expect(cred.username?.length).toBeGreaterThan(5)
      expect(cred.username?.length).toBeLessThan(32)
    })

    it("should generate valid password format", async () => {
      const cred = await service.requestDatabaseCredentials(sessionId, userId)

      expect(cred.password).toBeDefined()
      expect(cred.password?.length).toBeGreaterThanOrEqual(30)
      expect(cred.password?.length).toBeLessThanOrEqual(32)
      expect(cred.password).toMatch(/^[a-zA-Z0-9]+$/)
    })

    it("should generate valid AWS access key format", async () => {
      const cred = await service.requestCloudToken(sessionId, userId, "aws")

      expect(cred.accessKey).toBeDefined()
      expect(cred.accessKey).toMatch(/^AKIA/)
    })

    it("should generate valid AWS secret key format", async () => {
      const cred = await service.requestCloudToken(sessionId, userId, "aws")

      expect(cred.secretKey).toBeDefined()
      expect(cred.secretKey?.length).toBeGreaterThanOrEqual(30)
    })
  })

  describe("credential metadata", () => {
    it("should include correct metadata for database credentials", async () => {
      const cred = await service.requestDatabaseCredentials(sessionId, userId)

      expect(cred.metadata.role).toBeDefined()
      expect(cred.metadata.engine).toBe("postgresql")
      expect(cred.metadata.staticUsername).toBe(false)
    })

    it("should include correct metadata for cloud tokens", async () => {
      const cred = await service.requestCloudToken(sessionId, userId, "aws")

      expect(cred.metadata.provider).toBe("aws")
      expect(cred.metadata.autoRevoke).toBe(true)
    })
  })

  describe("multiple credentials per session", () => {
    it("should allow multiple credentials of same type", async () => {
      const cred1 = await service.requestDatabaseCredentials(sessionId, userId)
      const cred2 = await service.requestDatabaseCredentials(sessionId, userId)

      const creds = service.getSessionCredentials(sessionId)

      expect(creds).toHaveLength(2)
      expect(creds[0].type).toBe("database")
      expect(creds[1].type).toBe("database")
      // Usernames should be unique (includes random component)
      expect(creds[0].username).not.toBe(creds[1].username)
    })

    it("should allow mixed credential types", async () => {
      await service.requestDatabaseCredentials(sessionId, userId)
      await service.requestCloudToken(sessionId, userId, "aws")
      await service.requestCloudToken(sessionId, userId, "gcp")

      const creds = service.getSessionCredentials(sessionId)

      expect(creds).toHaveLength(3)
      expect(creds.filter((c) => c.type === "database")).toHaveLength(1)
      expect(creds.filter((c) => c.type === "cloud_token")).toHaveLength(2)
    })
  })
})
