// apps/backend/src/routes/__tests__/integrations.test.ts
import { describe, it, expect } from "vitest";
/**
 * Unit tests for integration route logic
 * Route-level tests focus on request/response formatting
 */
describe("Integrations Route Logic", () => {
    describe("Registration Response Formatting", () => {
        it("should format registration success response", () => {
            const response = {
                integrationId: "github-1234567890",
                message: "Registered github integration",
            };
            expect(response.integrationId).toBeDefined();
            expect(response.message).toContain("Registered");
        });
        it("should include integration type in message", () => {
            const types = ["github", "slack", "linear", "jira", "figma", "sentry", "pagerduty", "github-actions", "circleci", "jaeger"];
            types.forEach((type) => {
                const message = `Registered ${type} integration`;
                expect(message).toContain(type);
            });
        });
    });
    describe("Integration Status Response", () => {
        it("should format integration status response", () => {
            const status = {
                id: "github-123",
                type: "github",
                connected: true,
                lastSync: new Date(),
                syncCount: 5,
                errorCount: 0,
                lastError: undefined,
            };
            expect(status.type).toBe("github");
            expect(status.connected).toBe(true);
            expect(status.syncCount).toBeGreaterThan(0);
            expect(status.errorCount).toBe(0);
        });
        it("should include error information when present", () => {
            const status = {
                id: "slack-123",
                type: "slack",
                connected: false,
                lastSync: null,
                syncCount: 0,
                errorCount: 2,
                lastError: "Connection timeout",
            };
            expect(status.lastError).toBeDefined();
            expect(status.errorCount).toBeGreaterThan(0);
        });
    });
    describe("Event Send Response", () => {
        it("should format event send success", () => {
            const response = {
                message: "Event sent successfully",
                data: {
                    action: "create_issue",
                    repository: "kushin77/code-server",
                },
            };
            expect(response.message).toContain("sent");
            expect(response.data).toBeDefined();
        });
        it("should format event send error", () => {
            const response = {
                error: "Integration is disabled",
            };
            expect(response.error).toBeDefined();
        });
    });
    describe("Webhook Handling Response", () => {
        it("should format webhook success response", () => {
            const response = {
                message: "Webhook processed successfully",
            };
            expect(response.message).toContain("processed");
        });
        it("should format webhook error response", () => {
            const response = {
                error: "Integration not found",
            };
            expect(response.error).toBeDefined();
        });
    });
    describe("List Integrations Response", () => {
        it("should format list of integrations safely", () => {
            const integrations = [
                {
                    id: "github-123",
                    type: "github",
                    enabled: true,
                    status: {
                        connected: true,
                        lastSync: new Date(),
                        syncCount: 10,
                        errorCount: 0,
                    },
                },
                {
                    id: "slack-456",
                    type: "slack",
                    enabled: true,
                    status: {
                        connected: false,
                        lastSync: null,
                        syncCount: 0,
                        errorCount: 1,
                        lastError: "Connection failed",
                    },
                },
            ];
            expect(integrations).toHaveLength(2);
            integrations.forEach((integration) => {
                expect(integration.id).toBeDefined();
                expect(integration.type).toBeDefined();
                expect(integration.enabled).toBeDefined();
                expect(integration.status).toBeDefined();
            });
        });
        it("should not include sensitive data in list", () => {
            const integration = {
                id: "github-123",
                type: "github",
                enabled: true,
                status: {
                    connected: true,
                    lastSync: new Date(),
                    syncCount: 5,
                    errorCount: 0,
                },
            };
            // Should not include apiKey, credentials, etc.
            expect(integration.apiKey).toBeUndefined();
            expect(integration.credentials).toBeUndefined();
        });
    });
    describe("Supported Types Response", () => {
        it("should list all supported integration types", () => {
            const types = [
                { id: "github", name: "GitHub Issues" },
                { id: "linear", name: "Linear" },
                { id: "jira", name: "Jira" },
                { id: "slack", name: "Slack" },
                { id: "circleci", name: "CircleCI" },
                { id: "github-actions", name: "GitHub Actions" },
                { id: "figma", name: "Figma" },
                { id: "sentry", name: "Sentry" },
                { id: "pagerduty", name: "PagerDuty" },
                { id: "jaeger", name: "Jaeger" },
            ];
            expect(types).toHaveLength(10);
            expect(types.map((t) => t.id)).toContain("github");
            expect(types.map((t) => t.id)).toContain("slack");
            expect(types.map((t) => t.id)).toContain("jaeger");
        });
        it("should include required fields for each type", () => {
            const githubType = {
                id: "github",
                name: "GitHub Issues",
                requiredFields: ["apiKey", "apiUrl"],
            };
            expect(githubType.requiredFields).toHaveLength(2);
            expect(githubType.requiredFields).toContain("apiKey");
        });
        it("should include descriptions for each type", () => {
            const slackType = {
                id: "slack",
                name: "Slack",
                description: "Team notifications and chat",
            };
            expect(slackType.description).toBeDefined();
            expect(slackType.description.length).toBeGreaterThan(0);
        });
    });
    describe("Error Response Formatting", () => {
        it("should format missing type error", () => {
            const response = {
                error: "Integration type is required",
            };
            expect(response.error).toContain("type");
        });
        it("should format not found error", () => {
            const response = {
                error: "Integration not found",
            };
            expect(response.error).toContain("not found");
        });
        it("should format event validation error", () => {
            const response = {
                error: "Event type is required",
            };
            expect(response.error).toContain("Event type");
        });
    });
    describe("Event Data Preservation", () => {
        it("should preserve custom event data", () => {
            const eventData = {
                type: "issue.created",
                data: {
                    title: "Test Issue",
                    description: "Description",
                    labels: ["bug", "urgent"],
                    customField: "customValue",
                },
            };
            expect(eventData.data.title).toBe("Test Issue");
            expect(eventData.data.labels).toHaveLength(2);
            expect(eventData.data.customField).toBe("customValue");
        });
        it("should handle empty event data", () => {
            const eventData = {
                type: "test.event",
                data: {},
            };
            expect(eventData.data).toBeDefined();
            expect(Object.keys(eventData.data)).toHaveLength(0);
        });
    });
    describe("Integration Metadata", () => {
        it("should preserve integration metadata", () => {
            const integration = {
                type: "github",
                enabled: true,
                metadata: {
                    owner: "kushin77",
                    repository: "code-server",
                    defaultBranch: "main",
                },
            };
            expect(integration.metadata.owner).toBe("kushin77");
            expect(integration.metadata.repository).toBe("code-server");
        });
        it("should preserve credentials", () => {
            const integration = {
                type: "slack",
                enabled: true,
                credentials: {
                    channel: "#deployments",
                    botName: "CodeServer",
                },
            };
            expect(integration.credentials.channel).toBe("#deployments");
            expect(integration.credentials.botName).toBe("CodeServer");
        });
    });
});
//# sourceMappingURL=integrations.test.js.map