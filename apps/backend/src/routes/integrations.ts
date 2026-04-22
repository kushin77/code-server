// apps/backend/src/routes/integrations.ts
// @file: HTTP routes for integration hub (Issue #1302)
// Endpoints: POST /api/integrations/register, GET /api/integrations, POST /api/integrations/event, etc.

import { Router, Request, Response } from "express"
import { getIntegrationHub, type IntegrationConfig } from "../services/integrations/integration-hub.js"

const router = Router()
const hub = getIntegrationHub()

/**
 * POST /api/integrations/register
 * Register a new integration
 *
 * Body:
 * {
 *   "type": "github" | "slack" | "linear" | "jira" | "figma" | "sentry" | "pagerduty" | "github-actions" | "circleci" | "jaeger",
 *   "enabled": boolean,
 *   "apiKey": string (optional),
 *   "apiUrl": string (optional),
 *   "webhookUrl": string (optional),
 *   "projectId": string (optional),
 *   "credentials": object (optional)
 * }
 */
router.post("/register", (req: Request, res: Response) => {
  try {
    const { type, enabled, apiKey, apiUrl, webhookUrl, projectId, credentials, metadata } = req.body

    if (!type) {
      res.status(400).json({ error: "Integration type is required" })
      return
    }

    const result = hub.registerIntegration(type, {
      enabled: enabled !== false, // Default to enabled
      apiKey,
      apiUrl,
      webhookUrl,
      projectId,
      credentials,
      metadata,
    })

    if (result.success) {
      res.json({
        integrationId: result.integrationId,
        message: result.message,
      })
    } else {
      res.status(500).json({
        error: result.message,
      })
    }
  } catch (error) {
    const err = error as Error
    res.status(500).json({ error: err.message })
  }
})

/**
 * GET /api/integrations
 * Get all registered integrations
 */
router.get("/", (req: Request, res: Response) => {
  try {
    const integrations = hub.getIntegrations()

    // Map to response format without sensitive data
    const safeIntegrations = integrations.map((i) => ({
      id: i.id,
      type: i.config.type,
      enabled: i.config.enabled,
      status: {
        connected: i.status.connected,
        lastSync: i.status.lastSync,
        syncCount: i.status.syncCount,
        errorCount: i.status.errorCount,
        lastError: i.status.lastError,
      },
    }))

    res.json(safeIntegrations)
  } catch (error) {
    const err = error as Error
    res.status(500).json({ error: err.message })
  }
})

/**
 * GET /api/integrations/:integrationId
 * Get status of a specific integration
 */
router.get("/:integrationId", (req: Request, res: Response) => {
  try {
    const { integrationId } = req.params

    const status = hub.getStatus(integrationId)

    if (!status) {
      res.status(404).json({ error: "Integration not found" })
      return
    }

    res.json({
      id: integrationId,
      type: status.type,
      connected: status.connected,
      lastSync: status.lastSync,
      syncCount: status.syncCount,
      errorCount: status.errorCount,
      lastError: status.lastError,
    })
  } catch (error) {
    const err = error as Error
    res.status(500).json({ error: err.message })
  }
})

/**
 * POST /api/integrations/:integrationId/event
 * Send an event to an integration
 *
 * Body:
 * {
 *   "type": "issue.created" | "deployment.started" | etc,
 *   "data": { ... event payload ... }
 * }
 */
router.post("/:integrationId/event", async (req: Request, res: Response) => {
  try {
    const { integrationId } = req.params
    const { type, data } = req.body

    if (!type) {
      res.status(400).json({ error: "Event type is required" })
      return
    }

    const result = await hub.sendEvent(integrationId, {
      type,
      source: "api",
      data: data || {},
      userId: (req.user as any)?.id,
    })

    if (result.success) {
      res.json({
        message: result.message,
        data: result.data,
      })
    } else {
      res.status(500).json({
        error: result.message,
      })
    }
  } catch (error) {
    const err = error as Error
    res.status(500).json({ error: err.message })
  }
})

/**
 * POST /api/integrations/:integrationId/webhook
 * Receive webhook from integration
 *
 * Body: Integration-specific webhook payload
 */
router.post("/:integrationId/webhook", (req: Request, res: Response) => {
  try {
    const { integrationId } = req.params

    const result = hub.receiveWebhook(integrationId, req.body)

    if (result.success) {
      res.json({
        message: result.message,
      })
    } else {
      res.status(400).json({
        error: result.message,
      })
    }
  } catch (error) {
    const err = error as Error
    res.status(500).json({ error: err.message })
  }
})

/**
 * GET /api/integrations/types/supported
 * Get list of supported integration types
 */
router.get("/types/supported", (req: Request, res: Response) => {
  try {
    const types = [
      {
        id: "github",
        name: "GitHub Issues",
        description: "Track issues, pull requests, and projects",
        requiredFields: ["apiKey", "apiUrl"],
      },
      {
        id: "linear",
        name: "Linear",
        description: "Issue tracking and sprint planning",
        requiredFields: ["apiKey", "apiUrl", "workspaceId"],
      },
      {
        id: "jira",
        name: "Jira",
        description: "Enterprise issue tracking",
        requiredFields: ["apiKey", "apiUrl", "projectId"],
      },
      {
        id: "slack",
        name: "Slack",
        description: "Team notifications and chat",
        requiredFields: ["apiKey", "webhookUrl"],
      },
      {
        id: "circleci",
        name: "CircleCI",
        description: "CI/CD pipelines and workflows",
        requiredFields: ["apiKey", "apiUrl"],
      },
      {
        id: "github-actions",
        name: "GitHub Actions",
        description: "GitHub CI/CD workflows",
        requiredFields: ["apiKey", "apiUrl"],
      },
      {
        id: "figma",
        name: "Figma",
        description: "Design system and prototypes",
        requiredFields: ["apiKey", "projectId"],
      },
      {
        id: "sentry",
        name: "Sentry",
        description: "Error tracking and performance monitoring",
        requiredFields: ["apiKey", "apiUrl", "projectId"],
      },
      {
        id: "pagerduty",
        name: "PagerDuty",
        description: "Incident response and alerting",
        requiredFields: ["apiKey", "apiUrl"],
      },
      {
        id: "jaeger",
        name: "Jaeger",
        description: "Distributed tracing and APM",
        requiredFields: ["apiUrl"],
      },
    ]

    res.json(types)
  } catch (error) {
    const err = error as Error
    res.status(500).json({ error: err.message })
  }
})

export default router
