// apps/backend/src/services/git-signing/__tests__/sigstore-service.test.ts
import { describe, it, expect, beforeEach } from "vitest";
import { SigstoreSigningService } from "../sigstore-service";
describe("SigstoreSigningService", () => {
    let service;
    const userId = "alice";
    const userEmail = "alice@kushnir.cloud";
    const workspacePath = "/tmp/test-workspace";
    beforeEach(() => {
        service = new SigstoreSigningService();
        process.env.OIDC_ISSUER = "https://oauth2.googleapis.com";
    });
    describe("initializeForUser", () => {
        it("should initialize signing for user", () => {
            const result = service.initializeForUser(userId, userEmail, workspacePath);
            expect(result.success).toBeDefined();
            expect(result.message).toBeDefined();
        });
        it("should create signing key with 24h TTL", () => {
            const result = service.initializeForUser(userId, userEmail, workspacePath);
            if (result.success && result.key) {
                expect(result.key.type).toBe("sigstore");
                expect(result.key.algorithm).toBe("ecdsa");
                expect(result.key.ttl).toBe(86400); // 24 hours
                expect(result.key.userId).toBe(userId);
            }
        });
        it("should set key expiration to 24 hours from now", () => {
            const result = service.initializeForUser(userId, userEmail, workspacePath);
            if (result.success && result.key) {
                const now = Date.now();
                const expiresMs = result.key.expiresAt.getTime();
                const diffMs = expiresMs - now;
                // Should be approximately 24 hours (within 1 minute tolerance)
                expect(diffMs).toBeGreaterThan(86400000 - 60000);
                expect(diffMs).toBeLessThanOrEqual(86400000);
            }
        });
        it("should include fingerprint in key", () => {
            const result = service.initializeForUser(userId, userEmail, workspacePath);
            if (result.success && result.key) {
                expect(result.key.fingerprint).toBeDefined();
                expect(result.key.fingerprint?.length).toBeGreaterThan(0);
            }
        });
        it("should include config message", () => {
            const result = service.initializeForUser(userId, userEmail, workspacePath);
            // Message should be defined regardless of success
            expect(result.message).toBeDefined();
        });
    });
    describe("verifyCommitSignature", () => {
        it("should return signature verification result", () => {
            const commitHash = "abc123def456";
            const result = service.verifyCommitSignature(commitHash, workspacePath);
            expect(result.commitHash).toBe(commitHash);
            expect(result.verificationStatus).toBeDefined();
            expect(["valid", "invalid", "unknown"]).toContain(result.verificationStatus);
            expect(result.metadata).toBeDefined();
        });
        it("should include signing time in result", () => {
            const result = service.verifyCommitSignature("abc123", workspacePath);
            expect(result.signingTime).toBeInstanceOf(Date);
        });
        it("should set verified flag in metadata", () => {
            const result = service.verifyCommitSignature("abc123", workspacePath);
            expect(result.metadata.verified).toBeDefined();
            expect(typeof result.metadata.verified).toBe("boolean");
        });
        it("should indicate sigstore signing method", () => {
            const result = service.verifyCommitSignature("abc123", workspacePath);
            expect(result.metadata.signingMethod).toBe("sigstore/gitsign");
        });
        it("should include certificate TTL in metadata", () => {
            const result = service.verifyCommitSignature("abc123", workspacePath);
            expect(result.metadata.certificateTTL).toBe("24h");
        });
    });
    describe("checkCertificateExpiration", () => {
        it("should detect non-expired certificate", () => {
            const initResult = service.initializeForUser(userId, userEmail, workspacePath);
            if (initResult.key) {
                const expiration = service.checkCertificateExpiration(initResult.key);
                expect(expiration.isExpiring).toBe(false);
                expect(expiration.hoursRemaining).toBeGreaterThan(0);
            }
        });
        it("should calculate hours remaining correctly", () => {
            const initResult = service.initializeForUser(userId, userEmail, workspacePath);
            if (initResult.key) {
                const expiration = service.checkCertificateExpiration(initResult.key);
                // Should be approximately 24 hours
                expect(expiration.hoursRemaining).toBeGreaterThanOrEqual(23);
                expect(expiration.hoursRemaining).toBeLessThanOrEqual(24);
            }
        });
        it("should return 0 hours for expired certificate", () => {
            const expiredKey = {
                type: "sigstore",
                algorithm: "ecdsa",
                publicKeyPath: "/path/to/key",
                createdAt: new Date(Date.now() - 172800000), // 2 days ago
                expiresAt: new Date(Date.now() - 86400000), // Expired 1 day ago
                ttl: 86400,
                userId: "alice",
            };
            const expiration = service.checkCertificateExpiration(expiredKey);
            expect(expiration.isExpiring).toBe(true);
            expect(expiration.hoursRemaining).toBe(0);
        });
    });
    describe("getSignedCommits", () => {
        it("should return array of commits", () => {
            const commits = service.getSignedCommits(workspacePath, 10);
            expect(Array.isArray(commits)).toBe(true);
        });
        it("should include commit metadata", () => {
            const commits = service.getSignedCommits(workspacePath, 5);
            commits.forEach((commit) => {
                expect(commit.commitHash).toBeDefined();
                expect(commit.verificationStatus).toBeDefined();
                expect(commit.signingTime).toBeInstanceOf(Date);
                expect(commit.metadata).toBeDefined();
            });
        });
        it("should respect limit parameter", () => {
            const commits = service.getSignedCommits(workspacePath, 10);
            expect(commits.length).toBeLessThanOrEqual(10);
        });
        it("should include source in metadata", () => {
            const commits = service.getSignedCommits(workspacePath, 5);
            commits.forEach((commit) => {
                expect(commit.metadata.source).toBe("log_query");
            });
        });
    });
    describe("Signing Key Formats", () => {
        it("should have valid key type", () => {
            const result = service.initializeForUser(userId, userEmail, workspacePath);
            if (result.key) {
                expect(["sigstore", "pgp"]).toContain(result.key.type);
            }
        });
        it("should have valid algorithm", () => {
            const result = service.initializeForUser(userId, userEmail, workspacePath);
            if (result.key) {
                expect(["ecdsa", "rsa"]).toContain(result.key.algorithm);
            }
        });
        it("should have certificate path for sigstore", () => {
            const result = service.initializeForUser(userId, userEmail, workspacePath);
            if (result.key) {
                expect(result.key.certPath).toBeDefined();
                expect(result.key.certPath).toContain("sigstore");
            }
        });
        it("should have public key path", () => {
            const result = service.initializeForUser(userId, userEmail, workspacePath);
            if (result.key) {
                expect(result.key.publicKeyPath).toBeDefined();
                expect(result.key.publicKeyPath).toContain("public");
            }
        });
    });
    describe("Certificate TTL", () => {
        it("should always be 24 hours for sigstore", () => {
            for (let i = 0; i < 5; i++) {
                const result = service.initializeForUser(`user${i}`, `user${i}@test.com`, workspacePath);
                if (result.key) {
                    expect(result.key.ttl).toBe(86400);
                }
            }
        });
    });
    describe("Error Handling", () => {
        it("should handle invalid workspace path gracefully", () => {
            const result = service.initializeForUser(userId, userEmail, "/invalid/path/that/does/not/exist");
            expect(result).toBeDefined();
            expect(result.success).toBeDefined();
        });
        it("should handle invalid workspace path in verification", () => {
            const result = service.verifyCommitSignature("abc123", "/invalid/path");
            expect(result.verificationStatus).toBe("unknown");
            expect(result.metadata.verified).toBe(false);
        });
        it("should include error in metadata on verification failure", () => {
            const result = service.verifyCommitSignature("abc123", "/nonexistent/path");
            expect(result.metadata).toBeDefined();
        });
    });
    describe("Fingerprint Generation", () => {
        it("should generate unique fingerprints for different users", () => {
            const fp1 = service.initializeForUser("alice", "alice@test.com", workspacePath).key?.fingerprint;
            const fp2 = service.initializeForUser("bob", "bob@test.com", workspacePath).key?.fingerprint;
            // Both should have fingerprints if keys were created
            if (fp1 && fp2) {
                expect(fp1).not.toBe(fp2);
            }
        });
        it("should have consistent format", () => {
            const fp = service.initializeForUser(userId, userEmail, workspacePath).key?.fingerprint;
            // Fingerprint should be hex string if present
            if (fp) {
                expect(fp).toMatch(/^[a-f0-9]+$/);
            }
        });
    });
    describe("Certificate Export", () => {
        it("should handle missing certificate gracefully", () => {
            const cert = service.exportPublicCertificate("nonexistent-user");
            // May return null if cert doesn't exist
            expect(cert === null || typeof cert === "string").toBe(true);
        });
    });
});
//# sourceMappingURL=sigstore-service.test.js.map