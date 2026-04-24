// apps/backend/src/services/pr-preview/index.ts
// @file: PR Preview Environment Management Service
// @module: pr-preview
// @description: Auto-provision and manage preview environments for GitHub PRs with docker-compose orchestration
//
// Features:
// - Auto-provision full-stack (frontend+backend+database) on branch push
// - Manage preview URLs and lifecycle
// - Destroy on PR merge/close with 1-hour grace period
// - Track resources and billing
// - Support multiple concurrent previews per org
import { EventEmitter } from "events";
import { createHash } from "crypto";
/**
 * PR Preview Service
 */
export class PRPreviewService extends EventEmitter {
    constructor() {
        super();
        this.previews = new Map();
        this.previewCounter = 0;
        this.gracePeriodMs = 3600000; // 1 hour in milliseconds
        this.cleanupIntervalMs = 60000; // Check every minute
        this.lastCleanupCheck = Date.now();
        // Start cleanup interval for grace period cleanup
        this.startCleanupInterval();
    }
    /**
     * Create a new preview environment for a GitHub branch
     */
    createPreview(prNumber, branch, headSha, owner, repo) {
        try {
            const previewId = `preview-${prNumber}-${Date.now()}-${++this.previewCounter}`;
            const databasePassword = this.generateSecurePassword(32);
            const databaseUser = `pr_${prNumber}_user`;
            const databaseName = `preview_pr_${prNumber}`;
            const preview = {
                id: previewId,
                prNumber,
                branch,
                headSha,
                owner,
                repo,
                createdAt: new Date(),
                status: "provisioning",
                urls: {
                    frontend: `https://pr-${prNumber}-${owner}-${repo}.preview.kushnir.cloud`,
                    backend: `https://api-pr-${prNumber}-${owner}-${repo}.preview.kushnir.cloud`,
                    database: `postgres://${databaseUser}:${databasePassword}@db-pr-${prNumber}:5432/${databaseName}`,
                },
                resources: {
                    databaseName,
                    databaseUser,
                    databasePassword,
                    allocatedMemoryMb: 2048,
                    allocatedCpuCores: 2,
                },
                metrics: {
                    healthCheckStatus: "unknown",
                },
                tags: ["auto-provisioned", `pr-${prNumber}`, `branch-${branch}`],
            };
            this.previews.set(previewId, preview);
            // Emit provisioning started event
            this.emit("event", {
                type: "provisioning_started",
                previewId,
                prNumber,
                timestamp: new Date(),
                metadata: {
                    branch,
                    headSha: headSha.substring(0, 7),
                    urls: preview.urls,
                },
            });
            // Simulate async provisioning - in real implementation would invoke docker-compose
            this.simulateProvisioning(previewId);
            return {
                success: true,
                previewId,
                urls: preview.urls,
            };
        }
        catch (error) {
            const err = error;
            return {
                success: false,
                error: err.message,
            };
        }
    }
    /**
     * Get preview environment details
     */
    getPreview(previewId) {
        return this.previews.get(previewId) || null;
    }
    /**
     * Get all previews for a repository
     */
    getPreviewsByRepo(owner, repo) {
        return Array.from(this.previews.values()).filter((p) => p.owner === owner && p.repo === repo && p.status !== "destroyed");
    }
    /**
     * Get active previews (currently running)
     */
    getActivePreviewsByRepo(owner, repo) {
        return this.getPreviewsByRepo(owner, repo).filter((p) => p.status === "active");
    }
    /**
     * Perform health check on preview
     */
    healthCheck(previewId) {
        const preview = this.previews.get(previewId);
        if (!preview) {
            return { healthy: false, message: "Preview not found" };
        }
        if (preview.status === "destroyed" || preview.status === "destroying") {
            return { healthy: false, message: "Preview is being destroyed or already destroyed" };
        }
        // Simulate health check - in real implementation would call health endpoints
        const isHealthy = preview.status === "active";
        preview.metrics.lastHealthCheckAt = new Date();
        preview.metrics.healthCheckStatus = isHealthy ? "healthy" : "unhealthy";
        if (!isHealthy) {
            this.emit("event", {
                type: "health_check_failed",
                previewId,
                prNumber: preview.prNumber,
                timestamp: new Date(),
            });
        }
        return { healthy: isHealthy };
    }
    /**
     * Mark preview for destruction (starts grace period)
     */
    markForDestruction(previewId, reason = "closed") {
        const preview = this.previews.get(previewId);
        if (!preview) {
            return { success: false };
        }
        const gracePeriodEndsAt = new Date(Date.now() + this.gracePeriodMs);
        preview.gracePeriodEndsAt = gracePeriodEndsAt;
        if (reason === "merged") {
            preview.mergeMetadata = {
                mergedAt: new Date(),
                mergedBy: "github-api",
                destinationBranch: "main",
            };
        }
        return { success: true, gracePeriodEndsAt };
    }
    /**
     * Immediately destroy a preview environment
     */
    destroyPreview(previewId) {
        try {
            const preview = this.previews.get(previewId);
            if (!preview) {
                return { success: false, error: "Preview not found" };
            }
            preview.status = "destroying";
            // Emit destroying event
            this.emit("event", {
                type: "destroying_started",
                previewId,
                prNumber: preview.prNumber,
                timestamp: new Date(),
            });
            // Simulate async destruction - in real implementation would clean up docker resources
            setTimeout(() => {
                preview.status = "destroyed";
                this.emit("event", {
                    type: "destroyed",
                    previewId,
                    prNumber: preview.prNumber,
                    timestamp: new Date(),
                });
            }, 2000);
            return { success: true };
        }
        catch (error) {
            const err = error;
            return { success: false, error: err.message };
        }
    }
    /**
     * Get all previews with their current status
     */
    getAllPreviews() {
        return Array.from(this.previews.values()).filter((p) => p.status !== "destroyed");
    }
    /**
     * Get resource utilization across all active previews
     */
    getResourceUtilization() {
        const activePreviews = Array.from(this.previews.values()).filter((p) => p.status === "active");
        const totalMemoryMb = activePreviews.reduce((sum, p) => sum + (p.resources.allocatedMemoryMb || 0), 0);
        const totalCpuCores = activePreviews.reduce((sum, p) => sum + (p.resources.allocatedCpuCores || 0), 0);
        return {
            totalActivePreviews: activePreviews.length,
            totalMemoryMb,
            totalCpuCores,
            averageMemoryPerPreview: activePreviews.length > 0 ? totalMemoryMb / activePreviews.length : 0,
            averageCpuPerPreview: activePreviews.length > 0 ? totalCpuCores / activePreviews.length : 0,
        };
    }
    /**
     * Get preview statistics by repository
     */
    getRepoStatistics(owner, repo) {
        const repoPreviews = Array.from(this.previews.values()).filter((p) => p.owner === owner && p.repo === repo);
        const activePreviews = repoPreviews.filter((p) => p.status === "active");
        const gracePeriodPreviews = repoPreviews.filter((p) => p.gracePeriodEndsAt && p.status !== "destroyed");
        const totalHours = repoPreviews.reduce((sum, p) => {
            const endTime = p.gracePeriodEndsAt || new Date();
            const hours = (endTime.getTime() - p.createdAt.getTime()) / (1000 * 60 * 60);
            return sum + hours;
        }, 0);
        return {
            repo: `${owner}/${repo}`,
            totalCreated: repoPreviews.length,
            currentlyActive: activePreviews.length,
            gracePeriodActive: gracePeriodPreviews.length,
            totalHours: Math.round(totalHours * 100) / 100,
        };
    }
    /**
     * Get billing information for previews
     */
    calculateBilling(owner, repo, costPerHourUsd = 2.5) {
        const stats = this.getRepoStatistics(owner, repo);
        const totalCost = stats.totalHours * costPerHourUsd;
        return {
            repository: stats.repo,
            totalCost: Math.round(totalCost * 100) / 100,
            breakdown: {
                computerCost: Math.round((totalCost * 0.7) * 100) / 100,
                databaseCost: Math.round((totalCost * 0.2) * 100) / 100,
                networkCost: Math.round((totalCost * 0.1) * 100) / 100,
            },
        };
    }
    /**
     * Terminate the service and cleanup
     */
    terminate() {
        if (this.cleanupInterval) {
            clearInterval(this.cleanupInterval);
        }
    }
    /**
     * Start periodic cleanup of expired grace periods
     */
    startCleanupInterval() {
        this.cleanupInterval = setInterval(() => {
            this.performGracePeriodCleanup();
        }, this.cleanupIntervalMs);
    }
    /**
     * Check and destroy previews whose grace period has expired
     */
    performGracePeriodCleanup() {
        const now = Date.now();
        Array.from(this.previews.values()).forEach((preview) => {
            if (preview.gracePeriodEndsAt && preview.gracePeriodEndsAt.getTime() <= now && preview.status !== "destroying" && preview.status !== "destroyed") {
                // Grace period expired, destroy the preview
                this.destroyPreview(preview.id);
            }
        });
        this.lastCleanupCheck = now;
    }
    /**
     * Simulate provisioning process (in real implementation would use docker-compose)
     */
    simulateProvisioning(previewId) {
        setTimeout(() => {
            const preview = this.previews.get(previewId);
            if (!preview)
                return;
            preview.status = "active";
            preview.metrics.creationTimeMs = Date.now() - preview.createdAt.getTime();
            // Generate fake container ID
            preview.resources.containerId = this.generateContainerId();
            this.emit("event", {
                type: "provisioning_complete",
                previewId,
                prNumber: preview.prNumber,
                timestamp: new Date(),
                metadata: {
                    creationTimeMs: preview.metrics.creationTimeMs,
                    containerId: preview.resources.containerId,
                },
            });
        }, 3000);
    }
    /**
     * Generate secure random password
     */
    generateSecurePassword(length) {
        const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*()";
        let password = "";
        const crypto = require("crypto");
        const randomBytes = crypto.randomBytes(length);
        for (let i = 0; i < length; i++) {
            password += chars[randomBytes[i] % chars.length];
        }
        return password;
    }
    /**
     * Generate fake container ID
     */
    generateContainerId() {
        return createHash("sha256").update(`${Date.now()}-${Math.random()}`).digest("hex").substring(0, 12);
    }
}
// Singleton instance
let serviceInstance = null;
/**
 * Get or initialize the PR Preview Service
 */
export function getPRPreviewService() {
    if (!serviceInstance) {
        serviceInstance = new PRPreviewService();
    }
    return serviceInstance;
}
/**
 * Initialize the PR Preview Service (for testing)
 */
export function initPRPreviewService() {
    serviceInstance = new PRPreviewService();
    return serviceInstance;
}
//# sourceMappingURL=index.js.map