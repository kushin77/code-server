// @file        apps/backend/src/services/audit/audit-service.ts
// @module      audit/logging
// @description Immutable append-only audit logging for RBAC authorization decisions.
//              Writes are fire-and-forget (never block the request path).
import { getLogger } from '../../lib/logger.js';
const logger = getLogger('AuditService');
// ── Service ───────────────────────────────────────────────────────────────────
const INSERT_SQL = `
  INSERT INTO audit_logs (
    user_id, user_email, role, identity_type, user_agent,
    method, path, action, reason, status_code,
    ip_address, jwt_claims, session_id, trace_id
  ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14)
`;
export class AuditService {
    constructor(db) {
        /** In-flight write count — used in tests to assert flush happened. */
        this._writeCount = 0;
        this.db = db;
    }
    /**
     * Emit an audit event. Fire-and-forget: never throws, never blocks the
     * caller. Any DB error is caught and logged internally.
     */
    emit(event) {
        // Schedule write outside the current call stack so the request handler
        // returns immediately. setImmediate gives DB writes the lowest priority.
        setImmediate(() => {
            this._write(event).catch((err) => {
                logger.error('Audit write failed (non-critical)', {
                    error: err instanceof Error ? err.message : String(err),
                    userId: event.userId,
                    action: event.action,
                    path: event.path,
                });
            });
        });
    }
    async _write(event) {
        await this.db.query(INSERT_SQL, [
            event.userId, // [0]  user_id
            event.userEmail ?? null, // [1]  user_email
            event.role, // [2]  role
            event.identityType ?? 'human', // [3]  identity_type
            event.userAgent ?? null, // [4]  user_agent
            event.method, // [5]  method
            event.path, // [6]  path
            event.action, // [7]  action
            event.reason ?? null, // [8]  reason
            event.statusCode ?? null, // [9]  status_code
            event.ipAddress ?? null, // [10] ip_address
            event.jwtClaims ? JSON.stringify(event.jwtClaims) : null, // [11] jwt_claims
            event.sessionId ?? null, // [12] session_id
            event.traceId ?? null, // [13] trace_id
        ]);
        this._writeCount++;
    }
    /** Exposed for testing — number of successful DB writes so far. */
    get writeCount() {
        return this._writeCount;
    }
}
// ── Singleton ─────────────────────────────────────────────────────────────────
let _instance = null;
/**
 * Initialise the singleton. Call once at app startup with a live DB pool.
 */
export function initAuditService(db) {
    _instance = new AuditService(db);
    return _instance;
}
/**
 * Return the singleton, or null if not yet initialised.
 * Returns null instead of throwing so that routes/middleware can call this
 * without crashing when audit is not configured (e.g. in unit tests that
 * don't boot the full app).
 */
export function getAuditService() {
    return _instance;
}
/** Reset singleton — used in tests. */
export function resetAuditService() {
    _instance = null;
}
//# sourceMappingURL=audit-service.js.map