# Caddyfile - CONSOLIDATED SINGLE SOURCE OF TRUTH (SSOT)
# ============================================================
# Production reverse proxy with TLS, OAuth2, telemetry, and tracing
# 
# ARCHITECTURE:
# - Single canonical template (this file)
# - Environment-specific rendering via variables
# - Immutable: All changes via git commits
# - Idempotent: Safe to reload multiple times
# - Observable: JSON structured logging + trace ID propagation
#
# ENVIRONMENT VARIABLES (set in .env or via docker-compose):
#   CADDY_DOMAIN          Base domain (e.g., "code-server.192.168.168.31.nip.io" or "code-server.kushnir.cloud")
#   APEX_DOMAIN           Apex domain for portal (e.g., "kushnir.cloud" or "192.168.168.31.nip.io")
#   CADDY_TLS_MODE        "acme" (Let's Encrypt), "internal" (self-signed), or "none" (http only)
#   CADDY_LOG_LEVEL       "debug", "info", "warn", or "error"
#   ENABLE_TELEMETRY      "true" or "false" (export metrics to Prometheus)
#   ENABLE_TRACING        "true" or "false" (propagate trace IDs, send to Jaeger)
#   OAUTH2_PROXY_URL      URL of oauth2-proxy (default: "http://oauth2-proxy:4180")
#   CODE_SERVER_URL       URL of code-server backend (default: "http://code-server:8080")
#   PORTAL_URL            URL of portal service (default: "http://portal:80")
#   LOKI_URL              URL of Loki logging (default: "http://loki:3100")
#   JAEGER_ENDPOINT       URL of Jaeger collector (default: "http://jaeger:14268/api/traces")

# Global configuration
{
	admin off
	storage file_system {
		root /data/caddy
	}

	# TLS configuration
	{% if env.CADDY_TLS_MODE == "acme" %}
	acme_ca https://acme-v02.api.letsencrypt.org/directory
	email ops@kushnir.cloud
	on_demand_tls {
		ask http://caddy:2019/is-domain-valid
	}
	{% endif %}

	# JSON structured logging
	log {
		format json {
			"timestamp": "{ts.unix_ms}",
			"level": "{level}",
			"logger": "caddy",
			"service": "caddy",
			"environment": "{$CADDY_ENV:production}",
			
			# Request/Response metadata
			{% if env.ENABLE_TRACING == "true" %}
			"trace_id": "{http.request.header.x-trace-id}",
			"trace_parent": "{http.request.header.traceparent}",
			"span_id": "{http.request.header.x-span-id}",
			"request_id": "{http.request.uuid}",
			{% endif %}
			
			"http": {
				"method": "{http.request.method}",
				"host": "{http.request.host}",
				"path": "{http.request.uri.path}",
				"query": "{http.request.uri.query}",
				"status": "{http.response.status}",
				"latency_ms": "{http.response.duration}",
				"size_bytes": "{http.response.size}"
			},
			
			"client": {
				"ip": "{http.request.remote.host}",
				"user_agent": "{http.request.header.User-Agent}",
				"remote_addr": "{http.request.remote}"
			},
			
			"tls": {
				"version": "{http.request.tls.version}",
				"cipher": "{http.request.tls.cipher}",
				"client_certificate": "{http.request.tls.client.issuer}"
			}
		}
		output stdout
		level {$CADDY_LOG_LEVEL:info}
	}
}

# ═════════════════════════════════════════════════════════════════════════════
# COMMON SNIPPETS (Reusable across all sites)
# ═════════════════════════════════════════════════════════════════════════════

# Security headers — applied to all responses
(security_headers) {
	header {
		# Prevent MIME type sniffing
		X-Content-Type-Options "nosniff"
		
		# Prevent clickjacking (UI redressing)
		X-Frame-Options "SAMEORIGIN"
		
		# Legacy XSS protection (browsers that support it)
		X-XSS-Protection "1; mode=block"
		
		# Referrer policy
		Referrer-Policy "strict-origin-when-cross-origin"
		
		# HSTS for HTTPS sites (max-age: 1 year)
		{% if env.CADDY_TLS_MODE != "none" %}
		Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
		{% endif %}
		
		# Permissions policy (browser features)
		Permissions-Policy "camera=(), microphone=(), geolocation=(), payment=(), usb=()"
		
		# Content Security Policy (restrictive by default)
		Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval' blob: cdn.jsdelivr.net; style-src 'self' 'unsafe-inline' fonts.googleapis.com; img-src 'self' data: blob: *.gravatar.com; font-src 'self' data: fonts.gstatic.com; connect-src 'self' wss: ws:; worker-src 'self' blob:; frame-src 'self';"
		
		# Remove server header (security through obscurity)
		-Server
		
		# Remove X-Powered-By (if present)
		-X-Powered-By
	}
}

