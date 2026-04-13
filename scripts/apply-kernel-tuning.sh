#!/bin/bash
# apply-kernel-tuning.sh
# Applies Tier 1 kernel optimizations for performance enhancement

set -e

echo "╔════════════════════════════════════════════════════════════╗"
echo "║           TIER 1: KERNEL TUNING - SYSCTL SETUP            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "This script applies 5 critical kernel parameters for"
echo "performance optimization on Code Server Enterprise."
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "ERROR: This script must be run as root (use sudo)"
   exit 1
fi

echo "Starting kernel tuning application..."
echo ""

# Backup current sysctl.conf
BACKUP_DIR="/root/backups/kernel-tuning-$(date +%Y-%m-%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp /etc/sysctl.conf "$BACKUP_DIR/sysctl.conf.backup"
echo "✓ Backup created: $BACKUP_DIR/sysctl.conf.backup"

# Apply kernel parameters
echo ""
echo "Applying kernel parameters..."
echo ""

# 1. Max file descriptors
echo "Setting fs.file-max=2097152..."
sysctl -w fs.file-max=2097152
echo "fs.file-max=2097152" >> /etc/sysctl.conf
echo "✓ Max file descriptors: 2M"

# 2. TCP SYN backlog
echo "Setting net.ipv4.tcp_max_syn_backlog=8096..."
sysctl -w net.ipv4.tcp_max_syn_backlog=8096
echo "net.ipv4.tcp_max_syn_backlog=8096" >> /etc/sysctl.conf
echo "✓ TCP SYN backlog: 8096"

# 3. Listen backlog
echo "Setting net.core.somaxconn=4096..."
sysctl -w net.core.somaxconn=4096
echo "net.core.somaxconn=4096" >> /etc/sysctl.conf
echo "✓ Listen backlog: 4096"

# 4. TCP TIME_WAIT reuse
echo "Setting net.ipv4.tcp_tw_reuse=1..."
sysctl -w net.ipv4.tcp_tw_reuse=1
echo "net.ipv4.tcp_tw_reuse=1" >> /etc/sysctl.conf
echo "✓ TCP TIME_WAIT reuse: enabled"

# 5. TCP FIN timeout
echo "Setting net.ipv4.tcp_fin_timeout=60..."
sysctl -w net.ipv4.tcp_fin_timeout=60
echo "net.ipv4.tcp_fin_timeout=60" >> /etc/sysctl.conf
echo "✓ TCP FIN timeout: 60 seconds"

# Persist all changes
echo ""
echo "Persisting changes..."
sysctl -p /etc/sysctl.conf > /dev/null

# Verification
echo ""
echo "════════════════════════════════════════════════════════════"
echo "VERIFICATION - Kernel Parameters Applied:"
echo "════════════════════════════════════════════════════════════"
echo ""

echo "File descriptors:"
echo "  Current: $(cat /proc/sys/fs/file-max)"
[ "$(cat /proc/sys/fs/file-max)" = "2097152" ] && echo "  ✓ VERIFIED" || echo "  ⚠ CHECK FAILED"

echo ""
echo "TCP SYN backlog:"
echo "  Current: $(cat /proc/sys/net/ipv4/tcp_max_syn_backlog)"
[ "$(cat /proc/sys/net/ipv4/tcp_max_syn_backlog)" = "8096" ] && echo "  ✓ VERIFIED" || echo "  ⚠ CHECK FAILED"

echo ""
echo "Listen backlog (somaxconn):"
echo "  Current: $(cat /proc/sys/net/core/somaxconn)"
[ "$(cat /proc/sys/net/core/somaxconn)" = "4096" ] && echo "  ✓ VERIFIED" || echo "  ⚠ CHECK FAILED"

echo ""
echo "TCP TIME_WAIT reuse:"
echo "  Current: $(cat /proc/sys/net/ipv4/tcp_tw_reuse)"
[ "$(cat /proc/sys/net/ipv4/tcp_tw_reuse)" = "1" ] && echo "  ✓ VERIFIED" || echo "  ⚠ CHECK FAILED"

echo ""
echo "TCP FIN timeout:"
echo "  Current: $(cat /proc/sys/net/ipv4/tcp_fin_timeout)"
[ "$(cat /proc/sys/net/ipv4/tcp_fin_timeout)" = "60" ] && echo "  ✓ VERIFIED" || echo "  ⚠ CHECK FAILED"

echo ""
echo "════════════════════════════════════════════════════════════"
echo "✅ KERNEL TUNING COMPLETE"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Summary:"
echo "  • 5 kernel parameters optimized"
echo "  • Changes persisted to /etc/sysctl.conf"
echo "  • Backup saved: $BACKUP_DIR"
echo ""
echo "Next step: Update docker-compose.yml and restart containers"
echo ""
