# @file config/caddy/Caddyfile.tpl
# @description Caddy reverse proxy gateway configuration template
# @governance GOV-002 - All domains are variables, no hardcoding
# @automation Generated from template using scripts/ops/generate-caddy-config.sh
# @requirements: APEX_DOMAIN, IDE_DOMAIN, API_DOMAIN, AUTH_DOMAIN, PRIMARY_HOST

# ============================================================================
# CADDY GLOBAL CONFIGURATION
# ============================================================================

# Global options
{
	# Admin API disabled in production
	admin off
	
	# HTTP ports
	http_port 80
	https_port 443
	
	# Default timeout
	timeouts {
		read_body 30s
		read_header 10s
		write 30s
		idle_timeout 120s
	}
}

# ============================================================================
# APEX DOMAIN ROUTING
# ============================================================================

# Main site / health endpoint
https://{APEX_DOMAIN} {
	# Health check endpoint (no proxy)
	respond /health "OK" 200
	
	# API execution scheduler routes
	@api_execution path /api/execution/*
	handle @api_execution {
		uri strip_prefix /api/execution
		reverse_proxy execution-scheduler:8080 {
			header_up Host {APEX_DOMAIN}
			header_up X-Forwarded-For {http.request.remote.host}
			header_up X-Forwarded-Proto https
			header_up X-Real-IP {http.request.remote.host}
		}
	}
	
	# API OPA routes
	@api_opa path /api/opa/*
	handle @api_opa {
		uri strip_prefix /api/opa
		reverse_proxy opa:8181 {
			header_up Host {APEX_DOMAIN}
			header_up X-Forwarded-For {http.request.remote.host}
			header_up X-Forwarded-Proto https
			header_up X-Real-IP {http.request.remote.host}
		}
	}
	
	# Authentication routes
	@api_auth path /api/auth/*
	handle @api_auth {
		uri strip_prefix /api/auth
		reverse_proxy oauth2-proxy:4180 {
			header_up Host {APEX_DOMAIN}
			header_up X-Forwarded-For {http.request.remote.host}
			header_up X-Forwarded-Proto https
			header_up X-Real-IP {http.request.remote.host}
		}
	}
	
	# Default: return 404
	respond "Not Found" 404
	
	# Logging
	log {
		level INFO
		output file /var/log/caddy/access.log {
			roll_size 100mb
			roll_keep 5
			roll_keep_for 720h
		}
		format json
	}
	
	# TLS configuration (optional)
	# Uncomment when Let's Encrypt rate limit resets
	# tls {
	#   on_demand
	#   issuer acme {
	#     email {ADMIN_EMAIL}
	#   }
	# }
}

# ============================================================================
# HTTP REDIRECT (redirect all HTTP to HTTPS)
# ============================================================================

http://{APEX_DOMAIN} {
	redir https://{APEX_DOMAIN}{uri} permanent
}

# ============================================================================
# IDE DOMAIN (optional)
# ============================================================================

# IDE.APEX_DOMAIN routes (when enabled)
# https://{IDE_DOMAIN} {
#     reverse_proxy code-server:8443 {
#         header_up Host {IDE_DOMAIN}
#         header_up X-Forwarded-For {http.request.remote.host}
#         header_up X-Forwarded-Proto https
#     }
# }

# ============================================================================
# API DOMAIN (optional)
# ============================================================================

# API.APEX_DOMAIN routes (when enabled)
# https://{API_DOMAIN} {
#     @health path /health
#     handle @health {
#         respond "OK" 200
#     }
#     
#     reverse_proxy api:8080 {
#         header_up Host {API_DOMAIN}
#         header_up X-Forwarded-For {http.request.remote.host}
#         header_up X-Forwarded-Proto https
#     }
# }

# ============================================================================
# MONITORING & OBSERVABILITY
# ============================================================================

# Metrics endpoint (internal only - not exposed)
# localhost:9180 {
#     respond /metrics 500
# }

# ============================================================================
# EOF - config/caddy/Caddyfile.tpl
# ============================================================================