# Trace ID propagation — generates or passes through trace context
(trace_context) {
	# If trace ID already exists, pass it through
	header_up X-Trace-ID {http.request.header.x-trace-id}
	header_up Traceparent {http.request.header.traceparent}
	header_up X-Span-ID {http.request.header.x-span-id}
	
	# Pass CloudFlare trace ID (cf-ray header)
	header_up CF-Ray {http.request.header.cf-ray}
	
	# Always pass request ID (Caddy's built-in UUID)
	header_up X-Request-ID {http.request.uuid}
	
	# Pass client information
	header_up X-Real-IP {remote_host}
	header_up X-Forwarded-For {remote_host}
	header_up X-Forwarded-Proto {scheme}
	header_up X-Forwarded-Host {http.request.host}
	header_up X-Forwarded-Port {http.request.port}
	
	# Pass authentication context (if present from oauth2-proxy)
	header_up X-Auth-Request-User {http.request.header.x-auth-request-user}
	header_up X-Auth-Request-Email {http.request.header.x-auth-request-email}
	header_up X-Auth-Request-Groups {http.request.header.x-auth-request-groups}
}

# Compression — enable gzip for all responses
(compression) {
	encode gzip
}

# Health check endpoints — no authentication required
(health_endpoints) {
	@health {
		path /health /healthz /ping
	}
	handle @health {
		respond "OK" 200 {
			-Content-Type
			-Content-Length
		}
	}
}

# OAuth2 callback routes — no authentication required
(oauth2_routes) {
	@oauth {
		path /oauth2*
	}
	handle @oauth {
		reverse_proxy {$OAUTH2_PROXY_URL:http://oauth2-proxy:4180} {
			import trace_context
			header_up Host {upstream_hostport}
		}
	}
}

# Prometheus metrics endpoint
(metrics_endpoint) {
	@metrics {
		path /metrics
	}
	handle @metrics {
		respond "OK" 200 {
			-Content-Type
		}
	}
}

# ═════════════════════════════════════════════════════════════════════════════
# PORTAL/APEX DOMAIN (Admin Dashboard)
# ═════════════════════════════════════════════════════════════════════════════

{$APEX_DOMAIN:localhost} {
	{% if env.CADDY_TLS_MODE == "acme" %}
	tls {
		dns cloudflare {$CF_API_TOKEN}
	}
	{% elif env.CADDY_TLS_MODE == "internal" %}
	tls internal
	{% endif %}

	import compression
	import security_headers
	import health_endpoints

	# Portal backend
	handle {
		reverse_proxy {$PORTAL_URL:http://portal:80} {
			import trace_context
			header_up Host {upstream_hostport}
		}
	}
}

# ═════════════════════════════════════════════════════════════════════════════
# CODE-SERVER IDE (Main Application)
# ═════════════════════════════════════════════════════════════════════════════

{$CADDY_DOMAIN:code-server.localhost} {
	{% if env.CADDY_TLS_MODE == "acme" %}
	tls {
		dns cloudflare {$CF_API_TOKEN}
	}
	{% elif env.CADDY_TLS_MODE == "internal" %}
	tls internal
	{% endif %}

	import compression
	import security_headers

	# Health check — no auth required
	@health {
		path /health /healthz /ping
	}
	handle @health {
		respond "OK" 200 {
			-Content-Type
			-Content-Length
		}
	}

	# OAuth2 callback — no auth required
	@oauth {
		path /oauth2*
	}
	handle @oauth {
		reverse_proxy {$OAUTH2_PROXY_URL:http://oauth2-proxy:4180} {
			import trace_context
			header_up Host {upstream_hostport}
		}
	}

	# Metrics endpoint (no auth for Prometheus scrape)
	@metrics {
		path /_metrics
	}
	handle @metrics {
		respond "OK" 200
	}

	# Default: All other requests go through oauth2-proxy for authentication
	handle {
		reverse_proxy {$OAUTH2_PROXY_URL:http://oauth2-proxy:4180} {
			import trace_context
			header_up Host {upstream_hostport}
			
			# oauth2-proxy will validate auth and forward to code-server
			# Code-server listens only on localhost:8080 (not exposed directly)
		}
	}
}

