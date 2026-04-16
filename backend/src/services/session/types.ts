/**
 * Session schema types with version support.
 * When schema changes, increment CURRENT_SESSION_VERSION and add migration function.
 */

/**
 * Current session schema version.
 * Increment when session structure changes.
 * MUST have corresponding migration function in migration registry.
 */
export const CURRENT_SESSION_VERSION = 3;

/**
 * Session data structure (current version).
 * All new fields should be nullable or have defaults for backward compatibility.
 */
export interface Session {
  v: number; // Schema version (CRITICAL: always included)
  sub: string; // User subject (email from OAuth provider)
  iat: number; // Issued at (unix timestamp)
  exp: number; // Expires at (unix timestamp)
  google_id_token?: string; // OAuth2 ID token (opaque)
  user_prefs?: Record<string, unknown>; // User preferences (extensible)
  mfa_verified?: boolean; // MFA verification status (v2+)
  last_activity?: number; // Last activity timestamp (v3+)
}

/**
 * Result of session migration attempt.
 */
export interface MigrationResult {
  session: Session;
  dirty: boolean; // True if session was modified during migration
  from_version: number; // Original version before migration
  to_version: number; // Final version after migration
}

/**
 * Structured logging event for session migration.
 */
export interface SessionMigrationEvent {
  event: "session_migrated" | "session_already_current" | "session_invalid";
  from_v: number;
  to_v: number;
  user_hash: string; // Hash of user identifier (not the actual user ID)
  timestamp: number;
  error?: string; // If session_invalid
}

/**
 * Old session schema versions (for type safety during migration).
 */

export interface SessionV1 {
  v: 1;
  sub: string;
  iat: number;
  exp: number;
  google_id_token?: string;
}

export interface SessionV2 {
  v: 2;
  sub: string;
  iat: number;
  exp: number;
  google_id_token?: string;
  user_prefs?: Record<string, unknown>;
}

export type AnySession = SessionV1 | SessionV2 | Session;
