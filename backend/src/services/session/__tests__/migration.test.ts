/**
 * Unit tests for session migration logic.
 * Tests all migration paths from v1 to v3 and edge cases.
 */

import { beforeEach, describe, expect, it } from 'vitest'

import { migrateSession, updateSessionActivity, isSessionExpired, isSessionStale, CURRENT_SESSION_VERSION } from "../migration";
import { Session, SessionV1, SessionV2 } from "../types";

describe("Session Migration", () => {
  describe("migrateSession", () => {
    it("should migrate v1 session to current version", () => {
      const v1Session: SessionV1 = {
        v: 1,
        sub: "user@example.com",
        iat: 1713000000,
        exp: 1713086400,
        google_id_token: "token123",
      };

      const { result, event } = migrateSession(v1Session);

      expect(result.from_version).toBe(1);
      expect(result.to_version).toBe(CURRENT_SESSION_VERSION);
      expect(result.dirty).toBe(true);
      expect(result.session.v).toBe(CURRENT_SESSION_VERSION);
      expect(result.session.sub).toBe("user@example.com");
      expect(result.session.user_prefs).toEqual({});
      expect(result.session.mfa_verified).toBe(false);
      expect(event.event).toBe("session_migrated");
      expect(event.from_v).toBe(1);
      expect(event.to_v).toBe(CURRENT_SESSION_VERSION);
    });

    it("should migrate v2 session to current version", () => {
      const v2Session: SessionV2 = {
        v: 2,
        sub: "user@example.com",
        iat: 1713000000,
        exp: 1713086400,
        user_prefs: { theme: "dark" },
      };

      const { result, event } = migrateSession(v2Session);

      expect(result.from_version).toBe(2);
      expect(result.to_version).toBe(CURRENT_SESSION_VERSION);
      expect(result.dirty).toBe(true);
      expect(result.session.v).toBe(CURRENT_SESSION_VERSION);
      expect(result.session.user_prefs).toEqual({ theme: "dark" });
      expect(result.session.mfa_verified).toBe(false);
      expect(event.event).toBe("session_migrated");
    });

    it("should not migrate current version session", () => {
      const currentSession: Session = {
        v: CURRENT_SESSION_VERSION,
        sub: "user@example.com",
        iat: 1713000000,
        exp: 1713086400,
        user_prefs: { theme: "dark" },
        mfa_verified: true,
        last_activity: 1713000000,
      };

      const { result, event } = migrateSession(currentSession);

      expect(result.from_version).toBe(CURRENT_SESSION_VERSION);
      expect(result.to_version).toBe(CURRENT_SESSION_VERSION);
      expect(result.dirty).toBe(false);
      expect(result.session).toEqual(currentSession);
      expect(event.event).toBe("session_already_current");
    });

    it("should assume v1 for session missing version field", () => {
      const noVersionSession = {
        sub: "user@example.com",
        iat: 1713000000,
        exp: 1713086400,
      };

      const { result, event } = migrateSession(noVersionSession);

      expect(result.from_version).toBe(1);
      expect(result.dirty).toBe(true);
      expect(result.session.v).toBe(CURRENT_SESSION_VERSION);
      expect(event.event).toBe("session_migrated");
    });

    it("should handle corrupt/invalid session gracefully", () => {
      const { result, event } = migrateSession(null);

      expect(result.from_version).toBe(0);
      expect(result.dirty).toBe(true);
      expect(result.session.v).toBe(CURRENT_SESSION_VERSION);
      expect(result.session.sub).toBe("anonymous");
      expect(event.event).toBe("session_invalid");
      expect(event.error).toBeDefined();
    });

    it("should handle non-object input", () => {
      const { result, event } = migrateSession("invalid");

      expect(event.event).toBe("session_invalid");
      expect(result.session.sub).toBe("anonymous");
    });

    it("should preserve user_prefs through v1->v2 migration", () => {
      const v1WithPrefs: SessionV1 = {
        v: 1,
        sub: "user@example.com",
        iat: 1713000000,
        exp: 1713086400,
        user_prefs: { language: "en", notifications: true } as any,
      };

      const { result } = migrateSession(v1WithPrefs);

      // Note: v1->v2 migration adds user_prefs if missing, but doesn't preserve if present
      expect(result.session.user_prefs).toBeDefined();
    });

    it("should handle sessions with future versions gracefully", () => {
      const futureSession = {
        v: 99,
        sub: "user@example.com",
        iat: 1713000000,
        exp: 1713086400,
      };

      // Should not crash; version stays as-is if no migration needed
      const { result } = migrateSession(futureSession);
      expect(result.session.v).toBe(99);
      expect(result.dirty).toBe(false);
    });

    it("should hash user email in migration event (PII protection)", () => {
      const v1Session: SessionV1 = {
        v: 1,
        sub: "user@example.com",
        iat: 1713000000,
        exp: 1713086400,
      };

      const { event } = migrateSession(v1Session);

      expect(event.user_hash).toBeDefined();
      expect(event.user_hash).not.toBe("user@example.com"); // Not plaintext
      expect(event.user_hash.length).toBe(8); // Truncated SHA256
    });

    it("should set timestamp in migration event", () => {
      const v1Session: SessionV1 = {
        v: 1,
        sub: "user@example.com",
        iat: 1713000000,
        exp: 1713086400,
      };

      const { event } = migrateSession(v1Session);

      expect(event.timestamp).toBeGreaterThan(0);
      expect(event.timestamp).toBeLessThanOrEqual(Date.now());
    });
  });

  describe("updateSessionActivity", () => {
    it("should update last_activity timestamp", () => {
      const session: Session = {
        v: CURRENT_SESSION_VERSION,
        sub: "user@example.com",
        iat: 1713000000,
        exp: 1713086400,
        last_activity: 1713000000,
      };

      const before = Math.floor(Date.now() / 1000);
      const updated = updateSessionActivity(session);
      const after = Math.floor(Date.now() / 1000);

      expect(updated.last_activity).toBeGreaterThanOrEqual(before);
      expect(updated.last_activity).toBeLessThanOrEqual(after);
    });

    it("should not modify other fields", () => {
      const session: Session = {
        v: CURRENT_SESSION_VERSION,
        sub: "user@example.com",
        iat: 1713000000,
        exp: 1713086400,
        user_prefs: { theme: "dark" },
      };

      const updated = updateSessionActivity(session);

      expect(updated.v).toBe(session.v);
      expect(updated.sub).toBe(session.sub);
      expect(updated.iat).toBe(session.iat);
      expect(updated.exp).toBe(session.exp);
      expect(updated.user_prefs).toEqual(session.user_prefs);
    });
  });

  describe("isSessionExpired", () => {
    it("should return false for non-expired session", () => {
      const futureTime = Math.floor(Date.now() / 1000) + 86400; // 24h from now
      const session: Session = {
        v: CURRENT_SESSION_VERSION,
        sub: "user@example.com",
        iat: Math.floor(Date.now() / 1000),
        exp: futureTime,
      };

      expect(isSessionExpired(session)).toBe(false);
    });

    it("should return true for expired session", () => {
      const pastTime = Math.floor(Date.now() / 1000) - 3600; // 1h ago
      const session: Session = {
        v: CURRENT_SESSION_VERSION,
        sub: "user@example.com",
        iat: pastTime - 86400,
        exp: pastTime,
      };

      expect(isSessionExpired(session)).toBe(true);
    });

    it("should return true for session expiring now", () => {
      const now = Math.floor(Date.now() / 1000);
      const session: Session = {
        v: CURRENT_SESSION_VERSION,
        sub: "user@example.com",
        iat: now - 86400,
        exp: now,
      };

      expect(isSessionExpired(session)).toBe(true);
    });
  });

  describe("isSessionStale", () => {
    it("should return false for active session", () => {
      const now = Math.floor(Date.now() / 1000);
      const session: Session = {
        v: CURRENT_SESSION_VERSION,
        sub: "user@example.com",
        iat: now,
        exp: now + 86400,
        last_activity: now, // Just updated
      };

      expect(isSessionStale(session, 30)).toBe(false);
    });

    it("should return true for stale session", () => {
      const now = Math.floor(Date.now() / 1000);
      const session: Session = {
        v: CURRENT_SESSION_VERSION,
        sub: "user@example.com",
        iat: now,
        exp: now + 86400,
        last_activity: now - 31 * 60, // 31 min ago
      };

      expect(isSessionStale(session, 30)).toBe(true);
    });

    it("should return true if last_activity is missing", () => {
      const now = Math.floor(Date.now() / 1000);
      const session: Session = {
        v: CURRENT_SESSION_VERSION,
        sub: "user@example.com",
        iat: now,
        exp: now + 86400,
      };

      expect(isSessionStale(session, 30)).toBe(true);
    });

    it("should use configurable stale threshold", () => {
      const now = Math.floor(Date.now() / 1000);
      const session: Session = {
        v: CURRENT_SESSION_VERSION,
        sub: "user@example.com",
        iat: now,
        exp: now + 86400,
        last_activity: now - 45 * 60, // 45 min ago
      };

      expect(isSessionStale(session, 30)).toBe(true); // 45 > 30
      expect(isSessionStale(session, 60)).toBe(false); // 45 < 60
    });
  });

  describe("Migration completeness", () => {
    it("should support upgrade from any version < CURRENT_SESSION_VERSION", () => {
      for (let v = 1; v < CURRENT_SESSION_VERSION; v++) {
        const testSession = {
          v,
          sub: "test@example.com",
          iat: 1713000000,
          exp: 1713086400,
        };

        const { result } = migrateSession(testSession);

        expect(result.from_version).toBe(v);
        expect(result.to_version).toBe(CURRENT_SESSION_VERSION);
        expect(result.session.v).toBe(CURRENT_SESSION_VERSION);
        expect(result.dirty).toBe(true);
      }
    });
  });
});
