// @file        apps/backend/src/middleware/__tests__/jwt-auth.test.ts
// @module      middleware/__tests__
// @description Unit tests for JWT auth middleware (jwtAuth, requireJwt, requireGroups)
// @owner       platform
// @status      active
import { describe, it, expect, beforeEach, vi } from 'vitest';
// ── Mocks ─────────────────────────────────────────────────────────────────────
// Mock JwtValidator before importing the middleware
const mockValidateToken = vi.fn();
vi.mock('../services/auth/jwt-validator', () => ({
    JwtValidator: vi.fn(() => ({
        validateToken: mockValidateToken,
    })),
}));
// Import AFTER mocks are defined
const { jwtAuth, requireJwt, requireGroups, requireClaim, logJwt } = await import('../jwt-auth.js');
// ── Helpers ───────────────────────────────────────────────────────────────────
function makeReq(overrides = {}) {
    return {
        path: '/api/test',
        headers: {},
        ...overrides,
    };
}
function makeRes() {
    const json = vi.fn().mockReturnThis();
    const status = vi.fn().mockReturnValue({ json });
    const res = { status, json };
    return { res, json, status };
}
function makeNext() {
    return vi.fn();
}
const validClaims = {
    sub: 'code-server-internal',
    aud: 'code-server',
    iss: 'https://ide.kushnir.cloud',
    iat: Math.floor(Date.now() / 1000) - 60,
    exp: Math.floor(Date.now() / 1000) + 3540,
    groups: ['platform', 'service-account'],
};
// ── jwtAuth ───────────────────────────────────────────────────────────────────
describe('jwtAuth()', () => {
    let mockValidator;
    beforeEach(() => {
        vi.clearAllMocks();
        // Create a mock validator instance with the mocked validateToken method
        mockValidator = {
            validateToken: mockValidateToken,
        };
    });
    it('returns 401 when Authorization header is missing and optional=false', () => {
        const mw = jwtAuth({ audience: 'code-server', validator: mockValidator });
        const req = makeReq();
        const { res, status, json } = makeRes();
        const next = makeNext();
        mw(req, res, next);
        expect(status).toHaveBeenCalledWith(401);
        expect(json).toHaveBeenCalledWith(expect.objectContaining({ error: 'Unauthorized' }));
        expect(next).not.toHaveBeenCalled();
    });
    it('calls next() without token when optional=true', () => {
        const mw = jwtAuth({ audience: 'code-server', optional: true, validator: mockValidator });
        const req = makeReq();
        const { res } = makeRes();
        const next = makeNext();
        mw(req, res, next);
        expect(next).toHaveBeenCalledOnce();
    });
    it('returns 401 for malformed Authorization header', () => {
        const mw = jwtAuth({ audience: 'code-server', validator: mockValidator });
        const req = makeReq({ headers: { authorization: 'NotBearer xyz' } });
        const { res, status, json } = makeRes();
        const next = makeNext();
        mw(req, res, next);
        expect(status).toHaveBeenCalledWith(401);
        expect(json).toHaveBeenCalledWith(expect.objectContaining({ message: expect.stringContaining('format') }));
    });
    it('attaches claims on valid token and calls next()', async () => {
        mockValidateToken.mockResolvedValueOnce(validClaims);
        const mw = jwtAuth({ audience: 'code-server', validator: mockValidator });
        const req = makeReq({ headers: { authorization: 'Bearer valid.token.here' } });
        const { res } = makeRes();
        const next = makeNext();
        mw(req, res, next);
        await vi.waitFor(() => expect(next).toHaveBeenCalledOnce());
        // eslint-disable-next-line @typescript-eslint/no-explicit-any -- test code requires casting to attach custom jwt property
        expect(req.jwt).toMatchObject({ claims: validClaims, token: 'valid.token.here' });
    });
    it('returns 401 when validator throws', async () => {
        mockValidateToken.mockRejectedValueOnce(new Error('Token expired'));
        const mw = jwtAuth({ audience: 'code-server', validator: mockValidator });
        const req = makeReq({ headers: { authorization: 'Bearer expired.token.here' } });
        const { res, status, json } = makeRes();
        const next = makeNext();
        mw(req, res, next);
        await vi.waitFor(() => expect(status).toHaveBeenCalled());
        expect(status).toHaveBeenCalledWith(401);
        expect(json).toHaveBeenCalledWith(expect.objectContaining({ message: expect.stringContaining('Token expired') }));
        expect(next).not.toHaveBeenCalled();
    });
    it('skips validation for excluded routes', () => {
        const mw = jwtAuth({ audience: 'code-server', excludeRoutes: [/^\/health/], validator: mockValidator });
        const req = makeReq({ path: '/health', headers: {} });
        const { res } = makeRes();
        const next = makeNext();
        mw(req, res, next);
        expect(next).toHaveBeenCalledOnce();
        expect(mockValidateToken).not.toHaveBeenCalled();
    });
});
// ── requireJwt ────────────────────────────────────────────────────────────────
describe('requireJwt()', () => {
    it('calls next() when claims are present', () => {
        const mw = requireJwt();
        // eslint-disable-next-line @typescript-eslint/no-explicit-any -- test code requires casting to attach custom jwt property
        const req = makeReq();
        req.jwt = { claims: validClaims, token: 'tok' };
        const { res } = makeRes();
        const next = makeNext();
        mw(req, res, next);
        expect(next).toHaveBeenCalledOnce();
    });
    it('returns 401 when claims are absent', () => {
        const mw = requireJwt();
        const req = makeReq();
        const { res, status, json } = makeRes();
        const next = makeNext();
        mw(req, res, next);
        expect(status).toHaveBeenCalledWith(401);
        expect(json).toHaveBeenCalledWith(expect.objectContaining({ error: 'Unauthorized' }));
        expect(next).not.toHaveBeenCalled();
    });
});
// ── requireGroups ─────────────────────────────────────────────────────────────
describe('requireGroups()', () => {
    it('calls next() when subject is in a required group', () => {
        const mw = requireGroups(['platform']);
        // eslint-disable-next-line @typescript-eslint/no-explicit-any -- test code requires casting to attach custom jwt property
        const req = makeReq();
        req.jwt = { claims: validClaims, token: 'tok' };
        const { res } = makeRes();
        const next = makeNext();
        mw(req, res, next);
        expect(next).toHaveBeenCalledOnce();
    });
    it('returns 403 when subject is not in any required group', () => {
        const mw = requireGroups(['admin']);
        // eslint-disable-next-line @typescript-eslint/no-explicit-any -- test code requires casting to attach custom jwt property
        const req = makeReq();
        req.jwt = { claims: validClaims, token: 'tok' };
        const { res, status, json } = makeRes();
        const next = makeNext();
        mw(req, res, next);
        expect(status).toHaveBeenCalledWith(403);
        expect(json).toHaveBeenCalledWith(expect.objectContaining({ error: 'Forbidden' }));
        expect(next).not.toHaveBeenCalled();
    });
    it('returns 401 when no claims are attached', () => {
        const mw = requireGroups(['platform']);
        const req = makeReq();
        const { res, status } = makeRes();
        const next = makeNext();
        mw(req, res, next);
        expect(status).toHaveBeenCalledWith(401);
    });
});
// ── requireClaim ──────────────────────────────────────────────────────────────
describe('requireClaim()', () => {
    it('calls next() when claim is present', () => {
        const mw = requireClaim('sub');
        // eslint-disable-next-line @typescript-eslint/no-explicit-any -- test code requires casting to attach custom jwt property
        const req = makeReq();
        req.jwt = { claims: validClaims, token: 'tok' };
        const { res } = makeRes();
        const next = makeNext();
        mw(req, res, next);
        expect(next).toHaveBeenCalledOnce();
    });
    it('returns 403 when expected claim value does not match', () => {
        const mw = requireClaim('sub', 'wrong-service');
        // eslint-disable-next-line @typescript-eslint/no-explicit-any -- test code requires casting to attach custom jwt property
        const req = makeReq();
        req.jwt = { claims: validClaims, token: 'tok' };
        const { res, status } = makeRes();
        const next = makeNext();
        mw(req, res, next);
        expect(status).toHaveBeenCalledWith(403);
        expect(next).not.toHaveBeenCalled();
    });
    it('calls next() when claim value matches expected', () => {
        const mw = requireClaim('sub', 'code-server-internal');
        // eslint-disable-next-line @typescript-eslint/no-explicit-any -- test code requires casting to attach custom jwt property
        const req = makeReq();
        req.jwt = { claims: validClaims, token: 'tok' };
        const { res } = makeRes();
        const next = makeNext();
        mw(req, res, next);
        expect(next).toHaveBeenCalledOnce();
    });
});
// ── logJwt ────────────────────────────────────────────────────────────────────
describe('logJwt()', () => {
    it('calls next() and logs claims when present', () => {
        const consoleSpy = vi.spyOn(console, 'log').mockImplementation(() => { });
        const mw = logJwt();
        // eslint-disable-next-line @typescript-eslint/no-explicit-any -- test code requires casting to attach custom jwt property
        const req = makeReq();
        req.jwt = { claims: validClaims, token: 'tok' };
        const { res } = makeRes();
        const next = makeNext();
        mw(req, res, next);
        expect(next).toHaveBeenCalledOnce();
        expect(consoleSpy).toHaveBeenCalledWith(expect.stringContaining('code-server-internal'));
        consoleSpy.mockRestore();
    });
    it('calls next() silently when no claims present', () => {
        const consoleSpy = vi.spyOn(console, 'log').mockImplementation(() => { });
        const mw = logJwt();
        const req = makeReq();
        const { res } = makeRes();
        const next = makeNext();
        mw(req, res, next);
        expect(next).toHaveBeenCalledOnce();
        expect(consoleSpy).not.toHaveBeenCalled();
        consoleSpy.mockRestore();
    });
});
//# sourceMappingURL=jwt-auth.test.js.map