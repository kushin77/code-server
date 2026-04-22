#!/usr/bin/env python3
# @file        scripts/security/vault-init-collab.py
# @module      security/vault
# @description Initialize Vault for dynamic credentials (DB/Cloud)
#
import os
import sys
import json
import requests

VAULT_ADDR = os.getenv("VAULT_ADDR", "http://localhost:8200")
VAULT_TOKEN = os.getenv("VAULT_TOKEN", "dev-root-token-change-me")

def vault_api(method, path, data=None):
    url = f"{VAULT_ADDR}/v1{path}"
    headers = {"X-Vault-Token": VAULT_TOKEN}
    res = requests.request(method, url, headers=headers, json=data)
    if res.status_code >= 400:
        print(f"Error: {res.status_code} - {res.text}")
        return None
    return res.json() if res.content else {}

def setup():
    # 1. Enable Database secrets engine
    vault_api("POST", "/sys/mounts/database", {
        "type": "database"
    })
    
    # 2. Configure PostgreSQL connection
    # Note: Use env vars for real creds
    vault_api("POST", "/database/config/postgresql", {
        "plugin_name": "postgresql-database-plugin",
        "allowed_roles": ["collab-app"],
        "connection_url": "postgresql://{{username}}:{{password}}@postgres:5432/collab?sslmode=disable",
        "username": "postgres",
        "password": "change-me-postgres"
    })
    
    # 3. Create role for ephemeral DB creds
    vault_api("POST", "/database/roles/collab-app", {
        "db_name": "postgresql",
        "creation_statements": "CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT ALL PRIVILEGES ON DATABASE collab TO \"{{name}}\";",
        "default_ttl": "1h",
        "max_ttl": "24h"
    })

    # 4. Enable KV for other session secrets
    vault_api("POST", "/sys/mounts/collab-kv", {
        "type": "kv",
        "options": {"version": "2"}
    })

    print("Vault initialization complete for collaboration services.")

if __name__ == "__main__":
    setup()
