// apps/backend/src/services/integrations/__tests__/integration-hub.test.ts
import { describe, it, expect, beforeEach } from "vitest";
import { IntegrationHub } from "../integration-hub";
describe("IntegrationHub", () => {
    let hub;
    beforeEach(() => {
        hub = new IntegrationHub();
    });
    describe("registerIntegration", () => {
        it("should register a GitHub integration", () => {
            const result = hub.registerIntegration("github", {
                enabled: true,
                apiKey: "test-key",
                apiUrl: "https://api.github.com",
            });
            expect(result.success).toBe(true);
            expect(result.integrationId).toBeDefined();
            expect(result.message).toContain("github");
        });
        it("should register a Slack integration", () => {
            const result = hub.registerIntegration("slack", {
                enabled: true,
                apiKey: "xoxb-token",
                webhookUrl: "https://hooks.slack.com/services/...",
            });
            expect(result.success).toBe(true);
            expect(result.integrationId).toBeDefined();
        });
        it("should register a Linear integration", () => {
            const result = hub.registerIntegration("linear", {
                enabled: true,
                apiKey: "lin_api_key",
                apiUrl: "https://api.linear.app",
                workspaceId: "team-123",
            });
            expect(result.success).toBe(true);
            expect(result.message).toContain("linear");
        });
        it("should register a Jira integration", () => {
            const result = hub.registerIntegration("jira", {
                enabled: true,
                apiKey: "jira-token",
                apiUrl: "https://jira.company.com",
                projectId: "PROJ",
            });
            expect(result.success).toBe(true);
        });
        it("should register a GitHub Actions CI/CD integration", () => {
            const result = hub.registerIntegration("github-actions", {
                enabled: true,
                apiKey: "gh-token",
                apiUrl: "https://api.github.com",
            });
            expect(result.success).toBe(true);
        });
        it("should register a CircleCI integration", () => {
            const result = hub.registerIntegration("circleci", {
                enabled: true,
                apiKey: "circle-token",
                apiUrl: "https://circleci.com/api",
            });
            expect(result.success).toBe(true);
        });
        it("should register a Figma integration", () => {
            const result = hub.registerIntegration("figma", {
                enabled: true,
                apiKey: "figma-token",
                projectId: "file-id-123",
            });
            expect(result.success).toBe(true);
        });
        it("should register a Sentry integration", () => {
            const result = hub.registerIntegration("sentry", {
                enabled: true,
                apiKey: "sentry-dsn",
                apiUrl: "https://sentry.io",
                projectId: "proj-123",
            });
            expect(result.success).toBe(true);
        });
        it("should register a PagerDuty integration", () => {
            const result = hub.registerIntegration("pagerduty", {
                enabled: true,
                apiKey: "pd-token",
                apiUrl: "https://api.pagerduty.com",
            });
            expect(result.success).toBe(true);
        });
        it("should register a Jaeger APM integration", () => {
            const result = hub.registerIntegration("jaeger", {
                enabled: true,
                apiUrl: "http://localhost:16686",
            });
            expect(result.success).toBe(true);
        });
        it("should return unique integration IDs", () => {
            const result1 = hub.registerIntegration("github", {
                enabled: true,
                apiKey: "key1",
            });
            const result2 = hub.registerIntegration("github", {
                enabled: true,
                apiKey: "key2",
            });
            expect(result1.integrationId).not.toBe(result2.integrationId);
        });
        it("should track disabled integrations", () => {
            const result = hub.registerIntegration("slack", {
                enabled: false,
                apiKey: "token",
            });
            expect(result.success).toBe(true);
            const status = hub.getStatus(result.integrationId);
            expect(status?.connected).toBe(false);
        });
    });
    describe("sendEvent", () => {
        it("should send issue creation event to GitHub", async () => {
            const result = hub.registerIntegration("github", {
                enabled: true,
                apiKey: "test-key",
                apiUrl: "https://api.github.com",
            });
            const response = await hub.sendEvent(result.integrationId, {
                type: "issue.created",
                source: "github",
                data: {
                    title: "Test Issue",
                    description: "Test Description",
                },
            });
            expect(response.success).toBeDefined();
        });
        it("should send deployment event to CI/CD", async () => {
            const result = hub.registerIntegration("github-actions", {
                enabled: true,
                apiKey: "gh-token",
                apiUrl: "https://api.github.com",
            });
            const response = await hub.sendEvent(result.integrationId, {
                type: "deployment.started",
                source: "github-actions",
                data: {
                    ref: "main",
                    sha: "abc123",
                },
            });
            expect(response.success).toBeDefined();
        });
        it("should send message to Slack", async () => {
            const result = hub.registerIntegration("slack", {
                enabled: true,
                apiKey: "token",
                webhookUrl: "https://hooks.slack.com",
                credentials: { channel: "#deployments" },
            });
            const response = await hub.sendEvent(result.integrationId, {
                type: "deployment.completed",
                source: "slack",
                data: {
                    message: "Deployment successful",
                },
            });
            expect(response.success).toBeDefined();
        });
        it("should send error to Sentry", async () => {
            const result = hub.registerIntegration("sentry", {
                enabled: true,
                apiKey: "dsn",
                apiUrl: "https://sentry.io",
                projectId: "proj",
            });
            const response = await hub.sendEvent(result.integrationId, {
                type: "error.reported",
                source: "sentry",
                data: {
                    error: "Uncaught exception",
                    stackTrace: "at function (file.ts:10)",
                },
            });
            expect(response.success).toBeDefined();
        });
        it("should send trace to Jaeger", async () => {
            const result = hub.registerIntegration("jaeger", {
                enabled: true,
                apiUrl: "http://localhost:16686",
            });
            const response = await hub.sendEvent(result.integrationId, {
                type: "trace.recorded",
                source: "jaeger",
                data: {
                    traceId: "trace-123",
                    spanId: "span-456",
                    duration: 150,
                },
            });
            expect(response.success).toBeDefined();
        });
        it("should reject events to disabled integrations", async () => {
            const result = hub.registerIntegration("slack", {
                enabled: false,
                apiKey: "token",
            });
            const response = await hub.sendEvent(result.integrationId, {
                type: "test.event",
                source: "slack",
                data: {},
            });
            expect(response.success).toBe(false);
            expect(response.message).toContain("disabled");
        });
        it("should fail for non-existent integration", async () => {
            const response = await hub.sendEvent("non-existent-id", {
                type: "test.event",
                source: "github",
                data: {},
            });
            expect(response.success).toBe(false);
            expect(response.message).toContain("not found");
        });
    });
    describe("receiveWebhook", () => {
        it("should receive GitHub webhook", () => {
            const result = hub.registerIntegration("github", {
                enabled: true,
                apiKey: "key",
            });
            const response = hub.receiveWebhook(result.integrationId, {
                action: "opened",
                issue: { number: 123, title: "Test" },
            });
            expect(response.success).toBe(true);
        });
        it("should receive Slack webhook", () => {
            const result = hub.registerIntegration("slack", {
                enabled: true,
                apiKey: "key",
            });
            const response = hub.receiveWebhook(result.integrationId, {
                event: "app_mention",
                user: "U123",
                text: "@bot help",
            });
            expect(response.success).toBe(true);
        });
        it("should fail for non-existent integration", () => {
            const response = hub.receiveWebhook("invalid-id", {
                action: "test",
            });
            expect(response.success).toBe(false);
            expect(response.message).toContain("not found");
        });
    });
    describe("getStatus", () => {
        it("should return integration status", () => {
            const result = hub.registerIntegration("github", {
                enabled: true,
                apiKey: "key",
            });
            const status = hub.getStatus(result.integrationId);
            expect(status).toBeDefined();
            expect(status?.type).toBe("github");
            expect(status?.syncCount).toBe(0);
            expect(status?.errorCount).toBe(0);
        });
        it("should return null for non-existent integration", () => {
            const status = hub.getStatus("non-existent");
            expect(status).toBeNull();
        });
        it("should track sync count", async () => {
            const result = hub.registerIntegration("slack", {
                enabled: true,
                apiKey: "key",
                webhookUrl: "https://hooks.slack.com",
            });
            const statusBefore = hub.getStatus(result.integrationId);
            expect(statusBefore?.syncCount).toBe(0);
            await hub.sendEvent(result.integrationId, {
                type: "test",
                source: "slack",
                data: {},
            });
            const statusAfter = hub.getStatus(result.integrationId);
            expect(statusAfter?.syncCount).toBeGreaterThan(0);
        });
        it("should track error count", async () => {
            const result = hub.registerIntegration("invalid-integration", {
                enabled: false,
            });
            const statusBefore = hub.getStatus(result.integrationId);
            expect(statusBefore?.errorCount).toBe(0);
        });
    });
    describe("getIntegrations", () => {
        it("should return empty list initially", () => {
            const integrations = hub.getIntegrations();
            expect(integrations).toEqual([]);
        });
        it("should return all registered integrations", () => {
            hub.registerIntegration("github", { enabled: true, apiKey: "key1" });
            hub.registerIntegration("slack", { enabled: true, apiKey: "key2" });
            hub.registerIntegration("jira", { enabled: false, apiKey: "key3" });
            const integrations = hub.getIntegrations();
            expect(integrations).toHaveLength(3);
            expect(integrations.map((i) => i.config.type)).toContain("github");
            expect(integrations.map((i) => i.config.type)).toContain("slack");
            expect(integrations.map((i) => i.config.type)).toContain("jira");
        });
        it("should include config and status for each integration", () => {
            const result = hub.registerIntegration("github", {
                enabled: true,
                apiKey: "key",
            });
            const integrations = hub.getIntegrations();
            expect(integrations[0].id).toBe(result.integrationId);
            expect(integrations[0].config).toBeDefined();
            expect(integrations[0].status).toBeDefined();
        });
    });
    describe("Event Routing", () => {
        it("should route GitHub issue events", async () => {
            const result = hub.registerIntegration("github", {
                enabled: true,
                apiKey: "key",
                apiUrl: "https://api.github.com",
                credentials: { repository: "kushin77/code-server" },
            });
            const response = await hub.sendEvent(result.integrationId, {
                type: "issue.created",
                source: "github",
                data: {
                    title: "Feature Request",
                    description: "Add new feature",
                },
            });
            expect(response.success).toBe(true);
            expect(response.data?.action).toBe("create_issue");
        });
        it("should route Slack messages", async () => {
            const result = hub.registerIntegration("slack", {
                enabled: true,
                apiKey: "key",
                webhookUrl: "https://hooks.slack.com",
                credentials: { channel: "#alerts" },
            });
            const response = await hub.sendEvent(result.integrationId, {
                type: "alert.triggered",
                source: "slack",
                data: {
                    message: "CPU usage high",
                },
            });
            expect(response.success).toBe(true);
            expect(response.data?.action).toBe("send_message");
        });
        it("should route CI/CD events", async () => {
            const result = hub.registerIntegration("github-actions", {
                enabled: true,
                apiKey: "key",
                projectId: "workflow-id",
            });
            const response = await hub.sendEvent(result.integrationId, {
                type: "build.completed",
                source: "github-actions",
                data: {
                    status: "success",
                    duration: 300,
                },
            });
            expect(response.success).toBe(true);
            expect(response.data?.action).toBe("build.completed");
        });
    });
    describe("Integration Types", () => {
        it("should support all 10 integration types", () => {
            const types = ["github", "linear", "jira", "slack", "circleci", "github-actions", "figma", "sentry", "pagerduty", "jaeger"];
            types.forEach((type) => {
                const result = hub.registerIntegration(type, {
                    enabled: true,
                    apiKey: "test-key",
                    apiUrl: "https://api.example.com",
                });
                expect(result.success).toBe(true);
                expect(result.message).toContain(type);
            });
        });
    });
});
//# sourceMappingURL=integration-hub.test.js.map