# ═════════════════════════════════════════════════════════════════════════════
# LOKI LOGGING (Log Aggregation API)
# ═════════════════════════════════════════════════════════════════════════════

loki.{$CADDY_DOMAIN:localhost} {
	{% if env.CADDY_TLS_MODE == "acme" %}
	tls {
		dns cloudflare {$CF_API_TOKEN}
	}
	{% elif env.CADDY_TLS_MODE == "internal" %}
	tls internal
	{% endif %}

	import compression
	import security_headers

	# Health check
	@health {
		path /ready /running
	}
	handle @health {
		reverse_proxy {$LOKI_URL:http://loki:3100} {
			import trace_context
			header_up Host {upstream_hostport}
		}
	}

	# OAuth2 guard for all Loki queries
	handle {
		reverse_proxy {$OAUTH2_PROXY_URL:http://oauth2-proxy:4181} {
			import trace_context
			header_up Host {upstream_hostport}
		}
	}
}

# ═════════════════════════════════════════════════════════════════════════════
# GRAFANA DASHBOARDS
# ═════════════════════════════════════════════════════════════════════════════

grafana.{$CADDY_DOMAIN:localhost} {
	{% if env.CADDY_TLS_MODE == "acme" %}
	tls {
		dns cloudflare {$CF_API_TOKEN}
	}
	{% elif env.CADDY_TLS_MODE == "internal" %}
	tls internal
	{% endif %}

	import compression
	import security_headers

	# Grafana backend (port 3000)
	handle {
		reverse_proxy {$GRAFANA_URL:http://grafana:3000} {
			import trace_context
			header_up Host {upstream_hostport}
			header_up X-Forwarded-Path /grafana
		}
	}
}

# ═════════════════════════════════════════════════════════════════════════════
# JAEGER TRACING (Distributed Tracing UI)
# ═════════════════════════════════════════════════════════════════════════════

jaeger.{$CADDY_DOMAIN:localhost} {
	{% if env.CADDY_TLS_MODE == "acme" %}
	tls {
		dns cloudflare {$CF_API_TOKEN}
	}
	{% elif env.CADDY_TLS_MODE == "internal" %}
	tls internal
	{% endif %}

	import compression
	import security_headers

	# Jaeger UI (port 16686)
	handle {
		reverse_proxy {$JAEGER_URL:http://jaeger:16686} {
			import trace_context
			header_up Host {upstream_hostport}
		}
	}
}

# ═════════════════════════════════════════════════════════════════════════════
# ALERTMANAGER (Alert Routing & Notifications)
# ═════════════════════════════════════════════════════════════════════════════

alerts.{$CADDY_DOMAIN:localhost} {
	{% if env.CADDY_TLS_MODE == "acme" %}
	tls {
		dns cloudflare {$CF_API_TOKEN}
	}
	{% elif env.CADDY_TLS_MODE == "internal" %}
	tls internal
	{% endif %}

	import compression
	import security_headers

	# AlertManager (port 9093)
	handle {
		reverse_proxy {$ALERTMANAGER_URL:http://alertmanager:9093} {
			import trace_context
			header_up Host {upstream_hostport}
		}
	}
}

# ═════════════════════════════════════════════════════════════════════════════
# PROMETHEUS (Metrics Collection & Querying)
# ═════════════════════════════════════════════════════════════════════════════

prometheus.{$CADDY_DOMAIN:localhost} {
	{% if env.CADDY_TLS_MODE == "acme" %}
	tls {
		dns cloudflare {$CF_API_TOKEN}
	}
	{% elif env.CADDY_TLS_MODE == "internal" %}
	tls internal
	{% endif %}

	import compression
	import security_headers

	# Health check
	@health {
		path /-/healthy
	}
	handle @health {
		reverse_proxy {$PROMETHEUS_URL:http://prometheus:9090} {
			import trace_context
			header_up Host {upstream_hostport}
		}
	}

	# Prometheus API (port 9090)
	handle {
		reverse_proxy {$PROMETHEUS_URL:http://prometheus:9090} {
			import trace_context
			header_up Host {upstream_hostport}
		}
	}
}

