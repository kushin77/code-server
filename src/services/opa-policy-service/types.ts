// @file        src/services/opa-policy-service/types.ts
// @module      policy/opa-service
// @description Types for OPA policy bundle discovery, rollout, and decision logging
//

export type PolicyChannel = "stable" | "canary" | "rollback"

export interface BundlePointer {
  version: string
  bundle_manifest: string
}

export interface BundleCatalog {
  schema_version: string
  updated_at: string
  channels: Record<PolicyChannel, BundlePointer>
}

export interface DistributionRule {
  repo_pattern: string
  channel: PolicyChannel
}

export interface DistributionContract {
  rules: DistributionRule[]
}

export interface ResolvedPolicyBundle {
  repo: string
  channel: PolicyChannel
  version: string
  bundleManifest: string
}

export interface PolicyDecisionInput {
  actor: string
  repo: string
  action: "read" | "write" | "admin"
  correlationId?: string
}

export interface PolicyDecisionResult {
  decision: "allow" | "deny"
  reason: string
  channel: PolicyChannel
  bundleVersion: string
}

export interface DecisionLogEvent {
  timestamp: string
  correlation_id: string
  actor: string
  repo: string
  action: string
  decision: "allow" | "deny"
  reason: string
  policy_domain: string
  bundle_version: string
  channel: PolicyChannel
}

export interface DecisionQuery {
  correlationId?: string
  actor?: string
  decision?: "allow" | "deny"
  policyDomain?: string
  sinceIso?: string
}

export interface PolicyServiceConfig {
  catalogPath: string
  decisionLogPath: string
  retentionDays: number
}

export interface PromotionAuditEvent {
  timestamp: string
  event: "promote" | "rollback"
  channel: PolicyChannel
  version: string
  bundle_manifest: string
  reason: string
}
