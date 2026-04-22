// apps/backend/src/services/workspace/__tests__/hot-switch-service.test.ts
import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { initHotWorkspaceSwitchService, type WorkspaceState } from "../hot-switch-service.js"

describe("Hot Workspace Switching Service", () => {
  let service: ReturnType<typeof initHotWorkspaceSwitchService>

  function createMockWorkspace(id: string, name: string): WorkspaceState {
    return {
      id,
      userId: "user-123",
      workspaceId: id,
      name,
      files: [
        { path: "file1.ts", language: "typescript", isDirty: false, cursorLine: 0, cursorColumn: 0, scrollTop: 0 },
      ],
      editorState: {
        activeGroup: 0,
        groups: [{ files: ["file1.ts"], active: "file1.ts" }],
        sidebarVisible: true,
        sidebarSize: 300,
        panelVisible: true,
        panelHeight: 250,
      },
      terminals: [],
      settings: { theme: "dark", fontSize: 14, autoSave: true, extensions: [] },
      timestamp: new Date(),
      isActive: false,
    }
  }

  beforeEach(() => {
    service = initHotWorkspaceSwitchService()
  })

  afterEach(() => {
    service.resetMetrics()
  })

  describe("Workspace Registration", () => {
    it("should register a new workspace", () => {
      const ws = createMockWorkspace("ws-1", "Workspace 1")
      const result = service.registerWorkspace(ws)

      expect(result.success).toBe(true)
      expect(result.workspaceId).toBe("ws-1")
    })

    it("should reject when max concurrent workspaces exceeded", () => {
      // Register 5 workspaces (max)
      for (let i = 0; i < 5; i++) {
        service.registerWorkspace(createMockWorkspace(`ws-${i}`, `Workspace ${i}`))
      }

      // 6th should fail
      const result = service.registerWorkspace(createMockWorkspace("ws-5", "Workspace 5"))

      expect(result.success).toBe(false)
      expect(result.error).toContain("Maximum")
    })

    it("should emit workspace-registered event", () => {
      return new Promise<void>((resolve) => {
        const eventSpy = vi.fn()
        service.on("workspace-registered", eventSpy)

        const ws = createMockWorkspace("ws-1", "Test Workspace")
        service.registerWorkspace(ws)

        setTimeout(() => {
          expect(eventSpy).toHaveBeenCalled()
          expect(eventSpy.mock.calls[0][0].workspaceId).toBe("ws-1")
          resolve()
        }, 10)
      })
    })

    it("should enforce 5 concurrent workspace limit", () => {
      for (let i = 0; i < 5; i++) {
        service.registerWorkspace(createMockWorkspace(`ws-${i}`, `Workspace ${i}`))
      }

      expect(service.getWorkspaceCount()).toBe(5)

      const sixthResult = service.registerWorkspace(createMockWorkspace("ws-5", "Workspace 5"))
      expect(sixthResult.success).toBe(false)
      expect(service.getWorkspaceCount()).toBe(5)
    })
  })

  describe("Workspace Switching Performance", () => {
    it("should switch workspace in under 200ms", () => {
      service.registerWorkspace(createMockWorkspace("ws-1", "Workspace 1"))
      service.registerWorkspace(createMockWorkspace("ws-2", "Workspace 2"))

      const result = service.switchWorkspace(null, "ws-1")

      expect(result.success).toBe(true)
      expect(result.duration).toBeDefined()
      expect(result.duration!).toBeLessThan(200)
    })

    it("should switch between multiple workspaces quickly", () => {
      service.registerWorkspace(createMockWorkspace("ws-1", "Workspace 1"))
      service.registerWorkspace(createMockWorkspace("ws-2", "Workspace 2"))
      service.registerWorkspace(createMockWorkspace("ws-3", "Workspace 3"))

      service.switchWorkspace(null, "ws-1")
      const result2 = service.switchWorkspace("ws-1", "ws-2")
      const result3 = service.switchWorkspace("ws-2", "ws-3")

      expect(result2.duration).toBeLessThan(200)
      expect(result3.duration).toBeLessThan(200)
    })

    it("should handle rapid switching", () => {
      service.registerWorkspace(createMockWorkspace("ws-1", "Workspace 1"))
      service.registerWorkspace(createMockWorkspace("ws-2", "Workspace 2"))

      const startTime = Date.now()

      for (let i = 0; i < 10; i++) {
        const from = i % 2 === 0 ? "ws-1" : "ws-2"
        const to = i % 2 === 0 ? "ws-2" : "ws-1"
        service.switchWorkspace(from, to)
      }

      const totalTime = Date.now() - startTime
      expect(totalTime).toBeLessThan(2000) // 10 switches should be fast
    })

    it("should meet performance requirements consistently", () => {
      service.registerWorkspace(createMockWorkspace("ws-1", "Workspace 1"))
      service.registerWorkspace(createMockWorkspace("ws-2", "Workspace 2"))

      for (let i = 0; i < 50; i++) {
        const from = i % 2 === 0 ? "ws-1" : "ws-2"
        const to = i % 2 === 0 ? "ws-2" : "ws-1"
        service.switchWorkspace(from, to)
      }

      const percentage = service.getPercentageWithinRequirement()
      expect(percentage).toBeGreaterThan(95) // 95%+ should be under 200ms
    })
  })

  describe("Active Workspace Management", () => {
    it("should track active workspace", () => {
      service.registerWorkspace(createMockWorkspace("ws-1", "Workspace 1"))
      service.switchWorkspace(null, "ws-1")

      const active = service.getActiveWorkspace()
      expect(active).toBeDefined()
      expect(active?.id).toBe("ws-1")
    })

    it("should update active workspace on switch", () => {
      service.registerWorkspace(createMockWorkspace("ws-1", "Workspace 1"))
      service.registerWorkspace(createMockWorkspace("ws-2", "Workspace 2"))

      service.switchWorkspace(null, "ws-1")
      let active = service.getActiveWorkspace()
      expect(active?.id).toBe("ws-1")

      service.switchWorkspace("ws-1", "ws-2")
      active = service.getActiveWorkspace()
      expect(active?.id).toBe("ws-2")
    })

    it("should deactivate previous workspace", () => {
      service.registerWorkspace(createMockWorkspace("ws-1", "Workspace 1"))
      service.registerWorkspace(createMockWorkspace("ws-2", "Workspace 2"))

      service.switchWorkspace(null, "ws-1")
      service.switchWorkspace("ws-1", "ws-2")

      const ws1 = service.getWorkspace("ws-1")
      const ws2 = service.getWorkspace("ws-2")

      expect(ws1?.isActive).toBe(false)
      expect(ws2?.isActive).toBe(true)
    })
  })

  describe("Workspace Closure", () => {
    it("should close a workspace", () => {
      service.registerWorkspace(createMockWorkspace("ws-1", "Workspace 1"))

      const result = service.closeWorkspace("ws-1")

      expect(result.success).toBe(true)
      expect(service.getWorkspace("ws-1")).toBeNull()
    })

    it("should fail closing non-existent workspace", () => {
      const result = service.closeWorkspace("non-existent")

      expect(result.success).toBe(false)
      expect(result.error).toContain("not found")
    })

    it("should switch away when closing active workspace", () => {
      service.registerWorkspace(createMockWorkspace("ws-1", "Workspace 1"))
      service.registerWorkspace(createMockWorkspace("ws-2", "Workspace 2"))

      service.switchWorkspace(null, "ws-1")
      service.closeWorkspace("ws-1")

      const active = service.getActiveWorkspace()
      expect(active?.id).toBe("ws-2")
    })

    it("should emit workspace-closed event", () => {
      return new Promise<void>((resolve) => {
        const eventSpy = vi.fn()
        service.on("workspace-closed", eventSpy)

        service.registerWorkspace(createMockWorkspace("ws-1", "Workspace 1"))
        service.closeWorkspace("ws-1")

        setTimeout(() => {
          expect(eventSpy).toHaveBeenCalled()
          resolve()
        }, 10)
      })
    })
  })

  describe("State Updates", () => {
    it("should update workspace state", () => {
      service.registerWorkspace(createMockWorkspace("ws-1", "Workspace 1"))

      const result = service.updateWorkspaceState("ws-1", {
        settings: { theme: "light", fontSize: 16, autoSave: false, extensions: [] },
      })

      expect(result.success).toBe(true)
      const ws = service.getWorkspace("ws-1")
      expect(ws?.settings.theme).toBe("light")
    })

    it("should fail updating non-existent workspace", () => {
      const result = service.updateWorkspaceState("non-existent", {})

      expect(result.success).toBe(false)
    })

    it("should update timestamp on state change", () => {
      service.registerWorkspace(createMockWorkspace("ws-1", "Workspace 1"))
      const originalTime = service.getWorkspace("ws-1")?.timestamp

      service.updateWorkspaceState("ws-1", { name: "Updated" })
      const newTime = service.getWorkspace("ws-1")?.timestamp

      expect(newTime!.getTime()).toBeGreaterThanOrEqual(originalTime!.getTime())
    })
  })

  describe("Serialization", () => {
    it("should serialize workspace", () => {
      service.registerWorkspace(createMockWorkspace("ws-1", "Workspace 1"))

      const result = service.serializeWorkspace("ws-1")

      expect(result.success).toBe(true)
      expect(result.data).toBeDefined()
      expect(typeof result.data).toBe("string")
    })

    it("should deserialize workspace", () => {
      const original = createMockWorkspace("ws-1", "Workspace 1")
      service.registerWorkspace(original)

      const serializeResult = service.serializeWorkspace("ws-1")
      const deserializeResult = service.deserializeWorkspace(serializeResult.data!)

      expect(deserializeResult.success).toBe(true)
      expect(deserializeResult.state?.id).toBe("ws-1")
      expect(deserializeResult.state?.name).toBe("Workspace 1")
    })

    it("should preserve state through serialization cycle", () => {
      service.registerWorkspace(createMockWorkspace("ws-1", "Test Workspace"))
      service.updateWorkspaceState("ws-1", {
        settings: { theme: "light", fontSize: 16, autoSave: false, extensions: ["ext1"] },
      })

      const serialized = service.serializeWorkspace("ws-1")
      const deserialized = service.deserializeWorkspace(serialized.data!)

      expect(deserialized.state?.settings.theme).toBe("light")
      expect(deserialized.state?.settings.extensions).toContain("ext1")
    })
  })

  describe("Performance Metrics", () => {
    it("should calculate average switch time", () => {
      service.registerWorkspace(createMockWorkspace("ws-1", "Workspace 1"))
      service.registerWorkspace(createMockWorkspace("ws-2", "Workspace 2"))

      for (let i = 0; i < 5; i++) {
        const from = i % 2 === 0 ? "ws-1" : "ws-2"
        const to = i % 2 === 0 ? "ws-2" : "ws-1"
        service.switchWorkspace(from, to)
      }

      const average = service.getAverageSwitchTime()

      expect(average).toBeGreaterThanOrEqual(0)
      expect(average).toBeLessThan(200)
    })

    it("should calculate percentile switch times", () => {
      service.registerWorkspace(createMockWorkspace("ws-1", "Workspace 1"))
      service.registerWorkspace(createMockWorkspace("ws-2", "Workspace 2"))

      for (let i = 0; i < 20; i++) {
        const from = i % 2 === 0 ? "ws-1" : "ws-2"
        const to = i % 2 === 0 ? "ws-2" : "ws-1"
        service.switchWorkspace(from, to)
      }

      const p95 = service.getSwitchTimePercentile(95)
      const p99 = service.getSwitchTimePercentile(99)
      const average = service.getAverageSwitchTime()

      expect(p95).toBeGreaterThanOrEqual(average)
      expect(p99).toBeGreaterThanOrEqual(p95)
      expect(p99).toBeLessThan(200)
    })

    it("should track percentage within requirement", () => {
      service.registerWorkspace(createMockWorkspace("ws-1", "Workspace 1"))
      service.registerWorkspace(createMockWorkspace("ws-2", "Workspace 2"))

      for (let i = 0; i < 100; i++) {
        const from = i % 2 === 0 ? "ws-1" : "ws-2"
        const to = i % 2 === 0 ? "ws-2" : "ws-1"
        service.switchWorkspace(from, to)
      }

      const percentage = service.getPercentageWithinRequirement()

      expect(percentage).toBeGreaterThan(90)
      expect(percentage).toBeLessThanOrEqual(100)
    })

    it("should provide comprehensive statistics", () => {
      service.registerWorkspace(createMockWorkspace("ws-1", "Workspace 1"))
      service.registerWorkspace(createMockWorkspace("ws-2", "Workspace 2"))

      service.switchWorkspace(null, "ws-1")
      service.switchWorkspace("ws-1", "ws-2")

      const stats = service.getStatistics()

      expect(stats.totalWorkspaces).toBe(2)
      expect(stats.activeWorkspace).toBe("ws-2")
      expect(stats.maxConcurrent).toBe(5)
      expect(stats.totalSwitches).toBe(2)
      expect(stats.averageSwitchTime).toBeLessThan(200)
      expect(stats.p95SwitchTime).toBeLessThan(200)
      expect(stats.p99SwitchTime).toBeLessThan(200)
      expect(stats.percentageWithinRequirement).toBeGreaterThan(0)
      expect(stats.failedSwitches).toBe(0)
    })
  })

  describe("Event Emission", () => {
    it("should emit workspace-switched event", () => {
      return new Promise<void>((resolve) => {
        const eventSpy = vi.fn()
        service.on("workspace-switched", eventSpy)

        service.registerWorkspace(createMockWorkspace("ws-1", "Workspace 1"))
        service.switchWorkspace(null, "ws-1")

        setTimeout(() => {
          expect(eventSpy).toHaveBeenCalled()
          const event = eventSpy.mock.calls[0][0]
          expect(event.toWorkspace).toBe("ws-1")
          expect(event.withinRequirement).toBe(true)
          resolve()
        }, 10)
      })
    })
  })

  describe("Concurrent Workspace Management", () => {
    it("should manage 5 concurrent workspaces", () => {
      for (let i = 1; i <= 5; i++) {
        service.registerWorkspace(createMockWorkspace(`ws-${i}`, `Workspace ${i}`))
      }

      expect(service.getWorkspaceCount()).toBe(5)
    })

    it("should allow workspace replacement after close", () => {
      service.registerWorkspace(createMockWorkspace("ws-1", "Workspace 1"))
      expect(service.getWorkspaceCount()).toBe(1)

      service.closeWorkspace("ws-1")
      expect(service.getWorkspaceCount()).toBe(0)

      service.registerWorkspace(createMockWorkspace("ws-new", "New Workspace"))
      expect(service.getWorkspaceCount()).toBe(1)
    })

    it("should switch between all 5 workspaces", () => {
      for (let i = 1; i <= 5; i++) {
        service.registerWorkspace(createMockWorkspace(`ws-${i}`, `Workspace ${i}`))
      }

      for (let i = 1; i <= 5; i++) {
        const result = service.switchWorkspace(i === 1 ? null : `ws-${i - 1}`, `ws-${i}`)
        expect(result.success).toBe(true)
        expect(result.duration).toBeLessThan(200)
      }
    })
  })

  describe("Time Tracking", () => {
    it("should track time since last switch", () => {
      service.registerWorkspace(createMockWorkspace("ws-1", "Workspace 1"))
      service.switchWorkspace(null, "ws-1")

      const timeSinceSwitch = service.getTimeSinceLastSwitch()
      expect(timeSinceSwitch).toBeGreaterThanOrEqual(0)
      expect(timeSinceSwitch).toBeLessThan(100)
    })

    it("should return -1 when no switches yet", () => {
      const timeSince = service.getTimeSinceLastSwitch()
      expect(timeSince).toBe(-1)
    })
  })

  describe("Error Handling", () => {
    it("should handle switch to non-existent workspace", () => {
      const result = service.switchWorkspace(null, "non-existent")

      expect(result.success).toBe(false)
      expect(result.error).toContain("not found")
    })

    it("should handle serialization of non-existent workspace", () => {
      const result = service.serializeWorkspace("non-existent")

      expect(result.success).toBe(false)
    })

    it("should handle deserialization of invalid JSON", () => {
      const result = service.deserializeWorkspace("invalid json")

      expect(result.success).toBe(false)
    })
  })

  describe("Metrics Limiting", () => {
    it("should keep only last 1000 metrics", () => {
      service.registerWorkspace(createMockWorkspace("ws-1", "Workspace 1"))
      service.registerWorkspace(createMockWorkspace("ws-2", "Workspace 2"))

      // Perform 1500 switches
      for (let i = 0; i < 1500; i++) {
        const from = i % 2 === 0 ? "ws-1" : "ws-2"
        const to = i % 2 === 0 ? "ws-2" : "ws-1"
        service.switchWorkspace(from, to)
      }

      const metrics = service.getMetrics(1500)
      expect(metrics.length).toBeLessThanOrEqual(1000)
    })
  })
})