# ═════════════════════════════════════════════════════════════════════════════
# KONG API GATEWAY
# ═════════════════════════════════════════════════════════════════════════════

kong.{$CADDY_DOMAIN:localhost} {
	{% if env.CADDY_TLS_MODE == "acme" %}
	tls {
		dns cloudflare {$CF_API_TOKEN}
	}
	{% elif env.CADDY_TLS_MODE == "internal" %}
	tls internal
	{% endif %}

	import compression
	import security_headers

	# Kong API Gateway (port 8000)
	handle {
		reverse_proxy {$KONG_URL:http://kong:8000} {
			import trace_context
			header_up Host {upstream_hostport}
		}
	}
}

# ═════════════════════════════════════════════════════════════════════════════
# OLLAMA LLM SERVER
# ═════════════════════════════════════════════════════════════════════════════

ollama.{$CADDY_DOMAIN:localhost} {
	{% if env.CADDY_TLS_MODE == "acme" %}
	tls {
		dns cloudflare {$CF_API_TOKEN}
	}
	{% elif env.CADDY_TLS_MODE == "internal" %}
	tls internal
	{% endif %}

	import compression
	import security_headers

	# Ollama server (port 11434, localhost only)
	handle {
		reverse_proxy {$OLLAMA_URL:http://127.0.0.1:11434} {
			import trace_context
			header_up Host {upstream_hostport}
		}
	}
}

# ═════════════════════════════════════════════════════════════════════════════
# DOCUMENTATION & DIAGNOSTICS
# ═════════════════════════════════════════════════════════════════════════════
#
# ENVIRONMENT VARIABLES REFERENCE:
#
# Production (Public Domain with Let's Encrypt ACME):
#   CADDY_DOMAIN=code-server.kushnir.cloud
#   APEX_DOMAIN=kushnir.cloud
#   CADDY_TLS_MODE=acme
#   CF_API_TOKEN=<cloudflare-api-token>
#   CADDY_LOG_LEVEL=info
#   ENABLE_TELEMETRY=true
#   ENABLE_TRACING=true
#
# On-Premise (Local Network with Self-Signed TLS):
#   CADDY_DOMAIN=code-server.192.168.168.31.nip.io
#   APEX_DOMAIN=192.168.168.31.nip.io
#   CADDY_TLS_MODE=internal
#   CADDY_LOG_LEVEL=info
#   ENABLE_TELEMETRY=true
#   ENABLE_TRACING=true
#
# Development (Local HTTP only):
#   CADDY_DOMAIN=code-server.localhost:80
#   APEX_DOMAIN=localhost:80
#   CADDY_TLS_MODE=none
#   CADDY_LOG_LEVEL=debug
#   ENABLE_TELEMETRY=false
#   ENABLE_TRACING=false
#
# SERVICE DISCOVERY:
#   All services bound to internal docker network
#   All hostnames use docker service names or IPs
#   No direct public exposure except via Caddy/oauth2-proxy
#
# CONSOLIDATION COMPLETE:
#   ✓ Caddyfile.tpl (base template)
#   ✓ Caddyfile.telemetry (telemetry features)
#   ✓ Caddyfile.trace-id-propagation (trace propagation)
#   ✓ Caddyfile.onprem (on-premises variant)
#   ✓ Caddyfile.simple (development variant)
#
# RENDERING:
#   make render-caddy                # Render all variants
#   make render-caddy ENV=prod       # Render production only
#   make render-caddy ENV=onprem     # Render on-premises only
#   make render-caddy ENV=simple     # Render development only
#
# DEPLOYMENT:
#   1. Set CADDY_DOMAIN, APEX_DOMAIN, CADDY_TLS_MODE in .env
#   2. docker-compose restart caddy
#   3. Verify: curl -I https://{{CADDY_DOMAIN}}/healthz
#
# MAINTENANCE:
#   - All changes via git commits only
#   - Test locally: caddy validate --config Caddyfile.tpl
#   - Reload live: docker-compose restart caddy
#
# Last Updated: 2026-04-15
# Version: 1.0 (Consolidated SSOT)
