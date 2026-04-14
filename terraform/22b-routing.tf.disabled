# ════════════════════════════════════════════════════════════════════════════
# PHASE 22-B: BGP ROUTING & OPTIMIZATION - ON-PREMISES EDITION
# ════════════════════════════════════════════════════════════════════════════
# Purpose: Advanced routing, failover, traffic engineering
# Status: ELITE - Immutable (VyOS 1.4, Quagga), Independent, Duplicate-Free
# On-Premises Focus: BGP on Kuniper/VyOS for 192.168.168.0/24 subnet
# ════════════════════════════════════════════════════════════════════════════

terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

# ─── Locals: Immutable Configuration ─────────────────────────────────────────
locals {
  vyos_version = "1.4" # PINNED - Never change
  quagga_version = "1.2.4" # PINNED - Never change
  
  # BGP Configuration
  bgp_asn_primary   = 65000         # Autonomous System Number (on-prem)
  bgp_asn_upstream  = 64512         # Upstream provider ASN
  
  # Primary/Standby failover
  primary_router_ip   = "192.168.168.31"
  standby_router_ip   = "192.168.168.30"
  failure_threshold   = 2            # failures before failover
  health_check_interval = 5          # seconds
  
  # Traffic engineering
  local_preference_primary  = 200    # Higher = preferred
  local_preference_standby  = 100
  
  # On-prem specific
  management_vlan    = 100
  data_vlan          = 101
  uplink_interface   = "eth0"
  
  common_labels = {
    phase      = "22-b"
    component  = "bgp-routing"
    managed_by = "terraform"
  }
}

# ─── BGP Configuration Template (VyOS/Quagga) ────────────────────────────────
locals {
  vyos_bgp_config = <<-EOT
    protocols {
        bgp {
            asn: ${local.bgp_asn_primary}
            
            address-family {
                ipv4-unicast {
                    redistribute {
                        connected
                    }
                    network 192.168.168.0/24
                }
            }
            
            neighbor ${local.bgp_asn_upstream} {
                remote-as ${local.bgp_asn_upstream}
                address-family {
                    ipv4-unicast {
                        route-map {
                            import "UPSTREAM_IN"
                            export "UPSTREAM_OUT"
                        }
                    }
                }
            }
            
            neighbor ${local.standby_router_ip} {
                remote-as ${local.bgp_asn_primary}
                update-source ${local.primary_router_ip}
                address-family {
                    ipv4-unicast {
                        route-map {
                            import "IBGP_IN"
                        }
                    }
                }
            }
        }
    }
    
    policy {
        route-map "UPSTREAM_OUT" {
            rule 10 {
                action permit
                set {
                    as-path {
                        prepend ${local.bgp_asn_primary}  # Increase AS path for traffic engineering
                    }
                    local-preference ${local.local_preference_primary}
                }
            }
        }
        
        route-map "IBGP_IN" {
            rule 10 {
                action permit
                set {
                    local-preference ${local.local_preference_standby}
                }
            }
        }
    }
  EOT
}

# ─── Health Check Script (Bash) ──────────────────────────────────────────────
locals {
  healthcheck_script = <<-EOT
    #!/bin/bash
    # BGP Health Check for Primary/Standby Failover
    
    PRIMARY="${local.primary_router_ip}"
    STANDBY="${local.standby_router_ip}"
    THRESHOLD=${local.failure_threshold}
    INTERVAL=${local.health_check_interval}
    
    failure_count=0
    
    while true; do
      # Check primary router connectivity
      if ! ping -c 1 -W 2 $PRIMARY >/dev/null 2>&1; then
        ((failure_count++))
        echo "[$(date)] Health check failed for primary ($PRIMARY). Failures: $failure_count"
        
        if [ $failure_count -ge $THRESHOLD ]; then
          echo "[$(date)] FAILOVER: Switching to standby router ($STANDBY)"
          # Trigger failover (implementation specific)
          vtysh -c "configure terminal" \
                -c "router bgp ${local.bgp_asn_primary}" \
                -c "neighbor $STANDBY route-map IBGP_IN in" \
                -c "write memory" \
                -c "exit"
          failure_count=0
        fi
      else
        failure_count=0
        echo "[$(date)] Health check passed for primary ($PRIMARY)"
      fi
      
      sleep $INTERVAL
    done
  EOT
}

