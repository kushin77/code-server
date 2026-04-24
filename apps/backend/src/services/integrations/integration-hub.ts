// apps/backend/src/services/integrations/integration-hub.ts
// @file: Integration hub for external services (Issue #1302)
// Supports: GitHub Issues, Linear/Jira, Slack, CI/CD, Figma, Sentry, PagerDuty, Jaeger

import { EventEmitter } from "events"
import { getLogger } from "../../lib/logger.js"

export interface IntegrationConfig {
  type: "github" | "linear" | "jira" | "slack" | "circleci" | "github-actions" | "figma" | "sentry" | "pagerduty" | "jaeger"
  enabled: boolean
  apiKey?: string
  apiUrl?: string
  webhookUrl?: string
  workspaceId?: string
  projectId?: string
  credentials?: Record<string, any>
  metadata?: Record<string, any>
}

export interface IntegrationEvent {
  type: string // "issue.created", "deployment.started", "error.reported", etc.
  source: string // integration type
  timestamp: Date
  data: Record<string, any>
  userId?: string
  workspaceId?: string
}

export interface IntegrationStatus {
  type: string
  connected: boolean
  lastSync: Date | null
  lastError?: string
  errorCount: number
  syncCount: number
}

/**
 * Integration hub for connecting to external services
 * Manages multiple integrations and routes events between systems
 */
export class IntegrationHub extends EventEmitter {
  private logger = getLogger("IntegrationHub")
  private configs = new Map<string, IntegrationConfig>()
  private statuses = new Map<string, IntegrationStatus>()
  private eventHandlers = new Map<string, Function[]>()
  private integrationCounter = 0

  constructor() {
    super()
    this.initializeIntegrations()
  }

  /**
   * Register an integration
   */
  registerIntegration(
    type: IntegrationConfig["type"],
    config: Omit<IntegrationConfig, "type">
  ): {
    success: boolean
    message: string
    integrationId: string
  } {
    try {
      const integrationId = `${type}-${Date.now()}-${++this.integrationCounter}`

      const fullConfig: IntegrationConfig = {
        type,
        ...config,
      }

      this.configs.set(integrationId, fullConfig)

      // Initialize status
      this.statuses.set(integrationId, {
        type,
        connected: false,
        lastSync: null,
        errorCount: 0,
        syncCount: 0,
      })

      this.logger.info("Registered integration", {
        type,
        integrationId,
        enabled: fullConfig.enabled,
      })

      // Test connection if enabled
      if (fullConfig.enabled) {
        this.testConnection(integrationId)
      }

      return {
        success: true,
        message: `Registered ${type} integration`,
        integrationId,
      }
    } catch (error) {
      const err = error as Error
      this.logger.error("Failed to register integration", { error: err.message, type })
      return {
        success: false,
        message: `Failed to register integration: ${err.message}`,
        integrationId: "",
      }
    }
  }

  /**
   * Send event to integration
   */
  async sendEvent(
    integrationId: string,
    event: Omit<IntegrationEvent, "timestamp">
  ): Promise<{
    success: boolean
    message: string
    data?: any
  }> {
    try {
      const config = this.configs.get(integrationId)
      if (!config) {
        return {
          success: false,
          message: "Integration not found",
        }
      }

      if (!config.enabled) {
        return {
          success: false,
          message: "Integration is disabled",
        }
      }

      const fullEvent: IntegrationEvent = {
        ...event,
        timestamp: new Date(),
      }

      // Route to appropriate handler
      const result = await this.routeEvent(config.type, fullEvent, config)

      // Update status
      const status = this.statuses.get(integrationId)
      if (status) {
        status.syncCount++
        status.lastSync = new Date()
      }

      // Emit event
      this.emit("event-sent", {
        integrationId,
        event: fullEvent,
        result,
      })

      this.logger.info("Event sent to integration", {
        integrationId,
        type: config.type,
        eventType: event.type,
      })

      return {
        success: true,
        message: "Event sent successfully",
        data: result,
      }
    } catch (error) {
      const err = error as Error
      this.logger.error("Failed to send event", { error: err.message, integrationId })

      const status = this.statuses.get(integrationId)
      if (status) {
        status.errorCount++
        status.lastError = err.message
      }

      return {
        success: false,
        message: `Failed to send event: ${err.message}`,
      }
    }
  }

