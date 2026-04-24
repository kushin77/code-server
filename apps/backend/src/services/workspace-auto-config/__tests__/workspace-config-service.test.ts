// apps/backend/src/services/workspace-auto-config/__tests__/workspace-config-service.test.ts
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import * as fs from "fs"
import * as path from "path"
import { WorkspaceConfigurationService } from "../workspace-config-service"

vi.mock("fs")
vi.mock("path")

describe("WorkspaceConfigurationService", () => {
  let mockFs: any
  let mockPath: any
  let service: WorkspaceConfigurationService

  beforeEach(() => {
    mockFs = fs as any
    mockPath = path as any

    mockFs.existsSync = vi.fn().mockReturnValue(false)
    mockFs.mkdirSync = vi.fn()
    mockFs.readFileSync = vi.fn()
    mockFs.writeFileSync = vi.fn()
    mockPath.join = (...args: string[]) => args.join("/")

    service = new WorkspaceConfigurationService("/test/workspace")
  })

  afterEach(() => {
    vi.clearAllMocks()
  })

  describe("configureWorkspace", () => {
    it("should create .vscode directory if it doesn't exist", async () => {
      mockFs.existsSync.mockReturnValue(false)

      await service.configureWorkspace()

      expect(mockFs.mkdirSync).toHaveBeenCalledWith(
        "/test/workspace/.vscode",
        { recursive: true }
      )
    })

    it("should write workspace settings to .vscode/settings.json", async () => {
      mockFs.existsSync.mockReturnValue(false)

      await service.configureWorkspace()

      expect(mockFs.writeFileSync).toHaveBeenCalledWith(
        "/test/workspace/.vscode/settings.json",
        expect.any(String)
      )
    })

    it("should generate tasks.json with build tasks", async () => {
      mockFs.existsSync.mockReturnValue(false)

      await service.configureWorkspace()

      const writeCall = mockFs.writeFileSync.mock.calls.find((call: any) =>
        call[0].includes("tasks.json")
      )
      expect(writeCall).toBeDefined()

      const tasksContent = JSON.parse(writeCall[1])
      expect(tasksContent.version).toBe("2.0.0")
      expect(Array.isArray(tasksContent.tasks)).toBe(true)
    })

    it("should generate launch.json with debug configurations", async () => {
      mockFs.existsSync.mockReturnValue(false)

      await service.configureWorkspace()

      const writeCall = mockFs.writeFileSync.mock.calls.find((call: any) =>
        call[0].includes("launch.json")
      )
      expect(writeCall).toBeDefined()

      const launchContent = JSON.parse(writeCall[1])
      expect(launchContent.version).toBe("0.2.0")
      expect(Array.isArray(launchContent.configurations)).toBe(true)
    })

    it("should track progress with callback", async () => {
      const progressCallback = vi.fn()
      mockFs.existsSync.mockReturnValue(false)

      await service.configureWorkspace(progressCallback)

      expect(progressCallback).toHaveBeenCalled()
      const calls = progressCallback.mock.calls
      expect(calls[calls.length - 1][0].step).toBe("complete")
      expect(calls[calls.length - 1][0].progress).toBe(100)
    })

    it("should merge with existing settings", async () => {
      mockFs.existsSync.mockImplementation((filePath: string) => {
        return filePath.includes("settings.json")
      })
      mockFs.readFileSync.mockReturnValue(
        JSON.stringify({ "editor.fontSize": 14 })
      )

      await service.configureWorkspace()

      const writeCall = mockFs.writeFileSync.mock.calls.find((call: any) =>
        call[0].includes("settings.json")
      )
      const mergedSettings = JSON.parse(writeCall[1])
      expect(mergedSettings["editor.fontSize"]).toBe(14)
    })

    it("should not duplicate tasks when merging", async () => {
      mockFs.existsSync.mockImplementation((filePath: string) => {
        return filePath.includes("tasks.json")
      })
      mockFs.readFileSync.mockReturnValue(
        JSON.stringify({
          tasks: [{ label: "npm: build", type: "shell" }],
        })
      )

      await service.configureWorkspace()

      const writeCall = mockFs.writeFileSync.mock.calls.find((call: any) =>
        call[0].includes("tasks.json")
      )
      const tasksContent = JSON.parse(writeCall[1])
      const buildTaskCount = tasksContent.tasks.filter(
        (t: any) => t.label === "npm: build"
      ).length
      expect(buildTaskCount).toBe(1)
    })

    it("should not duplicate debug configurations when merging", async () => {
      mockFs.existsSync.mockImplementation((filePath: string) => {
        return filePath.includes("launch.json")
      })
      mockFs.readFileSync.mockReturnValue(
        JSON.stringify({
          configurations: [{ name: "Launch Program", type: "node" }],
        })
      )

      await service.configureWorkspace()

      const writeCall = mockFs.writeFileSync.mock.calls.find((call: any) =>
        call[0].includes("launch.json")
      )
      const launchContent = JSON.parse(writeCall[1])
      const launchConfigCount = launchContent.configurations.filter(
        (c: any) => c.name === "Launch Program"
      ).length
      expect(launchConfigCount).toBe(1)
    })

    it("should handle malformed existing tasks gracefully", async () => {
      mockFs.existsSync.mockImplementation((filePath: string) => {
        return filePath.includes("tasks.json")
      })
      mockFs.readFileSync.mockReturnValue("{ invalid json }")

      await service.configureWorkspace()

      expect(mockFs.writeFileSync).toHaveBeenCalled()
    })

    it("should emit progress events", async () => {
      mockFs.existsSync.mockReturnValue(false)
      const progressEvents: string[] = []

      service.on("progress", (progress) => {
        progressEvents.push(progress.step)
      })

      await service.configureWorkspace()

      expect(progressEvents).toContain("detecting")
      expect(progressEvents).toContain("writing-settings")
      expect(progressEvents).toContain("generating-tasks")
      expect(progressEvents).toContain("generating-debug")
      expect(progressEvents).toContain("complete")
    })

    it("should return correct profile structure", async () => {
      mockFs.existsSync.mockReturnValue(false)
      const result = await service.configureWorkspace()

      expect(result.profile).toBeDefined()
      expect(result.profile.extensions).toBeDefined()
      expect(Array.isArray(result.profile.extensions)).toBe(true)
      expect(result.profile.settings).toBeDefined()
      expect(result.profile.tasks).toBeDefined()
      expect(result.profile.debugConfigurations).toBeDefined()
    })

    it("should preserve user language-specific settings", async () => {
      mockFs.existsSync.mockReturnValue(true)
      mockFs.readFileSync.mockReturnValue(
        JSON.stringify({
          "[python]": { "editor.defaultFormatter": "ms-python.python" },
          "editor.fontSize": 14,
        })
      )

      await service.configureWorkspace()

      const writeCall = mockFs.writeFileSync.mock.calls.find((call: any) =>
        call[0].includes("settings.json")
      )
      const mergedSettings = JSON.parse(writeCall[1])
      expect(mergedSettings["[python]"]).toEqual({
        "editor.defaultFormatter": "ms-python.python",
      })
    })
  })
})
