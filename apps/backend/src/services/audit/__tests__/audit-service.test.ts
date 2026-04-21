// @file        apps/backend/src/services/audit/__tests__/audit-service.test.ts
// @module      audit/logging
// @description Unit tests for AuditService

import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import {
  AuditService,
  initAuditService,
  getAuditService,
  resetAuditService,
  type AuditDb,
  type AuditEvent,
} from '../audit-service';

// ── Helpers ───────────────────────────────────────────────────────────────────

function makeDb(): AuditDb & { query: ReturnType<typeof vi.fn> } {
  return { query: vi.fn().mockResolvedValue({}) };
}

const BASE_EVENT: AuditEvent = {
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
  await new Promise<void>((resolve) => setImmediate(resolve));
}

// ── Tests ─────────────────────────────────────────────────────────────────────

describe('AuditService', () => {
  let db: AuditDb & { query: ReturnType<typeof vi.fn> };

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
      const [sql, params] = db.query.mock.calls[0] as [string, unknown[]];
      expect(sql).toContain('INSERT INTO audit_logs');
      expect(params[0]).toBe('user-abc');           // userId     $1
      expect(params[1]).toBe('user@example.com');   // userEmail  $2
      expect(params[2]).toBe('admin');              // role       $3
      // params[3] = identityType                              $4
      expect(params[4]).toBe('GET');                // method     $5
      expect(params[5]).toBe('/api/admin/users');   // path       $6
      expect(params[6]).toBe('allow');              // action     $7
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

      const [, params] = db.query.mock.calls[0] as [string, unknown[]];
      expect(params[6]).toBe('deny');                  // action     $7
      expect(params[7]).toBe('requires_one_of:admin'); // reason     $8
      expect(params[8]).toBe(403);                     // statusCode $9
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

      const [, params] = db.query.mock.calls[0] as [string, unknown[]];
      expect(params[1]).toBeNull();  // userEmail  $2
      expect(params[7]).toBeNull();  // reason     $8
      expect(params[8]).toBeNull();  // statusCode $9
      expect(params[9]).toBeNull();  // ipAddress  $10
    });

    it('serialises jwtClaims as JSON string', async () => {
      const svc = new AuditService(db);
      svc.emit({ ...BASE_EVENT, jwtClaims: { sub: 'u1', groups: ['admin'] } });
      await flushImmediate();

      const [, params] = db.query.mock.calls[0] as [string, unknown[]];
      expect(params[10]).toBe(JSON.stringify({ sub: 'u1', groups: ['admin'] })); // jwtClaims $11
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
});
