// apps/backend/src/routes/workspace-hot-switch.ts
// @file: HTTP routes for hot workspace switching
// @module: workspace-hot-switch-routes
// @description: Fast workspace switching (<200ms) with IndexedDB state persistence
import { Router } from "express";
import { getHotWorkspaceSwitchService } from "../services/workspace/hot-switch-service.js";
const router = Router();
const service = getHotWorkspaceSwitchService();
/**
 * POST /api/workspaces
 * Register a new workspace for hot switching
 */
router.post("/", (req, res) => {
    try {
        const result = service.registerWorkspace(req.body);
        if (result.success) {
            res.status(201).json({ workspaceId: result.workspaceId, message: "Workspace registered" });
        }
        else {
            res.status(400).json({ error: result.error });
        }
    }
    catch (error) {
        const err = error;
        res.status(500).json({ error: err.message });
    }
});
/**
 * POST /api/workspaces/switch
 * Switch to a different workspace (<200ms)
 */
router.post("/switch", (req, res) => {
    try {
        const { fromWorkspaceId, toWorkspaceId } = req.body;
        if (!toWorkspaceId) {
            res.status(400).json({ error: "toWorkspaceId is required" });
            return;
        }
        const result = service.switchWorkspace(fromWorkspaceId || null, toWorkspaceId);
        if (result.success) {
            res.json({
                duration: result.duration,
                withinRequirement: result.duration < 200,
                message: `Switched in ${result.duration}ms`,
            });
        }
        else {
            res.status(400).json({ error: result.error });
        }
    }
    catch (error) {
        const err = error;
        res.status(500).json({ error: err.message });
    }
});
/**
 * GET /api/workspaces/active
 * Get currently active workspace
 */
router.get("/active", (req, res) => {
    try {
        const active = service.getActiveWorkspace();
        if (!active) {
            res.status(404).json({ error: "No active workspace" });
            return;
        }
        res.json(active);
    }
    catch (error) {
        const err = error;
        res.status(500).json({ error: err.message });
    }
});
/**
 * GET /api/workspaces
 * List all registered workspaces
 */
router.get("/", (req, res) => {
    try {
        const workspaces = service.getWorkspaces();
        res.json({
            total: workspaces.length,
            maxConcurrent: service.getConcurrentLimit(),
            workspaces,
        });
    }
    catch (error) {
        const err = error;
        res.status(500).json({ error: err.message });
    }
});
/**
 * GET /api/workspaces/:workspaceId
 * Get workspace details
 */
router.get("/:workspaceId", (req, res) => {
    try {
        const workspace = service.getWorkspace(req.params.workspaceId);
        if (!workspace) {
            res.status(404).json({ error: "Workspace not found" });
            return;
        }
        res.json(workspace);
    }
    catch (error) {
        const err = error;
        res.status(500).json({ error: err.message });
    }
});
/**
 * PATCH /api/workspaces/:workspaceId
 * Update workspace state
 */
router.patch("/:workspaceId", (req, res) => {
    try {
        const result = service.updateWorkspaceState(req.params.workspaceId, req.body);
        if (result.success) {
            res.json({ message: "Workspace state updated" });
        }
        else {
            res.status(400).json({ error: result.error });
        }
    }
    catch (error) {
        const err = error;
        res.status(500).json({ error: err.message });
    }
});
/**
 * DELETE /api/workspaces/:workspaceId
 * Close and unregister workspace
 */
router.delete("/:workspaceId", (req, res) => {
    try {
        const result = service.closeWorkspace(req.params.workspaceId);
        if (result.success) {
            res.json({ message: "Workspace closed" });
        }
        else {
            res.status(400).json({ error: result.error });
        }
    }
    catch (error) {
        const err = error;
        res.status(500).json({ error: err.message });
    }
});
/**
 * GET /api/workspaces/:workspaceId/serialize
 * Serialize workspace for IndexedDB persistence
 */
router.get("/:workspaceId/serialize", (req, res) => {
    try {
        const result = service.serializeWorkspace(req.params.workspaceId);
        if (result.success) {
            res.json({ data: result.data });
        }
        else {
            res.status(400).json({ error: result.error });
        }
    }
    catch (error) {
        const err = error;
        res.status(500).json({ error: err.message });
    }
});
/**
 * POST /api/workspaces/deserialize
 * Deserialize workspace from IndexedDB
 */
router.post("/deserialize", (req, res) => {
    try {
        const { data } = req.body;
        if (!data) {
            res.status(400).json({ error: "data is required" });
            return;
        }
        const result = service.deserializeWorkspace(data);
        if (result.success) {
            res.json({ state: result.state });
        }
        else {
            res.status(400).json({ error: result.error });
        }
    }
    catch (error) {
        const err = error;
        res.status(500).json({ error: err.message });
    }
});
/**
 * GET /api/workspaces/stats/performance
 * Get performance metrics
 */
router.get("/stats/performance", (req, res) => {
    try {
        const stats = service.getStatistics();
        res.json(stats);
    }
    catch (error) {
        const err = error;
        res.status(500).json({ error: err.message });
    }
});
export default router;
//# sourceMappingURL=workspace-hot-switch.js.map