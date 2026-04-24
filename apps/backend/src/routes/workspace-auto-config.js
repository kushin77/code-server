// apps/backend/src/routes/workspace-auto-config.ts
// Workspace auto-configuration HTTP endpoints
import { Router } from "express";
import { ProjectDetectionEngine, ProjectType } from "../services/workspace-auto-config/detection-engine";
import { WorkspaceConfigurationService } from "../services/workspace-auto-config/workspace-config-service";
export const router = Router();
/**
 * POST /api/workspace/detect
 * Detect project type for workspace at given path
 *
 * Body: { workspacePath: string }
 * Response: { type: ProjectType, confidence: 0-100, detectedFiles: string[], timestamp: string }
 */
router.post("/detect", async (req, res) => {
    try {
        const { workspacePath } = req.body;
        if (!workspacePath) {
            return res.status(400).json({ error: "workspacePath is required" });
        }
        const engine = new ProjectDetectionEngine(workspacePath);
        const result = await engine.detectProjectType(2000); // 2-second timeout
        return res.json({
            type: result.type,
            confidence: result.confidence,
            detectedFiles: result.detectedFiles,
            timestamp: result.timestamp,
        });
    }
    catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        return res.status(500).json({ error: message });
    }
});
/**
 * POST /api/workspace/profile
 * Get workspace profile for detected or specified project type
 *
 * Body: { workspacePath: string, projectType?: ProjectType }
 * Response: { type, extensions, settings, tasks, debugConfigurations }
 */
router.post("/profile", async (req, res) => {
    try {
        const { workspacePath, projectType } = req.body;
        if (!workspacePath) {
            return res.status(400).json({ error: "workspacePath is required" });
        }
        const engine = new ProjectDetectionEngine(workspacePath);
        // If projectType is specified, use it; otherwise detect
        let typeToUse = projectType;
        if (!typeToUse) {
            const detectionResult = await engine.detectProjectType(2000);
            typeToUse = detectionResult.type;
        }
        const profile = engine.getProfileForType(typeToUse);
        return res.json({
            type: profile.type,
            extensions: profile.extensions,
            settings: profile.settings,
            tasks: profile.tasks,
            debugConfigurations: profile.debugConfigurations,
        });
    }
    catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        return res.status(500).json({ error: message });
    }
});
/**
 * POST /api/workspace/configure
 * Apply workspace configuration (settings, tasks, debug configs)
 * This performs auto-configuration after user approval
 *
 * Body: { workspacePath: string, projectType?: ProjectType }
 * Response: { success: boolean, profile: WorkspaceProfile, errors: string[] }
 */
router.post("/configure", async (req, res) => {
    try {
        const { workspacePath, projectType } = req.body;
        if (!workspacePath) {
            return res.status(400).json({ error: "workspacePath is required" });
        }
        const configService = new WorkspaceConfigurationService(workspacePath);
        // If projectType is specified, use it; otherwise let service detect
        const result = await configService.configureWorkspace();
        return res.json({
            success: result.success,
            profile: {
                type: result.profile.type,
                extensions: result.profile.extensions,
                settings: result.profile.settings,
                tasks: result.profile.tasks,
                debugConfigurations: result.profile.debugConfigurations,
            },
            errors: result.errors,
        });
    }
    catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        return res.status(500).json({ error: message });
    }
});
/**
 * GET /api/workspace/project-types
 * List all supported project types
 *
 * Response: { types: ProjectType[], descriptions: { [type]: string } }
 */
router.get("/project-types", (req, res) => {
    const types = Object.values(ProjectType);
    const descriptions = {
        [ProjectType.NODE_TYPESCRIPT]: "Node.js + TypeScript",
        [ProjectType.NODE_JAVASCRIPT]: "Node.js + JavaScript",
        [ProjectType.PYTHON]: "Python (plain)",
        [ProjectType.PYTHON_DJANGO]: "Python + Django",
        [ProjectType.GO]: "Go",
        [ProjectType.RUST]: "Rust",
        [ProjectType.JAVA]: "Java (plain)",
        [ProjectType.JAVA_SPRING]: "Java + Spring",
        [ProjectType.CPP]: "C++",
        [ProjectType.CSHARP]: "C#",
        [ProjectType.PHP]: "PHP",
        [ProjectType.RUBY]: "Ruby",
        [ProjectType.UNKNOWN]: "Unknown/Unsupported",
    };
    return res.json({
        types,
        descriptions,
    });
});
//# sourceMappingURL=workspace-auto-config.js.map