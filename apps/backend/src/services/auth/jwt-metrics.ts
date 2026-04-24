#!/usr/bin/env node
// @file        apps/backend/src/services/auth/jwt-metrics.ts
// @module      services/auth
// @description Prometheus-compatible metrics for JWT service-to-service authentication
// @owner       Infrastructure Team
// @status      ACTIVE

/**
 * Simple Prometheus metrics registry for JWT auth operations.
 *
 * Exposes counters, histograms, and gauges as plain text in Prometheus exposition format.
 * Intentionally dependency-free: uses a lightweight in-process store so this module
 * can be imported without requiring the `prom-client` NPM package.
 */

// ---------------------------------------------------------------------------
// Internal metric store
// ---------------------------------------------------------------------------

/** Labels map */
type Labels = Record<string, string>;

interface CounterEntry {
  type: 'counter';
  help: string;
  values: Map<string, number>;
}

interface HistogramBucket {
  le: number;
  count: number;
}

interface HistogramEntry {
  type: 'histogram';
  help: string;
  buckets: number[]; // upper bounds in milliseconds
  observations: Map<string, { sum: number; count: number; buckets: HistogramBucket[] }>;
}

interface GaugeEntry {
  type: 'gauge';
  help: string;
  values: Map<string, number>;
}

type MetricEntry = CounterEntry | HistogramEntry | GaugeEntry;
const registry: Map<string, MetricEntry> = new Map();

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function labelsKey(labels: Labels): string {
  return Object.entries(labels)
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([k, v]) => `${k}="${v}"`)
    .join(',');
}

function labelsStr(labels: Labels): string {
  const k = labelsKey(labels);
  return k ? `{${k}}` : '';
}

// ---------------------------------------------------------------------------
// Counter
// ---------------------------------------------------------------------------

function registerCounter(name: string, help: string): void {
  if (!registry.has(name)) {
    registry.set(name, { type: 'counter', help, values: new Map() });
  }
}

export function incCounter(name: string, labels: Labels = {}, amount = 1): void {
  const entry = registry.get(name) as CounterEntry | undefined;
  if (!entry) return;
  const key = labelsKey(labels);
  entry.values.set(key, (entry.values.get(key) ?? 0) + amount);
}

// ---------------------------------------------------------------------------
// Histogram
// ---------------------------------------------------------------------------

const DEFAULT_LATENCY_BUCKETS = [1, 5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000];

function registerHistogram(name: string, help: string, buckets = DEFAULT_LATENCY_BUCKETS): void {
  if (!registry.has(name)) {
    registry.set(name, { type: 'histogram', help, buckets, observations: new Map() });
  }
}

export function observeHistogram(name: string, valueMs: number, labels: Labels = {}): void {
  const entry = registry.get(name) as HistogramEntry | undefined;
  if (!entry) return;
  const key = labelsKey(labels);
  if (!entry.observations.has(key)) {
    entry.observations.set(key, {
      sum: 0,
      count: 0,
      buckets: entry.buckets.map((le) => ({ le, count: 0 })),
    });
  }
  const obs = entry.observations.get(key)!;
  obs.sum += valueMs;
  obs.count += 1;
  for (const bucket of obs.buckets) {
    if (valueMs <= bucket.le) bucket.count += 1;
  }
}

// ---------------------------------------------------------------------------
// Gauge
// ---------------------------------------------------------------------------

function registerGauge(name: string, help: string): void {
  if (!registry.has(name)) {
    registry.set(name, { type: 'gauge', help, values: new Map() });
  }
}

export function setGauge(name: string, value: number, labels: Labels = {}): void {
  const entry = registry.get(name) as GaugeEntry | undefined;
  if (!entry) return;
  entry.values.set(labelsKey(labels), value);
}

export function incGauge(name: string, labels: Labels = {}, amount = 1): void {
  const entry = registry.get(name) as GaugeEntry | undefined;
  if (!entry) return;
  const key = labelsKey(labels);
  entry.values.set(key, (entry.values.get(key) ?? 0) + amount);
}

// ---------------------------------------------------------------------------
// Metric definitions
// ---------------------------------------------------------------------------

// Token validation
registerHistogram(
  'jwt_validator_duration_ms',
  'JWT validation duration in milliseconds',
  DEFAULT_LATENCY_BUCKETS,
);
registerCounter('jwt_validations_total', 'Total JWT validation attempts', );
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
  recordValidation(durationMs: number, success: boolean, reason?: string): void {
    incCounter('jwt_validations_total', { result: success ? 'success' : 'failure' });
    observeHistogram('jwt_validator_duration_ms', durationMs, {
      result: success ? 'success' : 'failure',
    });
    if (!success && reason) {
      incCounter('jwt_validation_errors_total', { reason });
    }
  },

  // JWKS cache
  recordJwksCacheHit(): void {
    incCounter('jwt_jwks_cache_hits_total');
  },
  recordJwksCacheMiss(): void {
    incCounter('jwt_jwks_cache_misses_total');
  },
  recordJwksFetch(success: boolean): void {
    incCounter('jwt_jwks_fetch_total');
    if (!success) incCounter('jwt_jwks_fetch_errors_total');
  },

  // Token client
  recordTokenIssued(): void {
    incCounter('jwt_token_issued_total');
  },
  recordTokenRefresh(): void {
    incCounter('jwt_token_refresh_total');
  },
  recordTokenError(reason: string): void {
    incCounter('jwt_token_errors_total', { reason });
  },
  setTokenTtl(seconds: number): void {
    setGauge('jwt_token_ttl_seconds', seconds);
  },

  // Active requests
  startValidation(): void {
    incGauge('jwt_active_validations');
  },
  endValidation(): void {
    incGauge('jwt_active_validations', {}, -1);
  },
};

// ---------------------------------------------------------------------------
// Prometheus text exposition
// ---------------------------------------------------------------------------

/**
 * Render all registered metrics as Prometheus text format (version 0.0.4).
 */
export function renderMetrics(): string {
  const lines: string[] = [];

  for (const [name, entry] of registry) {
    lines.push(`# HELP ${name} ${entry.help}`);
    lines.push(`# TYPE ${name} ${entry.type}`);

    if (entry.type === 'counter' || entry.type === 'gauge') {
      for (const [labelKey, value] of entry.values) {
        const labelPart = labelKey ? `{${labelKey}}` : '';
        lines.push(`${name}${labelPart} ${value}`);
      }
    } else if (entry.type === 'histogram') {
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
export function metricsHandler(
  _req: { path: string },
  res: { setHeader(k: string, v: string): void; status(n: number): { end(s: string): void } },
): void {
  const body = renderMetrics();
  res.setHeader('Content-Type', 'text/plain; version=0.0.4; charset=utf-8');
  res.status(200).end(body);
}
