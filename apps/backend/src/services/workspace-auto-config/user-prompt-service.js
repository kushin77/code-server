// apps/backend/src/services/workspace-auto-config/user-prompt-service.ts
// @file: VS Code user prompt service for workspace auto-configuration (Issue #1048 Phase 3)
// Generates walkthrough prompts and handles user approval flow
import { EventEmitter } from "events";
import { ProjectType } from "./detection-engine";
/**
 * VS Code user prompt service for workspace auto-configuration
 * Generates user-friendly prompts and handles approval flow
 */
export class UserPromptService extends EventEmitter {
    constructor(options) {
        super();
        this.workspaceRoot = options.workspaceRoot;
        this.detectedType = options.detectedType;
        this.profile = options.profile;
        this.confidence = options.confidence;
    }
    /**
     * Generate walkthrough metadata for VS Code
     * Used with vscode.window.createWalkthrough() API
     */
    generateWalkthroughMetadata() {
        const typeLabel = this.getProjectTypeLabel(this.detectedType);
        const confidenceLabel = this.getConfidenceLabel(this.confidence);
        return {
            id: `kushnir-cloud.workspace-config-${this.detectedType}`,
            title: `Configure Workspace for ${typeLabel}`,
            description: `We detected your workspace is a ${typeLabel} project (${confidenceLabel} confidence). Would you like us to auto-configure your IDE?`,
            steps: [
                {
                    id: "welcome",
                    title: "Welcome to Smart Workspace Configuration",
                    description: `We've detected that your workspace is a ${typeLabel} project.`,
                    completionEvents: [],
                },
                {
                    id: "review-profile",
                    title: "Review Suggested Configuration",
                    description: this.generateProfileDescription(),
                    completionEvents: [],
                },
                {
                    id: "extensions",
                    title: `Install ${this.profile.extensions.length} Recommended Extensions`,
                    description: this.generateExtensionsDescription(),
                    completionEvents: [],
                },
                {
                    id: "settings",
                    title: "Apply Workspace Settings",
                    description: "We'll configure formatting, linting, and language-specific settings.",
                    completionEvents: [],
                },
                {
                    id: "tasks",
                    title: "Add Build and Test Tasks",
                    description: `Add ${this.profile.tasks.length} predefined tasks for quick builds and testing.`,
                    completionEvents: [],
                },
                {
                    id: "debug",
                    title: "Configure Debugging",
                    description: `Setup ${this.profile.debugConfigurations.length} debug configuration(s) for your project.`,
                    completionEvents: [],
                },
                {
                    id: "complete",
                    title: "Configuration Complete!",
                    description: "Your workspace is now configured. Start coding!",
                    completionEvents: [],
                },
            ],
        };
    }
    /**
     * Generate HTML/Markdown for profile review step
     */
    generateProfileDescription() {
        const extensionCount = this.profile.extensions.length;
        const taskCount = this.profile.tasks.length;
        const debugCount = this.profile.debugConfigurations.length;
        return `
**Configuration Includes:**
- **Extensions:** ${extensionCount} recommended extensions for better IDE experience
- **Settings:** Language-specific formatting and linting rules
- **Tasks:** ${taskCount} build/test tasks for quick execution
- **Debug Configs:** ${debugCount} debug configuration(s) ready to use

All changes will be merged with your existing settings — nothing will be lost.
`;
    }
    /**
     * Generate extensions list for display
     */
    generateExtensionsDescription() {
        const extensions = this.profile.extensions
            .map((ext) => `- **${ext}**`)
            .join("\n");
        return `The following extensions will be installed:\n${extensions}`;
    }
    /**
     * Get human-readable project type label
     */
    getProjectTypeLabel(type) {
        const labels = {
            [ProjectType.NODE_TYPESCRIPT]: "Node.js + TypeScript",
            [ProjectType.NODE_JAVASCRIPT]: "Node.js + JavaScript",
            [ProjectType.PYTHON]: "Python",
            [ProjectType.PYTHON_DJANGO]: "Python + Django",
            [ProjectType.GO]: "Go",
            [ProjectType.RUST]: "Rust",
            [ProjectType.JAVA]: "Java",
            [ProjectType.JAVA_SPRING]: "Java + Spring",
            [ProjectType.CPP]: "C++",
            [ProjectType.CSHARP]: "C#",
            [ProjectType.PHP]: "PHP",
            [ProjectType.RUBY]: "Ruby",
            [ProjectType.UNKNOWN]: "Unknown",
        };
        return labels[type] || "Unknown";
    }
    /**
     * Get human-readable confidence label
     */
    getConfidenceLabel(confidence) {
        if (confidence >= 90)
            return "high";
        if (confidence >= 70)
            return "medium";
        if (confidence >= 50)
            return "fair";
        return "low";
    }
    /**
     * Generate approval prompt text
     */
    generateApprovalPrompt() {
        const typeLabel = this.getProjectTypeLabel(this.detectedType);
        const confidenceLabel = this.getConfidenceLabel(this.confidence);
        return {
            title: `Configure Workspace for ${typeLabel}?`,
            message: `We detected your workspace is a ${typeLabel} project (${confidenceLabel} confidence). We can auto-configure:
- ${this.profile.extensions.length} recommended extensions
- Formatting and linting settings
- ${this.profile.tasks.length} build/test tasks
- ${this.profile.debugConfigurations.length} debug configuration(s)

Your existing settings will be preserved.`,
            buttons: [
                { label: "✓ Yes, Configure", action: "approve" },
                { label: "✗ No, Skip", action: "decline" },
                { label: "⚙ Customize...", action: "customize" },
            ],
        };
    }
    /**
     * Generate customization options
     */
    generateCustomizationOptions() {
        return {
            title: "Customize Configuration",
            options: [
                {
                    id: "install-extensions",
                    label: `Install ${this.profile.extensions.length} Extensions`,
                    description: "Add recommended extensions for better IDE experience",
                    defaultChecked: true,
                },
                {
                    id: "apply-settings",
                    label: "Apply Workspace Settings",
                    description: "Configure formatting, linting, and language settings",
                    defaultChecked: true,
                },
                {
                    id: "add-tasks",
                    label: `Add ${this.profile.tasks.length} Build/Test Tasks`,
                    description: "Create quick build and test commands",
                    defaultChecked: true,
                },
                {
                    id: "setup-debug",
                    label: `Configure ${this.profile.debugConfigurations.length} Debug Config(s)`,
                    description: "Setup debugging for your project type",
                    defaultChecked: true,
                },
            ],
        };
    }
    /**
     * Process user response and return prompt result
     */
    processUserResponse(action, customizations) {
        if (action === "decline") {
            return {
                approved: false,
                projectType: this.detectedType,
            };
        }
        if (action === "approve") {
            return {
                approved: true,
                projectType: this.detectedType,
            };
        }
        // Customize action
        if (!customizations) {
            customizations = {};
        }
        return {
            approved: true,
            projectType: this.detectedType,
            customizationApplied: {
                skipSettings: !customizations["apply-settings"],
                skipTasks: !customizations["add-tasks"],
                skipDebugConfigs: !customizations["setup-debug"],
            },
        };
    }
}
//# sourceMappingURL=user-prompt-service.js.map