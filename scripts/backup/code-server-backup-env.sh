#!/bin/bash
#
# @file code-server-backup-env.sh
# @module backup
# @description Backup environment configuration
# @author Operations Team
# @version 1.0
#
# Source this file in backup scripts to set environment variables
#

# Backup storage locations
export BACKUP_DIR="/home/akushnir/.backup-storage/daily"
export NAS_BACKUP="/home/akushnir/.nas-backup"  # Update to actual NAS mount path

# PostgreSQL connection settings
export POSTGRES_HOST="localhost"
export POSTGRES_PORT="5432"
export POSTGRES_USER="postgres"
export POSTGRES_PASSWORD=""  # Set via .pgpass or Docker exec
export POSTGRES_DB="postgres"

# Redis connection settings
export REDIS_HOST="localhost"
export REDIS_PORT="6379"
export REDIS_PASSWORD=""  # If authentication required
export REDIS_CONTAINER="code-server-redis"

# Backup retention policies
export POSTGRES_RETENTION_DAYS="30"
export REDIS_RETENTION_DAYS="7"
export VOLUMES_RETENTION_DAYS="30"

# Email configuration (optional)
export REPORT_EMAIL="ops@kushnir.cloud"
export SEND_EMAIL="false"  # Set to true if mail configured

# Logging
export LOG_DIR="/var/log"
export BACKUP_LOG_LEVEL="INFO"  # INFO, WARNING, ERROR

# Docker settings
export DOCKER_COMPOSE_FILE="/home/akushnir/code-server/docker-compose.yml"
export DOCKER_COMPOSE_PROJECT="code-server"
