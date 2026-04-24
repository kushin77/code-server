// @file        src/services/opa-policy-service/index.ts
// @module      policy/opa-service
// @description Enterprise OPA policy service for bundle discovery, rollout lifecycle, and decision logging
//
import * as fs from "fs";
import * as path from "path";
function nowIso() {
    return new Date().toISOString();
}
function globToRegex(pattern) {
    const escaped = pattern.replace(/[.+^${}()|[\]\\]/g, "\\$&");
    return new RegExp(`^${escaped.replace(/\*/g, ".*")}$`);
}
function parseJson(content) {
    return JSON.parse(content);
}
export class OpaPolicyService {
    constructor(config) {
        this.distribution = { rules: [] };
        this.config = config;
    }
    loadCatalog() {
        const raw = fs.readFileSync(this.config.catalogPath, "utf-8");
        return parseJson(raw);
    }
    saveCatalog(catalog) {
        const next = {
            ...catalog,
            updated_at: nowIso(),
        };
        fs.writeFileSync(this.config.catalogPath, JSON.stringify(next, null, 2) + "\n", "utf-8");
    }
    setDistributionContract(contract) {
        this.distribution = contract;
    }
    resolveBundle(repo) {
        const catalog = this.loadCatalog();
        const channel = this.resolveChannel(repo);
        const pointer = catalog.channels[channel];
        return {
            repo,
            channel,
            version: pointer.version,
            bundleManifest: pointer.bundle_manifest,
        };
    }
    simulateDecision(input) {
        const bundle = this.resolveBundle(input.repo);
        if (bundle.channel === "rollback" && input.action !== "read") {
            return {
                decision: "deny",
                reason: "rollback channel is read-only for safety",
                channel: bundle.channel,
                bundleVersion: bundle.version,
            };
        }
        return {
            decision: "allow",
            reason: "policy bundle resolved and action permitted",
            channel: bundle.channel,
            bundleVersion: bundle.version,
        };
    }
    logDecision(input, result, policyDomain = "governance") {
        const event = {
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
        };
        const line = JSON.stringify(event);
        fs.mkdirSync(path.dirname(this.config.decisionLogPath), { recursive: true });
        fs.appendFileSync(this.config.decisionLogPath, `${line}\n`, "utf-8");
        this.pruneDecisionLog();
        return event;
    }
    queryDecisionLogs(query = {}) {
        if (!fs.existsSync(this.config.decisionLogPath)) {
            return [];
        }
        const cutoff = query.sinceIso ? new Date(query.sinceIso).getTime() : undefined;
        const rows = fs
            .readFileSync(this.config.decisionLogPath, "utf-8")
            .split(/\r?\n/)
            .filter((line) => line.trim().length > 0)
            .map((line) => parseJson(line));
        return rows.filter((row) => {
            if (query.correlationId && row.correlation_id !== query.correlationId)
                return false;
            if (query.actor && row.actor !== query.actor)
                return false;
            if (query.decision && row.decision !== query.decision)
                return false;
            if (query.policyDomain && row.policy_domain !== query.policyDomain)
                return false;
            if (cutoff && new Date(row.timestamp).getTime() < cutoff)
                return false;
            return true;
        });
    }
    promoteBundle(channel, version, bundleManifest) {
        const catalog = this.loadCatalog();
        catalog.channels[channel] = { version, bundle_manifest: bundleManifest };
        this.saveCatalog(catalog);
        return this.writePromotionAudit({
            timestamp: nowIso(),
            event: "promote",
            channel,
            version,
            bundle_manifest: bundleManifest,
            reason: "promotion",
        });
    }
    rollbackBundle(channel, version, bundleManifest, reason) {
        const trimmedReason = reason.trim();
        if (trimmedReason.length === 0) {
            throw new Error("rollback reason is required");
        }
        const catalog = this.loadCatalog();
        catalog.channels[channel] = { version, bundle_manifest: bundleManifest };
        this.saveCatalog(catalog);
        return this.writePromotionAudit({
            timestamp: nowIso(),
            event: "rollback",
            channel,
            version,
            bundle_manifest: bundleManifest,
            reason: trimmedReason,
        });
    }
    resolveChannel(repo) {
        for (const rule of this.distribution.rules) {
            if (globToRegex(rule.repo_pattern).test(repo)) {
                return rule.channel;
            }
        }
        return "stable";
    }
    pruneDecisionLog() {
        if (!fs.existsSync(this.config.decisionLogPath)) {
            return;
        }
        const retentionMs = this.config.retentionDays * 24 * 60 * 60 * 1000;
        const cutoff = Date.now() - retentionMs;
        const lines = fs
            .readFileSync(this.config.decisionLogPath, "utf-8")
            .split(/\r?\n/)
            .filter((line) => line.trim().length > 0);
        const kept = lines.filter((line) => {
            const row = parseJson(line);
            return new Date(row.timestamp).getTime() >= cutoff;
        });
        fs.writeFileSync(this.config.decisionLogPath, kept.join("\n") + (kept.length > 0 ? "\n" : ""), "utf-8");
    }
    writePromotionAudit(event) {
        const auditPath = `${this.config.decisionLogPath}.promotion.jsonl`;
        fs.mkdirSync(path.dirname(auditPath), { recursive: true });
        fs.appendFileSync(auditPath, `${JSON.stringify(event)}\n`, "utf-8");
        return event;
    }
}
export * from "./types";
//# sourceMappingURL=index.js.map