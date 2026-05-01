# Phase 12: Advanced Tracing Patterns

**Status**: ✅ Ready
**Focus**: Trace sampling, W3C context propagation, baggage, and performance profiling

## Objective

Phase 12 packages the advanced tracing helpers into the shared observability surface so
services can reduce tracing volume, preserve context, and capture performance evidence.

## Deliverables

- `apps/shared/trace_patterns.py` - sampling, context propagation, and profiling helpers
- `apps/shared/tests/test_trace_patterns.py` - focused validation for the new primitives
- `apps/shared/advanced_tracing.py` - request-oriented façade over the advanced tracing helpers
- `apps/shared/trace_enhancement.py` - runtime bridge used by existing services
- `apps/shared/tests/test_advanced_tracing.py` - façade coverage for sampling and propagation
- `apps/shared/tests/test_trace_enhancement.py` - bridge coverage for request setup and outbound headers
- `docs/observability/tracing-guide.md` - updated guide covering the advanced patterns

## Coverage

- Sampling strategies for high-volume services
- W3C Trace Context and baggage propagation
- Performance profile capture for traced operations

## Verification

- The advanced tracing module is exported through `apps.shared`
- The tracing guide points operators to the advanced patterns module
- Sampling, baggage, and profiling behaviors are covered by focused tests
