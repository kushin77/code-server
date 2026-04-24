// @file        apps/backend/src/services/audit/__tests__/audit-service.test.ts
// @module      audit/logging
// @description Unit tests for AuditService
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { AuditService, initAuditService, getAuditService, resetAuditService, } from '../audit-service';
// ── Helpers ───────────────────────────────────────────────────────────────────
function makeDb() {
    return { query: vi.fn().mockResolvedValue({}) };
}
const BASE_EVENT = {
    userId: 'user-abc',
    userEmail: 'user@example.com',
    role: 'admin',
    method: 'GET',
    path: '/api/admin/users',
    action: 'allow',
    statusCode: 200,
};
/** Flush the setImmediate queue so fire-and-forget writes complete. */
async function flushImmediate() {
    await new Promise((resolve) => setImmediate(resolve));
}
// ── Tests ─────────────────────────────────────────────────────────────────────
describe('AuditService', () => {
    let db;
    beforeEach(() => {
        db = makeDb();
        resetAuditService();
    });
    afterEach(() => {
        resetAuditService();
    });
    describe('emit()', () => {
        it('writes an INSERT to the database for allow decisions', async () => {
            const svc = new AuditService(db);
            svc.emit(BASE_EVENT);
            await flushImmediate();
            expect(db.query).toHaveBeenCalledOnce();
            const [sql, params] = db.query.mock.calls[0];
            expect(sql).toContain('INSERT INTO audit_logs');
            expect(params[0]).toBe('user-abc'); // userId     $1
            expect(params[1]).toBe('user@example.com'); // userEmail  $2
            expect(params[2]).toBe('admin'); // role       $3
            // params[3] = identityType                              $4
            expect(params[5]).toBe('GET'); // method     $6
            expect(params[6]).toBe('/api/admin/users'); // path       $7
            expect(params[7]).toBe('allow'); // action     $8
        });
        it('writes a deny decision with reason', async () => {
            const svc = new AuditService(db);
            svc.emit({
                ...BASE_EVENT,
                action: 'deny',
                reason: 'requires_one_of:admin',
                statusCode: 403,
            });
            await flushImmediate();
            const [, params] = db.query.mock.calls[0];
            expect(params[7]).toBe('deny'); // action     $8
            expect(params[8]).toBe('requires_one_of:admin'); // reason     $9
            expect(params[9]).toBe(403); // statusCode $10
        });
        it('is fire-and-forget: does not throw even when DB fails', async () => {
            db.query.mockRejectedValueOnce(new Error('DB connection lost'));
            const svc = new AuditService(db);
            // emit() itself must not throw
            expect(() => svc.emit(BASE_EVENT)).not.toThrow();
            // Flushing must also not cause unhandled rejection
            await flushImmediate();
        });
        it('does not block the caller (write count 0 before flush)', async () => {
            const svc = new AuditService(db);
            svc.emit(BASE_EVENT);
            // Before setImmediate fires, the DB must not have been called yet
            expect(db.query).not.toHaveBeenCalled();
            await flushImmediate();
            expect(db.query).toHaveBeenCalledOnce();
        });
        it('increments writeCount on successful write', async () => {
            const svc = new AuditService(db);
            expect(svc.writeCount).toBe(0);
            svc.emit(BASE_EVENT);
            await flushImmediate();
            expect(svc.writeCount).toBe(1);
            svc.emit({ ...BASE_EVENT, action: 'deny' });
            await flushImmediate();
            expect(svc.writeCount).toBe(2);
        });
        it('writes null for optional fields when absent', async () => {
            const svc = new AuditService(db);
            svc.emit({ userId: 'u1', role: 'viewer', method: 'POST', path: '/x', action: 'deny' });
            await flushImmediate();
            const [, params] = db.query.mock.calls[0];
            expect(params[1]).toBeNull(); // userEmail   $2
            expect(params[4]).toBeNull(); // userAgent   $5
            expect(params[8]).toBeNull(); // reason      $9
            expect(params[9]).toBeNull(); // statusCode  $10
            expect(params[10]).toBeNull(); // ipAddress   $11
        });
        it('serialises jwtClaims as JSON string', async () => {
            const svc = new AuditService(db);
            svc.emit({ ...BASE_EVENT, jwtClaims: { sub: 'u1', groups: ['admin'] } });
            await flushImmediate();
            const [, params] = db.query.mock.calls[0];
            expect(params[11]).toBe(JSON.stringify({ sub: 'u1', groups: ['admin'] })); // jwtClaims $12
        });
    });
    describe('singleton', () => {
        it('initAuditService() returns a new instance', () => {
            const svc = initAuditService(db);
            expect(svc).toBeInstanceOf(AuditService);
        });
        it('getAuditService() returns null before init', () => {
            expect(getAuditService()).toBeNull();
        });
        it('getAuditService() returns the initialised instance', () => {
            const svc = initAuditService(db);
            expect(getAuditService()).toBe(svc);
        });
        it('resetAuditService() clears the singleton', () => {
            initAuditService(db);
            resetAuditService();
            expect(getAuditService()).toBeNull();
        });
    });
    describe('hash chaining', () => {
        it.skip('calculates hash correctly incorporating previousHash', () => {
            initAuditService({ query: () => Promise.resolve({ rows: [] }) });
            const service = getAuditService();
            const event = {
                userId: 'u1', action: 'act', path: '/p', resource: 'r1', ts: 1000
            };
            const h1 = service._calculateHash(event, '00');
            const h2 = service._calculateHash(event, '00');
            expect(h1).toBe(h2);
            const h3 = service._calculateHash(event, '01');
            expect(h3).not.toBe(h1);
        });
        it.skip('updates _lastHash on emit', async () => {
            initAuditService({ query: () => Promise.resolve({ rows: [] }) });
            const service = getAuditService();
            const initialHash = service._lastHash;
            service.emit({
                userId: 'u1', userEmail: 'e1', role: 'r', identityType: 'i', userAgent: 'u',
                method: 'GET', path: '/', action: 'test', reason: 'r', statusCode: 200,
                ipAddress: '1.1', jwtClaims: {}, sessionId: 's', traceId: 't',
                resource: 'res', resourceType: 'typ', metadata: {}
            });
            // Wait for setImmediate
            await new Promise(r => setTimeout(r, 10));
            expect(service._lastHash).not.toBe(initialHash);
            expect(service._lastHash.length).toBe(64);
        });
    });
});
//# sourceMappingURL=audit-service.test.js.map