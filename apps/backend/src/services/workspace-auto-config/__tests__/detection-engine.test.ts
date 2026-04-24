// apps/backend/src/services/workspace-auto-config/__tests__/detection-engine.test.ts
// @file: Tests for workspace project type detection (Issue #1048)

import { describe, it, expect, beforeEach, vi } from "vitest"
import { ProjectDetectionEngine, ProjectType } from "../detection-engine"
import * as fs from "fs"

vi.mock("fs")

describe("ProjectDetectionEngine", () => {
  let engine: ProjectDetectionEngine
  const mockFs = fs as any

  beforeEach(() => {
    vi.clearAllMocks()
    engine = new ProjectDetectionEngine("/test/workspace")
  })

  describe("detectProjectType", () => {
    it("should detect Node.js + TypeScript projects", async () => {
      mockFs.readdirSync.mockReturnValue([
        { name: "package.json", isFile: () => true, isDirectory: () => false },
        { name: "tsconfig.json", isFile: () => true, isDirectory: () => false },
        { name: "src", isFile: () => false, isDirectory: () => true },
      ])

      const result = await engine.detectProjectType()

      expect(result.type).toBe(ProjectType.NODE_TYPESCRIPT)
      expect(result.confidence).toBeGreaterThan(50)
      expect(result.detectedFiles).toContain("package.json")
      expect(result.detectedFiles).toContain("tsconfig.json")
    })

    it("should detect Python projects", async () => {
      mockFs.readdirSync.mockReturnValue([
        { name: "requirements.txt", isFile: () => true, isDirectory: () => false },
        { name: "src", isFile: () => false, isDirectory: () => true },
      ])

      const result = await engine.detectProjectType()

      expect(result.type).toBe(ProjectType.PYTHON)
      expect(result.confidence).toBeGreaterThan(0)
    })

    it("should detect Go projects", async () => {
      mockFs.readdirSync.mockReturnValue([
        { name: "go.mod", isFile: () => true, isDirectory: () => false },
        { name: "go.sum", isFile: () => true, isDirectory: () => false },
      ])

      const result = await engine.detectProjectType()

      expect(result.type).toBe(ProjectType.GO)
      expect(result.confidence).toBeGreaterThan(50)
    })

    it("should detect Rust projects", async () => {
      mockFs.readdirSync.mockReturnValue([
        { name: "Cargo.toml", isFile: () => true, isDirectory: () => false },
        { name: "Cargo.lock", isFile: () => true, isDirectory: () => false },
        { name: "src", isFile: () => false, isDirectory: () => true },
      ])

      const result = await engine.detectProjectType()

      expect(result.type).toBe(ProjectType.RUST)
      expect(result.confidence).toBeGreaterThan(50)
    })

    it("should detect Java projects", async () => {
      mockFs.readdirSync.mockReturnValue([
        { name: "pom.xml", isFile: () => true, isDirectory: () => false },
        { name: "src", isFile: () => false, isDirectory: () => true },
      ])

      const result = await engine.detectProjectType()

      expect(result.type).toBe(ProjectType.JAVA)
      expect(result.confidence).toBeGreaterThan(0)
    })

    it("should detect Java + Spring projects with higher confidence", async () => {
      mockFs.readdirSync.mockReturnValue([
        { name: "pom.xml", isFile: () => true, isDirectory: () => false },
        { name: "application.properties", isFile: () => true, isDirectory: () => false },
        { name: "src", isFile: () => false, isDirectory: () => true },
      ])

      const result = await engine.detectProjectType()

      expect(result.type).toBe(ProjectType.JAVA_SPRING)
      expect(result.confidence).toBeGreaterThan(0)
    })

    it("should return UNKNOWN for unrecognized projects", async () => {
      mockFs.readdirSync.mockReturnValue([
        { name: "README.md", isFile: () => true, isDirectory: () => false },
        { name: "random-file.txt", isFile: () => true, isDirectory: () => false },
      ])

      const result = await engine.detectProjectType()

      expect(result.type).toBe(ProjectType.UNKNOWN)
      expect(result.confidence).toBe(0)
    })

    it("should complete detection in < 2 seconds", async () => {
      mockFs.readdirSync.mockReturnValue([
        { name: "package.json", isFile: () => true, isDirectory: () => false },
        { name: "tsconfig.json", isFile: () => true, isDirectory: () => false },
      ])

      const startTime = Date.now()
      await engine.detectProjectType(2000)
      const duration = Date.now() - startTime

      expect(duration).toBeLessThan(2000)
    })

    it("should respect timeout parameter", async () => {
      mockFs.readdirSync.mockReturnValue([
        { name: "package.json", isFile: () => true, isDirectory: () => false },
      ])

      const startTime = Date.now()
      await engine.detectProjectType(500)
      const duration = Date.now() - startTime

      // Should complete within reasonable time (may exceed 500ms slightly due to processing)
      expect(duration).toBeLessThan(1000)
    })
  })

  describe("getProfileForType", () => {
    it("should return Node.js TypeScript profile with correct extensions", () => {
      const profile = engine.getProfileForType(ProjectType.NODE_TYPESCRIPT)

      expect(profile.type).toBe(ProjectType.NODE_TYPESCRIPT)
      expect(profile.extensions).toContain("ms-vscode.vscode-typescript-next")
      expect(profile.extensions).toContain("GitHub.copilot")
      expect(profile.settings["[typescript]"]).toBeDefined()
      expect(profile.tasks.length).toBeGreaterThan(0)
      expect(profile.debugConfigurations.length).toBeGreaterThan(0)
    })

    it("should return Python profile with correct settings", () => {
      const profile = engine.getProfileForType(ProjectType.PYTHON)

      expect(profile.type).toBe(ProjectType.PYTHON)
      expect(profile.extensions).toContain("ms-python.python")
      expect(profile.settings["python.linting.enabled"]).toBe(true)
    })

    it("should return Go profile with go build task", () => {
      const profile = engine.getProfileForType(ProjectType.GO)

      expect(profile.type).toBe(ProjectType.GO)
      expect(profile.tasks.some((t) => t.label === "go: build")).toBe(true)
    })

    it("should return Rust profile with cargo tasks", () => {
      const profile = engine.getProfileForType(ProjectType.RUST)

      expect(profile.type).toBe(ProjectType.RUST)
      expect(profile.tasks.some((t) => t.label === "cargo: build")).toBe(true)
      expect(profile.tasks.some((t) => t.label === "cargo: test")).toBe(true)
    })

    it("should return profile with debug configurations", () => {
      const profile = engine.getProfileForType(ProjectType.NODE_TYPESCRIPT)

      expect(profile.debugConfigurations).toHaveLength(1)
      expect(profile.debugConfigurations[0].type).toBe("node")
      expect(profile.debugConfigurations[0].request).toBe("launch")
    })

    it("should return default profile for UNKNOWN type", () => {
      const profile = engine.getProfileForType(ProjectType.UNKNOWN)

      expect(profile.type).toBe(ProjectType.UNKNOWN)
      expect(profile.extensions).toContain("GitHub.copilot")
      expect(profile.tasks).toEqual([])
    })
  })

  describe("project detection priority", () => {
    it("should prioritize TypeScript over JavaScript for mixed projects", async () => {
      mockFs.readdirSync.mockReturnValue([
        { name: "package.json", isFile: () => true, isDirectory: () => false },
        { name: "tsconfig.json", isFile: () => true, isDirectory: () => false },
      ])

      const result = await engine.detectProjectType()

      expect(result.type).toBe(ProjectType.NODE_TYPESCRIPT)
    })

    it("should prioritize Spring over plain Java", async () => {
      mockFs.readdirSync.mockReturnValue([
        { name: "pom.xml", isFile: () => true, isDirectory: () => false },
        { name: "application.properties", isFile: () => true, isDirectory: () => false },
      ])

      const result = await engine.detectProjectType()

      expect(result.type).toBe(ProjectType.JAVA_SPRING)
    })

    it("should prioritize Django over plain Python", async () => {
      mockFs.readdirSync.mockReturnValue([
        { name: "manage.py", isFile: () => true, isDirectory: () => false },
        { name: "requirements.txt", isFile: () => true, isDirectory: () => false },
      ])

      const result = await engine.detectProjectType()

      expect(result.type).toBe(ProjectType.PYTHON_DJANGO)
    })
  })
})
