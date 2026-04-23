#!/usr/bin/env node
/**
 * @file        apps/backend/src/services/resource-quota/index.ts
 * @module      resource-quota
 * @description Resource quota service for enforcing cgroups-based resource limits with tiered quotas
 *
 */
import { EventEmitter } from "events";
import { getLogger } from "../../lib/logger";
const logger = getLogger("resource-quota");
/**
 * Quota tier definitions with resource limits
 */
export var QuotaTier;
(function (QuotaTier) {
    QuotaTier["SMALL"] = "small";
    QuotaTier["MEDIUM"] = "medium";
    QuotaTier["LARGE"] = "large";
})(QuotaTier || (QuotaTier = {}));
/**
 * ResourceQuotaService manages resource quotas and enforcement
 */
export class ResourceQuotaService extends EventEmitter {
    constructor() {
        super();
        this.quotaConfigs = new Map();
        this.activeQuotas = new Map();
        this.resourceUsage = new Map();
        this.violationHistory = new Map();
        this.costLedger = new Map();
        this.costBudgets = new Map();
        this.costAlerts = new Map();
        this.sessionProjects = new Map();
        this.costRates = {
            cpuHourUsd: 0.05,
            ramGbHourUsd: 0.01,
            storageGbDayUsd: 0.023 / 30,
            gpuHourUsd: 0.95,
        };
        this.monitoringInterval = null;
        this.initializeQuotaConfigs();
    }
    /**
     * Get or create singleton instance
     */
    static getInstance() {
        if (!ResourceQuotaService.instance) {
            ResourceQuotaService.instance = new ResourceQuotaService();
        }
        return ResourceQuotaService.instance;
    }
    /**
     * Initialize default quota configurations
     */
    initializeQuotaConfigs() {
        // Small tier: 2 CPU cores, 2GB RAM, 1000 IOPS, 10Mbps
        this.quotaConfigs.set(QuotaTier.SMALL, {
            cpuLimit: 2000,
            memoryLimit: 2 * 1024 * 1024 * 1024,
            diskIOLimit: 1000,
            bandwidthLimit: 10 * 1024 * 1024, // 10 MB/s
        });
        // Medium tier: 4 CPU cores, 8GB RAM, 5000 IOPS, 50Mbps
        this.quotaConfigs.set(QuotaTier.MEDIUM, {
            cpuLimit: 4000,
            memoryLimit: 8 * 1024 * 1024 * 1024,
            diskIOLimit: 5000,
            bandwidthLimit: 50 * 1024 * 1024, // 50 MB/s
        });
        // Large tier: 8 CPU cores, 32GB RAM, 20000 IOPS, 200Mbps
        this.quotaConfigs.set(QuotaTier.LARGE, {
            cpuLimit: 8000,
            memoryLimit: 32 * 1024 * 1024 * 1024,
            diskIOLimit: 20000,
            bandwidthLimit: 200 * 1024 * 1024, // 200 MB/s
        });
    }
    /**
     * Enforce quota for a session
     */
    enforceQuota(sessionId, userId, tier, context) {
        const config = this.quotaConfigs.get(tier);
        if (!config) {
            throw new Error(`Invalid quota tier: ${tier}`);
        }
        const projectId = context?.projectId ?? "default";
        const enforcement = {
            sessionId,
            userId,
            projectId,
            tier,
            cpuLimit: config.cpuLimit,
            memoryLimit: config.memoryLimit,
            diskIOLimit: config.diskIOLimit,
            bandwidthLimit: config.bandwidthLimit,
            status: "active",
            violations: 0,
            createdAt: Date.now(),
            updatedAt: Date.now(),
        };
        this.activeQuotas.set(sessionId, enforcement);
        this.sessionProjects.set(sessionId, projectId);
        this.emit("quotaEnforced", enforcement);
        logger.info(`Quota enforced for session ${sessionId}`, {
            userId,
            tier,
            projectId,
            cpuLimit: config.cpuLimit,
        });
        return enforcement;
    }
    /**
     * Update resource usage for a session
     */
    updateResourceUsage(sessionId, usage) {
        const existing = this.resourceUsage.get(sessionId) || {
            cpuUsage: 0,
            memoryUsage: 0,
            diskIOUsage: 0,
            bandwidthUsage: 0,
            storageUsage: 0,
            gpuUsage: 0,
            timestamp: Date.now(),
        };
        const updated = {
            cpuUsage: usage.cpuUsage !== undefined ? usage.cpuUsage : existing.cpuUsage,
            memoryUsage: usage.memoryUsage !== undefined ? usage.memoryUsage : existing.memoryUsage,
            diskIOUsage: usage.diskIOUsage !== undefined ? usage.diskIOUsage : existing.diskIOUsage,
            bandwidthUsage: usage.bandwidthUsage !== undefined
                ? usage.bandwidthUsage
                : existing.bandwidthUsage,
            storageUsage: usage.storageUsage !== undefined ? usage.storageUsage : existing.storageUsage,
            gpuUsage: usage.gpuUsage !== undefined ? usage.gpuUsage : existing.gpuUsage,
            timestamp: Date.now(),
        };
        this.resourceUsage.set(sessionId, updated);
        // Check for violations
        this.checkQuotaViolations(sessionId);
        return updated;
    }
    /**
     * Check for quota violations and throttle if necessary
     */
    checkQuotaViolations(sessionId) {
        const quota = this.activeQuotas.get(sessionId);
        const usage = this.resourceUsage.get(sessionId);
        if (!quota || !usage) {
            return;
        }
        const violations = [];
        // Check CPU
        if (usage.cpuUsage > quota.cpuLimit) {
            violations.push({
                sessionId,
                userId: quota.userId,
                violationType: "cpu",
                currentUsage: usage.cpuUsage,
                limit: quota.cpuLimit,
                severity: usage.cpuUsage > quota.cpuLimit * 1.2 ? "critical" : "warning",
                timestamp: Date.now(),
            });
        }
        // Check Memory
        if (usage.memoryUsage > quota.memoryLimit) {
            violations.push({
                sessionId,
                userId: quota.userId,
                violationType: "memory",
                currentUsage: usage.memoryUsage,
                limit: quota.memoryLimit,
                severity: usage.memoryUsage > quota.memoryLimit * 1.2 ? "critical" : "warning",
                timestamp: Date.now(),
            });
        }
        // Check Disk I/O
        if (usage.diskIOUsage > quota.diskIOLimit) {
            violations.push({
                sessionId,
                userId: quota.userId,
                violationType: "diskIO",
                currentUsage: usage.diskIOUsage,
                limit: quota.diskIOLimit,
                severity: usage.diskIOUsage > quota.diskIOLimit * 1.2 ? "critical" : "warning",
                timestamp: Date.now(),
            });
        }
        // Check Bandwidth
        if (usage.bandwidthUsage > quota.bandwidthLimit) {
            violations.push({
                sessionId,
                userId: quota.userId,
                violationType: "bandwidth",
                currentUsage: usage.bandwidthUsage,
                limit: quota.bandwidthLimit,
                severity: usage.bandwidthUsage > quota.bandwidthLimit * 1.2 ? "critical" : "warning",
                timestamp: Date.now(),
            });
        }
        // Store violations
        if (violations.length > 0) {
            const history = this.violationHistory.get(sessionId) || [];
            history.push(...violations);
            this.violationHistory.set(sessionId, history.slice(-100)); // Keep last 100
            quota.violations += violations.length;
            quota.lastViolationTime = Date.now();
            // Throttle if critical
            const hasCritical = violations.some((v) => v.severity === "critical");
            if (hasCritical) {
                quota.status = "throttled";
                this.emit("quotaThrottled", { sessionId, violations });
                logger.warn(`Quota throttled for session ${sessionId}`, {
                    violations: violations.length,
                });
            }
            else {
                this.emit("quotaWarning", { sessionId, violations });
                logger.info(`Quota warning for session ${sessionId}`, {
                    violations: violations.length,
                });
            }
        }
    }
    getMonthKey(timestamp = Date.now()) {
        const date = new Date(timestamp);
        const month = String(date.getUTCMonth() + 1).padStart(2, "0");
        return `${date.getUTCFullYear()}-${month}`;
    }
    getCostRecordBucket(monthKey) {
        const bucket = this.costLedger.get(monthKey);
        if (bucket) {
            return bucket;
        }
        const created = [];
        this.costLedger.set(monthKey, created);
        return created;
    }
    getCostBudgetKey(scope, identifier, monthKey) {
        return `${scope}:${identifier}:${monthKey}`;
    }
    summarizeCostEntries(entries, scope) {
        const summaries = new Map();
        for (const entry of entries) {
            const identifier = scope === "user" ? entry.userId : entry.projectId;
            const current = summaries.get(identifier) ?? {
                scope,
                identifier,
                cpuHours: 0,
                ramGbHours: 0,
                storageGbDays: 0,
                gpuHours: 0,
                estimatedCostUsd: 0,
                sampleCount: 0,
            };
            current.cpuHours += entry.cpuHours;
            current.ramGbHours += entry.ramGbHours;
            current.storageGbDays += entry.storageGbDays;
            current.gpuHours += entry.gpuHours;
            current.estimatedCostUsd += entry.estimatedCostUsd;
            current.sampleCount += 1;
            summaries.set(identifier, current);
        }
        return Array.from(summaries.values()).sort((left, right) => right.estimatedCostUsd - left.estimatedCostUsd);
    }
    calculateBudgetStatus(spentUsd, monthlyBudgetUsd) {
        if (spentUsd >= monthlyBudgetUsd) {
            return "exceeded";
        }
        const utilizationPercent = monthlyBudgetUsd > 0 ? (spentUsd / monthlyBudgetUsd) * 100 : 0;
        if (utilizationPercent >= 90) {
            return "critical";
        }
        if (utilizationPercent >= 75) {
            return "warning";
        }
        return "healthy";
    }
    calculateSpentAmount(scope, identifier, monthKey) {
        const entries = this.costLedger.get(monthKey) || [];
        return entries
            .filter((entry) => (scope === "user" ? entry.userId : entry.projectId) === identifier)
            .reduce((sum, entry) => sum + entry.estimatedCostUsd, 0);
    }
    updateCostBudget(scope, identifier, monthKey) {
        const key = this.getCostBudgetKey(scope, identifier, monthKey);
        const budget = this.costBudgets.get(key);
        if (!budget) {
            return undefined;
        }
        const spentUsd = this.calculateSpentAmount(scope, identifier, monthKey);
        const remainingUsd = Math.max(budget.monthlyBudgetUsd - spentUsd, 0);
        const utilizationPercent = budget.monthlyBudgetUsd > 0 ? (spentUsd / budget.monthlyBudgetUsd) * 100 : 0;
        const status = this.calculateBudgetStatus(spentUsd, budget.monthlyBudgetUsd);
        const updated = {
            ...budget,
            spentUsd,
            remainingUsd,
            utilizationPercent,
            status,
            updatedAt: Date.now(),
        };
        this.costBudgets.set(key, updated);
        const previousStatus = budget.status;
        if (status === "healthy") {
            this.costAlerts.delete(key);
        }
        else if (status !== previousStatus) {
            const threshold = status === "critical" || status === "exceeded" ? 90 : 75;
            const alert = {
                scope,
                identifier,
                monthKey,
                monthlyBudgetUsd: budget.monthlyBudgetUsd,
                spentUsd,
                remainingUsd,
                utilizationPercent,
                threshold,
                severity: status === "critical" || status === "exceeded" ? "critical" : "warning",
                message: status === "exceeded"
                    ? `${scope} ${identifier} budget exceeded for ${monthKey}`
                    : `${scope} ${identifier} budget nearing limit for ${monthKey}`,
                timestamp: Date.now(),
            };
            this.costAlerts.set(key, alert);
            this.emit("costBudgetAlert", alert);
            logger.warn(`Cost budget alert for ${scope} ${identifier}`, {
                monthKey,
                spentUsd,
                monthlyBudgetUsd: budget.monthlyBudgetUsd,
                status,
            });
        }
        return updated;
    }
    /**
     * Record a cost sample for a session.
     */
    recordSessionCost(sessionId, sample) {
        if (sample.durationMs <= 0) {
            throw new Error("durationMs must be greater than zero");
        }
        const quota = this.activeQuotas.get(sessionId);
        if (!quota) {
            throw new Error(`Quota not found for session ${sessionId}`);
        }
        const monthKey = this.getMonthKey();
        const projectId = sample.projectId ?? quota.projectId ?? this.sessionProjects.get(sessionId) ?? "default";
        const durationHours = sample.durationMs / 3600000;
        const cpuHours = (sample.cpuMillicores / 1000) * durationHours;
        const ramGbHours = (sample.memoryBytes / (1024 ** 3)) * durationHours;
        const storageGbDays = ((sample.storageBytes ?? 0) / (1024 ** 3)) * (sample.durationMs / 86400000);
        const gpuHours = (sample.gpuCount ?? 0) * durationHours;
        const estimatedCostUsd = cpuHours * this.costRates.cpuHourUsd +
            ramGbHours * this.costRates.ramGbHourUsd +
            storageGbDays * this.costRates.storageGbDayUsd +
            gpuHours * this.costRates.gpuHourUsd;
        const entry = {
            sessionId,
            userId: quota.userId,
            projectId,
            monthKey,
            durationMs: sample.durationMs,
            cpuHours,
            ramGbHours,
            storageGbDays,
            gpuHours,
            estimatedCostUsd,
            timestamp: Date.now(),
        };
        const bucket = this.getCostRecordBucket(monthKey);
        bucket.push(entry);
        this.sessionProjects.set(sessionId, projectId);
        this.updateCostBudget("user", quota.userId, monthKey);
        this.updateCostBudget("project", projectId, monthKey);
        this.emit("costRecorded", entry);
        logger.info(`Cost recorded for session ${sessionId}`, {
            projectId,
            estimatedCostUsd: Number(estimatedCostUsd.toFixed(6)),
        });
        return entry;
    }
    /**
     * Set or update a monthly budget for a user or project.
     */
    setCostBudget(scope, identifier, monthlyBudgetUsd, monthKey = this.getMonthKey()) {
        if (monthlyBudgetUsd <= 0) {
            throw new Error("monthlyBudgetUsd must be greater than zero");
        }
        const spentUsd = this.calculateSpentAmount(scope, identifier, monthKey);
        const remainingUsd = Math.max(monthlyBudgetUsd - spentUsd, 0);
        const utilizationPercent = monthlyBudgetUsd > 0 ? (spentUsd / monthlyBudgetUsd) * 100 : 0;
        const status = this.calculateBudgetStatus(spentUsd, monthlyBudgetUsd);
        const budget = {
            scope,
            identifier,
            monthKey,
            monthlyBudgetUsd,
            spentUsd,
            remainingUsd,
            utilizationPercent,
            status,
            updatedAt: Date.now(),
        };
        const key = this.getCostBudgetKey(scope, identifier, monthKey);
        this.costBudgets.set(key, budget);
        this.updateCostBudget(scope, identifier, monthKey);
        logger.info(`Cost budget configured for ${scope} ${identifier}`, {
            monthKey,
            monthlyBudgetUsd,
        });
        return this.costBudgets.get(key) || budget;
    }
    /**
     * Get monthly cost budgets for a month.
     */
    getCostBudgets(monthKey) {
        const resolvedMonthKey = monthKey ?? this.getMonthKey();
        return Array.from(this.costBudgets.values())
            .filter((budget) => budget.monthKey === resolvedMonthKey)
            .sort((left, right) => right.utilizationPercent - left.utilizationPercent);
    }
    /**
     * Get active cost alerts for a month.
     */
    getCostAlerts(monthKey) {
        const resolvedMonthKey = monthKey ?? this.getMonthKey();
        return Array.from(this.costAlerts.values())
            .filter((alert) => alert.monthKey === resolvedMonthKey)
            .sort((left, right) => right.utilizationPercent - left.utilizationPercent);
    }
    /**
     * Build a monthly cost report.
     */
    getMonthlyCostReport(monthKey) {
        const resolvedMonthKey = monthKey ?? this.getMonthKey();
        const entries = this.costLedger.get(resolvedMonthKey) || [];
        const byUser = this.summarizeCostEntries(entries, "user").map((summary) => ({
            ...summary,
            budget: this.costBudgets.get(this.getCostBudgetKey("user", summary.identifier, resolvedMonthKey)),
        }));
        const byProject = this.summarizeCostEntries(entries, "project").map((summary) => ({
            ...summary,
            budget: this.costBudgets.get(this.getCostBudgetKey("project", summary.identifier, resolvedMonthKey)),
        }));
        const totals = entries.reduce((accumulator, entry) => ({
            scope: "total",
            identifier: resolvedMonthKey,
            cpuHours: accumulator.cpuHours + entry.cpuHours,
            ramGbHours: accumulator.ramGbHours + entry.ramGbHours,
            storageGbDays: accumulator.storageGbDays + entry.storageGbDays,
            gpuHours: accumulator.gpuHours + entry.gpuHours,
            estimatedCostUsd: accumulator.estimatedCostUsd + entry.estimatedCostUsd,
            sampleCount: accumulator.sampleCount + 1,
        }), {
            scope: "total",
            identifier: resolvedMonthKey,
            cpuHours: 0,
            ramGbHours: 0,
            storageGbDays: 0,
            gpuHours: 0,
            estimatedCostUsd: 0,
            sampleCount: 0,
        });
        return {
            monthKey: resolvedMonthKey,
            totals,
            byUser,
            byProject,
            budgets: this.getCostBudgets(resolvedMonthKey),
            alerts: this.getCostAlerts(resolvedMonthKey),
        };
    }
    /**
     * Get current resource usage for a session
     */
    getResourceUsage(sessionId) {
        return this.resourceUsage.get(sessionId);
    }
    /**
     * Get quota enforcement for a session
     */
    getQuotaEnforcement(sessionId) {
        return this.activeQuotas.get(sessionId);
    }
    /**
     * Update quota tier for a session
     */
    updateQuotaTier(sessionId, tier) {
        const quota = this.activeQuotas.get(sessionId);
        if (!quota) {
            throw new Error(`Quota not found for session ${sessionId}`);
        }
        const config = this.quotaConfigs.get(tier);
        if (!config) {
            throw new Error(`Invalid quota tier: ${tier}`);
        }
        quota.tier = tier;
        quota.cpuLimit = config.cpuLimit;
        quota.memoryLimit = config.memoryLimit;
        quota.diskIOLimit = config.diskIOLimit;
        quota.bandwidthLimit = config.bandwidthLimit;
        quota.updatedAt = Date.now();
        quota.violations = 0; // Reset on tier change
        this.emit("quotaTierUpdated", quota);
        logger.info(`Quota tier updated for session ${sessionId}`, { tier });
        return quota;
    }
    /**
     * Pause quota enforcement for a session
     */
    pauseQuota(sessionId) {
        const quota = this.activeQuotas.get(sessionId);
        if (!quota) {
            throw new Error(`Quota not found for session ${sessionId}`);
        }
        quota.status = "paused";
        quota.updatedAt = Date.now();
        this.emit("quotaPaused", quota);
        logger.info(`Quota paused for session ${sessionId}`);
        return quota;
    }
    /**
     * Resume quota enforcement for a session
     */
    resumeQuota(sessionId) {
        const quota = this.activeQuotas.get(sessionId);
        if (!quota) {
            throw new Error(`Quota not found for session ${sessionId}`);
        }
        quota.status = "active";
        quota.updatedAt = Date.now();
        this.emit("quotaResumed", quota);
        logger.info(`Quota resumed for session ${sessionId}`);
        return quota;
    }
    /**
     * Remove quota enforcement for a session
     */
    removeQuota(sessionId) {
        const quota = this.activeQuotas.get(sessionId);
        if (!quota) {
            return false;
        }
        this.activeQuotas.delete(sessionId);
        this.resourceUsage.delete(sessionId);
        this.violationHistory.delete(sessionId);
        this.emit("quotaRemoved", { sessionId });
        logger.info(`Quota removed for session ${sessionId}`);
        return true;
    }
    /**
     * Get violation history for a session
     */
    getViolationHistory(sessionId) {
        return this.violationHistory.get(sessionId) || [];
    }
    /**
     * Get cost entries for a month.
     */
    getCostEntries(monthKey) {
        const resolvedMonthKey = monthKey ?? this.getMonthKey();
        return [...(this.costLedger.get(resolvedMonthKey) || [])];
    }
    /**
     * Get all active quotas
     */
    getAllActiveQuotas() {
        return Array.from(this.activeQuotas.values());
    }
    /**
     * Get quota tier configuration
     */
    getQuotaConfig(tier) {
        return this.quotaConfigs.get(tier);
    }
    /**
     * Get all quota tier configurations
     */
    getAllQuotaConfigs() {
        return new Map(this.quotaConfigs);
    }
    /**
     * Calculate quota utilization percentage
     */
    calculateUtilization(sessionId) {
        const quota = this.activeQuotas.get(sessionId);
        const usage = this.resourceUsage.get(sessionId);
        if (!quota || !usage) {
            return {
                cpu: 0,
                memory: 0,
                diskIO: 0,
                bandwidth: 0,
                overallPercentage: 0,
            };
        }
        const cpu = (usage.cpuUsage / quota.cpuLimit) * 100;
        const memory = (usage.memoryUsage / quota.memoryLimit) * 100;
        const diskIO = (usage.diskIOUsage / quota.diskIOLimit) * 100;
        const bandwidth = (usage.bandwidthUsage / quota.bandwidthLimit) * 100;
        const overallPercentage = (cpu + memory + diskIO + bandwidth) / 4;
        return {
            cpu: Math.min(cpu, 100),
            memory: Math.min(memory, 100),
            diskIO: Math.min(diskIO, 100),
            bandwidth: Math.min(bandwidth, 100),
            overallPercentage: Math.min(overallPercentage, 100),
        };
    }
    /**
     * Get statistics for all sessions
     */
    getStatistics() {
        const quotas = Array.from(this.activeQuotas.values());
        const throttledCount = quotas.filter((q) => q.status === "throttled").length;
        const totalViolations = quotas.reduce((sum, q) => sum + q.violations, 0);
        let totalUtilization = 0;
        quotas.forEach((quota) => {
            const util = this.calculateUtilization(quota.sessionId);
            totalUtilization += util.overallPercentage;
        });
        const averageUtilization = quotas.length > 0 ? totalUtilization / quotas.length : 0;
        return {
            totalActiveSessions: quotas.length,
            totalViolations,
            throttledSessions: throttledCount,
            averageUtilization,
        };
    }
    /**
     * Start monitoring interval (for testing/simulation)
     */
    startMonitoring(intervalMs = 5000) {
        if (this.monitoringInterval) {
            return;
        }
        this.monitoringInterval = setInterval(() => {
            const quotas = Array.from(this.activeQuotas.values());
            quotas.forEach((quota) => {
                this.checkQuotaViolations(quota.sessionId);
                const usage = this.resourceUsage.get(quota.sessionId);
                if (usage) {
                    this.recordSessionCost(quota.sessionId, {
                        durationMs: intervalMs,
                        cpuMillicores: usage.cpuUsage,
                        memoryBytes: usage.memoryUsage,
                        storageBytes: usage.storageUsage ?? 0,
                        gpuCount: usage.gpuUsage ?? 0,
                        projectId: quota.projectId,
                    });
                }
            });
        }, intervalMs);
        logger.info(`Resource quota monitoring started`, { intervalMs });
    }
    /**
     * Stop monitoring interval
     */
    stopMonitoring() {
        if (this.monitoringInterval) {
            clearInterval(this.monitoringInterval);
            this.monitoringInterval = null;
            logger.info("Resource quota monitoring stopped");
        }
    }
    /**
     * Reset service for testing
     */
    reset() {
        this.stopMonitoring();
        this.activeQuotas.clear();
        this.resourceUsage.clear();
        this.violationHistory.clear();
        this.costLedger.clear();
        this.costBudgets.clear();
        this.costAlerts.clear();
        this.sessionProjects.clear();
        this.removeAllListeners();
        logger.debug("Resource quota service reset");
    }
}
ResourceQuotaService.instance = null;
// Export singleton instance
const quotaService = new ResourceQuotaService();
export default quotaService;
//# sourceMappingURL=index.js.map