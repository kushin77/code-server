import { Router } from 'express';
import { createWorkspaceMapService } from '../services/workspace-map';
export const router = Router();
// Initialize workspace map service for a workspace
router.post('/:workspaceId/init', (req, res) => {
    try {
        const { workspaceId } = req.params;
        const service = createWorkspaceMapService({ workspaceId });
        res.json({
            success: true,
            workspaceId,
            message: 'Workspace map initialized',
        });
    }
    catch (error) {
        res.status(500).json({ error: 'Failed to initialize workspace map' });
    }
});
// Register a user session
router.post('/:workspaceId/sessions', (req, res) => {
    try {
        const { workspaceId } = req.params;
        const { userId, userName } = req.body;
        if (!userId || !userName) {
            return res.status(400).json({ error: 'userId and userName are required' });
        }
        const service = createWorkspaceMapService({ workspaceId });
        service.registerSession(userId, userName);
        res.json({
            success: true,
            session: { userId, userName, status: 'online' },
        });
    }
    catch (error) {
        res.status(500).json({ error: 'Failed to register session' });
    }
});
// Update user activity
router.post('/:workspaceId/sessions/:userId/activity', (req, res) => {
    try {
        const { workspaceId, userId } = req.params;
        const { currentFile, cursorPosition } = req.body;
        if (!currentFile) {
            return res.status(400).json({ error: 'currentFile is required' });
        }
        const service = createWorkspaceMapService({ workspaceId });
        service.updateUserActivity(userId, currentFile, cursorPosition);
        res.json({ success: true, userId, currentFile });
    }
    catch (error) {
        res.status(500).json({ error: 'Failed to update user activity' });
    }
});
// Mark user as idle
router.post('/:workspaceId/sessions/:userId/idle', (req, res) => {
    try {
        const { workspaceId, userId } = req.params;
        const service = createWorkspaceMapService({ workspaceId });
        service.markUserIdle(userId);
        res.json({ success: true, userId, status: 'idle' });
    }
    catch (error) {
        res.status(500).json({ error: 'Failed to mark user idle' });
    }
});
// Unregister user session
router.post('/:workspaceId/sessions/:userId/unregister', (req, res) => {
    try {
        const { workspaceId, userId } = req.params;
        const service = createWorkspaceMapService({ workspaceId });
        service.unregisterSession(userId);
        res.json({ success: true, userId, message: 'Session unregistered' });
    }
    catch (error) {
        res.status(500).json({ error: 'Failed to unregister session' });
    }
});
// Get workspace snapshot
router.get('/:workspaceId/snapshot', (req, res) => {
    try {
        const { workspaceId } = req.params;
        const service = createWorkspaceMapService({ workspaceId });
        const snapshot = service.getWorkspaceSnapshot();
        res.json(snapshot);
    }
    catch (error) {
        res.status(500).json({ error: 'Failed to get workspace snapshot' });
    }
});
// Get active files
router.get('/:workspaceId/files', (req, res) => {
    try {
        const { workspaceId } = req.params;
        const { pattern } = req.query;
        const service = createWorkspaceMapService({ workspaceId });
        let files = service.getActiveFiles();
        if (pattern && typeof pattern === 'string') {
            files = service.queryActiveFiles(pattern);
        }
        res.json({ files, totalFiles: files.length });
    }
    catch (error) {
        res.status(500).json({ error: 'Failed to get active files' });
    }
});
// Get active sessions
router.get('/:workspaceId/sessions', (req, res) => {
    try {
        const { workspaceId } = req.params;
        const service = createWorkspaceMapService({ workspaceId });
        const sessions = service.getActiveSessions();
        res.json({ sessions, totalSessions: sessions.length });
    }
    catch (error) {
        res.status(500).json({ error: 'Failed to get active sessions' });
    }
});
// Get session details
router.get('/:workspaceId/sessions/:userId', (req, res) => {
    try {
        const { workspaceId, userId } = req.params;
        const service = createWorkspaceMapService({ workspaceId });
        const session = service.getSession(userId);
        if (!session) {
            return res.status(404).json({ error: 'Session not found' });
        }
        res.json(session);
    }
    catch (error) {
        res.status(500).json({ error: 'Failed to get session' });
    }
});
// Get users on a specific file
router.get('/:workspaceId/files/:filePath/users', (req, res) => {
    try {
        const { workspaceId } = req.params;
        const { filePath } = req.query;
        if (!filePath) {
            return res.status(400).json({ error: 'filePath query parameter is required' });
        }
        const service = createWorkspaceMapService({ workspaceId });
        const users = service.getUsersOnFile(filePath);
        res.json({ filePath, users, totalUsers: users.length });
    }
    catch (error) {
        res.status(500).json({ error: 'Failed to get users on file' });
    }
});
// Get workspace statistics
router.get('/:workspaceId/stats', (req, res) => {
    try {
        const { workspaceId } = req.params;
        const service = createWorkspaceMapService({ workspaceId });
        const stats = service.getStatistics();
        res.json(stats);
    }
    catch (error) {
        res.status(500).json({ error: 'Failed to get workspace statistics' });
    }
});
//# sourceMappingURL=workspace-map.js.map