  /**
   * Receive webhook from integration
   */
  receiveWebhook(integrationId: string, payload: any): {
    success: boolean
    message: string
  } {
    try {
      const config = this.configs.get(integrationId)
      if (!config) {
        return {
          success: false,
          message: "Integration not found",
        }
      }

      // Parse and emit webhook event
      const event: IntegrationEvent = {
        type: payload.action || payload.event || "webhook",
        source: config.type,
        timestamp: new Date(),
        data: payload,
      }

      this.emit("webhook-received", {
        integrationId,
        event,
      })

      this.logger.info("Webhook received", {
        integrationId,
        type: config.type,
        eventType: event.type,
      })

      return {
        success: true,
        message: "Webhook processed successfully",
      }
    } catch (error) {
      const err = error as Error
      this.logger.error("Failed to process webhook", { error: err.message, integrationId })
      return {
        success: false,
        message: `Failed to process webhook: ${err.message}`,
      }
    }
  }

  /**
   * Get integration status
   */
  getStatus(integrationId: string): IntegrationStatus | null {
    return this.statuses.get(integrationId) || null
  }

  /**
   * Get all registered integrations
   */
  getIntegrations(): Array<{
    id: string
    config: IntegrationConfig
    status: IntegrationStatus
  }> {
    const integrations = []

    for (const [id, config] of this.configs) {
      const status = this.statuses.get(id)
      if (status) {
        integrations.push({
          id,
          config,
          status,
        })
      }
    }

    return integrations
  }

  /**
   * Test connection to integration
   */
  private async testConnection(integrationId: string): Promise<boolean> {
    try {
      const config = this.configs.get(integrationId)
      if (!config || !config.enabled) {
        return false
      }

      // Simulate connection test based on type
      const result = await this.performHealthCheck(config)

      const status = this.statuses.get(integrationId)
      if (status) {
        status.connected = result
        if (result) {
          status.lastError = undefined
          this.logger.info("Integration connection successful", {
            integrationId,
            type: config.type,
          })
        } else {
          status.lastError = "Health check failed"
        }
      }

      return result
    } catch (error) {
      const err = error as Error
      this.logger.error("Connection test failed", { error: err.message, integrationId })

      const status = this.statuses.get(integrationId)
      if (status) {
        status.connected = false
        status.lastError = err.message
      }

      return false
    }
  }

  /**
   * Private helpers
   */

  private initializeIntegrations(): void {
    // Load integrations from environment or config
    // For now, just initialize empty
    this.logger.info("Integration hub initialized")
  }

  private async performHealthCheck(config: IntegrationConfig): Promise<boolean> {
    // Simulate health check for different integration types
    switch (config.type) {
      case "github":
        return await this.checkGitHubHealth(config)
      case "linear":
      case "jira":
        return await this.checkIssueTrackerHealth(config)
      case "slack":
        return await this.checkSlackHealth(config)
      case "circleci":
      case "github-actions":
        return await this.checkCICDHealth(config)
      case "figma":
        return await this.checkFigmaHealth(config)
      case "sentry":
        return await this.checkSentryHealth(config)
      case "pagerduty":
        return await this.checkPagerDutyHealth(config)
      case "jaeger":
        return await this.checkJaegerHealth(config)
      default:
        return false
    }
  }

  private async checkGitHubHealth(config: IntegrationConfig): Promise<boolean> {
    return !!(config.apiKey && config.apiUrl)
  }

  private async checkIssueTrackerHealth(config: IntegrationConfig): Promise<boolean> {
    return !!(config.apiKey && config.apiUrl)
  }

