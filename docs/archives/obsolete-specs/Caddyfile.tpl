# ⚠️  LEGACY TEMPLATE — For reference only
# In production, use the dynamic Caddyfile that reads {$DOMAIN} from environment
# This template was used by Terraform for local development before domain migration

localhost {
    # Tier 1 Performance: HTTP/2, Compression, Connection Pooling
    # Estimated improvement: 15-20% latency reduction, 30-40% bandwidth reduction
    
    # Compression (gzip + brotli) — reduces payload size by 60-80%
    encode gzip
    encode brotli
    
    # HTTP/2 Server Push — pre-loads critical assets
    # Note: Paths must match actual code-server asset paths
    push /static/bundle.js
    push /static/styles.css
    
    # Connection optimization: Keep-Alive + pipeline
    # Handled by reverse_proxy connection reuse
    
    # One-shot endpoint to clear stale workbench cache/storage in a regular profile.
    @reset path /reset-browser-state
    header @reset Clear-Site-Data "\"cache\", \"storage\""
    respond @reset 200

    # Prevent stale JS/CSS bundles from persisting across patched deployments.
    @stableAssets path /stable-*
    header @stableAssets Cache-Control "no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0"
    header @stableAssets Pragma "no-cache"
    header @stableAssets Expires "0"

    # Reverse proxy to code-server — optimized for concurrency
    reverse_proxy ${code_server_host}:${code_server_port} {
        # Preserve original headers
        header_up X-Real-IP {http.request.remote.host}
        header_up X-Forwarded-For {http.request.remote.host}
        header_up X-Forwarded-Proto https

        # WebSocket support required for code-server terminal, extensions and live sync
        flush_interval -1
    }

    # Security headers
    header X-Content-Type-Options nosniff
    header X-Frame-Options SAMEORIGIN
    header X-XSS-Protection "1; mode=block"
    header Strict-Transport-Security "max-age=31536000; includeSubDomains"
    header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval' blob:; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self' wss: ws:; worker-src 'self' blob:; frame-src 'self';"
}

# HTTP to HTTPS redirect (for legacy local deployments)
http://localhost {
    redir https://localhost{uri} permanent
}
