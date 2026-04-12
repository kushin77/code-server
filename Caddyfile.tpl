localhost {
    # Auto HTTPS
    encode gzip
    
    # Reverse proxy to code-server
    reverse_proxy ${code_server_host}:${code_server_port} {
        # Preserve original headers
        header_uri / X-Real-IP {http.request.remote.host}
        header_uri / X-Forwarded-For {http.request.remote.host}
        header_uri / X-Forwarded-Proto https
        
        # WebSocket support required for code-server
        websocket
    }
    
    # Security headers
    header X-Content-Type-Options nosniff
    header X-Frame-Options SAMEORIGIN
    header X-XSS-Protection "1; mode=block"
    header Strict-Transport-Security "max-age=31536000; includeSubDomains"
    header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline';"
    
    # Timeouts
    reverse_proxy_read_timeout 3600s
    reverse_proxy_header_timeout 3600s
}

# HTTP to HTTPS redirect
http://localhost {
    redir https://localhost{uri} permanent
}
