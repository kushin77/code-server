/**
 * AI Model Router — #323: Hybrid Ollama + HuggingFace inference routing
 *
 * Policy engine: local-first with deterministic fallback
 * Security: egress requires AI_EGRESS_ENABLED=true + HF_API_TOKEN
 * Observability: emits Prometheus-format metrics to stdout (scrape via otel-collector)
 */
import * as fs from "fs";
import * as path from "path";
import * as yaml from "js-yaml";
import { getAuditService } from "../audit/audit-service";
function loadRegistry() {
    const configPath = path.resolve(__dirname, "../../../config/model-registry.yml");
    const raw = fs.readFileSync(configPath, "utf8");
    return yaml.load(raw);
}
// ─── Router ───────────────────────────────────────────────────────────────────
export class AIRouter {
    constructor() {
        this.registry = loadRegistry();
        // Emit audit event for registry read (if audit service available)
        const auditService = getAuditService();
        if (auditService) {
            auditService.emit({
                action: 'allow',
                resourceType: 'config',
                fileAction: 'read',
                method: 'READ',
            });
        }
    }
    /**
     * Route a task to the appropriate model/provider.
     * Enforces: local_only blocks egress, egress requires explicit env var.
     */
    route(req) {
        const taskKey = `${req.task}_completion`.replace("chat_completion", "chat");
        const taskConfig = this.registry.routing.task_routing[taskKey];
        const primaryId = req.prefer_model ?? taskConfig?.primary;
        const fallbackId = taskConfig?.fallback ?? null;
        const primaryModel = this.findModel(primaryId);
        if (primaryModel && this.canRoute(primaryModel)) {
            return this.buildResult(primaryModel, false);
        }
        // Fallback path
        if (this.registry.routing.fallback_enabled && fallbackId) {
            const fallbackModel = this.findModel(fallbackId);
            if (fallbackModel && this.canRoute(fallbackModel)) {
                this.emitMetric("ai_fallback_total", { from_provider: primaryModel?.provider ?? "none", to_provider: fallbackModel.provider, reason: "primary_unavailable" });
                return this.buildResult(fallbackModel, true);
            }
        }
        throw new Error(`[AIRouter] No available provider for task=${req.task} model=${primaryId}`);
    }
    findModel(id) {
        if (!id)
            return undefined;
        return this.registry.models.find((m) => m.id === id);
    }
    canRoute(model) {
        // local_only: always allowed (on-prem)
        if (model.routing_policy === "local_only")
            return true;
        // egress: requires AI_EGRESS_ENABLED=true and HF_API_TOKEN set
        if (model.privacy_class === "egress") {
            const egressEnv = this.registry.routing.egress_enabled_env;
            if (process.env[egressEnv] !== "true") {
                this.emitMetric("ai_egress_blocked_total", { model: model.id, reason: "egress_disabled" });
                return false;
            }
            const apiKeyEnv = this.registry.providers.huggingface?.api_key_env;
            if (!apiKeyEnv || !process.env[apiKeyEnv]) {
                this.emitMetric("ai_egress_blocked_total", { model: model.id, reason: "missing_api_key" });
                return false;
            }
            return true;
        }
        return true;
    }
    buildResult(model, was_fallback) {
        const provider = this.registry.providers[model.provider];
        const headers = { "Content-Type": "application/json" };
        let endpoint = provider.base_url;
        if (model.provider === "ollama") {
            endpoint = `${provider.base_url}/api/generate`;
        }
        else if (model.provider === "huggingface") {
            endpoint = `${provider.base_url}/models/${model.hf_model}`;
            const apiKeyEnv = provider.api_key_env;
            headers["Authorization"] = `Bearer ${process.env[apiKeyEnv]}`;
        }
        this.emitMetric("ai_request_total", { provider: model.provider, model: model.id, status: "routed" });
        return { provider: model.provider, model_id: model.id, endpoint, headers, was_fallback };
    }
    /** Prometheus-format metric emission for otel-collector scraping */
    emitMetric(name, labels) {
        const labelStr = Object.entries(labels).map(([k, v]) => `${k}="${v}"`).join(",");
        // In production, replace this with a real Prometheus client counter
        console.log(`# METRIC ${name}{${labelStr}} 1`);
    }
}
export default AIRouter;
//# sourceMappingURL=router.js.map