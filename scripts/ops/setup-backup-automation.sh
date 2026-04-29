#!/bin/bash
# Setup automated backup jobs via cron
# Configures backup automation for PostgreSQL, Redis, volumes, and configs

set -e
trap 'echo "❌ Setup failed at line $LINENO"; exit 1' ERR

echo "╔════════════════════════════════════════════════════════════╗"
echo "║      Automated Backup Setup - Cron Configuration            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

SCRIPTS_DIR="/home/akushnir/code-server/scripts/ops"

# Make all backup scripts executable
echo "Making backup scripts executable..."
chmod +x "$SCRIPTS_DIR"/{postgres,redis,volume,config,backup-health}-*

echo "✓ Scripts are executable"
echo ""

# Display cron configuration
echo "Recommended cron jobs:"
echo "─────────────────────"
echo ""
echo "# PostgreSQL daily backup at 2 AM"
echo "0 2 * * * $SCRIPTS_DIR/postgres-backup.sh >> /var/log/postgres-backup.log 2>&1"
echo ""
echo "# Redis daily backup at 2:30 AM"
echo "30 2 * * * $SCRIPTS_DIR/redis-backup.sh >> /var/log/redis-backup.log 2>&1"
echo ""
echo "# Volume daily snapshots at 3 AM"
echo "0 3 * * * $SCRIPTS_DIR/volume-snapshot.sh >> /var/log/volume-snapshot.log 2>&1"
echo ""
echo "# Configuration backup on every commit (git hook)"
echo "# Create .git/hooks/post-commit:"
echo "$SCRIPTS_DIR/config-backup.sh >> /var/log/config-backup.log 2>&1"
echo ""
echo "# Backup health check daily at 4 AM"
echo "0 4 * * * $SCRIPTS_DIR/backup-health-check.sh >> /var/log/backup-health.log 2>&1"
echo ""

echo "To apply these jobs, run:"
echo "  crontab -e"
echo ""
echo "And add the lines above to your crontab."
echo ""

# Check if we can set up cron automatically
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Installation Instructions                                 ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "1. Create backup directories:"
echo "   sudo mkdir -p /backups/{postgres,redis,volumes}"
echo "   sudo chown \$(whoami):\$(whoami) /backups"
echo "   sudo chmod 755 /backups"
echo ""
echo "2. Edit crontab:"
echo "   crontab -e"
echo ""
echo "3. Add the cron entries shown above"
echo ""
echo "4. Verify setup:"
echo "   crontab -l  # Should show all entries"
echo ""
echo "5. Test each script manually:"
echo "   bash $SCRIPTS_DIR/postgres-backup.sh"
echo "   bash $SCRIPTS_DIR/redis-backup.sh"
echo "   bash $SCRIPTS_DIR/volume-snapshot.sh"
echo "   bash $SCRIPTS_DIR/config-backup.sh"
echo "   bash $SCRIPTS_DIR/backup-health-check.sh"
echo ""
echo "6. Schedule automated health checks:"
echo "   curl http://localhost:9090/health || echo 'Monitor: PostgreSQL backup status'"
echo ""
echo "✅ Backup automation ready for configuration"
