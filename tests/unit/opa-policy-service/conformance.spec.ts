// @file        tests/unit/opa-policy-service/conformance.spec.ts
// @module      policy/opa-service
// @description Conformance tests for OPA policy service bundle lifecycle and decision logging
//

import * as fs from "fs"
import * as os from "os"
import * as path from "path"
import { afterEach, beforeEach, describe, expect, it } from "vitest"
import { OpaPolicyService } from "../../../src/services/opa-policy-service"

function makeCatalogFile(root: string): string {
  const p = path.join(root, "bundle-catalog.json")
  const catalog = {
    schema_version: "1",
    updated_at: "2026-04-18T00:00:00Z",
    channels: {
      stable: {
        version: "1.0.0",
        bundle_manifest: "artifacts/policy-bundles/policy-bundle-1.0.0-stable.manifest.json",
      },
      canary: {
        version: "1.0.0",
        bundle_manifest: "artifacts/policy-bundles/policy-bundle-1.0.0-canary.manifest.json",
      },
      rollback: {
        version: "0.9.9",
        bundle_manifest: "artifacts/policy-bundles/policy-bundle-0.9.9-stable.manifest.json",
      },
    },
  }
  fs.writeFileSync(p, JSON.stringify(catalog, null, 2) + "\n", "utf-8")
  return p
}

describe("OpaPolicyService conformance", () => {
  let tempDir: string
  let catalogPath: string
  let decisionLogPath: string

  beforeEach(() => {
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "opa-policy-service-"))
    catalogPath = makeCatalogFile(tempDir)
    decisionLogPath = path.join(tempDir, "decision-log.jsonl")
  })

  afterEach(() => {
    fs.rmSync(tempDir, { recursive: true, force: true })
  })

  it("resolves stable channel by default", () => {
    const service = new OpaPolicyService({
      catalogPath,
      decisionLogPath,
      retentionDays: 7,
    })

    const resolved = service.resolveBundle("https://github.com/kushin77/code-server")

    expect(resolved.channel).toBe("stable")
    expect(resolved.version).toBe("1.0.0")
  })

  it("routes repo to canary when distribution contract matches", () => {
    const service = new OpaPolicyService({
      catalogPath,
      decisionLogPath,
      retentionDays: 7,
    })

    service.setDistributionContract({
      rules: [
        {
          repo_pattern: "https://github.com/kushin77/experimental-*",
          channel: "canary",
        },
      ],
    })

    const resolved = service.resolveBundle("https://github.com/kushin77/experimental-portal")
    expect(resolved.channel).toBe("canary")
  })

  it("denies mutating action on rollback channel in simulation", () => {
    const service = new OpaPolicyService({
      catalogPath,
      decisionLogPath,
      retentionDays: 7,
    })

    service.setDistributionContract({
      rules: [
        {
          repo_pattern: "https://github.com/kushin77/legacy-*",
          channel: "rollback",
        },
      ],
    })

    const result = service.simulateDecision({
      actor: "admin@example.com",
      repo: "https://github.com/kushin77/legacy-app",
      action: "write",
      correlationId: "corr-rollback-1",
    })

    expect(result.decision).toBe("deny")
    expect(result.reason).toContain("read-only")
  })

  it("logs and queries decision events by correlation id", () => {
    const service = new OpaPolicyService({
      catalogPath,
      decisionLogPath,
      retentionDays: 7,
    })

    const result = service.simulateDecision({
      actor: "alice@example.com",
      repo: "https://github.com/kushin77/code-server",
      action: "read",
      correlationId: "corr-100",
    })

    service.logDecision(
      {
        actor: "alice@example.com",
        repo: "https://github.com/kushin77/code-server",
        action: "read",
        correlationId: "corr-100",
      },
      result,
      "security",
    )

    const events = service.queryDecisionLogs({ correlationId: "corr-100" })
    expect(events).toHaveLength(1)
    expect(events[0].policy_domain).toBe("security")
  })

  it("prunes old decision logs according to retention", () => {
    const service = new OpaPolicyService({
      catalogPath,
      decisionLogPath,
      retentionDays: 1,
    })

    const oldLine = JSON.stringify({
      timestamp: "2020-01-01T00:00:00.000Z",
      correlation_id: "old-1",
      actor: "old@example.com",
      repo: "repo",
      action: "read",
      decision: "allow",
      reason: "old",
      policy_domain: "governance",
      bundle_version: "0.0.1",
      channel: "stable",
    })
    fs.writeFileSync(decisionLogPath, `${oldLine}\n`, "utf-8")

    const result = service.simulateDecision({
      actor: "new@example.com",
      repo: "https://github.com/kushin77/code-server",
      action: "read",
      correlationId: "new-1",
    })

    service.logDecision(
      {
        actor: "new@example.com",
        repo: "https://github.com/kushin77/code-server",
        action: "read",
        correlationId: "new-1",
      },
      result,
    )

    const lines = fs
      .readFileSync(decisionLogPath, "utf-8")
      .split(/\r?\n/)
      .filter((line) => line.trim().length > 0)

    expect(lines).toHaveLength(1)
    expect(lines[0]).toContain("new-1")
  })

  it("writes promotion audit event", () => {
    const service = new OpaPolicyService({
      catalogPath,
      decisionLogPath,
      retentionDays: 7,
    })

    const event = service.promoteBundle(
      "stable",
      "1.1.0",
      "artifacts/policy-bundles/policy-bundle-1.1.0-stable.manifest.json",
    )

    expect(event.event).toBe("promote")

    const updatedCatalog = JSON.parse(fs.readFileSync(catalogPath, "utf-8"))
    expect(updatedCatalog.channels.stable.version).toBe("1.1.0")

    const auditPath = `${decisionLogPath}.promotion.jsonl`
    const auditLines = fs
      .readFileSync(auditPath, "utf-8")
      .split(/\r?\n/)
      .filter((line) => line.trim().length > 0)

    expect(auditLines).toHaveLength(1)
    expect(auditLines[0]).toContain("\"event\":\"promote\"")
  })

  it("requires reason for rollback", () => {
    const service = new OpaPolicyService({
      catalogPath,
      decisionLogPath,
      retentionDays: 7,
    })

    expect(() => {
      service.rollbackBundle("rollback", "1.0.0", "manifest.json", " ")
    }).toThrowError("rollback reason is required")
  })
})
