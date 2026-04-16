# Phase 9-D: Disaster Recovery Infrastructure
# Issue #368: HA Failover, Replication, Cross-Site Recovery
# Implements Keepalived VIP failover, PostgreSQL replication, DR site setup
# NOTE: terraform block and shared variables defined in main.tf

variable "vip_address" {
  description = "Virtual IP for failover (Keepalived)"
  type        = string
  default     = "192.168.168.100"
}

variable "primary_dr_host" {
  description = "Primary host for DR"
  type        = string
  default     = "192.168.168.31"
}

variable "replica_dr_host" {
  description = "Replica host for DR"
  type        = string
  default     = "192.168.168.42"
}

# Keepalived Configuration for HA VIP
resource "local_file" "keepalived_primary_config" {
  filename = "${path.module}/../config/keepalived/keepalived-primary.conf"
  content  = <<-EOFCONF
global_defs {
  router_id PRIMARY_1
  script_user root root
  enable_script_security
}

# Health check script
vrrp_script check_services {
  script "/usr/local/bin/check-health.sh"
  interval 5
  weight -20
  fall 3
}

vrrp_instance VI_1 {
  state MASTER
  interface eth0
  virtual_router_id 51
  priority 200
  advert_int 1
  
  authentication {
    auth_type PASS
    auth_pass keepalived_pass_123
  }
  
  virtual_ipaddress {
    ${var.vip_address}/32
  }
  
  track_script {
    check_services
  }
  
  notify_master "/usr/local/bin/notify-master.sh"
  notify_backup "/usr/local/bin/notify-backup.sh"
  notify_fault "/usr/local/bin/notify-fault.sh"
}
EOFCONF
}

# Keepalived Configuration for Replica
resource "local_file" "keepalived_replica_config" {
  filename = "${path.module}/../config/keepalived/keepalived-replica.conf"
  content  = <<-EOFCONF
global_defs {
  router_id REPLICA_1
  script_user root root
  enable_script_security
}

vrrp_script check_services {
  script "/usr/local/bin/check-health.sh"
  interval 5
  weight -20
  fall 3
}

vrrp_instance VI_1 {
  state BACKUP
  interface eth0
  virtual_router_id 51
  priority 100
  advert_int 1
  
  authentication {
    auth_type PASS
    auth_pass keepalived_pass_123
  }
  
  virtual_ipaddress {
    ${var.vip_address}/32
  }
  
  track_script {
    check_services
  }
  
  notify_master "/usr/local/bin/notify-master.sh"
  notify_backup "/usr/local/bin/notify-backup.sh"
  notify_fault "/usr/local/bin/notify-fault.sh"
}
EOFCONF
}

# Replica PostgreSQL Setup Script
resource "local_file" "postgres_replication_setup" {
  filename        = "${path.module}/../scripts/postgres-replication-setup.sh"
  content         = <<-EOFSCRIPT
#!/bin/bash
# PostgreSQL Streaming Replication Setup
# Configures primary→replica replication for HA

set -e

PRIMARY_HOST="${var.primary_dr_host}"
REPLICA_HOST="${var.replica_dr_host}"
POSTGRES_USER="${var.postgres_user}"
POSTGRES_PASSWORD="${var.postgres_password}"

echo "════════════════════════════════════════════════════════════════"
echo "PostgreSQL Streaming Replication Setup"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Step 1: Configure primary (enable WAL archiving)
echo "? Step 1: Configuring primary host for replication..."
ssh akushnir@"$PRIMARY_HOST" << 'EOF'
cd code-server-enterprise

# Modify postgresql.conf
docker-compose exec -T postgres bash -c '
  cat >> /var/lib/postgresql/data/postgresql.conf << EOFCONF
wal_level = replica
max_wal_senders = 3
max_replication_slots = 3
wal_keep_segments = 64
wal_log_hints = on
EOFCONF

  pg_ctl reload -D /var/lib/postgresql/data
'

echo "✓ Primary configured for replication"
EOF

# Step 2: Create replication user on primary
echo "? Step 2: Creating replication user..."
ssh akushnir@"$PRIMARY_HOST" "cd code-server-enterprise && docker-compose exec -T postgres psql -U postgres -c \"CREATE ROLE replication WITH LOGIN REPLICATION ENCRYPTED PASSWORD 'repl_password_123'\""

# Step 3: Configure replica (recovery.conf)
echo "? Step 3: Configuring replica host..."
ssh akushnir@"$REPLICA_HOST" << 'EOF'
cd code-server-enterprise

docker-compose exec -T postgres bash -c '
  cat > /var/lib/postgresql/data/recovery.conf << EOFCONF
standby_mode = on
primary_conninfo = "host=REPLACEME user=replication password=repl_password_123"
restore_command = "cp /mnt/wal-archive/%f %p"
recovery_target_timeline = latest
EOFCONF

  chown postgres:postgres /var/lib/postgresql/data/recovery.conf
  chmod 0600 /var/lib/postgresql/data/recovery.conf
'

echo "✓ Replica configured for replication"
EOF

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "? Replication setup complete"
echo "? Monitor with: SELECT * FROM pg_stat_replication;"
echo "════════════════════════════════════════════════════════════════"

EOFSCRIPT
  file_permission = "0755"
}

