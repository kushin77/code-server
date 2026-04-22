#!/usr/bin/env node
/**
 * @file        apps/backend/src/routes/resource-quota.ts
 * @module      routes/resource-quota
 * @description HTTP routes for resource quota management
 *
 */

import { Router, Request, Response } from "express";
import { getLogger } from "../lib/logger";
import ResourceQuotaService, { QuotaTier, QuotaEnforcement } from "../services/resource-quota";

const logger = getLogger("resource-quota-routes");
const router = Router();
const quotaService = ResourceQuotaService.getInstance();

/**
 * POST /resource-quotas/enforce
 * Enforce a resource quota for a session
 */
router.post("/enforce", (req: Request, res: Response) => {
  try {
    const { sessionId, userId, tier } = req.body;

    if (!sessionId || !userId || !tier) {
      return res.status(400).json({
        error: "Missing required fields: sessionId, userId, tier",
      });
    }

    if (!Object.values(QuotaTier).includes(tier)) {
      return res.status(400).json({
        error: `Invalid tier. Must be one of: ${Object.values(QuotaTier).join(", ")}`,
      });
    }

    const enforcement = quotaService.enforceQuota(sessionId, userId, tier);
    res.status(201).json({
      success: true,
      data: enforcement,
    });
  } catch (error) {
    logger.error("Error enforcing quota", { error });
    res.status(500).json({
      error: "Failed to enforce quota",
      details: error instanceof Error ? error.message : "Unknown error",
    });
  }
});

/**
 * PUT /resource-quotas/:sessionId/usage
 * Update resource usage for a session
 */
router.put("/:sessionId/usage", (req: Request, res: Response) => {
  try {
    const { sessionId } = req.params;
    const { cpuUsage, memoryUsage, diskIOUsage, bandwidthUsage } = req.body;

    const usage = quotaService.updateResourceUsage(sessionId, {
      cpuUsage,
      memoryUsage,
      diskIOUsage,
      bandwidthUsage,
    });

    res.status(200).json({
      success: true,
      data: usage,
    });
  } catch (error) {
    logger.error("Error updating resource usage", { error });
    res.status(500).json({
      error: "Failed to update resource usage",
      details: error instanceof Error ? error.message : "Unknown error",
    });
  }
});

/**
 * GET /resource-quotas/:sessionId/usage
 * Get current resource usage for a session
 */
router.get("/:sessionId/usage", (req: Request, res: Response) => {
  try {
    const { sessionId } = req.params;
    const usage = quotaService.getResourceUsage(sessionId);

    if (!usage) {
      return res.status(404).json({
        error: "No usage data found for session",
      });
    }

    res.status(200).json({
      success: true,
      data: usage,
    });
  } catch (error) {
    logger.error("Error retrieving resource usage", { error });
    res.status(500).json({
      error: "Failed to retrieve resource usage",
      details: error instanceof Error ? error.message : "Unknown error",
    });
  }
});

/**
 * GET /resource-quotas/:sessionId
 * Get quota enforcement details for a session
 */
router.get("/:sessionId", (req: Request, res: Response) => {
  try {
    const { sessionId } = req.params;
    const enforcement = quotaService.getQuotaEnforcement(sessionId);

    if (!enforcement) {
      return res.status(404).json({
        error: "Quota not found for session",
      });
    }

    res.status(200).json({
      success: true,
      data: enforcement,
    });
  } catch (error) {
    logger.error("Error retrieving quota", { error });
    res.status(500).json({
      error: "Failed to retrieve quota",
      details: error instanceof Error ? error.message : "Unknown error",
    });
  }
});

/**
 * PATCH /resource-quotas/:sessionId/tier
 * Update quota tier for a session
 */
router.patch("/:sessionId/tier", (req: Request, res: Response) => {
  try {
    const { sessionId } = req.params;
    const { tier } = req.body;

    if (!tier) {
      return res.status(400).json({
        error: "Missing required field: tier",
      });
    }

    if (!Object.values(QuotaTier).includes(tier)) {
      return res.status(400).json({
        error: `Invalid tier. Must be one of: ${Object.values(QuotaTier).join(", ")}`,
      });
    }

    const updated = quotaService.updateQuotaTier(sessionId, tier);
    res.status(200).json({
      success: true,
      data: updated,
    });
  } catch (error) {
    logger.error("Error updating quota tier", { error });
    res.status(500).json({
      error: "Failed to update quota tier",
      details: error instanceof Error ? error.message : "Unknown error",
    });
  }
});

/**
 * PATCH /resource-quotas/:sessionId/pause
 * Pause quota enforcement
 */
