localhost {
    # Auto HTTPS
    encode gzip

    # One-shot endpoint to clear stale workbench cache/storage in a regular profile.
    @reset path /reset-browser-state
    header @reset Clear-Site-Data "\"cache\", \"storage\""
    respond @reset 200

    # Prevent stale JS/CSS bundles from persisting across patched deployments.
    @stableAssets path /stable-*
    header @stableAssets Cache-Control "no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0"
    header @stableAssets Pragma "no-cache"
    header @stableAssets Expires "0"

    # Reverse proxy to code-server
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

# HTTP to HTTPS redirect
http://localhost {
    redir https://localhost{uri} permanent
}