# ─── BGP Configuration File (Quagga/FRRouting format) ───────────────────────
resource "null_resource" "bgp_config_file" {
  triggers = {
    config_hash = md5(local.vyos_bgp_config)
  }

  provisioner "local-exec" {
    command = "echo '${replace(local.vyos_bgp_config, "'", "'\\''")}' > /tmp/bgp-config.txt"
  }

  provisioner "local-exec" {
    command = "echo 'BGP configuration template generated for review'"
  }
}

# ─── Route Map Policies ──────────────────────────────────────────────────────
locals {
  route_map_config = {
    "UPSTREAM_OUT" = {
      rule_10 = {
        action = "permit"
        set = {
          as_path_prepend       = local.bgp_asn_primary
          local_preference      = local.local_preference_primary
          metric                = 100
        }
      }
    },
    
    "IBGP_IN" = {
      rule_10 = {
        action = "permit"
        set = {
          local_preference = local.local_preference_standby
        }
      }
    },
    
    "OUTBOUND" = {
      rule_10 = {
        match = {
          address_list = "192.168.168.0/24"
        }
        action = "permit"
        set = {
          origin = "IGP"
        }
      }
    }
  }
}

# ─── Traffic Engineering Configuration ───────────────────────────────────────
locals {
  traffic_engineering = {
    # Load balancing ratio (primary:standby)
    load_balance = "80:20"
    
    # Failover timeout
    failover_timeout_seconds = 30
    
    # FlowSpec rules (upstream DDoS mitigation)
    flowspec_rules = [
      {
        name        = "DDoS-Mitigation"
        destination = "0.0.0.0/0"
        rate_limit  = "100mbps"
        action      = "discard"
      }
    ]
    
    # BGP communities for classification
    communities = {
      "INTERNAL"   = "65000:1000"
      "PREFERRED"  = "65000:2000"
      "BACKUP"     = "65000:3000"
      "REJECT"     = "65000:9000"
    }
  }
}

# ─── Health Check Monitoring (Prometheus rules) ──────────────────────────────
locals {
  prometheus_bgp_rules = <<-EOT
    groups:
    - name: bgp_health
      interval: 30s
      rules:
      # BGP peer state monitoring
      - alert: BGPPeerDown
        expr: |
          bgp_peer_state{peer="${local.standby_router_ip}"} == 0
        for: 1m
        labels:
          severity: critical
          phase: "22-b"
        annotations:
          summary: "BGP peer down: {{ $labels.peer }}"
          action: "Check network connectivity, review BGP logs"
      
      # Route count anomaly
      - alert: BGPRouteAnomaloutput
        expr: |
          increase(bgp_routes_total[5m]) > 10
        for: 2m
        labels:
          severity: warning
          phase: "22-b"
        annotations:
          summary: "Unusual BGP route changes detected"
          dashboard: "grafana/bgp-monitoring"
      
      # Failover Health
      - alert: FailoverThresholdApproaching
        expr: |
          bgp_failover_checks_failed > (${local.failure_threshold} - 1)
        labels:
          severity: warning
          phase: "22-b"
        annotations:
          summary: "Failover threshold approaching"
          action: "Investigate primary link health"
  EOT
}

# ─── BGP Prefix List Configuration ───────────────────────────────────────────
locals {
  prefix_lists = {
    "INTERNAL_NETS" = [
      "192.168.168.0/24",    # Management network
      "10.0.0.0/8",          # Private networks
      "172.16.0.0/12"
    ],
    
    "CUSTOMER_ROUTES" = [
      "203.0.113.0/24"       # Example customer network
    ]
  }
}

# ─── Outputs ─────────────────────────────────────────────────────────────────
output "vyos_version" {
  value       = local.vyos_version
  description = "VyOS version (immutable, pinned)"
}

output "bgp_configuration" {
  value = {
    primary_asn  = local.bgp_asn_primary
    upstream_asn = local.bgp_asn_upstream
    primary_ip   = local.primary_router_ip
    standby_ip   = local.standby_router_ip
  }
  description = "BGP configuration summary"
}

output "failover_settings" {
  value = {
    failure_threshold       = local.failure_threshold
    health_check_interval   = local.health_check_interval
    local_preference_primary = local.local_preference_primary
    local_preference_standby = local.local_preference_standby
  }
  description = "Failover and traffic engineering settings"
}

output "traffic_engineering_summary" {
  value = {
    load_balance_ratio = local.traffic_engineering.load_balance
    failover_timeout   = "${local.traffic_engineering.failover_timeout_seconds}s"
    route_maps         = keys(local.route_map_config)
    prefix_lists       = keys(local.prefix_lists)
  }
  description = "Traffic engineering configuration"
}
