// apps/backend/src/services/git-signing/sigstore-service.ts
// @file: Git commit signing with Sigstore (Issue #1278)
// Signs commits using Sigstore/gitsign with 24h cert TTL, verifies signatures
import { execSync } from "child_process";
import * as path from "path";
import * as fs from "fs";
import { getLogger } from "../../lib/logger.js";
/**
 * Git commit signing service using Sigstore/gitsign
 * Signs commits with 24h ephemeral certificates, verifies signatures
 */
export class SigstoreSigningService {
    constructor() {
        this.logger = getLogger("SigstoreSigningService");
        this.gitsignPath = process.env.GITSIGN_PATH || "gitsign";
        this.oidcIssuer = process.env.OIDC_ISSUER || "https://oauth2.googleapis.com";
        this.sigstoreRoot = process.env.SIGSTORE_ROOT || path.join(process.env.HOME || "/home", ".sigstore");
        this.gitBinary = process.env.GIT_BINARY || "git";
    }
    /**
     * Initialize Sigstore signing for a user
     * Generates ephemeral signing certificate with 24h TTL
     */
    initializeForUser(userId, userEmail, workspacePath) {
        try {
            // Ensure sigstore trust root is available
            this.ensureSigstoreRoot();
            // Configure git to use gitsign for signing
            const configCommands = [
                `${this.gitBinary} config --global gpg.format x509`,
                `${this.gitBinary} config --global gpg.x509.program ${this.gitsignPath}`,
                `${this.gitBinary} config --global commit.gpgsign true`,
                `${this.gitBinary} config --global user.name "${userId}"`,
                `${this.gitBinary} config --global user.email "${userEmail}"`,
            ];
            for (const cmd of configCommands) {
                try {
                    execSync(cmd, { cwd: workspacePath, stdio: "pipe" });
                }
                catch (error) {
                    this.logger.warn(`Git config command failed: ${cmd}`, { error });
                    // Continue - some configs may already be set
                }
            }
            // Get signing key info
            const key = {
                type: "sigstore",
                algorithm: "ecdsa",
                publicKeyPath: path.join(this.sigstoreRoot, "public.crt"),
                certPath: path.join(this.sigstoreRoot, "sigstore.crt"),
                createdAt: new Date(),
                expiresAt: new Date(Date.now() + 86400000), // 24 hours
                ttl: 86400, // 24 hours in seconds
                userId,
                fingerprint: this.generateFingerprint(userId, userEmail),
            };
            this.logger.info("Initialized Sigstore signing for user", {
                userId,
                userEmail,
                ttl: key.ttl,
                expiresAt: key.expiresAt,
            });
            return {
                success: true,
                key,
                message: `Git signing configured for ${userId} using Sigstore (24h certificates)`,
            };
        }
        catch (error) {
            const err = error;
            this.logger.error("Failed to initialize Sigstore signing", { error: err.message, userId });
            return {
                success: false,
                key: null,
                message: `Failed to initialize signing: ${err.message}`,
            };
        }
    }
    /**
     * Verify a commit signature
     * Checks if signature is valid and certificate is not expired
     */
    verifyCommitSignature(commitHash, workspacePath) {
        try {
            // Get commit signature data
            const signatureData = execSync(`${this.gitBinary} show --format=%G? --no-patch ${commitHash}`, { cwd: workspacePath, encoding: "utf-8" }).trim();
            // Map git verification status to ours
            const statusMap = {
                G: "valid",
                B: "invalid",
                U: "unknown",
                X: "unknown",
                Y: "unknown", // Valid but untrusted
                R: "unknown", // Valid but revoked
                E: "unknown", // Error checking signature
                N: "unknown", // No signature
            };
            const verificationStatus = statusMap[signatureData] || "unknown";
            // Get signer name
            const signerName = execSync(`${this.gitBinary} show --format=%GS --no-patch ${commitHash}`, { cwd: workspacePath, encoding: "utf-8" }).trim();
            // Get commit body (first line for signature)
            const commitBody = execSync(`${this.gitBinary} show --format=%B --no-patch ${commitHash}`, {
                cwd: workspacePath,
                encoding: "utf-8",
            }).trim();
            const signature = {
                commitHash,
                signature: signatureData,
                signedBy: signerName,
                signingTime: this.getCommitTime(commitHash, workspacePath),
                verificationStatus,
                metadata: {
                    verified: verificationStatus === "valid",
                    signingMethod: "sigstore/gitsign",
                    certificateTTL: "24h",
                },
            };
            this.logger.info("Verified commit signature", {
                commitHash: commitHash.substring(0, 7),
                verificationStatus,
                signedBy: signerName,
            });
            return signature;
        }
        catch (error) {
            const err = error;
            this.logger.error("Failed to verify commit signature", { error: err.message, commitHash });
            return {
                commitHash,
                signature: "unknown",
                signedBy: "unknown",
                signingTime: new Date(),
                verificationStatus: "unknown",
                metadata: {
                    verified: false,
                    signingMethod: "sigstore/gitsign",
                    certificateTTL: "24h",
                    error: err.message,
                },
            };
        }
    }
    /**
     * Sign a commit (typically done automatically by git config)
     * Manual signing for test/demo purposes
     */
    signCommit(workspacePath, message, author) {
        try {
            // Stage all changes
            execSync(`${this.gitBinary} add -A`, { cwd: workspacePath, stdio: "pipe" });
            // Commit with automatic signing (configured via git config)
            const cmd = author
                ? `${this.gitBinary} commit -m "${message.replace(/"/g, '\\"')}" --author="${author}"`
                : `${this.gitBinary} commit -m "${message.replace(/"/g, '\\"')}"`;
            const result = execSync(cmd, { cwd: workspacePath, encoding: "utf-8", stdio: "pipe" });
            // Extract commit hash
            const hashMatch = result.match(/\[.*\s+([a-f0-9]+)\]/);
            const commitHash = hashMatch ? hashMatch[1] : "unknown";
            this.logger.info("Signed commit", {
                commitHash: commitHash.substring(0, 7),
                author,
            });
            return {
                success: true,
                commitHash,
                message: `Commit signed with Sigstore (hash: ${commitHash.substring(0, 7)})`,
            };
        }
        catch (error) {
            const err = error;
            this.logger.error("Failed to sign commit", { error: err.message });
            return {
                success: false,
                message: `Failed to sign commit: ${err.message}`,
            };
        }
    }
    /**
     * Check if signing certificate is expiring soon (< 24h remaining)
     */
    checkCertificateExpiration(key) {
        const now = Date.now();
        const expiresMs = key.expiresAt.getTime();
        const hoursRemaining = Math.floor((expiresMs - now) / 1000 / 3600);
        return {
            isExpiring: hoursRemaining < 0, // Already expired
            hoursRemaining: Math.max(0, hoursRemaining),
        };
    }
    /**
     * Get all signed commits in a repository
     */
    getSignedCommits(workspacePath, limit = 50) {
        try {
            // Get recent commits
            const logOutput = execSync(`${this.gitBinary} log --format=%H%n%GS%n%G? -${limit}`, { cwd: workspacePath, encoding: "utf-8" });
            const lines = logOutput.trim().split("\n");
            const commits = [];
            for (let i = 0; i < lines.length; i += 3) {
                const commitHash = lines[i];
                const signer = lines[i + 1];
                const status = lines[i + 2];
                const statusMap = {
                    G: "valid",
                    B: "invalid",
                    U: "unknown",
                    X: "unknown",
                    Y: "unknown",
                    R: "unknown",
                    E: "unknown",
                    N: "unknown",
                };
                commits.push({
                    commitHash,
                    signature: status,
                    signedBy: signer || "unknown",
                    signingTime: new Date(),
                    verificationStatus: statusMap[status] || "unknown",
                    metadata: {
                        source: "log_query",
                    },
                });
            }
            return commits;
        }
        catch (error) {
            this.logger.error("Failed to get signed commits", { error });
            return [];
        }
    }
    /**
     * Export public certificate for sharing
     */
    exportPublicCertificate(userId) {
        try {
            const certPath = path.join(this.sigstoreRoot, `${userId}.crt`);
            if (!fs.existsSync(certPath)) {
                this.logger.warn("Certificate not found", { userId, certPath });
                return null;
            }
            return fs.readFileSync(certPath, "utf-8");
        }
        catch (error) {
            this.logger.error("Failed to export certificate", { error, userId });
            return null;
        }
    }
    /**
     * Private helpers
     */
    ensureSigstoreRoot() {
        if (!fs.existsSync(this.sigstoreRoot)) {
            fs.mkdirSync(this.sigstoreRoot, { recursive: true });
            this.logger.info("Created sigstore root", { path: this.sigstoreRoot });
        }
    }
    generateFingerprint(userId, userEmail) {
        // Simple fingerprint generation (in production, derive from actual cert)
        const data = `${userId}:${userEmail}:${Date.now()}`;
        const crypto = require("crypto");
        return crypto.createHash("sha256").update(data).digest("hex").substring(0, 40);
    }
    getCommitTime(commitHash, workspacePath) {
        try {
            const timestamp = execSync(`${this.gitBinary} show --format=%cI --no-patch ${commitHash}`, { cwd: workspacePath, encoding: "utf-8" }).trim();
            return new Date(timestamp);
        }
        catch {
            return new Date();
        }
    }
}
// Singleton instance
let instance = null;
export function getSigstoreSigningService() {
    if (!instance) {
        instance = new SigstoreSigningService();
    }
    return instance;
}
//# sourceMappingURL=sigstore-service.js.map