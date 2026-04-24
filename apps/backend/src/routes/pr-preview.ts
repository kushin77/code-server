// apps/backend/src/routes/pr-preview.ts
// @file: HTTP routes for PR preview environments
// @module: pr-preview-routes
// @description: Auto-provision and manage GitHub PR preview environments

import { Router, Request, Response } from "express"
import { getPRPreviewService } from "../services/pr-preview/index.js"

const router = Router()
const service = getPRPreviewService()

/**
 * POST /api/previews
 * Create a new PR preview environment
 *
 * Body:
 * {
 *   "prNumber": number,
 *   "branch": string,
 *   "headSha": string,
 *   "owner": string,
 *   "repo": string
 * }
 */
router.post("/", (req: Request, res: Response) => {
  try {
    const { prNumber, branch, headSha, owner, repo } = req.body

    if (!prNumber || !branch || !headSha || !owner || !repo) {
      res.status(400).json({ error: "Missing required fields: prNumber, branch, headSha, owner, repo" })
      return
    }

    const result = service.createPreview(prNumber, branch, headSha, owner, repo)

    if (result.success) {
      res.status(201).json({
        previewId: result.previewId,
        urls: result.urls,
        status: "provisioning",
        message: "Preview environment provisioning started",
      })
    } else {
      res.status(500).json({ error: result.error })
    }
  } catch (error) {
    const err = error as Error
    res.status(500).json({ error: err.message })
  }
})

/**
 * GET /api/previews/:previewId
 * Get preview details
 */
router.get("/:previewId", (req: Request, res: Response) => {
  try {
    const { previewId } = req.params

    const preview = service.getPreview(previewId)

    if (!preview) {
      res.status(404).json({ error: "Preview not found" })
      return
    }

    res.json({
      id: preview.id,
      prNumber: preview.prNumber,
      branch: preview.branch,
      status: preview.status,
      createdAt: preview.createdAt,
      urls: preview.urls,
      metrics: preview.metrics,
      gracePeriodEndsAt: preview.gracePeriodEndsAt,
      tags: preview.tags,
    })
  } catch (error) {
    const err = error as Error
    res.status(500).json({ error: err.message })
  }
})

/**
 * GET /api/previews/repo/:owner/:repo
 * List all previews for a repository
 */
router.get("/repo/:owner/:repo", (req: Request, res: Response) => {
  try {
    const { owner, repo } = req.params

    const previews = service.getPreviewsByRepo(owner, repo)
    const active = service.getActivePreviewsByRepo(owner, repo)

    res.json({
      repository: `${owner}/${repo}`,
      total: previews.length,
      active: active.length,
      previews: previews.map((p) => ({
        id: p.id,
        prNumber: p.prNumber,
        status: p.status,
        branch: p.branch,
        urls: p.urls,
        createdAt: p.createdAt,
      })),
    })
  } catch (error) {
    const err = error as Error
    res.status(500).json({ error: err.message })
  }
})

/**
 * GET /api/previews/:previewId/health
 * Perform health check on preview
 */
router.get("/:previewId/health", (req: Request, res: Response) => {
  try {
    const { previewId } = req.params

    const health = service.healthCheck(previewId)

    res.json({
      previewId,
      healthy: health.healthy,
      message: health.message,
      timestamp: new Date(),
    })
  } catch (error) {
    const err = error as Error
    res.status(500).json({ error: err.message })
  }
})

/**
 * POST /api/previews/:previewId/mark-for-destruction
 * Mark preview for destruction (starts grace period)
 *
 * Body:
 * {
 *   "reason": "merged" | "closed"
 * }
 */
router.post("/:previewId/mark-for-destruction", (req: Request, res: Response) => {
  try {
    const { previewId } = req.params
    const { reason = "closed" } = req.body

    const result = service.markForDestruction(previewId, reason)

    if (result.success) {
      res.json({
        previewId,
        gracePeriodEndsAt: result.gracePeriodEndsAt,
        message: `Preview marked for destruction with 1-hour grace period`,
      })
    } else {
      res.status(404).json({ error: "Preview not found" })
    }
  } catch (error) {
    const err = error as Error
    res.status(500).json({ error: err.message })
  }
})

/**
 * DELETE /api/previews/:previewId
 * Immediately destroy preview environment
 */
router.delete("/:previewId", (req: Request, res: Response) => {
  try {
    const { previewId } = req.params

    const result = service.destroyPreview(previewId)

    if (result.success) {
      res.json({
        previewId,
        message: "Preview destruction initiated",
      })
    } else {
      res.status(404).json({ error: result.error })
    }
  } catch (error) {
    const err = error as Error
    res.status(500).json({ error: err.message })
  }
})

/**
 * GET /api/previews
 * List all active previews
 */
router.get("/", (req: Request, res: Response) => {
  try {
    const allPreviews = service.getAllPreviews()

    res.json({
      total: allPreviews.length,
      previews: allPreviews.map((p) => ({
        id: p.id,
        prNumber: p.prNumber,
        repository: `${p.owner}/${p.repo}`,
        status: p.status,
        branch: p.branch,
        createdAt: p.createdAt,
        urls: p.urls,
      })),
    })
  } catch (error) {
    const err = error as Error
    res.status(500).json({ error: err.message })
  }
})

/**
 * GET /api/previews/resource-utilization
 * Get resource utilization across all previews
 */
router.get("/resource-utilization", (req: Request, res: Response) => {
  try {
    const utilization = service.getResourceUtilization()

    res.json({
      totalActivePreviews: utilization.totalActivePreviews,
      totalMemoryMb: utilization.totalMemoryMb,
      totalCpuCores: utilization.totalCpuCores,
      averageMemoryPerPreview: utilization.averageMemoryPerPreview,
      averageCpuPerPreview: utilization.averageCpuPerPreview,
    })
  } catch (error) {
    const err = error as Error
    res.status(500).json({ error: err.message })
  }
})

/**
 * GET /api/previews/repo/:owner/:repo/stats
 * Get repository statistics
 */
router.get("/repo/:owner/:repo/stats", (req: Request, res: Response) => {
  try {
    const { owner, repo } = req.params

    const stats = service.getRepoStatistics(owner, repo)

    res.json(stats)
  } catch (error) {
    const err = error as Error
    res.status(500).json({ error: err.message })
  }
})

/**
 * GET /api/previews/repo/:owner/:repo/billing
 * Get billing information for repository
 */
router.get("/repo/:owner/:repo/billing", (req: Request, res: Response) => {
  try {
    const { owner, repo } = req.params
    const costPerHour = parseFloat(req.query.costPerHour as string) || 2.5

    const billing = service.calculateBilling(owner, repo, costPerHour)

    res.json(billing)
  } catch (error) {
    const err = error as Error
    res.status(500).json({ error: err.message })
  }
})

export default router
