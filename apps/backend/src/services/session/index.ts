/**
 * Session management module.
 * Provides versioned session schema with transparent server-side migration.
 *
 * @example
 * ```typescript
 * import { migrateSession, updateSessionActivity } from '@/services/session';
 *
 * // In auth middleware:
 * const raw = getSessionFromRedis();
 * const { result, event } = migrateSession(raw);
 * logSessionEvent(event); // Structured logging
 *
 * if (result.dirty) {
 *   // Session was upgraded; save back to Redis with Set-Cookie
 *   setSessionInRedis(result.session);
 *   setCookie(result.session);
 * }
 *
 * // After each request:
 * updateSessionActivity(result.session);
 * ```
 */

export {
  CURRENT_SESSION_VERSION,
  migrateSession,
  updateSessionActivity,
  isSessionExpired,
  isSessionStale,
} from "./migration";

export type {
  Session,
  SessionV1,
  SessionV2,
  AnySession,
  MigrationResult,
  SessionMigrationEvent,
} from "./types";
