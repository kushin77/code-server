// @file        src/services/opa-policy-service/index.ts
// @module      policy/opa-service
// @description Enterprise OPA policy service for bundle discovery, rollout lifecycle, and decision logging
//

import * as fs from "fs"
import * as path from "path"
import {
  BundleCatalog,
  DecisionLogEvent,
  DecisionQuery,
  DistributionContract,
  PolicyDecisionInput,
  PolicyDecisionResult,
  PolicyServiceConfig,
  PromotionAuditEvent,
  ResolvedPolicyBundle,
  PolicyChannel,
} from "./types"

function nowIso(): string {
  return new Date().toISOString()
}

function globToRegex(pattern: string): RegExp {
  const escaped = pattern.replace(/[.+^${}()|[\]\\]/g, "\\$&")
  return new RegExp(`^${escaped.replace(/\*/g, ".*")}$`)
}

function parseJson<T>(content: string): T {
  return JSON.parse(content) as T
}

export class OpaPolicyService {
  private readonly config: PolicyServiceConfig
  private distribution: DistributionContract = { rules: [] }

  constructor(config: PolicyServiceConfig) {
    this.config = config
  }

  loadCatalog(): BundleCatalog {
    const raw = fs.readFileSync(this.config.catalogPath, "utf-8")
    return parseJson<BundleCatalog>(raw)
  }

  saveCatalog(catalog: BundleCatalog): void {
    const next = {
      ...catalog,
      updated_at: nowIso(),
    }
    fs.writeFileSync(this.config.catalogPath, JSON.stringify(next, null, 2) + "\n", "utf-8")
  }

  setDistributionContract(contract: DistributionContract): void {
    this.distribution = contract
  }

  resolveBundle(repo: string): ResolvedPolicyBundle {
    const catalog = this.loadCatalog()
    const channel = this.resolveChannel(repo)
    const pointer = catalog.channels[channel]

    return {
      repo,
      channel,
      version: pointer.version,
      bundleManifest: pointer.bundle_manifest,
    }
  }

  simulateDecision(input: PolicyDecisionInput): PolicyDecisionResult {
    const bundle = this.resolveBundle(input.repo)

    if (bundle.channel === "rollback" && input.action !== "read") {
      return {
        decision: "deny",
        reason: "rollback channel is read-only for safety",
        channel: bundle.channel,
        bundleVersion: bundle.version,
      }
    }

    return {
      decision: "allow",
      reason: "policy bundle resolved and action permitted",
      channel: bundle.channel,
      bundleVersion: bundle.version,
    }
  }

  logDecision(input: PolicyDecisionInput, result: PolicyDecisionResult, policyDomain = "governance"): DecisionLogEvent {
    const event: DecisionLogEvent = {
      timestamp: nowIso(),
      correlation_id: input.correlationId || `corr-${Date.now()}`,
      actor: input.actor,
      repo: input.repo,
      action: input.action,
      decision: result.decision,
      reason: result.reason,
      policy_domain: policyDomain,
      bundle_version: result.bundleVersion,
      channel: result.channel,
    }

    const line = JSON.stringify(event)
    fs.mkdirSync(path.dirname(this.config.decisionLogPath), { recursive: true })
    fs.appendFileSync(this.config.decisionLogPath, `${line}\n`, "utf-8")
    this.pruneDecisionLog()

    return event
  }

  queryDecisionLogs(query: DecisionQuery = {}): DecisionLogEvent[] {
    if (!fs.existsSync(this.config.decisionLogPath)) {
      return []
    }

    const cutoff = query.sinceIso ? new Date(query.sinceIso).getTime() : undefined
    const rows = fs
      .readFileSync(this.config.decisionLogPath, "utf-8")
      .split(/\r?\n/)
      .filter((line) => line.trim().length > 0)
      .map((line) => parseJson<DecisionLogEvent>(line))

    return rows.filter((row) => {
      if (query.correlationId && row.correlation_id !== query.correlationId) return false
      if (query.actor && row.actor !== query.actor) return false
      if (query.decision && row.decision !== query.decision) return false
      if (query.policyDomain && row.policy_domain !== query.policyDomain) return false
      if (cutoff && new Date(row.timestamp).getTime() < cutoff) return false
      return true
    })
  }

  promoteBundle(channel: PolicyChannel, version: string, bundleManifest: string): PromotionAuditEvent {
    const catalog = this.loadCatalog()
    catalog.channels[channel] = { version, bundle_manifest: bundleManifest }
    this.saveCatalog(catalog)

    return this.writePromotionAudit({
      timestamp: nowIso(),
      event: "promote",
      channel,
      version,
      bundle_manifest: bundleManifest,
      reason: "promotion",
    })
  }

  rollbackBundle(channel: PolicyChannel, version: string, bundleManifest: string, reason: string): PromotionAuditEvent {
    const trimmedReason = reason.trim()
    if (trimmedReason.length === 0) {
      throw new Error("rollback reason is required")
    }

    const catalog = this.loadCatalog()
    catalog.channels[channel] = { version, bundle_manifest: bundleManifest }
    this.saveCatalog(catalog)

    return this.writePromotionAudit({
      timestamp: nowIso(),
      event: "rollback",
      channel,
      version,
      bundle_manifest: bundleManifest,
      reason: trimmedReason,
    })
  }

  private resolveChannel(repo: string): PolicyChannel {
    for (const rule of this.distribution.rules) {
      if (globToRegex(rule.repo_pattern).test(repo)) {
        return rule.channel
      }
    }
    return "stable"
  }

  private pruneDecisionLog(): void {
    if (!fs.existsSync(this.config.decisionLogPath)) {
      return
    }

    const retentionMs = this.config.retentionDays * 24 * 60 * 60 * 1000
    const cutoff = Date.now() - retentionMs
    const lines = fs
      .readFileSync(this.config.decisionLogPath, "utf-8")
      .split(/\r?\n/)
      .filter((line) => line.trim().length > 0)

    const kept = lines.filter((line) => {
      const row = parseJson<DecisionLogEvent>(line)
      return new Date(row.timestamp).getTime() >= cutoff
    })

    fs.writeFileSync(this.config.decisionLogPath, kept.join("\n") + (kept.length > 0 ? "\n" : ""), "utf-8")
  }

  private writePromotionAudit(event: PromotionAuditEvent): PromotionAuditEvent {
    const auditPath = `${this.config.decisionLogPath}.promotion.jsonl`
    fs.mkdirSync(path.dirname(auditPath), { recursive: true })
    fs.appendFileSync(auditPath, `${JSON.stringify(event)}\n`, "utf-8")
    return event
  }
}

export * from "./types"
