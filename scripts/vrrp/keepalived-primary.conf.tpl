#!/bin/bash
################################################################################
# scripts/vrrp/keepalived-primary.conf.tpl
# Keepalived configuration for PRIMARY host (192.168.168.31)
# Role: VRRP MASTER — owns the Virtual IP 192.168.168.30
# 
# Managed by: P2 #365 (VRRP Virtual IP Failover)
# Source: scripts/vrrp/keepalived-primary.conf.tpl
# Template: YES — processed by envsubst for variable substitution
# Replaces: Manual Keepalived installation (IaC approach)
################################################################################

global_defs {
    # VRRP process ID and heartbeat pid
    router_id ${VRRP_ROUTER_ID:-PROD_PRIMARY}
    
    # Syslog identification
    script_user root
    enable_script_security
    
    # Prevent multiple Keepalived instances
    max_auto_priority 100
}

# ─────────────────────────────────────────────────────────────────────────────
# Health Check: Docker services are running
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
# VRRP Instance: Production Virtual IP
# ─────────────────────────────────────────────────────────────────────────────
vrrp_instance PROD_VIP {
    state MASTER                    # PRIMARY runs as MASTER initially
    interface ${VRRP_INTERFACE:-eth0}
    
    # Unique VRRP instance ID (1-255)
    virtual_router_id ${VRRP_ROUTER_ID_NUM:-51}
    
    # Priority determines who owns the VIP
    # Primary: 110 (preferred)
    # Replica: 100 (backup)
    # When primary health fails (weight -20), priority = 90, lower than replica
    priority 110
    
    # Advertisement interval (heartbeat)
    advert_int 1
    
    # Authentication (VRRP password for cluster coherence)
    authentication {
        auth_type PASS
        auth_pass ${VRRP_AUTH_SECRET:-$(date +%s | md5sum | cut -c 1-8)}
    }
    
    # Non-preemptive: primary doesn't auto-reclaim VIP after recovery
    # Prevents flapping if primary recovers frequently
    nopreempt
    
    # Virtual IPs owned by this instance (when MASTER)
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
