// apps/backend/src/routes/ephemeral-credentials.ts
// @file: HTTP routes for ephemeral credentials (Issue #1280)
// Endpoints: POST /api/credentials/request, POST /api/credentials/verify-expiration, DELETE /api/credentials/revoke
import { Router } from "express";
import { getEphemeralCredentialsService } from "../services/ephemeral-credentials/vault-service.js";
const router = Router();
const credentialsService = getEphemeralCredentialsService();
/**
 * POST /api/credentials/request
 * Request new ephemeral credentials for session
 *
 * Body:
 * {
 *   "type": "database" | "cloud_token",
 *   "provider": "aws" | "gcp" | "azure" (for cloud_token only),
 *   "ttl": 3600 (optional, default from env)
 * }
 */
router.post("/request", async (req, res) => {
    try {
        const { type, provider, ttl } = req.body;
        const sessionId = req.session?.id;
        const userId = req.user?.id;
        if (!sessionId) {
            res.status(401).json({ error: "Unauthorized - no session" });
            return;
        }
        if (!userId) {
            res.status(401).json({ error: "Unauthorized - no user" });
            return;
        }
        if (!type || (type !== "database" && type !== "cloud_token")) {
            res.status(400).json({ error: 'Invalid type - must be "database" or "cloud_token"' });
            return;
        }
        let credential;
        if (type === "database") {
            credential = await credentialsService.requestDatabaseCredentials(sessionId, userId, ttl);
        }
        else {
            // cloud_token
            if (!provider || !["aws", "gcp", "azure"].includes(provider)) {
                res.status(400).json({ error: 'Provider required for cloud_token - must be "aws", "gcp", or "azure"' });
                return;
            }
            credential = await credentialsService.requestCloudToken(sessionId, userId, provider, ttl);
        }
        // Mask sensitive fields in response
        res.json({
            type: credential.type,
            username: credential.username,
            // Don't send password/token/keys to client
            issuedAt: credential.issuedAt,
            expiresAt: credential.expiresAt,
            ttl: credential.ttl,
            metadata: credential.metadata,
        });
    }
    catch (error) {
        const err = error;
        res.status(500).json({ error: err.message });
    }
});
/**
 * GET /api/credentials
 * Get all credentials for current session
 */
router.get("/", (req, res) => {
    try {
        const sessionId = req.session?.id;
        if (!sessionId) {
            res.status(401).json({ error: "Unauthorized - no session" });
            return;
        }
        const credentials = credentialsService.getSessionCredentials(sessionId);
        // Map to response format without sensitive data
        const safeCredentials = credentials.map((cred) => ({
            type: cred.type,
            username: cred.username,
            issuedAt: cred.issuedAt,
            expiresAt: cred.expiresAt,
            ttl: cred.ttl,
            metadata: cred.metadata,
        }));
        res.json(safeCredentials);
    }
    catch (error) {
        const err = error;
        res.status(500).json({ error: err.message });
    }
});
/**
 * POST /api/credentials/verify-expiration
 * Check if any credentials are expiring soon (< 5 min)
 *
 * Returns:
 * {
 *   "hasExpiringCredentials": boolean,
 *   "credentials": [
 *     {
 *       "username": "app_alice_...",
 *       "type": "database",
 *       "isExpiring": boolean,
 *       "minutesRemaining": number
 *     }
 *   ]
 * }
 */
router.post("/verify-expiration", (req, res) => {
    try {
        const sessionId = req.session?.id;
        if (!sessionId) {
            res.status(401).json({ error: "Unauthorized - no session" });
            return;
        }
        const credentials = credentialsService.getSessionCredentials(sessionId);
        const expirationStatus = credentials.map((cred) => {
            const expiration = credentialsService.checkCredentialExpiration(cred);
            return {
                username: cred.username,
                type: cred.type,
                isExpiring: expiration.isExpiring,
                minutesRemaining: expiration.minutesRemaining,
            };
        });
        const hasExpiringCredentials = expirationStatus.some((c) => c.isExpiring);
        res.json({
            hasExpiringCredentials,
            credentials: expirationStatus,
        });
    }
    catch (error) {
        const err = error;
        res.status(500).json({ error: err.message });
    }
});
/**
 * DELETE /api/credentials/revoke
 * Revoke all session credentials
 *
 * Called on logout or session expiration
 */
router.delete("/revoke", async (req, res) => {
    try {
        const sessionId = req.session?.id;
        if (!sessionId) {
            res.status(401).json({ error: "Unauthorized - no session" });
            return;
        }
        await credentialsService.revokeSessionCredentials(sessionId);
        res.json({ message: "All credentials revoked" });
    }
    catch (error) {
        const err = error;
        res.status(500).json({ error: err.message });
    }
});
export default router;
//# sourceMappingURL=ephemeral-credentials.js.map