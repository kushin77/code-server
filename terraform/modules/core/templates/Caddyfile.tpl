# @file terraform/modules/core/templates/Caddyfile.tpl
# @description Production Caddy gateway template for portal + SSO routing
# @governance GOV-002: Deterministic IaC, immutable infrastructure

{
  admin off
  http_port 80
  https_port 443
}

https://{APEX_DOMAIN} {
  respond /health "OK" 200

  handle /oauth2/* {
    reverse_proxy oauth2-proxy:4180 {
      header_up Host {APEX_DOMAIN}
      header_up X-Forwarded-For {http.request.remote.host}
      header_up X-Forwarded-Proto https
      header_up X-Real-IP {http.request.remote.host}
    }
  }

  handle /api/* {
    forward_auth http://oauth2-proxy:4180 {
      uri /oauth2/auth
      copy_headers X-Auth-Request-User X-Auth-Request-Email Authorization
      handle_errors 401 403 {
        redir /oauth2/sign_in?rd={http.request.uri} 302
      }
    }

    uri strip_prefix /api
    reverse_proxy backend:8000 {
      header_up Host {APEX_DOMAIN}
      header_up X-Forwarded-For {http.request.remote.host}
      header_up X-Forwarded-Proto https
      header_up X-Real-IP {http.request.remote.host}
    }
  }

  handle {
    forward_auth http://oauth2-proxy:4180 {
      uri /oauth2/auth
      copy_headers X-Auth-Request-User X-Auth-Request-Email Authorization
      handle_errors 401 403 {
        redir /oauth2/sign_in?rd={http.request.uri} 302
      }
    }

    root * /etc/caddy/portal
    try_files {path} /index.html
    file_server
  }
}

http://{APEX_DOMAIN} {
  redir https://{APEX_DOMAIN}{uri} permanent
}

https://{IDE_DOMAIN} {
  respond /health "OK" 200

  handle /oauth2/* {
    reverse_proxy oauth2-proxy:4180 {
      header_up Host {IDE_DOMAIN}
      header_up X-Forwarded-For {http.request.remote.host}
      header_up X-Forwarded-Proto https
      header_up X-Real-IP {http.request.remote.host}
    }
  }

  handle {
    forward_auth http://oauth2-proxy:4180 {
      uri /oauth2/auth
      copy_headers X-Auth-Request-User X-Auth-Request-Email Authorization
      handle_errors 401 403 {
        redir /oauth2/sign_in?rd={http.request.uri} 302
      }
    }

    reverse_proxy code-server:8443 {
      header_up Host {IDE_DOMAIN}
      header_up X-Forwarded-Host {http.request.host}
      header_up X-Forwarded-Proto https
      header_up X-Real-IP {http.request.remote.host}
    }
  }
}

http://{IDE_DOMAIN} {
  redir https://{IDE_DOMAIN}{uri} permanent
}

https://{API_DOMAIN} {
  respond /health "OK" 200

  handle /oauth2/* {
    reverse_proxy oauth2-proxy:4180 {
      header_up Host {API_DOMAIN}
      header_up X-Forwarded-For {http.request.remote.host}
      header_up X-Forwarded-Proto https
      header_up X-Real-IP {http.request.remote.host}
    }
  }

  handle {
    forward_auth http://oauth2-proxy:4180 {
      uri /oauth2/auth
      copy_headers X-Auth-Request-User X-Auth-Request-Email Authorization
      handle_errors 401 403 {
        redir /oauth2/sign_in?rd={http.request.uri} 302
      }
    }

    reverse_proxy backend:8000 {
      header_up Host {API_DOMAIN}
      header_up X-Forwarded-For {http.request.remote.host}
      header_up X-Forwarded-Proto https
      header_up X-Real-IP {http.request.remote.host}
    }
  }
}

http://{API_DOMAIN} {
  redir https://{API_DOMAIN}{uri} permanent
}

https://{AUTH_DOMAIN} {
  respond /health "OK" 200

  handle /oauth2/* {
    reverse_proxy oauth2-proxy:4180 {
      header_up Host {AUTH_DOMAIN}
      header_up X-Forwarded-For {http.request.remote.host}
      header_up X-Forwarded-Proto https
      header_up X-Real-IP {http.request.remote.host}
    }
  }

  handle {
    redir /oauth2/sign_in 302
  }
}

http://{AUTH_DOMAIN} {
  redir https://{AUTH_DOMAIN}{uri} permanent
}