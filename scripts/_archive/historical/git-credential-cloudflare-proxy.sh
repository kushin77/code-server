#!/bin/bash
# Git Credential Helper: Route all git credential requests through Cloudflare proxy
# This enables developers to use 'git push' without direct SSH key access
# Used by: git config credential.helper cloudflare-proxy

set -e

# Read git credential protocol from stdin
read operation

# Cloudflare session token (provided by Cloudflare Access)
SESSION_TOKEN="${CLOUDFLARE_SESSION_TOKEN:-}"
PROXY_URL="${GIT_PROXY_URL:-https://proxy.dev.yourdomain.com/git}"

case "$operation" in
  get)
    # Developer needs git credentials
    # Read the credential request (protocol, host, username)
    declare -A cred
    while IFS='=' read -r key value; do
      [[ -z "$key" ]] && break
      cred[$key]="$value"
    done

    protocol="${cred[protocol]}"
    host="${cred[host]}"
    username="${cred[username]}"

    # Call proxy to authenticate (proxy handles SSH key)
    response=$(curl -s -H "Authorization: Bearer $SESSION_TOKEN" \
      "$PROXY_URL/credentials?host=$host&username=$username" \
      --data "protocol=$protocol")

    if [ $? -eq 0 ]; then
      # Return credential in git credential protocol format
      echo "protocol=${cred[protocol]}"
      echo "host=${cred[host]}"
      echo "username=developer"
      echo "password=$response"
    else
      # Authentication failed
      exit 1
    fi
    ;;

  store)
    # Git wants to store credentials (we don't - handled by proxy)
    # Just discard the request
    ;;

  erase)
    # Git wants to forget credentials (no-op for proxy mode)
    ;;
esac

exit 0
