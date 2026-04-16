# ════════════════════════════════════════════════════════════════════════════
# Phase 8-B: Falco Runtime Security - eBPF syscall monitoring
# Issue #359: Falco for container anomaly detection, malware, cryptominers
# ════════════════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────────────────────────────────────
# 1. Falco eBPF Kernel Module Installation
# ─────────────────────────────────────────────────────────────────────────────

variable "falco_version" {
  type        = string
  description = "Falco version (immutable)"
  default     = "0.36.0"
}

variable "falco_rules_version" {
  type        = string
  description = "Falco rules version (immutable)"
  default     = "0.36.0"
}

resource "null_resource" "falco_installation" {
  provisioner "local-exec" {
    command = "bash ${path.module}/../scripts/deploy-falco.sh"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "bash ${path.module}/../scripts/cleanup-falco.sh"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# 2. Falco Configuration - Syscall Monitoring
# ─────────────────────────────────────────────────────────────────────────────

resource "local_file" "falco_config" {
  filename = "${path.module}/../config/falco/falco.yaml"
  content  = <<-EOH
# Falco v${var.falco_version} configuration
engine:
  kind: gRPC
  gRPC:
    enabled: true
    threadiness: 0
  kmod:
    buf_size_preset: 4
  ebpf:
    enabled: true
    probe: /root/.falco/falco-${var.falco_version}-x86_64.o

output:
  syslog:
    enabled: true
    facility: LOG_LOCAL1
    priority: LOG_WARNING
    tag: "falco"
  http:
    enabled: true
    url: "http://alertmanager:9093/api/v1/alerts"
  file:
    enabled: true
    filename: "/var/log/falco/alerts.log"

# Load default + custom rules
rules_files:
  - /etc/falco/falco_rules.yaml
  - /etc/falco/falco_rules.local.yaml
  - /etc/falco/k8s_audit_rules.yaml
  - /etc/falco/rules.d

# System call buffering
syscall_event_drops:
  actions:
    - log
    - alert
  rate: 0.03333
  max_burst: 1000

# JSON output for structured logging
json_output: true
file_output:
  enabled: true
  keep_alive: false
  filename: /var/log/falco/events.json
EOH

  depends_on = [null_resource.falco_installation]
}

# ─────────────────────────────────────────────────────────────────────────────
# 3. Falco Custom Rules - Security Monitoring
# ─────────────────────────────────────────────────────────────────────────────

resource "local_file" "falco_custom_rules" {
  filename = "${path.module}/../config/falco/rules.local.yaml"
  content  = <<-EOH
# Custom Falco rules for code-server infrastructure
# Priority: CRITICAL (must have), HIGH (should have), MEDIUM (nice-to-have)

# ═══════════════════════════════════════════════════════════════════════════
# 1. MALWARE DETECTION (8 rules)
# ═══════════════════════════════════════════════════════════════════════════

- rule: Unauthorized Executable Write
  desc: Detect write to binary/executable locations
  condition: >
    write and
    container and
    fd.name in (/usr/bin, /usr/local/bin, /bin, /sbin, /usr/sbin) and
    not proc.name in (install, cp, mv, tar, curl, wget, dpkg, rpm, apt, yum)
  output: >
    Unauthorized write to executable directory
    (user=%user.name container=%container.name file=%fd.name proc=%proc.name)
  priority: CRITICAL
  tags: [malware, file_modification]

- rule: Unauthorized Shell Spawn
  desc: Detect unexpected shell spawning (backdoor indicator)
  condition: >
    spawned_process and
    container and
    proc.name in (sh, bash, zsh, ksh) and
    ppid.name not in (docker, sshd, cron, systemd, init) and
    not proc.pname in (supervisord, s6-supervise)
  output: >
    Unauthorized shell spawn
    (user=%user.name container=%container.name parent=%proc.pname proc=%proc.name)
  priority: CRITICAL
  tags: [malware, shell_access, backdoor]

- rule: Reverse Shell Detection
  desc: Detect reverse shell connections (backdoor)
  condition: >
    outbound and
    container and
    fd.snet = "AF_INET" and
    fd.sport < 1024 and
    proc.name not in (python, ruby, perl, bash, sh, node)
  output: >
    Suspicious outbound connection (reverse shell indicator)
    (user=%user.name container=%container.name proc=%proc.name dest=%fd.sip:%fd.sport)
  priority: CRITICAL
  tags: [malware, network, reverse_shell]

- rule: Kernel Module Modification
  desc: Detect kernel module insertion/removal (rootkit)
  condition: >
    syscall in (init_module, delete_module) and
    container
  output: >
    Kernel module modification (rootkit indicator)
    (user=%user.name container=%container.name syscall=%syscall.name)
  priority: CRITICAL
  tags: [malware, kernel, rootkit]

- rule: Unauthorized Privilege Escalation
  desc: Detect setuid/setgid binary execution with privilege escalation
  condition: >
    execve and
    container and
    proc.uid = 0 and
    ppid.uid != 0
  output: >
    Privilege escalation detected
    (user=%user.name container=%container.name parent=%proc.pname proc=%proc.name uid=%proc.uid)
  priority: CRITICAL
  tags: [privilege_escalation, security_threat]

- rule: Memory Injection Detection
  desc: Detect ptrace-based memory injection (process injection attack)
  condition: >
    syscall = ptrace and
    container and
    not proc.name in (gdb, strace, lldb, valgrind)
  output: >
    Memory injection attempt
    (user=%user.name container=%container.name attacker=%proc.name target=%fd.name)
  priority: CRITICAL
  tags: [malware, memory_injection, process_injection]

- rule: Unauthorized Cron/At Usage
  desc: Detect cron/at job creation by unauthorized users
  condition: >
    (execve and (proc.name in (crontab, at))) and
    container and
    user.uid > 1000
  output: >
    Unauthorized cron job creation
    (user=%user.name container=%container.name proc=%proc.name)
  priority: HIGH
  tags: [persistence, cron_abuse]

- rule: Cryptominer Detection
  desc: Detect cryptocurrency mining activity
  condition: >
    spawned_process and
    container and
    (proc.name in (xmrig, cpuminer, minerd, ethminer) or
     proc.cmdline contains "stratum" or
     proc.cmdline contains "mining" or
     proc.cmdline contains "xmr-pool")
  output: >
    Cryptominer detected
    (user=%user.name container=%container.name proc=%proc.name cmdline=%proc.cmdline)
  priority: CRITICAL
  tags: [malware, cryptomining, resource_abuse]

# ═══════════════════════════════════════════════════════════════════════════
# 2. PRIVILEGE ESCALATION (10 rules)
# ═══════════════════════════════════════════════════════════════════════════

- rule: Sudo Usage
  desc: Log all sudo executions
  condition: >
    spawned_process and
    proc.name = sudo
  output: >
    Sudo execution
    (user=%user.name real_uid=%user.uid container=%container.name target=%proc.pname)
  priority: HIGH
  tags: [privilege_escalation, audit]

- rule: Unexpected Sudo
  desc: Alert on sudo from non-interactive sessions
  condition: >
    spawned_process and
    proc.name = sudo and
    not proc.pname in (bash, sh, zsh, ksh, systemd)
  output: >
    Unexpected sudo (possible exploit)
    (user=%user.name container=%container.name parent=%proc.pname)
  priority: HIGH
  tags: [privilege_escalation, security_threat]

- rule: Setuid Execution
  desc: Track setuid binary execution
  condition: >
    execve and
    fd.mode contains "S_ISUID" and
    not proc.name in (sudo, su, passwd, chsh, newgrp)
  output: >
    Setuid binary execution
    (user=%user.name container=%container.name proc=%proc.name uid=%proc.uid)
  priority: MEDIUM
  tags: [privilege_escalation, audit]

- rule: Capability Modification
  desc: Detect capability set/unset (CAP_SYS_ADMIN, CAP_NET_ADMIN)
  condition: >
    syscall = capset and
    container
  output: >
    Capability modification
    (user=%user.name container=%container.name syscall=%syscall.name)
  priority: HIGH
  tags: [privilege_escalation, capabilities]

- rule: PAM/NSS Manipulation
  desc: Detect /etc/passwd, /etc/shadow, /etc/sudoers modification
  condition: >
    write and
    container and
    fd.name in (/etc/passwd, /etc/shadow, /etc/sudoers, /etc/sudoers.d)
  output: >
    Authentication file modification (possible privilege escalation)
    (user=%user.name container=%container.name file=%fd.name)
  priority: CRITICAL
  tags: [privilege_escalation, auth_bypass]

- rule: Group Modification
  desc: Detect group changes
  condition: >
    write and
    container and
    fd.name = /etc/group
  output: >
    Group modification
    (user=%user.name container=%container.name file=%fd.name)
  priority: HIGH
  tags: [privilege_escalation, auth]

- rule: LD_PRELOAD Injection
  desc: Detect LD_PRELOAD environment variable (library injection attack)
  condition: >
    spawned_process and
    container and
    proc.env contains "LD_PRELOAD"
  output: >
    LD_PRELOAD injection detected (library hijacking)
    (user=%user.name container=%container.name proc=%proc.name)
  priority: CRITICAL
  tags: [privilege_escalation, library_injection]

- rule: Unauthorized SSH Key Addition
  desc: Detect SSH key addition to authorized_keys
  condition: >
    write and
    container and
    fd.name glob "*/~/.ssh/authorized_keys" and
    user.uid > 1000
  output: >
    SSH key addition by non-admin user
    (user=%user.name container=%container.name file=%fd.name)
  priority: HIGH
  tags: [privilege_escalation, persistence, ssh]

- rule: Docker Socket Access
  desc: Detect unauthorized Docker socket access (container escape)
  condition: >
    open and
    container and
    fd.name = /var/run/docker.sock and
    user.uid > 1000
  output: >
    Unauthorized Docker socket access (possible container escape)
    (user=%user.name container=%container.name)
  priority: CRITICAL
  tags: [privilege_escalation, container_escape, docker]

- rule: Sysctl Modification
  desc: Detect kernel parameter modification (hardening bypass)
  condition: >
    execve and
    container and
    proc.name = sysctl
  output: >
    Kernel parameter modification
    (user=%user.name container=%container.name cmdline=%proc.cmdline)
  priority: HIGH
  tags: [privilege_escalation, hardening_bypass]

# ═══════════════════════════════════════════════════════════════════════════
# 3. SUSPICIOUS BEHAVIOR (15 rules)
# ═══════════════════════════════════════════════════════════════════════════

- rule: Suspicious Package Manager Usage
  desc: Alert on package manager usage outside expected times
  condition: >
    spawned_process and
    container and
    proc.name in (apt, yum, dpkg, rpm) and
    user.uid = 0
  output: >
    Package manager executed
    (user=%user.name container=%container.name proc=%proc.name cmdline=%proc.cmdline)
  priority: MEDIUM
  tags: [suspicious_behavior, package_mgmt]

- rule: Suspicious Network Tool Usage
  desc: Detect nmap, netstat, tcpdump (recon tools)
  condition: >
    spawned_process and
    container and
    proc.name in (nmap, netstat, ss, tcpdump, nc, ncat, telnet)
  output: >
    Network recon tool executed
    (user=%user.name container=%container.name proc=%proc.name)
  priority: MEDIUM
  tags: [suspicious_behavior, recon]

- rule: Suspicious Outbound Connection
  desc: Detect outbound connections to suspicious destinations
  condition: >
    outbound and
    container and
    not fd.snet in ("AF_UNIX", "AF_INET") and
    not fd.sip in (8.8.8.8, 8.8.4.4, 1.1.1.1)
  output: >
    Suspicious outbound connection
    (user=%user.name container=%container.name dest=%fd.sip:%fd.sport)
  priority: MEDIUM
  tags: [suspicious_behavior, network]

- rule: Large File Download
  desc: Alert on downloads > 100MB (potential malware/data exfiltration)
  condition: >
    syscall in (read, readv) and
    container and
    fd.bytes > 104857600
  output: >
    Large file download/read
    (user=%user.name container=%container.name file=%fd.name size=%fd.bytes)
  priority: HIGH
  tags: [suspicious_behavior, data_exfiltration]

- rule: Process Hiding Attempt
  desc: Detect process from being hidden via /proc manipulation
  condition: >
    write and
    container and
    fd.name glob "/proc/*/comm"
  output: >
    Process hiding attempt
    (user=%user.name container=%container.name file=%fd.name)
  priority: HIGH
  tags: [suspicious_behavior, process_hiding]

# ═══════════════════════════════════════════════════════════════════════════
# 4. COMPLIANCE VIOLATIONS (12 rules)
# ═══════════════════════════════════════════════════════════════════════════

- rule: Unauthorized File Access
  desc: Detect reads to sensitive files
  condition: >
    open and
    container and
    fd.name in (/etc/shadow, /etc/secret*, /etc/ssl/private/*, /root/.ssh) and
    not proc.name in (sudo, su, systemd, sshd) and
    user.uid > 0
  output: >
    Unauthorized sensitive file access
    (user=%user.name container=%container.name file=%fd.name proc=%proc.name)
  priority: HIGH
  tags: [compliance, data_protection]

- rule: Failed Sudo Authentication
  desc: Alert on failed sudo attempts
  condition: >
    spawned_process and
    proc.name = sudo and
    exit_code != 0
  output: >
    Failed sudo authentication
    (user=%user.name container=%container.name exit_code=%proc.exit_code)
  priority: MEDIUM
  tags: [compliance, audit]

- rule: Unencrypted Credential Transmission
  desc: Detect sending credentials over unencrypted channel
  condition: >
    syscall in (write, sendto) and
    container and
    (fd.data contains "password" or fd.data contains "secret" or fd.data contains "token") and
    not fd.sport = 443
  output: >
    Unencrypted credential transmission
    (user=%user.name container=%container.name dest=%fd.sip:%fd.sport)
  priority: CRITICAL
  tags: [compliance, data_protection, encryption]

- rule: Excessive File Change Rate
  desc: Alert on suspicious file modification bursts
  condition: >
    write and
    container and
    event_count > 1000 in 60s
  output: >
    Excessive file modification rate (possible malware)
    (user=%user.name container=%container.name rate=%event_count/min)
  priority: HIGH
  tags: [compliance, anomaly_detection]

EOH

  depends_on = [null_resource.falco_installation]
}

# ─────────────────────────────────────────────────────────────────────────────
# 4. Falco Sidekick - Output Dispatcher for Alerts
# ─────────────────────────────────────────────────────────────────────────────

resource "local_file" "falco_sidekick_config" {
  filename = "${path.module}/../config/falco/sidekick-config.yaml"
  content  = <<-EOH
# Falco Sidekick v0.30.0 - Output dispatcher
server:
  listenaddress: "0.0.0.0"
  listenport: 2801

debug: false

# AlertManager webhook
alertmanager:
  enabled: true
  hostport: "alertmanager:9093"

# Syslog output
syslog:
  enabled: true
  host: "localhost"
  port: 514
  facility: "LOG_LOCAL1"
  protocol: "tcp"

# Webhook output (custom integrations)
webhook:
  enabled: true
  address: "http://alertmanager:9093/api/v1/alerts"
  minimumpriority: "WARNING"

# S3 output (for long-term audit)
s3:
  enabled: false
  # Configure: bucket, endpoint, accesskey, secretkey, prefix

# Elasticsearch output (optional)
elasticsearch:
  enabled: false
  # Configure: host, port, index

EOF

  depends_on = [null_resource.falco_installation]
}

# ─────────────────────────────────────────────────────────────────────────────
# 5. Monitoring & Alerting - Falco Event Tracking
# ─────────────────────────────────────────────────────────────────────────────

resource "local_file" "falco_monitoring_alerts" {
  filename = "${path.module}/../config/monitoring/falco-alerts.yaml"
  content  = yamlencode({
    groups = [
      {
        name  = "falco-runtime-security"
        rules = [
          {
            alert      = "FalcoCriticalEvent"
            expr       = "increase(falco_events_total{priority=\"CRITICAL\"}[5m]) > 0"
            for        = "1m"
            labels     = { severity = "critical" }
            annotations = { summary = "Falco CRITICAL event detected" }
          },
          {
            alert      = "FalcoHighEventRate"
            expr       = "rate(falco_events_total[5m]) > 100"
            for        = "5m"
            labels     = { severity = "warning" }
            annotations = { summary = "High event rate (possible DoS or malware)" }
          },
          {
            alert      = "FalcoCryptominingDetected"
            expr       = "increase(falco_events_total{rule=\"Cryptominer Detection\"}[5m]) > 0"
            for        = "1m"
            labels     = { severity = "critical" }
            annotations = { summary = "Cryptominer activity detected" }
          },
          {
            alert      = "FalcoPrivilegeEscalation"
            expr       = "increase(falco_events_total{rule=~\".*Privilege Escalation.*\"}[5m]) > 0"
            for        = "1m"
            labels     = { severity = "high" }
            annotations = { summary = "Privilege escalation attempt detected" }
          },
          {
            alert      = "FalcoReverseShell"
            expr       = "increase(falco_events_total{rule=\"Reverse Shell Detection\"}[5m]) > 0"
            for        = "1m"
            labels     = { severity = "critical" }
            annotations = { summary = "Reverse shell connection detected (backdoor)" }
          },
          {
            alert      = "FalcoKernelModification"
            expr       = "increase(falco_events_total{rule=\"Kernel Module Modification\"}[5m]) > 0"
            for        = "1m"
            labels     = { severity = "critical" }
            annotations = { summary = "Rootkit attempt (kernel module modification)" }
          },
          {
            alert      = "FalcoUnauthorizedShell"
            expr       = "increase(falco_events_total{rule=\"Unauthorized Shell Spawn\"}[5m]) > 0"
            for        = "1m"
            labels     = { severity = "high" }
            annotations = { summary = "Unauthorized shell spawn (backdoor indicator)" }
          },
        ]
      }
    ]
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# 6. Outputs
# ─────────────────────────────────────────────────────────────────────────────

output "falco_status" {
  value       = "CONFIGURED - Falco v${var.falco_version} eBPF monitoring enabled"
  description = "Falco deployment status"
}

output "falco_config_file" {
  value       = local_file.falco_config.filename
  description = "Falco configuration file path"
}

output "falco_rules_file" {
  value       = local_file.falco_custom_rules.filename
  description = "Falco custom rules file path"
}

output "falco_sidekick_config_file" {
  value       = local_file.falco_sidekick_config.filename
  description = "Falco Sidekick configuration file path"
}

output "falco_rules_summary" {
  value = {
    malware_detection        = "8 rules (unauthorized exec, reverse shell, kernel mods, crypto mining)"
    privilege_escalation     = "10 rules (sudo, setuid, capabilities, PAM, SSH keys, Docker socket)"
    suspicious_behavior      = "15 rules (network tools, file downloads, process hiding, network connections)"
    compliance_violations    = "12 rules (sensitive file access, auth failures, unencrypted creds)"
    total_rules             = "45+ custom rules"
  }
  description = "Falco custom security rules summary"
}

output "monitoring_alerts_file" {
  value       = local_file.falco_monitoring_alerts.filename
  description = "Prometheus alert rules for Falco events"
}

output "critical_alerts" {
  value = [
    "FalcoCriticalEvent - Any CRITICAL security event",
    "FalcoCryptominingDetected - Cryptominer activity",
    "FalcoReverseShell - Backdoor connection attempts",
    "FalcoKernelModification - Rootkit attempts",
    "FalcoPrivilegeEscalation - Privilege escalation attempts",
  ]
  description = "Critical security alerts from Falco"
}