router.patch("/:sessionId/pause", (req: Request, res: Response) => {
  try {
    const { sessionId } = req.params;
    const paused = quotaService.pauseQuota(sessionId);

    res.status(200).json({
      success: true,
      data: paused,
    });
  } catch (error) {
    logger.error("Error pausing quota", { error });
    res.status(500).json({
      error: "Failed to pause quota",
      details: error instanceof Error ? error.message : "Unknown error",
    });
  }
});

/**
 * PATCH /resource-quotas/:sessionId/resume
 * Resume quota enforcement
 */
router.patch("/:sessionId/resume", (req: Request, res: Response) => {
  try {
    const { sessionId } = req.params;
    const resumed = quotaService.resumeQuota(sessionId);

    res.status(200).json({
      success: true,
      data: resumed,
    });
  } catch (error) {
    logger.error("Error resuming quota", { error });
    res.status(500).json({
      error: "Failed to resume quota",
      details: error instanceof Error ? error.message : "Unknown error",
    });
  }
});

/**
 * DELETE /resource-quotas/:sessionId
 * Remove quota enforcement for a session
 */
router.delete("/:sessionId", (req: Request, res: Response) => {
  try {
    const { sessionId } = req.params;
    const removed = quotaService.removeQuota(sessionId);

    if (!removed) {
      return res.status(404).json({
        error: "Quota not found for session",
      });
    }

    res.status(204).send();
  } catch (error) {
    logger.error("Error removing quota", { error });
    res.status(500).json({
      error: "Failed to remove quota",
      details: error instanceof Error ? error.message : "Unknown error",
    });
  }
});

/**
 * GET /resource-quotas/:sessionId/violations
 * Get violation history for a session
 */
router.get("/:sessionId/violations", (req: Request, res: Response) => {
  try {
    const { sessionId } = req.params;
    const violations = quotaService.getViolationHistory(sessionId);

    res.status(200).json({
      success: true,
      data: violations,
      count: violations.length,
    });
  } catch (error) {
    logger.error("Error retrieving violations", { error });
    res.status(500).json({
      error: "Failed to retrieve violations",
      details: error instanceof Error ? error.message : "Unknown error",
    });
  }
});

/**
 * GET /resource-quotas/:sessionId/utilization
 * Get resource utilization percentage for a session
 */
router.get("/:sessionId/utilization", (req: Request, res: Response) => {
  try {
    const { sessionId } = req.params;
    const utilization = quotaService.calculateUtilization(sessionId);

    res.status(200).json({
      success: true,
      data: utilization,
    });
  } catch (error) {
    logger.error("Error calculating utilization", { error });
    res.status(500).json({
      error: "Failed to calculate utilization",
      details: error instanceof Error ? error.message : "Unknown error",
    });
  }
});

/**
 * GET /resource-quotas/configs/all
 * Get all quota tier configurations
 */
router.get("/configs/all", (req: Request, res: Response) => {
  try {
    const configs = quotaService.getAllQuotaConfigs();
    const configMap: Record<string, any> = {};

    configs.forEach((config, tier) => {
      configMap[tier] = config;
    });

    res.status(200).json({
      success: true,
      data: configMap,
    });
  } catch (error) {
    logger.error("Error retrieving quota configs", { error });
    res.status(500).json({
      error: "Failed to retrieve quota configs",
      details: error instanceof Error ? error.message : "Unknown error",
    });
  }
});

/**
 * GET /resource-quotas/stats/all
 * Get global statistics
 */
router.get("/stats/all", (req: Request, res: Response) => {
  try {
    const stats = quotaService.getStatistics();

    res.status(200).json({
      success: true,
      data: stats,
    });
  } catch (error) {
    logger.error("Error retrieving statistics", { error });
    res.status(500).json({
      error: "Failed to retrieve statistics",
      details: error instanceof Error ? error.message : "Unknown error",
    });
  }
});

/**
 * GET /resource-quotas/list/active
 * List all active quotas
 */
router.get("/list/active", (req: Request, res: Response) => {
  try {
    const quotas = quotaService.getAllActiveQuotas();

    res.status(200).json({
      success: true,
      data: quotas,
      count: quotas.length,
    });
  } catch (error) {
    logger.error("Error listing active quotas", { error });
    res.status(500).json({
      error: "Failed to list active quotas",
      details: error instanceof Error ? error.message : "Unknown error",
    });
  }
});

export const initializeResourceQuotaRoutes = (app: any) => {
  app.use("/api/resource-quotas", router);
  logger.info("Resource quota routes initialized");
};

export default router;
