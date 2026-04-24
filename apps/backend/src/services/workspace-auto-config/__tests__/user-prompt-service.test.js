// apps/backend/src/services/workspace-auto-config/__tests__/user-prompt-service.test.ts
import { describe, it, expect, beforeEach } from "vitest";
import { UserPromptService } from "../user-prompt-service";
import { ProjectType } from "../detection-engine";
describe("UserPromptService", () => {
    let promptService;
    beforeEach(() => {
        promptService = new UserPromptService({
            workspaceRoot: "/test/workspace",
            detectedType: ProjectType.NODE_TYPESCRIPT,
            confidence: 95,
            profile: {
                type: ProjectType.NODE_TYPESCRIPT,
                extensions: [
                    "ms-vscode.vscode-typescript-next",
                    "esbenp.prettier-vscode",
                    "ms-eslint.vscode-eslint",
                ],
                settings: {
                    "[typescript]": {
                        "editor.defaultFormatter": "esbenp.prettier-vscode",
                    },
                },
                tasks: [
                    { label: "npm: build", command: "npm", args: ["run", "build"] },
                    { label: "npm: test", command: "npm", args: ["test"] },
                ],
                debugConfigurations: [
                    {
                        name: "Launch Program",
                        type: "node",
                        request: "launch",
                        program: "${workspaceFolder}/dist/index.js",
                    },
                ],
            },
        });
    });
    describe("generateWalkthroughMetadata", () => {
        it("should generate walkthrough metadata with correct structure", () => {
            const metadata = promptService.generateWalkthroughMetadata();
            expect(metadata.id).toContain("workspace-config");
            expect(metadata.title).toContain("Node.js + TypeScript");
            expect(metadata.description).toContain("high confidence");
            expect(Array.isArray(metadata.steps)).toBe(true);
        });
        it("should include all 7 walkthrough steps", () => {
            const metadata = promptService.generateWalkthroughMetadata();
            expect(metadata.steps.length).toBe(7);
            expect(metadata.steps[0].id).toBe("welcome");
            expect(metadata.steps[6].id).toBe("complete");
        });
        it("should generate correct confidence label for high confidence", () => {
            const metadata = promptService.generateWalkthroughMetadata();
            expect(metadata.description).toContain("high");
        });
        it("should generate correct confidence label for medium confidence", () => {
            const service = new UserPromptService({
                workspaceRoot: "/test",
                detectedType: ProjectType.PYTHON,
                confidence: 75,
                profile: {
                    type: ProjectType.PYTHON,
                    extensions: ["ms-python.python"],
                    settings: {},
                    tasks: [],
                    debugConfigurations: [],
                },
            });
            const metadata = service.generateWalkthroughMetadata();
            expect(metadata.description).toContain("medium");
        });
        it("should generate correct confidence label for fair confidence", () => {
            const service = new UserPromptService({
                workspaceRoot: "/test",
                detectedType: ProjectType.GO,
                confidence: 60,
                profile: {
                    type: ProjectType.GO,
                    extensions: ["golang.go"],
                    settings: {},
                    tasks: [],
                    debugConfigurations: [],
                },
            });
            const metadata = service.generateWalkthroughMetadata();
            expect(metadata.description).toContain("fair");
        });
    });
    describe("generateApprovalPrompt", () => {
        it("should generate approval prompt with correct structure", () => {
            const prompt = promptService.generateApprovalPrompt();
            expect(prompt.title).toContain("Node.js + TypeScript");
            expect(prompt.message).toContain("3 recommended extensions");
            expect(prompt.message).toContain("2 build/test tasks");
            expect(Array.isArray(prompt.buttons)).toBe(true);
        });
        it("should include 3 action buttons", () => {
            const prompt = promptService.generateApprovalPrompt();
            expect(prompt.buttons.length).toBe(3);
            expect(prompt.buttons[0].action).toBe("approve");
            expect(prompt.buttons[1].action).toBe("decline");
            expect(prompt.buttons[2].action).toBe("customize");
        });
        it("should include extension count in message", () => {
            const prompt = promptService.generateApprovalPrompt();
            expect(prompt.message).toContain("3 recommended extensions");
        });
        it("should include task count in message", () => {
            const prompt = promptService.generateApprovalPrompt();
            expect(prompt.message).toContain("2 build/test tasks");
        });
        it("should include debug config count in message", () => {
            const prompt = promptService.generateApprovalPrompt();
            expect(prompt.message).toContain("1 debug configuration");
        });
    });
    describe("generateCustomizationOptions", () => {
        it("should generate customization options with correct structure", () => {
            const options = promptService.generateCustomizationOptions();
            expect(options.title).toBe("Customize Configuration");
            expect(Array.isArray(options.options)).toBe(true);
        });
        it("should include 4 customization options", () => {
            const options = promptService.generateCustomizationOptions();
            expect(options.options.length).toBe(4);
        });
        it("should include extension installation option", () => {
            const options = promptService.generateCustomizationOptions();
            const extOption = options.options.find((o) => o.id === "install-extensions");
            expect(extOption).toBeDefined();
            expect(extOption?.label).toContain("3 Extensions");
            expect(extOption?.defaultChecked).toBe(true);
        });
        it("should include settings option", () => {
            const options = promptService.generateCustomizationOptions();
            const settingsOption = options.options.find((o) => o.id === "apply-settings");
            expect(settingsOption).toBeDefined();
            expect(settingsOption?.defaultChecked).toBe(true);
        });
        it("should include task option", () => {
            const options = promptService.generateCustomizationOptions();
            const taskOption = options.options.find((o) => o.id === "add-tasks");
            expect(taskOption).toBeDefined();
            expect(taskOption?.label).toContain("2 Build/Test Tasks");
            expect(taskOption?.defaultChecked).toBe(true);
        });
        it("should include debug option", () => {
            const options = promptService.generateCustomizationOptions();
            const debugOption = options.options.find((o) => o.id === "setup-debug");
            expect(debugOption).toBeDefined();
            expect(debugOption?.defaultChecked).toBe(true);
        });
    });
    describe("processUserResponse", () => {
        it("should return approved:false for decline action", () => {
            const result = promptService.processUserResponse("decline");
            expect(result.approved).toBe(false);
            expect(result.projectType).toBe(ProjectType.NODE_TYPESCRIPT);
        });
        it("should return approved:true for approve action", () => {
            const result = promptService.processUserResponse("approve");
            expect(result.approved).toBe(true);
            expect(result.projectType).toBe(ProjectType.NODE_TYPESCRIPT);
            expect(result.customizationApplied).toBeUndefined();
        });
        it("should return customizations for customize action", () => {
            const result = promptService.processUserResponse("customize", {
                "apply-settings": false,
                "add-tasks": true,
                "setup-debug": true,
            });
            expect(result.approved).toBe(true);
            expect(result.customizationApplied).toBeDefined();
            expect(result.customizationApplied?.skipSettings).toBe(true);
            expect(result.customizationApplied?.skipTasks).toBe(false);
        });
        it("should skip debug configs if deselected", () => {
            const result = promptService.processUserResponse("customize", {
                "apply-settings": true,
                "add-tasks": true,
                "setup-debug": false,
            });
            expect(result.customizationApplied?.skipDebugConfigs).toBe(true);
        });
    });
    describe("Project type label generation", () => {
        it("should generate correct label for Node.js TypeScript", () => {
            const prompt = promptService.generateApprovalPrompt();
            expect(prompt.title).toContain("Node.js + TypeScript");
        });
        it("should handle all project types", () => {
            const types = [
                ProjectType.NODE_TYPESCRIPT,
                ProjectType.NODE_JAVASCRIPT,
                ProjectType.PYTHON,
                ProjectType.PYTHON_DJANGO,
                ProjectType.GO,
                ProjectType.RUST,
                ProjectType.JAVA,
                ProjectType.JAVA_SPRING,
                ProjectType.CPP,
                ProjectType.CSHARP,
                ProjectType.PHP,
                ProjectType.RUBY,
            ];
            for (const type of types) {
                const service = new UserPromptService({
                    workspaceRoot: "/test",
                    detectedType: type,
                    confidence: 80,
                    profile: {
                        type,
                        extensions: [],
                        settings: {},
                        tasks: [],
                        debugConfigurations: [],
                    },
                });
                const prompt = service.generateApprovalPrompt();
                expect(prompt.title).not.toContain("Unknown");
            }
        });
    });
});
//# sourceMappingURL=user-prompt-service.test.js.map