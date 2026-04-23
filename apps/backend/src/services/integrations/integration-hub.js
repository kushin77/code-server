// apps/backend/src/services/integrations/integration-hub.ts
// @file: Integration hub for external services (Issue #1302)
// Supports: GitHub Issues, Linear/Jira, Slack, CI/CD, Figma, Sentry, PagerDuty, Jaeger
import { EventEmitter } from "events";
import { getLogger } from "../../lib/logger.js";
/**
 * Integration hub for connecting to external services
 * Manages multiple integrations and routes events between systems
 */
export class IntegrationHub extends EventEmitter {
    constructor() {
        super();
        this.logger = getLogger("IntegrationHub");
        this.configs = new Map();
        this.statuses = new Map();
        this.eventHandlers = new Map();
        this.integrationCounter = 0;
        this.initializeIntegrations();
    }
    /**
     * Register an integration
     */
    registerIntegration(type, config) {
        try {
            const integrationId = `${type}-${Date.now()}-${++this.integrationCounter}`;
            const fullConfig = {
                type,
                ...config,
            };
            this.configs.set(integrationId, fullConfig);
            // Initialize status
            this.statuses.set(integrationId, {
                type,
                connected: false,
                lastSync: null,
                errorCount: 0,
                syncCount: 0,
            });
            this.logger.info("Registered integration", {
                type,
                integrationId,
                enabled: fullConfig.enabled,
            });
            // Test connection if enabled
            if (fullConfig.enabled) {
                this.testConnection(integrationId);
            }
            return {
                success: true,
                message: `Registered ${type} integration`,
                integrationId,
            };
        }
        catch (error) {
            const err = error;
            this.logger.error("Failed to register integration", { error: err.message, type });
            return {
                success: false,
                message: `Failed to register integration: ${err.message}`,
                integrationId: "",
            };
        }
    }
    /**
     * Send event to integration
     */
    async sendEvent(integrationId, event) {
        try {
            const config = this.configs.get(integrationId);
            if (!config) {
                return {
                    success: false,
                    message: "Integration not found",
                };
            }
            if (!config.enabled) {
                return {
                    success: false,
                    message: "Integration is disabled",
                };
            }
            const fullEvent = {
                ...event,
                timestamp: new Date(),
            };
            // Route to appropriate handler
            const result = await this.routeEvent(config.type, fullEvent, config);
            // Update status
            const status = this.statuses.get(integrationId);
            if (status) {
                status.syncCount++;
                status.lastSync = new Date();
            }
            // Emit event
            this.emit("event-sent", {
                integrationId,
                event: fullEvent,
                result,
            });
            this.logger.info("Event sent to integration", {
                integrationId,
                type: config.type,
                eventType: event.type,
            });
            return {
                success: true,
                message: "Event sent successfully",
                data: result,
            };
        }
        catch (error) {
            const err = error;
            this.logger.error("Failed to send event", { error: err.message, integrationId });
            const status = this.statuses.get(integrationId);
            if (status) {
                status.errorCount++;
                status.lastError = err.message;
            }
            return {
                success: false,
                message: `Failed to send event: ${err.message}`,
            };
        }
    }
    /**
     * Receive webhook from integration
     */
    receiveWebhook(integrationId, payload) {
        try {
            const config = this.configs.get(integrationId);
            if (!config) {
                return {
                    success: false,
                    message: "Integration not found",
                };
            }
            // Parse and emit webhook event
            const event = {
                type: payload.action || payload.event || "webhook",
                source: config.type,
                timestamp: new Date(),
                data: payload,
            };
            this.emit("webhook-received", {
                integrationId,
                event,
            });
            this.logger.info("Webhook received", {
                integrationId,
                type: config.type,
                eventType: event.type,
            });
            return {
                success: true,
                message: "Webhook processed successfully",
            };
        }
        catch (error) {
            const err = error;
            this.logger.error("Failed to process webhook", { error: err.message, integrationId });
            return {
                success: false,
                message: `Failed to process webhook: ${err.message}`,
            };
        }
    }
    /**
     * Get integration status
     */
    getStatus(integrationId) {
        return this.statuses.get(integrationId) || null;
    }
    /**
     * Get all registered integrations
     */
    getIntegrations() {
        const integrations = [];
        for (const [id, config] of this.configs) {
            const status = this.statuses.get(id);
            if (status) {
                integrations.push({
                    id,
                    config,
                    status,
                });
            }
        }
        return integrations;
    }
    /**
     * Test connection to integration
     */
    async testConnection(integrationId) {
        try {
            const config = this.configs.get(integrationId);
            if (!config || !config.enabled) {
                return false;
            }
            // Simulate connection test based on type
            const result = await this.performHealthCheck(config);
            const status = this.statuses.get(integrationId);
            if (status) {
                status.connected = result;
                if (result) {
                    status.lastError = undefined;
                    this.logger.info("Integration connection successful", {
                        integrationId,
                        type: config.type,
                    });
                }
                else {
                    status.lastError = "Health check failed";
                }
            }
            return result;
        }
        catch (error) {
            const err = error;
            this.logger.error("Connection test failed", { error: err.message, integrationId });
            const status = this.statuses.get(integrationId);
            if (status) {
                status.connected = false;
                status.lastError = err.message;
            }
            return false;
        }
    }
    /**
     * Private helpers
     */
    initializeIntegrations() {
        // Load integrations from environment or config
        // For now, just initialize empty
        this.logger.info("Integration hub initialized");
    }
    async performHealthCheck(config) {
        // Simulate health check for different integration types
        switch (config.type) {
            case "github":
                return await this.checkGitHubHealth(config);
            case "linear":
            case "jira":
                return await this.checkIssueTrackerHealth(config);
            case "slack":
                return await this.checkSlackHealth(config);
            case "circleci":
            case "github-actions":
                return await this.checkCICDHealth(config);
            case "figma":
                return await this.checkFigmaHealth(config);
            case "sentry":
                return await this.checkSentryHealth(config);
            case "pagerduty":
                return await this.checkPagerDutyHealth(config);
            case "jaeger":
                return await this.checkJaegerHealth(config);
            default:
                return false;
        }
    }
    async checkGitHubHealth(config) {
        return !!(config.apiKey && config.apiUrl);
    }
    async checkIssueTrackerHealth(config) {
        return !!(config.apiKey && config.apiUrl);
    }
    async checkSlackHealth(config) {
        return !!(config.apiKey && config.webhookUrl);
    }
    async checkCICDHealth(config) {
        return !!(config.apiKey && config.apiUrl);
    }
    async checkFigmaHealth(config) {
        return !!(config.apiKey && config.projectId);
    }
    async checkSentryHealth(config) {
        return !!(config.apiKey && config.apiUrl);
    }
    async checkPagerDutyHealth(config) {
        return !!(config.apiKey && config.apiUrl);
    }
    async checkJaegerHealth(config) {
        return !!(config.apiUrl);
    }
    async routeEvent(type, event, config) {
        switch (type) {
            case "github":
                return await this.routeGitHubEvent(event, config);
            case "linear":
            case "jira":
                return await this.routeIssueTrackerEvent(event, config);
            case "slack":
                return await this.routeSlackEvent(event, config);
            case "circleci":
            case "github-actions":
                return await this.routeCICDEvent(event, config);
            case "figma":
                return await this.routeFigmaEvent(event, config);
            case "sentry":
                return await this.routeSentryEvent(event, config);
            case "pagerduty":
                return await this.routePagerDutyEvent(event, config);
            case "jaeger":
                return await this.routeJaegerEvent(event, config);
            default:
                return {};
        }
    }
    async routeGitHubEvent(event, config) {
        // Route GitHub issue events
        if (event.type === "issue.created") {
            return {
                action: "create_issue",
                repository: config.credentials?.repository,
                title: event.data.title,
                body: event.data.description,
            };
        }
        return {};
    }
    async routeIssueTrackerEvent(event, config) {
        // Route Linear/Jira issue events
        return {
            action: event.type,
            projectId: config.projectId,
            data: event.data,
        };
    }
    async routeSlackEvent(event, config) {
        // Route Slack notifications
        return {
            action: "send_message",
            channel: config.credentials?.channel,
            message: event.data.message || event.type,
        };
    }
    async routeCICDEvent(event, config) {
        // Route CI/CD pipeline events
        return {
            action: event.type,
            projectId: config.projectId,
            data: event.data,
        };
    }
    async routeFigmaEvent(event, config) {
        // Route Figma design events
        return {
            action: event.type,
            fileId: config.projectId,
            data: event.data,
        };
    }
    async routeSentryEvent(event, config) {
        // Route Sentry error events
        return {
            action: "report_error",
            projectId: config.projectId,
            error: event.data.error,
            stackTrace: event.data.stackTrace,
        };
    }
    async routePagerDutyEvent(event, config) {
        // Route PagerDuty incident events
        return {
            action: event.type,
            integrationId: config.credentials?.integrationId,
            data: event.data,
        };
    }
    async routeJaegerEvent(event, config) {
        // Route Jaeger APM trace events
        return {
            action: "record_trace",
            traceId: event.data.traceId,
            spanId: event.data.spanId,
            duration: event.data.duration,
        };
    }
}
// Singleton instance
let instance = null;
export function getIntegrationHub() {
    if (!instance) {
        instance = new IntegrationHub();
    }
    return instance;
}
//# sourceMappingURL=integration-hub.js.map