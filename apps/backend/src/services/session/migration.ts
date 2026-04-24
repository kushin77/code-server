/**
 * Session migration registry and logic.
 * Handles transparent version upgrades for session payloads.
 */

import { CURRENT_SESSION_VERSION, Session, SessionV1, SessionV2, AnySession, MigrationResult, SessionMigrationEvent } from "./types";
import crypto from "crypto";

/**
 * Migration functions from version N to version N+1.
 * Key must equal source version (e.g., 1 migrates v1->v2, 2 migrates v2->v3).
 */
const MIGRATIONS: Record<number, (session: any) => any> = {
  // V1 -> V2: Add user_prefs field
  1: (session: SessionV1): SessionV2 => ({
    ...session,
    v: 2,
    user_prefs: session.user_prefs || {},
  }),

  // V2 -> V3: Add mfa_verified and last_activity fields
  2: (session: SessionV2): Session => ({
    ...session,
    v: 3,
    mfa_verified: session.mfa_verified ?? false,
    last_activity: session.last_activity ?? session.iat,
  }),
};

/**
 * Migrate a session from any version to CURRENT_SESSION_VERSION.
 * Returns the migrated session, a dirty flag, and event for logging.
 *
 * @param raw Raw session object (may be old version or corrupt)
 * @returns MigrationResult with session, dirty flag, and version info
 */
export function migrateSession(raw: unknown): {
  result: MigrationResult;
  event: SessionMigrationEvent;
} {
  let session: any;
  let dirty = false;
  let fromVersion = 1; // Default to v1 if no version field

  // Validate input is an object
  if (!raw || typeof raw !== "object") {
    return {
      result: {
        session: createDefaultSession(),
        dirty: true,
        from_version: 0,
        to_version: CURRENT_SESSION_VERSION,
      },
      event: {
        event: "session_invalid",
        from_v: 0,
        to_v: CURRENT_SESSION_VERSION,
        user_hash: "unknown",
        timestamp: Date.now(),
        error: "Input is not a valid object",
      },
    };
  }

  session = raw;

  // Determine starting version
  if (typeof session.v === "number" && session.v > 0) {
    fromVersion = session.v;
  } else {
    // No version field; assume v1 and mark dirty
    dirty = true;
    fromVersion = 1;
    session = { ...session, v: 1 };
  }

  // If already at current version, no migration needed
  if (fromVersion === CURRENT_SESSION_VERSION) {
    return {
      result: {
        session: session as Session,
        dirty: false,
        from_version: fromVersion,
        to_version: CURRENT_SESSION_VERSION,
      },
      event: {
        event: "session_already_current",
        from_v: fromVersion,
        to_v: CURRENT_SESSION_VERSION,
        user_hash: hashUser(session.sub || "unknown"),
        timestamp: Date.now(),
      },
    };
  }

  // Run migrations from current version to CURRENT_SESSION_VERSION
  while (session.v < CURRENT_SESSION_VERSION) {
    const currentVersion = session.v;
    const migrator = MIGRATIONS[currentVersion];

    if (!migrator) {
      // Missing migration function is a critical error
      throw new Error(
        `No migration function for version ${currentVersion}. ` +
        `Cannot upgrade session from v${currentVersion} to v${CURRENT_SESSION_VERSION}.`
      );
    }

    session = migrator(session);
    dirty = true;
  }

  return {
    result: {
      session: session as Session,
      dirty,
      from_version: fromVersion,
      to_version: CURRENT_SESSION_VERSION,
    },
    event: {
      event: "session_migrated",
      from_v: fromVersion,
      to_v: CURRENT_SESSION_VERSION,
      user_hash: hashUser(session.sub || "unknown"),
      timestamp: Date.now(),
    },
  };
}

/**
 * Create a default (minimal valid) session.
 * Used when session is corrupt or missing.
 */
function createDefaultSession(): Session {
  const now = Math.floor(Date.now() / 1000);
  return {
    v: CURRENT_SESSION_VERSION,
    sub: "anonymous",
    iat: now,
    exp: now + 86400, // 24h default
    user_prefs: {},
    mfa_verified: false,
    last_activity: now,
  };
}

/**
 * Hash a user identifier for logging (PII protection).
 */
function hashUser(sub: string): string {
  if (!sub || sub === "anonymous") {
    return "anonymous";
  }
  return crypto.createHash("sha256").update(sub).digest("hex").substring(0, 8);
}

/**
 * Update last_activity timestamp on session.
 * Called after each successful request.
 */
export function updateSessionActivity(session: Session): Session {
  return {
    ...session,
    last_activity: Math.floor(Date.now() / 1000),
  };
}

/**
 * Check if session is expired.
 */
export function isSessionExpired(session: Session): boolean {
  return session.exp <= Math.floor(Date.now() / 1000);
}

/**
 * Check if session is stale (last activity > X minutes).
 * Default: 30 minutes.
 */
export function isSessionStale(session: Session, staleAfterMinutes = 30): boolean {
  if (!session.last_activity) {
    return true;
  }
  const staleThreshold = Math.floor(Date.now() / 1000) - staleAfterMinutes * 60;
  return session.last_activity < staleThreshold;
}
