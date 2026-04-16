#!/usr/bin/env bash
# @file        config/pgbouncer/entrypoint.sh
# @module      config/pgbouncer
# @description PgBouncer Docker entrypoint — generates userlist.txt from env vars
#
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Generate userlist.txt from environment variables
# PgBouncer auth_type=md5 expects: "username" "md5<md5(password+username)>"
# ─────────────────────────────────────────────────────────────────────────────
USERLIST="/etc/pgbouncer/userlist.txt"
DB_USER="${POSTGRES_USER:-codeserver}"
DB_PASS="${POSTGRES_PASSWORD:-change-me-in-env}"

md5hash() {
  printf '%s' "${1}${2}" | md5sum | awk '{print "md5" $1}'
}

echo "\"${DB_USER}\" \"$(md5hash "${DB_PASS}" "${DB_USER}")\"" > "${USERLIST}"
echo '"pgbouncer" "pgbouncer"' >> "${USERLIST}"

exec pgbouncer /etc/pgbouncer/pgbouncer.ini "$@"
