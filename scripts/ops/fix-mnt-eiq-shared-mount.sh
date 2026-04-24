#!/usr/bin/env bash
# @file        scripts/ops/fix-mnt-eiq-shared-mount.sh
# @module      infrastructure/storage
# @description Sync /etc/fstab between replicas - add missing mnt-eiq-shared mount (P1 #1637)
# @owner       On-call ops
# @status      Infrastructure maintenance

set -euo pipefail

SCRIPT_DIR=""
source "/scripts/_common/init.sh"
init_repo

PRIMARY_HOST=""
STANDBY_HOST=""
NAS_HOST=""
NAS_EXPORT="/mnt/eiq-shared"

GREEN=
