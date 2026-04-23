// apps/backend/src/services/workspace-auto-config/workspace-config-service.ts
// @file: Applies workspace configuration profile to IDE (Issue #1048 Phase 2)
// Installs extensions, writes settings, generates tasks and debug configs
import * as fs from "fs";
import * as path from "path";
import { EventEmitter } from "events";
import { ProjectDetectionEngine, ProjectType } from "./detection-engine";
export class WorkspaceConfigurationService extends EventEmitter {
    constructor(workspaceRoot) {
        super();
        this.workspaceRoot = workspaceRoot;
        this.vscodeDirPath = path.join(workspaceRoot, ".vscode");
        this.detectionEngine = new ProjectDetectionEngine(workspaceRoot);
    }
    async configureWorkspace(onProgress) {
        const errors = [];
        try {
            // Step 1: Detect project type
            this.emitProgress(onProgress, {
                step: "detecting",
                progress: 10,
                message: "Detecting project type...",
                errors: [],
            });
            const detectionResult = await this.detectionEngine.detectProjectType();
            const profile = this.detectionEngine.getProfileForType(detectionResult.type);
            if (detectionResult.type === ProjectType.UNKNOWN) {
                errors.push("Could not detect project type. Using default configuration.");
            }
            // Step 2: Prepare workspace directory
            this.ensureVscodeDirectory();
            // Step 3: Write settings
            this.emitProgress(onProgress, {
                step: "writing-settings",
                progress: 30,
                message: "Writing workspace settings...",
                errors,
            });
            await this.writeWorkspaceSettings(profile);
            // Step 4: Generate tasks.json
            this.emitProgress(onProgress, {
                step: "generating-tasks",
                progress: 60,
                message: "Generating build tasks...",
                errors,
            });
            await this.generateTasksJson(profile);
            // Step 5: Generate launch.json (debug configs)
            this.emitProgress(onProgress, {
                step: "generating-debug",
                progress: 80,
                message: "Generating debug configurations...",
                errors,
            });
            await this.generateLaunchJson(profile);
            // Step 6: Complete
            this.emitProgress(onProgress, {
                step: "complete",
                progress: 100,
                message: "Workspace configured successfully!",
                errors,
            });
            return {
                success: errors.length === 0,
                profile,
                errors,
            };
        }
        catch (error) {
            const errorMessage = error instanceof Error ? error.message : String(error);
            errors.push(errorMessage);
            return {
                success: false,
                profile: this.detectionEngine.getProfileForType(ProjectType.UNKNOWN),
                errors,
            };
        }
    }
    ensureVscodeDirectory() {
        if (!fs.existsSync(this.vscodeDirPath)) {
            fs.mkdirSync(this.vscodeDirPath, { recursive: true });
        }
    }
    async writeWorkspaceSettings(profile) {
        const settingsPath = path.join(this.vscodeDirPath, "settings.json");
        // Read existing settings if they exist
        let existingSettings = {};
        if (fs.existsSync(settingsPath)) {
            try {
                const content = fs.readFileSync(settingsPath, "utf-8");
                existingSettings = JSON.parse(content);
            }
            catch {
                // If parsing fails, start fresh
            }
        }
        // Merge profile settings with existing settings
        // Profile settings take precedence, but don't override user language-specific settings
        const mergedSettings = {
            ...existingSettings,
            ...profile.settings,
        };
        // Preserve any existing language-specific settings that aren't in the profile
        for (const [key, value] of Object.entries(existingSettings)) {
            if (key.startsWith("[") && key.endsWith("]") && !profile.settings[key]) {
                mergedSettings[key] = value;
            }
        }
        fs.writeFileSync(settingsPath, JSON.stringify(mergedSettings, null, 2));
    }
    async generateTasksJson(profile) {
        const tasksPath = path.join(this.vscodeDirPath, "tasks.json");
        // Read existing tasks if they exist
        let existingTasks = [];
        if (fs.existsSync(tasksPath)) {
            try {
                const content = fs.readFileSync(tasksPath, "utf-8");
                const parsed = JSON.parse(content);
                existingTasks = parsed.tasks || [];
            }
            catch {
                // If parsing fails, start fresh
            }
        }
        // Merge profile tasks with existing tasks (avoid duplicates)
        const taskLabels = new Set(existingTasks.map((t) => t.label));
        const mergedTasks = [...existingTasks];
        for (const profileTask of profile.tasks) {
            if (!taskLabels.has(profileTask.label)) {
                mergedTasks.push({
                    label: profileTask.label,
                    type: "shell",
                    command: profileTask.command,
                    args: profileTask.args || [],
                });
            }
        }
        const tasksConfig = {
            version: "2.0.0",
            tasks: mergedTasks,
        };
        fs.writeFileSync(tasksPath, JSON.stringify(tasksConfig, null, 2));
    }
    async generateLaunchJson(profile) {
        const launchPath = path.join(this.vscodeDirPath, "launch.json");
        // Read existing launch config if it exists
        let existingConfigs = [];
        if (fs.existsSync(launchPath)) {
            try {
                const content = fs.readFileSync(launchPath, "utf-8");
                const parsed = JSON.parse(content);
                existingConfigs = parsed.configurations || [];
            }
            catch {
                // If parsing fails, start fresh
            }
        }
        // Merge profile debug configs with existing configs (avoid duplicates by name)
        const configNames = new Set(existingConfigs.map((c) => c.name));
        const mergedConfigs = [...existingConfigs];
        for (const profileConfig of profile.debugConfigurations) {
            if (!configNames.has(profileConfig.name)) {
                mergedConfigs.push(profileConfig);
            }
        }
        const launchConfig = {
            version: "0.2.0",
            configurations: mergedConfigs,
        };
        fs.writeFileSync(launchPath, JSON.stringify(launchConfig, null, 2));
    }
    emitProgress(callback, progress) {
        this.emit("progress", progress);
        if (callback) {
            callback(progress);
        }
    }
}
//# sourceMappingURL=workspace-config-service.js.map