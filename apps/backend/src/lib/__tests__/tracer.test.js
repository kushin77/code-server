/**
 * @file        backend/src/lib/__tests__/tracer.test.ts
 * @module      tracer.test
 * @description Unit tests for tracer initialization and middleware.
 */
import { vi, afterEach, describe, it, expect } from 'vitest';
vi.mock('@opentelemetry/api', () => ({
    trace: {
        getActiveSpan: vi.fn(),
    },
    context: {},
    SpanStatusCode: { ERROR: 2, OK: 1, UNSET: 0 },
}));
import { tracingMiddleware, errorTracingMiddleware, getCurrentTraceContext } from '../../middleware/tracing';
import { trace, SpanStatusCode } from '@opentelemetry/api';
const mockGetActiveSpan = trace.getActiveSpan;
const makeReq = () => ({ url: '/api/test' });
const makeRes = () => {
    const headers = {};
    const locals = {};
    return {
        headers,
        locals,
        setHeader: vi.fn((k, v) => { headers[k] = v; }),
    };
};
const makeNext = () => vi.fn();
describe('tracingMiddleware', () => {
    afterEach(() => vi.clearAllMocks());
    it('injects X-Trace-Id and X-Span-Id headers when span is active', () => {
        mockGetActiveSpan.mockReturnValue({
            spanContext: () => ({ traceId: 'abc123', spanId: 'def456' }),
        });
        const req = makeReq();
        const res = makeRes();
        const next = makeNext();
        tracingMiddleware(req, res, next);
        expect(res.headers['X-Trace-Id']).toBe('abc123');
        expect(res.headers['X-Span-Id']).toBe('def456');
        expect(res.locals['traceId']).toBe('abc123');
        expect(res.locals['spanId']).toBe('def456');
        expect(next).toHaveBeenCalledTimes(1);
    });
    it('skips header injection when no active span', () => {
        mockGetActiveSpan.mockReturnValue(undefined);
        const req = makeReq();
        const res = makeRes();
        const next = makeNext();
        tracingMiddleware(req, res, next);
        expect(res.headers['X-Trace-Id']).toBeUndefined();
        expect(next).toHaveBeenCalledTimes(1);
    });
});
describe('errorTracingMiddleware', () => {
    afterEach(() => vi.clearAllMocks());
    it('records exception and sets ERROR status on active span', () => {
        const mockSpan = {
            setStatus: vi.fn(),
            recordException: vi.fn(),
            spanContext: () => ({ traceId: 'aaa', spanId: 'bbb' }),
        };
        mockGetActiveSpan.mockReturnValue(mockSpan);
        const err = new Error('test error');
        const req = makeReq();
        const res = makeRes();
        const next = makeNext();
        errorTracingMiddleware(err, req, res, next);
        expect(mockSpan.setStatus).toHaveBeenCalledWith({ code: SpanStatusCode.ERROR, message: 'test error' });
        expect(mockSpan.recordException).toHaveBeenCalledWith(err);
        expect(next).toHaveBeenCalledWith(err);
    });
    it('passes error to next even when no active span', () => {
        mockGetActiveSpan.mockReturnValue(undefined);
        const err = new Error('no span');
        const next = makeNext();
        errorTracingMiddleware(err, makeReq(), makeRes(), next);
        expect(next).toHaveBeenCalledWith(err);
    });
});
describe('getCurrentTraceContext', () => {
    afterEach(() => vi.clearAllMocks());
    it('returns traceId and spanId when span is active', () => {
        mockGetActiveSpan.mockReturnValue({
            spanContext: () => ({ traceId: 'trace-1', spanId: 'span-1' }),
        });
        const result = getCurrentTraceContext();
        expect(result).toEqual({ traceId: 'trace-1', spanId: 'span-1' });
    });
    it('returns undefined when no span is active', () => {
        mockGetActiveSpan.mockReturnValue(undefined);
        expect(getCurrentTraceContext()).toBeUndefined();
    });
});
//# sourceMappingURL=tracer.test.js.map