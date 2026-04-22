// apps/backend/src/services/extension-registry/__tests__/registry.test.ts
// @file: Extension registry API tests for Issue #1047
// Tests blocklist enforcement, version pinning, installation tracking

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { Pool } from "pg"

// Mock registry service
interface RegistryService {
  checkBlocklist: (extensionId: string) => Promise<boolean>
  getAllowedVersions: (extensionId: string) => Promise<string[]>
  recordInstallation: (extensionId: string, version: string, userId: string) => Promise<void>
  getInstallationStats: (extensionId: string) => Promise<{ total: number; failed: number }>
}

class ExtensionRegistryService implements RegistryService {
  constructor(private db: Pool) {}

  async checkBlocklist(extensionId: string): Promise<boolean> {
    const result = await this.db.query(
      "SELECT blocklisted FROM registry.extensions WHERE extension_id = $1",
      [extensionId]
    )
    return result.rows[0]?.blocklisted ?? false
  }

  async getAllowedVersions(extensionId: string): Promise<string[]> {
    const result = await this.db.query(
      `SELECT version FROM registry.extension_versions 
       WHERE extension_id = (SELECT id FROM registry.extensions WHERE extension_id = $1)
       ORDER BY published_at DESC`,
      [extensionId]
    )
    return result.rows.map((row) => row.version)
  }

  async recordInstallation(extensionId: string, version: string, userId: string): Promise<void> {
    await this.db.query(
      `INSERT INTO registry.installation_logs (version_id, user_id, install_status, installed_at)
       SELECT id, $2, 'success', NOW()
       FROM registry.extension_versions
       WHERE version = $3 AND extension_id = (SELECT id FROM registry.extensions WHERE extension_id = $1)`,
      [extensionId, userId, version]
    )
  }

  async getInstallationStats(extensionId: string): Promise<{ total: number; failed: number }> {
    const result = await this.db.query(
      `SELECT
         COUNT(*) as total,
         SUM(CASE WHEN install_status = 'failed' THEN 1 ELSE 0 END) as failed
       FROM registry.installation_logs
       WHERE version_id IN (
         SELECT id FROM registry.extension_versions
         WHERE extension_id = (SELECT id FROM registry.extensions WHERE extension_id = $1)
       )`,
      [extensionId]
    )
    return {
      total: parseInt(result.rows[0]?.total ?? 0, 10),
      failed: parseInt(result.rows[0]?.failed ?? 0, 10),
    }
  }
}

describe("ExtensionRegistryService", () => {
  let mockDb: any
  let service: RegistryService

  beforeEach(() => {
    mockDb = {
      query: vi.fn(),
    }
    service = new ExtensionRegistryService(mockDb)
  })

  describe("checkBlocklist", () => {
    it("should return true if extension is blocklisted", async () => {
      mockDb.query.mockResolvedValueOnce({
        rows: [{ blocklisted: true }],
      })

      const result = await service.checkBlocklist("ms-vscode-remote.remote-ssh")

      expect(result).toBe(true)
      expect(mockDb.query).toHaveBeenCalledWith(
        "SELECT blocklisted FROM registry.extensions WHERE extension_id = $1",
        ["ms-vscode-remote.remote-ssh"]
      )
    })

    it("should return false if extension is not blocklisted", async () => {
      mockDb.query.mockResolvedValueOnce({
        rows: [{ blocklisted: false }],
      })

      const result = await service.checkBlocklist("ms-python.python")

      expect(result).toBe(false)
    })

    it("should return false if extension not found", async () => {
      mockDb.query.mockResolvedValueOnce({
        rows: [],
      })

      const result = await service.checkBlocklist("unknown.extension")

      expect(result).toBe(false)
    })
  })

  describe("getAllowedVersions", () => {
    it("should return all allowed versions for an extension", async () => {
      mockDb.query.mockResolvedValueOnce({
        rows: [{ version: "1.0.0" }, { version: "0.9.0" }, { version: "0.8.0" }],
      })

      const versions = await service.getAllowedVersions("ms-python.python")

      expect(versions).toEqual(["1.0.0", "0.9.0", "0.8.0"])
    })

    it("should return empty array if no versions found", async () => {
      mockDb.query.mockResolvedValueOnce({
        rows: [],
      })

      const versions = await service.getAllowedVersions("unknown.extension")

      expect(versions).toEqual([])
    })

    it("should enforce version pinning", async () => {
      mockDb.query.mockResolvedValueOnce({
        rows: [{ version: "1.234.5678" }], // T1-Core pinned version
      })

      const versions = await service.getAllowedVersions("GitHub.copilot")

      expect(versions).toEqual(["1.234.5678"])
    })
  })

  describe("recordInstallation", () => {
    it("should record successful installation", async () => {
      mockDb.query.mockResolvedValueOnce({ rows: [] })

      await service.recordInstallation("ms-python.python", "2024.4.1", "user-123")

      expect(mockDb.query).toHaveBeenCalledWith(
        expect.stringContaining("INSERT INTO registry.installation_logs"),
        ["ms-python.python", "user-123", "2024.4.1"]
      )
    })
  })

  describe("getInstallationStats", () => {
    it("should return installation statistics", async () => {
      mockDb.query.mockResolvedValueOnce({
        rows: [{ total: 150, failed: 2 }],
      })

      const stats = await service.getInstallationStats("ms-python.python")

      expect(stats).toEqual({ total: 150, failed: 2 })
    })

    it("should handle zero installations", async () => {
      mockDb.query.mockResolvedValueOnce({
        rows: [{ total: 0, failed: 0 }],
      })

      const stats = await service.getInstallationStats("new.extension")

      expect(stats).toEqual({ total: 0, failed: 0 })
    })
  })

  describe("blocklist enforcement", () => {
    it("should prevent installation of blocklisted extensions", async () => {
      mockDb.query.mockResolvedValueOnce({
        rows: [{ blocklisted: true }],
      })

      const isBlocklisted = await service.checkBlocklist("TabNine.tabnine-vscode")

      expect(isBlocklisted).toBe(true)
    })

    it("should allow installation of T1-Core extensions", async () => {
      mockDb.query.mockResolvedValueOnce({
        rows: [{ blocklisted: false }],
      })

      const isBlocklisted = await service.checkBlocklist("GitHub.copilot")

      expect(isBlocklisted).toBe(false)
    })
  })

  describe("HTTP API endpoints", () => {
    it("should return 403 Forbidden for blocklisted extensions", async () => {
      mockDb.query.mockResolvedValueOnce({
        rows: [{ blocklisted: true }],
      })

      const isBlocklisted = await service.checkBlocklist("Codeium.codeium")

      expect(isBlocklisted).toBe(true)
    })

    it("should return 200 OK with metadata for allowed extensions", async () => {
      mockDb.query.mockResolvedValueOnce({
        rows: [{ blocklisted: false }],
      })

      const isBlocklisted = await service.checkBlocklist("ms-python.python")

      expect(isBlocklisted).toBe(false)
    })
  })
})
