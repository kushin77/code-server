# Caddyfile.tpl — SINGLE SOURCE OF TRUTH
# ========================================
# This is the canonical Caddy configuration template.
# All environment-specific Caddyfile variants are rendered from this file.
#
# Render targets (in Makefile):
#   make render-caddy-prod      → Caddyfile         (production: HTTPS + oauth2)
#   make render-caddy-onprem    → Caddyfile.onprem  (on-prem: HTTP only)
#   make render-caddy-simple    → Caddyfile.simple  (simple: minimal dev)
#
# Environment variables used (set in .env or passed via make):
#   CADDY_TLS_BLOCK       e.g. "tls internal" or "tls /path/cert /path/key"
#   CADDY_DOMAIN          e.g. "ide.kushnir.cloud" or ":80"
#   CODE_SERVER_UPSTREAM  e.g. "code-server:8080" or "oauth2-proxy:4180"
#   CADDY_LOG_LEVEL       e.g. "info" or "debug"
#
# DO NOT edit rendered files (Caddyfile, Caddyfile.onprem) directly.
# Edit this template and re-render.

{
	admin off
	log {
		format json
		output stdout
		level ${CADDY_LOG_LEVEL:-info}
	}

	# Uncomment for public TLS with Let's Encrypt ACME:
	# acme_ca https://acme-v02.api.letsencrypt.org/directory
	# email ops@kushnir.cloud
}

# ─── Security Headers Snippet ────────────────────────────────────────────────
(security_headers) {
	header {
		X-Content-Type-Options    "nosniff"
		X-Frame-Options           "SAMEORIGIN"
		X-XSS-Protection          "1; mode=block"
		Referrer-Policy           "strict-origin-when-cross-origin"
		Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
		Permissions-Policy        "camera=(), microphone=(), geolocation=()"
		Content-Security-Policy   "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval' blob:; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self' wss: ws:; worker-src 'self' blob:; frame-src 'self';"
		-Server
	}
}

# ─── Main Domain ─────────────────────────────────────────────────────────────
${CADDY_DOMAIN:-ide.kushnir.cloud} {
	${CADDY_TLS_BLOCK:-tls internal}

	encode gzip
	import security_headers

	log {
		format json
		output stdout
		level ${CADDY_LOG_LEVEL:-info}
	}

	# Health check endpoints — no auth required
	@health path /healthz /ping /health
	handle @health {
		respond "OK" 200
	}

	# OAuth2 callback — no auth guard required
	@oauth path /oauth2*
	handle @oauth {
		reverse_proxy oauth2-proxy:4180 {
			header_up Host             {upstream_hostport}
			header_up X-Real-IP        {remote_host}
		}
	}

	# Default: all requests route through oauth2-proxy (enforces SSO)
	handle {
		reverse_proxy ${CODE_SERVER_UPSTREAM:-oauth2-proxy:4180} {
			header_up Host             {upstream_hostport}
			header_up X-Real-IP        {remote_host}
			header_up X-Forwarded-Proto {scheme}
			header_up X-Forwarded-For  {remote_host}
			header_up X-Original-URI   {uri}
			flush_interval -1
		}
	}
}

# ─── Monitoring Ports (direct access, no oauth on internal network) ──────────
:${GRAFANA_PORT:-3001} {
	reverse_proxy grafana:3000 {
		header_up Host     {upstream_hostport}
		header_up X-Real-IP {remote_host}
	}
}

:${PROMETHEUS_PORT:-9090} {
	reverse_proxy prometheus:9090 {
		header_up Host     {upstream_hostport}
		header_up X-Real-IP {remote_host}
	}
}

:${ALERTMANAGER_PORT:-9093} {
	reverse_proxy alertmanager:9093 {
		header_up Host     {upstream_hostport}
		header_up X-Real-IP {remote_host}
	}
}

:${JAEGER_PORT:-16686} {
	reverse_proxy jaeger:16686 {
		header_up Host     {upstream_hostport}
		header_up X-Real-IP {remote_host}
	}
}

}

# HTTP to HTTPS redirect (for legacy local deployments)
http://localhost {
    redir https://localhost{uri} permanent
}
