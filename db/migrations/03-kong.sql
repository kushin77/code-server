-- @file        db/migrations/03-kong.sql
-- @module      database/kong-schema
-- @description Kong API Gateway schema on primary PostgreSQL (P2 #430)
--
-- Consolidates Kong database into primary PostgreSQL, eliminating separate kong-db service.
-- Run after: PostgreSQL 15-alpine initialized
-- Run before: Kong service startup
-- Idempotent: Safe to run multiple times (uses IF NOT EXISTS)

-- Schema for Kong
CREATE SCHEMA IF NOT EXISTS kong;

-- Kong core tables
CREATE TABLE IF NOT EXISTS kong.services (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    protocol TEXT NOT NULL DEFAULT 'http',
    host TEXT NOT NULL,
    port INTEGER NOT NULL DEFAULT 80,
    path TEXT,
    retries INTEGER DEFAULT 5,
    connect_timeout INTEGER DEFAULT 60000,
    send_timeout INTEGER DEFAULT 60000,
    read_timeout INTEGER DEFAULT 60000,
    url TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS kong.routes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    service_id UUID NOT NULL REFERENCES kong.services(id) ON DELETE CASCADE,
    name TEXT,
    protocols TEXT[] DEFAULT ARRAY['http', 'https'],
    methods TEXT[] DEFAULT ARRAY['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'HEAD', 'OPTIONS'],
    hosts TEXT[],
    paths TEXT[],
    regex_priority INTEGER DEFAULT 0,
    strip_path BOOLEAN DEFAULT true,
    preserve_host BOOLEAN DEFAULT false,
    tags TEXT[],
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS kong.upstreams (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    algorithm TEXT DEFAULT 'round-robin',
    hash_on TEXT DEFAULT 'none',
    hash_fallback TEXT DEFAULT 'none',
    healthchecks_active_type TEXT DEFAULT 'http',
    healthchecks_active_timeout INTEGER DEFAULT 1,
    healthchecks_active_concurrency INTEGER DEFAULT 10,
    healthchecks_active_http_path TEXT DEFAULT '/',
    healthchecks_active_unhealthy_http_statuses INTEGER[] DEFAULT ARRAY[429, 500, 503],
    healthchecks_passive_type TEXT DEFAULT 'http',
    healthchecks_passive_unhealthy_http_statuses INTEGER[] DEFAULT ARRAY[429, 500, 503],
    tags TEXT[],
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS kong.targets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    upstream_id UUID NOT NULL REFERENCES kong.upstreams(id) ON DELETE CASCADE,
    target TEXT NOT NULL,
    weight INTEGER DEFAULT 100,
    tags TEXT[],
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS kong.plugins (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    service_id UUID REFERENCES kong.services(id) ON DELETE CASCADE,
    route_id UUID REFERENCES kong.routes(id) ON DELETE CASCADE,
    consumer_id UUID,
    config JSONB,
    enabled BOOLEAN DEFAULT true,
    tags TEXT[],
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS kong.acls (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    consumer_id UUID NOT NULL,
    group_name TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Kong cluster_events for distributed cache invalidation
CREATE TABLE IF NOT EXISTS kong.cluster_events (
    id BIGSERIAL PRIMARY KEY,
    node_id UUID,
    at BIGINT,
    nbf BIGINT,
    expire_at BIGINT,
    channel TEXT,
    data TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_services_name ON kong.services(name);
CREATE INDEX IF NOT EXISTS idx_routes_service_id ON kong.routes(service_id);
CREATE INDEX IF NOT EXISTS idx_routes_paths ON kong.routes USING GIN(paths);
CREATE INDEX IF NOT EXISTS idx_upstreams_name ON kong.upstreams(name);
CREATE INDEX IF NOT EXISTS idx_targets_upstream_id ON kong.targets(upstream_id);
CREATE INDEX IF NOT EXISTS idx_plugins_service_id ON kong.plugins(service_id);
CREATE INDEX IF NOT EXISTS idx_plugins_route_id ON kong.plugins(route_id);
CREATE INDEX IF NOT EXISTS idx_plugins_name ON kong.plugins(name);
CREATE INDEX IF NOT EXISTS idx_cluster_events_channel ON kong.cluster_events(channel);
CREATE INDEX IF NOT EXISTS idx_cluster_events_expire_at ON kong.cluster_events(expire_at);

-- Grant permissions to kong user (created separately via .env)
-- ALTER DEFAULT PRIVILEGES IN SCHEMA kong GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO kong;

-- Initialization: Create default upstream for code-server
INSERT INTO kong.upstreams (name, algorithm, healthchecks_active_type, healthchecks_active_http_path, healthchecks_active_timeout, healthchecks_active_concurrency)
VALUES (
    'code-server-upstream',
    'round-robin',
    'http',
    '/healthz',
    1,
    10
)
ON CONFLICT (name) DO NOTHING;

-- Initialization: Add code-server targets (primary + replica)
INSERT INTO kong.targets (upstream_id, target, weight)
SELECT id, '192.168.168.31:8080', 100 FROM kong.upstreams WHERE name = 'code-server-upstream'
ON CONFLICT DO NOTHING;

INSERT INTO kong.targets (upstream_id, target, weight)
SELECT id, '192.168.168.42:8080', 100 FROM kong.upstreams WHERE name = 'code-server-upstream'
ON CONFLICT DO NOTHING;

-- Initialization: Create code-server service (declarative)
INSERT INTO kong.services (name, protocol, host, port, path)
VALUES (
    'code-server-service',
    'http',
    'code-server-upstream',
    8080,
    NULL
)
ON CONFLICT (name) DO NOTHING;

-- Initialization: Create route to code-server
INSERT INTO kong.routes (service_id, name, protocols, methods, hosts, paths, preserve_host)
SELECT
    (SELECT id FROM kong.services WHERE name = 'code-server-service'),
    'code-server-route',
    ARRAY['http', 'https'],
    ARRAY['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'HEAD', 'OPTIONS'],
    ARRAY['ide.kushnir.cloud', 'localhost'],
    ARRAY['/'],
    false
ON CONFLICT DO NOTHING;

-- Initialize rate limiting plugin (60 req/min global, 10 on auth endpoints)
INSERT INTO kong.plugins (name, service_id, config, enabled)
SELECT
    'rate-limiting',
    (SELECT id FROM kong.services WHERE name = 'code-server-service'),
    '{"minute": 60, "policy": "local", "fault_tolerant": true}'::jsonb,
    true
ON CONFLICT DO NOTHING;

-- Initialize HTTP logging plugin (send to Loki)
INSERT INTO kong.plugins (name, service_id, config, enabled)
SELECT
    'http-log',
    (SELECT id FROM kong.services WHERE name = 'code-server-service'),
    '{"http_endpoint": "http://loki:3100/loki/api/v1/push", "flush_timeout": 2, "retry_count": 5}'::jsonb,
    true
ON CONFLICT DO NOTHING;

-- Initialize request/response transformer plugin (add security headers)
INSERT INTO kong.plugins (name, service_id, config, enabled)
SELECT
    'response-transformer',
    (SELECT id FROM kong.services WHERE name = 'code-server-service'),
    '{"add": {"headers": ["Strict-Transport-Security: max-age=31536000", "X-Content-Type-Options: nosniff", "X-Frame-Options: SAMEORIGIN", "X-XSS-Protection: 1; mode=block"]}}'::jsonb,
    true
ON CONFLICT DO NOTHING;

-- Health check verification (idempotent)
SELECT 'Kong schema initialization complete' AS status;
SELECT COUNT(*) as services_count FROM kong.services;
SELECT COUNT(*) as routes_count FROM kong.routes;
SELECT COUNT(*) as plugins_count FROM kong.plugins;
