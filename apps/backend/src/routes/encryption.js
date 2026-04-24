// apps/backend/src/routes/encryption.ts
// @file: HTTP routes for E2EE collaboration (Issue #1277)
import { Router } from "express";
import { getE2EEService } from "../services/encryption/e2ee-collaboration-service.js";
const router = Router();
const e2eeService = getE2EEService();
/**
 * POST /api/encryption/e2ee/sessions/init
 * Initialize a new E2EE session for a user/workspace
 *
 * Body:
 * {
 *   "userId": string,
 *   "workspaceId": string
 * }
 */
router.post("/e2ee/sessions/init", (req, res) => {
    try {
        const { userId, workspaceId } = req.body;
        if (!userId || !workspaceId) {
            res.status(400).json({ error: "userId and workspaceId are required" });
            return;
        }
        const result = e2eeService.initializeSession(userId, workspaceId);
        if (result.success) {
            res.json({
                sessionId: result.sessionId,
                publicKey: result.publicKey,
                ephemeralPublicKey: result.ephemeralPublicKey,
            });
        }
        else {
            res.status(500).json({
                error: "Failed to initialize session",
            });
        }
    }
    catch (error) {
        const err = error;
        res.status(500).json({ error: err.message });
    }
});
/**
 * GET /api/encryption/e2ee/sessions/:sessionId
 * Get session status
 */
router.get("/e2ee/sessions/:sessionId", (req, res) => {
    try {
        const { sessionId } = req.params;
        const session = e2eeService.getSessionStatus(sessionId);
        if (!session) {
            res.status(404).json({ error: "Session not found" });
            return;
        }
        res.json({
            sessionId: session.sessionId,
            workspaceId: session.workspaceId,
            userId: session.userId,
            isActive: session.isActive,
            createdAt: session.createdAt,
            expiresAt: session.expiresAt,
        });
    }
    catch (error) {
        const err = error;
        res.status(500).json({ error: err.message });
    }
});
/**
 * POST /api/encryption/e2ee/encrypt
 * Encrypt a collaboration message
 *
 * Body:
 * {
 *   "sessionId": string,
 *   "message": string,
 *   "userId": string
 * }
 */
router.post("/e2ee/encrypt", async (req, res) => {
    try {
        const { sessionId, message, userId } = req.body;
        if (!sessionId || !message || !userId) {
            res.status(400).json({ error: "sessionId, message, and userId are required" });
            return;
        }
        const result = await e2eeService.encryptMessage(sessionId, message, userId);
        if (result.success) {
            res.json({
                messageId: result.messageId,
                encryptedMessage: result.encryptedMessage,
                algorithm: result.algorithm,
            });
        }
        else {
            res.status(500).json({
                error: "Failed to encrypt message",
            });
        }
    }
    catch (error) {
        const err = error;
        res.status(500).json({ error: err.message });
    }
});
/**
 * POST /api/encryption/e2ee/decrypt
 * Decrypt a collaboration message
 *
 * Body:
 * {
 *   "sessionId": string,
 *   "messageId": string,
 *   "encryptedMessage": string,
 *   "userId": string
 * }
 */
router.post("/e2ee/decrypt", async (req, res) => {
    try {
        const { sessionId, messageId, encryptedMessage, userId } = req.body;
        if (!sessionId || !messageId || !encryptedMessage || !userId) {
            res.status(400).json({
                error: "sessionId, messageId, encryptedMessage, and userId are required",
            });
            return;
        }
        const result = await e2eeService.decryptMessage(sessionId, messageId, encryptedMessage, userId);
        if (result.success) {
            res.json({
                decryptedContent: result.decryptedContent,
            });
        }
        else {
            res.status(400).json({
                error: "Failed to decrypt message",
            });
        }
    }
    catch (error) {
        const err = error;
        res.status(500).json({ error: err.message });
    }
});
/**
 * POST /api/encryption/e2ee/verify-forward-secrecy
 * Verify forward secrecy for a message
 *
 * Body:
 * {
 *   "sessionId": string,
 *   "messageId": string
 * }
 */
router.post("/e2ee/verify-forward-secrecy", (req, res) => {
    try {
        const { sessionId, messageId } = req.body;
        if (!sessionId || !messageId) {
            res.status(400).json({ error: "sessionId and messageId are required" });
            return;
        }
        const result = e2eeService.verifyForwardSecrecy(sessionId, messageId);
        res.json({
            forwardSecure: result.forwardSecure,
            ratchetRotated: result.ratchetRotated,
        });
    }
    catch (error) {
        const err = error;
        res.status(500).json({ error: err.message });
    }
});
/**
 * DELETE /api/encryption/e2ee/sessions/:sessionId
 * Terminate a session and clear keys
 */
router.delete("/e2ee/sessions/:sessionId", (req, res) => {
    try {
        const { sessionId } = req.params;
        const result = e2eeService.terminateSession(sessionId);
        if (result.success) {
            res.json({
                message: "Session terminated",
                keysCleared: result.keysCleared,
            });
        }
        else {
            res.status(400).json({
                error: "Failed to terminate session",
            });
        }
    }
    catch (error) {
        const err = error;
        res.status(500).json({ error: err.message });
    }
});
/**
 * POST /api/encryption/e2ee/backup-keys
 * Backup encryption keys to Vault
 */
router.post("/e2ee/backup-keys", async (req, res) => {
    try {
        const result = await e2eeService.backupKeysToVault();
        if (result.success) {
            res.json({
                backupId: result.backupId,
                keysBackedUp: result.keysBackedUp,
            });
        }
        else {
            res.status(500).json({
                error: "Failed to backup keys",
            });
        }
    }
    catch (error) {
        const err = error;
        res.status(500).json({ error: err.message });
    }
});
/**
 * POST /api/encryption/e2ee/restore-keys
 * Restore encryption keys from Vault backup
 *
 * Body:
 * {
 *   "backupId": string
 * }
 */
router.post("/e2ee/restore-keys", async (req, res) => {
    try {
        const { backupId } = req.body;
        if (!backupId) {
            res.status(400).json({ error: "backupId is required" });
            return;
        }
        const result = await e2eeService.restoreKeysFromVault(backupId);
        if (result.success) {
            res.json({
                keysRestored: result.keysRestored,
            });
        }
        else {
            res.status(500).json({
                error: "Failed to restore keys",
            });
        }
    }
    catch (error) {
        const err = error;
        res.status(500).json({ error: err.message });
    }
});
export default router;
//# sourceMappingURL=encryption.js.map