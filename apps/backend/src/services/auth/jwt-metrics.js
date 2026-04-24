#!/usr/bin/env node
// @file        apps/backend/src/services/auth/jwt-metrics.ts
// @module      services/auth
// @description Prometheus-compatible metrics for JWT service-to-service authentication
// @owner       Infrastructure Team
// @status      ACTIVE
const registry = new Map();
// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
function labelsKey(labels) {
    return Object.entries(labels)
        .sort(([a], [b]) => a.localeCompare(b))
        .map(([k, v]) => `${k}="${v}"`)
        .join(',');
}
function labelsStr(labels) {
    const k = labelsKey(labels);
    return k ? `{${k}}` : '';
}
// ---------------------------------------------------------------------------
// Counter
// ---------------------------------------------------------------------------
function registerCounter(name, help) {
    if (!registry.has(name)) {
        registry.set(name, { type: 'counter', help, values: new Map() });
    }
}
export function incCounter(name, labels = {}, amount = 1) {
    const entry = registry.get(name);
    if (!entry)
        return;
    const key = labelsKey(labels);
    entry.values.set(key, (entry.values.get(key) ?? 0) + amount);
}
// ---------------------------------------------------------------------------
// Histogram
// ---------------------------------------------------------------------------
const DEFAULT_LATENCY_BUCKETS = [1, 5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000];
function registerHistogram(name, help, buckets = DEFAULT_LATENCY_BUCKETS) {
    if (!registry.has(name)) {
        registry.set(name, { type: 'histogram', help, buckets, observations: new Map() });
    }
}
export function observeHistogram(name, valueMs, labels = {}) {
    const entry = registry.get(name);
    if (!entry)
        return;
    const key = labelsKey(labels);
    if (!entry.observations.has(key)) {
        entry.observations.set(key, {
            sum: 0,
            count: 0,
            buckets: entry.buckets.map((le) => ({ le, count: 0 })),
        });
    }
    const obs = entry.observations.get(key);
    obs.sum += valueMs;
    obs.count += 1;
    for (const bucket of obs.buckets) {
        if (valueMs <= bucket.le)
            bucket.count += 1;
    }
}
// ---------------------------------------------------------------------------
// Gauge
// ---------------------------------------------------------------------------
function registerGauge(name, help) {
    if (!registry.has(name)) {
        registry.set(name, { type: 'gauge', help, values: new Map() });
    }
}
export function setGauge(name, value, labels = {}) {
    const entry = registry.get(name);
    if (!entry)
        return;
    entry.values.set(labelsKey(labels), value);
}
export function incGauge(name, labels = {}, amount = 1) {
    const entry = registry.get(name);
    if (!entry)
        return;
    const key = labelsKey(labels);
    entry.values.set(key, (entry.values.get(key) ?? 0) + amount);
}
// ---------------------------------------------------------------------------
// Metric definitions
// ---------------------------------------------------------------------------
// Token validation
registerHistogram('jwt_validator_duration_ms', 'JWT validation duration in milliseconds', DEFAULT_LATENCY_BUCKETS);
registerCounter('jwt_validations_total', 'Total JWT validation attempts');
registerCounter('jwt_validation_errors_total', 'Total JWT validation failures by reason');
// JWKS cache
registerCounter('jwt_jwks_cache_hits_total', 'JWKS cache hits');
registerCounter('jwt_jwks_cache_misses_total', 'JWKS cache misses');
registerCounter('jwt_jwks_fetch_total', 'JWKS endpoint fetches');
registerCounter('jwt_jwks_fetch_errors_total', 'JWKS fetch failures');
// Token client
registerCounter('jwt_token_issued_total', 'Tokens acquired from issuer');
registerCounter('jwt_token_refresh_total', 'Proactive token refreshes');
registerCounter('jwt_token_errors_total', 'Token acquisition errors');
registerGauge('jwt_token_ttl_seconds', 'Remaining TTL of the cached service token');
// Active requests
registerGauge('jwt_active_validations', 'In-flight JWT validation operations');
// ---------------------------------------------------------------------------
// Named convenience functions (avoids magic-string callers)
// ---------------------------------------------------------------------------
export const jwtMetrics = {
    // Validation
    recordValidation(durationMs, success, reason) {
        incCounter('jwt_validations_total', { result: success ? 'success' : 'failure' });
        observeHistogram('jwt_validator_duration_ms', durationMs, {
            result: success ? 'success' : 'failure',
        });
        if (!success && reason) {
            incCounter('jwt_validation_errors_total', { reason });
        }
    },
    // JWKS cache
    recordJwksCacheHit() {
        incCounter('jwt_jwks_cache_hits_total');
    },
    recordJwksCacheMiss() {
        incCounter('jwt_jwks_cache_misses_total');
    },
    recordJwksFetch(success) {
        incCounter('jwt_jwks_fetch_total');
        if (!success)
            incCounter('jwt_jwks_fetch_errors_total');
    },
    // Token client
    recordTokenIssued() {
        incCounter('jwt_token_issued_total');
    },
    recordTokenRefresh() {
        incCounter('jwt_token_refresh_total');
    },
    recordTokenError(reason) {
        incCounter('jwt_token_errors_total', { reason });
    },
    setTokenTtl(seconds) {
        setGauge('jwt_token_ttl_seconds', seconds);
    },
    // Active requests
    startValidation() {
        incGauge('jwt_active_validations');
    },
    endValidation() {
        incGauge('jwt_active_validations', {}, -1);
    },
};
// ---------------------------------------------------------------------------
// Prometheus text exposition
// ---------------------------------------------------------------------------
/**
 * Render all registered metrics as Prometheus text format (version 0.0.4).
 */
export function renderMetrics() {
    const lines = [];
    for (const [name, entry] of registry) {
        lines.push(`# HELP ${name} ${entry.help}`);
        lines.push(`# TYPE ${name} ${entry.type}`);
        if (entry.type === 'counter' || entry.type === 'gauge') {
            for (const [labelKey, value] of entry.values) {
                const labelPart = labelKey ? `{${labelKey}}` : '';
                lines.push(`${name}${labelPart} ${value}`);
            }
        }
        else if (entry.type === 'histogram') {
            for (const [labelKey, obs] of entry.observations) {
                const prefix = labelKey ? `,${labelKey}` : '';
                for (const bucket of obs.buckets) {
                    lines.push(`${name}_bucket{le="${bucket.le}"${prefix}} ${bucket.count}`);
                }
                lines.push(`${name}_bucket{le="+Inf"${prefix}} ${obs.count}`);
                lines.push(`${name}_sum${labelKey ? `{${labelKey}}` : ''} ${obs.sum}`);
                lines.push(`${name}_count${labelKey ? `{${labelKey}}` : ''} ${obs.count}`);
            }
        }
        lines.push('');
    }
    return lines.join('\n');
}
/**
 * Express route handler that serves Prometheus metrics.
 *
 * Mount on /metrics or a dedicated port before JWT middleware.
 *
 * @example
 *   import { metricsHandler } from './jwt-metrics';
 *   app.get('/metrics', metricsHandler);
 */
export function metricsHandler(_req, res) {
    const body = renderMetrics();
    res.setHeader('Content-Type', 'text/plain; version=0.0.4; charset=utf-8');
    res.status(200).end(body);
}
//# sourceMappingURL=jwt-metrics.js.map