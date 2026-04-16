#!/bin/bash
################################################################################
# scripts/vrrp/keepalived-replica.conf.tpl
# Keepalived configuration for REPLICA host (192.168.168.42)
# Role: VRRP BACKUP — monitors primary and takes over if primary fails
# 
# Managed by: P2 #365 (VRRP Virtual IP Failover)
# Source: scripts/vrrp/keepalived-replica.conf.tpl
# Template: YES — processed by envsubst for variable substitution
# Replaces: Manual Keepalived installation (IaC approach)
################################################################################

global_defs {
    # VRRP process ID and heartbeat pid
    router_id ${VRRP_ROUTER_ID:-PROD_REPLICA}
    
    # Syslog identification
    script_user root
    enable_script_security
    
    # Prevent multiple Keepalived instances
    max_auto_priority 100
}

# ─────────────────────────────────────────────────────────────────────────────
# Health Check: Docker services are running (on replica)
# ─────────────────────────────────────────────────────────────────────────────
vrrp_script chk_services {
    # Check if core services are healthy
    script "/usr/local/sbin/check-services.sh"
    interval 2          # Check every 2 seconds
    weight -20          # Weight reduction if service check fails
    fall 2              # Need 2 failures to consider service down
    rise 2              # Need 2 successes to recover
    user root
}

# ─────────────────────────────────────────────────────────────────────────────
# VRRP Instance: Production Virtual IP (REPLICA WATCHES)
# ─────────────────────────────────────────────────────────────────────────────
vrrp_instance PROD_VIP {
    state BACKUP                    # REPLICA runs as BACKUP (monitoring)
    interface ${VRRP_INTERFACE:-eth0}
    
    # Unique VRRP instance ID (MUST match primary)
    virtual_router_id ${VRRP_ROUTER_ID_NUM:-51}
    
    # Priority determines who owns the VIP
    # Primary: 110 (preferred)
    # Replica: 100 (backup — lower than primary)
    # If primary health fails, primary priority becomes 90, replica becomes MASTER
    priority 100
    
    # Advertisement interval (heartbeat)
    advert_int 1
    
    # Authentication (VRRP password — MUST match primary)
    authentication {
        auth_type PASS
        auth_pass ${VRRP_AUTH_SECRET:-$(date +%s | md5sum | cut -c 1-8)}
    }
    
    # Non-preemptive: doesn't auto-reclaim if it was briefly MASTER
    # Primary will reclaim when it recovers (due to higher priority)
    nopreempt
    
    # Virtual IPs (only taken if promoted to MASTER due to primary failure)
    virtual_ipaddress {
        ${VRRP_VIRTUAL_IP:-192.168.168.30}/24 dev ${VRRP_INTERFACE:-eth0} label ${VRRP_INTERFACE:-eth0}:vip
    }
    
    # Track service health
    track_script {
        chk_services weight -20
    }
    
    # Notify scripts: Execute on state transitions
    notify_master       "/usr/local/sbin/vrrp-notify.sh MASTER"
    notify_backup       "/usr/local/sbin/vrrp-notify.sh BACKUP"
    notify_fault        "/usr/local/sbin/vrrp-notify.sh FAULT"
    
    # Optional: Fast failover via ARP gratuitous announcements
    garp_master_delay 1
    garp_master_repeat 5
    garp_lower_priority_delay 5
    garp_lower_priority_repeat 5
}

# ─────────────────────────────────────────────────────────────────────────────
# Optional: Virtual Route (for advanced multi-gateway scenarios)
# Uncomment if using multiple default gateways
# ─────────────────────────────────────────────────────────────────────────────
# vrrp_static_routes {
#     192.168.168.0/24 via 192.168.168.1 dev eth0
# }
#
# vrrp_static_rules {
#     from 192.168.168.0/24 table 10
# }