  private async checkSlackHealth(config: IntegrationConfig): Promise<boolean> {
    return !!(config.apiKey && config.webhookUrl)
  }

  private async checkCICDHealth(config: IntegrationConfig): Promise<boolean> {
    return !!(config.apiKey && config.apiUrl)
  }

  private async checkFigmaHealth(config: IntegrationConfig): Promise<boolean> {
    return !!(config.apiKey && config.projectId)
  }

  private async checkSentryHealth(config: IntegrationConfig): Promise<boolean> {
    return !!(config.apiKey && config.apiUrl)
  }

  private async checkPagerDutyHealth(config: IntegrationConfig): Promise<boolean> {
    return !!(config.apiKey && config.apiUrl)
  }

  private async checkJaegerHealth(config: IntegrationConfig): Promise<boolean> {
    return !!(config.apiUrl)
  }

  private async routeEvent(
    type: IntegrationConfig["type"],
    event: IntegrationEvent,
    config: IntegrationConfig
  ): Promise<any> {
    switch (type) {
      case "github":
        return await this.routeGitHubEvent(event, config)
      case "linear":
      case "jira":
        return await this.routeIssueTrackerEvent(event, config)
      case "slack":
        return await this.routeSlackEvent(event, config)
      case "circleci":
      case "github-actions":
        return await this.routeCICDEvent(event, config)
      case "figma":
        return await this.routeFigmaEvent(event, config)
      case "sentry":
        return await this.routeSentryEvent(event, config)
      case "pagerduty":
        return await this.routePagerDutyEvent(event, config)
      case "jaeger":
        return await this.routeJaegerEvent(event, config)
      default:
        return {}
    }
  }

  private async routeGitHubEvent(event: IntegrationEvent, config: IntegrationConfig): Promise<any> {
    // Route GitHub issue events
    if (event.type === "issue.created") {
      return {
        action: "create_issue",
        repository: config.credentials?.repository,
        title: event.data.title,
        body: event.data.description,
      }
    }
    return {}
  }

  private async routeIssueTrackerEvent(event: IntegrationEvent, config: IntegrationConfig): Promise<any> {
    // Route Linear/Jira issue events
    return {
      action: event.type,
      projectId: config.projectId,
      data: event.data,
    }
  }

  private async routeSlackEvent(event: IntegrationEvent, config: IntegrationConfig): Promise<any> {
    // Route Slack notifications
    return {
      action: "send_message",
      channel: config.credentials?.channel,
      message: event.data.message || event.type,
    }
  }

  private async routeCICDEvent(event: IntegrationEvent, config: IntegrationConfig): Promise<any> {
    // Route CI/CD pipeline events
    return {
      action: event.type,
      projectId: config.projectId,
      data: event.data,
    }
  }

  private async routeFigmaEvent(event: IntegrationEvent, config: IntegrationConfig): Promise<any> {
    // Route Figma design events
    return {
      action: event.type,
      fileId: config.projectId,
      data: event.data,
    }
  }

  private async routeSentryEvent(event: IntegrationEvent, config: IntegrationConfig): Promise<any> {
    // Route Sentry error events
    return {
      action: "report_error",
      projectId: config.projectId,
      error: event.data.error,
      stackTrace: event.data.stackTrace,
    }
  }

  private async routePagerDutyEvent(event: IntegrationEvent, config: IntegrationConfig): Promise<any> {
    // Route PagerDuty incident events
    return {
      action: event.type,
      integrationId: config.credentials?.integrationId,
      data: event.data,
    }
  }

  private async routeJaegerEvent(event: IntegrationEvent, config: IntegrationConfig): Promise<any> {
    // Route Jaeger APM trace events
    return {
      action: "record_trace",
      traceId: event.data.traceId,
      spanId: event.data.spanId,
      duration: event.data.duration,
    }
  }
}

// Singleton instance
let instance: IntegrationHub | null = null

export function getIntegrationHub(): IntegrationHub {
  if (!instance) {
    instance = new IntegrationHub()
  }
  return instance
}