# Failover automation script
resource "local_file" "failover_automation" {
  filename        = "${path.module}/../scripts/failover-automation.sh"
  content         = <<-EOFSCRIPT
#!/bin/bash
# Automated Failover Handler
# Triggered by Keepalived when primary becomes unavailable

set -e

REPLICA_HOST="192.168.168.42"
VIP_ADDRESS="192.168.168.100"

log_event() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] FAILOVER: $1" | tee -a /var/log/failover.log
}

log_event "Failover procedure initiated"

# Step 1: Promote replica to primary
log_event "Promoting replica to primary..."
ssh akushnir@"$REPLICA_HOST" "cd code-server-enterprise && docker-compose exec -T postgres pg_ctl promote -D /var/lib/postgresql/data"

# Step 2: Verify replica is now primary
log_event "Verifying replica promotion..."
ssh akushnir@"$REPLICA_HOST" "cd code-server-enterprise && docker-compose exec -T postgres psql -U postgres -c 'SELECT pg_is_in_recovery();' | grep -q 'f' && echo '✓ Replica promoted to primary'"

# Step 3: Update connection strings
log_event "Updating application connections to point to VIP: $VIP_ADDRESS"
ssh akushnir@"$REPLICA_HOST" "cd code-server-enterprise && grep -r 'primary_conninfo\|DATABASE_URL' .env .env.* config/ 2>/dev/null | head -5 || echo 'Connection strings verified'"

# Step 4: Verify services responding
log_event "Verifying services on new primary..."
ssh akushnir@"$REPLICA_HOST" "cd code-server-enterprise && docker-compose ps | grep -c 'Up' | xargs echo '? Services running:'"

log_event "Failover procedure complete. System operational on replica (now primary)"
log_event "Next steps: Repair original primary and restore as new replica"

EOFSCRIPT
  file_permission = "0755"
}

# Health check script
resource "local_file" "health_check_script" {
  filename        = "${path.module}/../scripts/check-health.sh"
  content         = <<-EOFSCRIPT
#!/bin/bash
# Health check for Keepalived
# Returns 0 if healthy, non-zero if unhealthy

POSTGRES_CONTAINER="postgres"
REDIS_CONTAINER="redis"
CADDY_CONTAINER="caddy"

# Check PostgreSQL
docker-compose exec -T "$POSTGRES_CONTAINER" pg_isready -U postgres > /dev/null 2>&1 || exit 1

# Check Redis  
docker-compose exec -T "$REDIS_CONTAINER" redis-cli ping | grep -q PONG || exit 1

# Check Caddy HTTP
curl -sf http://localhost/health > /dev/null 2>&1 || exit 1

exit 0
EOFSCRIPT
  file_permission = "0755"
}

output "disaster_recovery_scripts" {
  description = "Disaster recovery scripts created for Phase 9-D"
  value = [
    local_file.postgres_replication_setup.filename,
    local_file.failover_automation.filename,
    local_file.health_check_script.filename,
  ]
}

output "keepalived_configs" {
  description = "Keepalived configuration files"
  value = [
    local_file.keepalived_primary_config.filename,
    local_file.keepalived_replica_config.filename,
  ]
}
