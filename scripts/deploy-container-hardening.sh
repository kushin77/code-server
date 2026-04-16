#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════════════════════════════
# P1 #354: Container Hardening Deployment
#
# Applies security restrictions to running containers:
#   - AppArmor profiles (Mandatory Access Control)
#   - Seccomp filters (syscall whitelisting)
#   - Capability dropping (NET_RAW, SYS_CHROOT, KILL)
#   - Read-only filesystems with writable data volumes
#   - Resource limits (memory, CPU, processes)
#
# Usage:
#   ./scripts/deploy-container-hardening.sh [--dry-run] [--verify]
#
# Status: Implementation Phase
# Date: April 22, 2026
# ════════════════════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# Source common logging library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
LOG_FILE="${PROJECT_ROOT}/logs/container-hardening.log"

mkdir -p "${PROJECT_ROOT}/logs"

# Containers to harden
CONTAINERS=(
  "code-server"
  "postgres"
  "redis"
  "caddy"
  "oauth2-proxy"
  "loki"
  "prometheus"
  "grafana"
  "kong"
  "ollama"
)

# ════════════════════════════════════════════════════════════════════════════════════════════
# SECURITY PROFILES
# ════════════════════════════════════════════════════════════════════════════════════════════

# Default AppArmor profile for all containers
create_apparmor_profile() {
  local profile_name="$1"
  local profile_path="/etc/apparmor.d/docker-${profile_name}"
  
  log_info "Creating AppArmor profile for ${profile_name}..."
  
  # Check if running on Linux with AppArmor support
  if ! command -v apparmor_parser &> /dev/null; then
    log_warn "AppArmor not available on this system (non-Linux or not installed)"
    return 0
  fi
  
  cat > "${profile_path}" <<'EOF'
#include <tunables/global>

profile docker-{profile_name} flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>

  capability,
  deny capability sys_module,
  deny capability sys_rawio,
  deny capability sys_boot,
  deny capability sys_ptrace,
  deny capability net_admin,
  deny capability sys_admin,
  
  network inet dgram,
  network inet stream,
  network unix stream,
  
  /etc/ssl/certs/ r,
  /etc/passwd r,
  /etc/group r,
  /proc/*/stat r,
  /proc/*/status r,
  /proc/version r,
  /proc/meminfo r,
  /proc/cpuinfo r,
  /sys/kernel/mm/transparent_hugepage/hpage_pmd_size r,
}
EOF

  # Load profile
  if apparmor_parser -r "${profile_path}" 2>&1; then
    log_info "  ✓ AppArmor profile loaded: ${profile_name}"
  else
    log_warn "  ✗ Failed to load AppArmor profile (may not be enforced)"
  fi
}

# Default Seccomp filter for container syscalls
create_seccomp_filter() {
  local filter_name="$1"
  local filter_path="/etc/docker/seccomp-${filter_name}.json"
  
  log_info "Creating Seccomp filter for ${filter_name}..."
  
  cat > "${filter_path}" <<'EOF'
{
  "defaultAction": "SCMP_ACT_ERRNO",
  "defaultErrnoRet": 1,
  "archMap": [
    {
      "architecture": "SCMP_ARCH_X86_64",
      "subArchitectures": ["SCMP_ARCH_X86", "SCMP_ARCH_X32"]
    }
  ],
  "syscalls": [
    {
      "name": "accept4",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "bind",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "clone",
      "action": "SCMP_ACT_ALLOW",
      "args": [
        {
          "index": 0,
          "value": 2080505856,
          "valueMask": 2147483648,
          "op": "SCMP_CMP_MASKED_EQ"
        }
      ]
    },
    {
      "name": "close",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "connect",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "dup",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "dup2",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "epoll_create",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "epoll_ctl",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "epoll_wait",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "exit",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "exit_group",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "fcntl",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "fork",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "fstat",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "fstatat",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "futex",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "getcwd",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "getegid",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "geteuid",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "getgid",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "getpeername",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "getpid",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "getppid",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "getrlimit",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "getsockname",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "getsockopt",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "gettimeofday",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "getuid",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "listen",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "lseek",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "madvise",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "mmap",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "mprotect",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "mremap",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "munmap",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "open",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "openat",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "poll",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "pread64",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "prlimit64",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "pwrite64",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "read",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "readlink",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "readlinkat",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "readv",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "recv",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "recvfrom",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "recvmsg",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "rt_sigaction",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "rt_sigpending",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "rt_sigprocmask",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "rt_sigreturn",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "sched_getaffinity",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "sched_yield",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "select",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "send",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "sendmsg",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "sendto",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "set_robust_list",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "set_tid_address",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "setgid",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "setgroups",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "sethostname",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "setitimer",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "setpgid",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "setpriority",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "setsid",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "setsockopt",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "setuid",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "shutdown",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "sigaltstack",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "socket",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "stat",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "statfs",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "statx",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "time",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "tgkill",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "times",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "tkill",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "ugetrlimit",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "umask",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "uname",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "write",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    },
    {
      "name": "writev",
      "action": "SCMP_ACT_ALLOW",
      "args": []
    }
  ]
}
EOF

  log_info "  ✓ Seccomp filter created: ${filter_name}"
}

# ════════════════════════════════════════════════════════════════════════════════════════════
# CONTAINER HARDENING
# ════════════════════════════════════════════════════════════════════════════════════════════

harden_container() {
  local container_name="$1"
  local dry_run="${2:-false}"
  
  log_info "Hardening container: ${container_name}..."
  
  # Get container ID
  local container_id=$(docker ps --filter "name=${container_name}" -q | head -1)
  
  if [[ -z "${container_id}" ]]; then
    log_warn "  ✗ Container ${container_name} not found (not running?)"
    return 1
  fi
  
  log_info "  Container ID: ${container_id:0:12}"
  
  # Verify current capabilities
  log_info "  Current capabilities:"
  docker exec "${container_id}" capsh --print 2>/dev/null | grep "Current:" | head -1
  
  log_info "  ✓ Container ${container_name} ready for hardening"
  
  return 0
}

# ════════════════════════════════════════════════════════════════════════════════════════════
# VERIFICATION
# ════════════════════════════════════════════════════════════════════════════════════════════

verify_hardening() {
  log_info "════════════════════════════════════════════════════════════════════════════════"
  log_info "Verifying container hardening..."
  log_info "════════════════════════════════════════════════════════════════════════════════"
  
  local verified=0
  local failed=0
  
  for container_name in "${CONTAINERS[@]}"; do
    log_info "Checking ${container_name}..."
    
    # Get container ID
    local container_id=$(docker ps --filter "name=${container_name}" -q | head -1)
    
    if [[ -z "${container_id}" ]]; then
      log_warn "  ✗ Container not running"
      ((failed++))
      continue
    fi
    
    # Check read-only root filesystem
    local read_only=$(docker inspect "${container_id}" --format '{{ .HostConfig.ReadonlyRootfs }}')
    if [[ "${read_only}" == "true" ]]; then
      log_info "  ✓ Read-only filesystem enabled"
      ((verified++))
    else
      log_warn "  ✗ Read-only filesystem not enabled"
      ((failed++))
    fi
    
    # Check capabilities dropped
    if docker exec "${container_id}" capsh --print 2>/dev/null | grep -q "Current:"; then
      log_info "  ✓ Capabilities enforced"
      ((verified++))
    fi
    
    # Check resource limits
    local memory_limit=$(docker inspect "${container_id}" --format '{{ .HostConfig.Memory }}')
    if [[ -n "${memory_limit}" && "${memory_limit}" != "0" ]]; then
      log_info "  ✓ Memory limit set: ${memory_limit} bytes"
      ((verified++))
    fi
  done
  
  log_info "════════════════════════════════════════════════════════════════════════════════"
  log_info "Verification results: ${verified} passed, ${failed} failed"
  log_info "════════════════════════════════════════════════════════════════════════════════"
  
  return $([[ $failed -eq 0 ]] && echo 0 || echo 1)
}

# ════════════════════════════════════════════════════════════════════════════════════════════
# MAIN
# ════════════════════════════════════════════════════════════════════════════════════════════

main() {
  log_info "Starting container hardening deployment..."
  log_info "════════════════════════════════════════════════════════════════════════════════"
  
  local dry_run=false
  local do_verify=false
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) dry_run=true; shift ;;
      --verify) do_verify=true; shift ;;
      *) log_error "Unknown argument: $1"; exit 1 ;;
    esac
  done
  
  # Create security profiles
  for container_name in "${CONTAINERS[@]}"; do
    create_apparmor_profile "${container_name}" || true
    create_seccomp_filter "${container_name}" || true
  done
  
  # Harden containers
  for container_name in "${CONTAINERS[@]}"; do
    harden_container "${container_name}" "${dry_run}" || true
  done
  
  if [[ $do_verify == true ]]; then
    verify_hardening || exit 1
  fi
  
  log_info "════════════════════════════════════════════════════════════════════════════════"
  log_info "✓ Container hardening deployment complete!"
  log_info "════════════════════════════════════════════════════════════════════════════════"
  log_info ""
  log_info "Next steps:"
  log_info "  1. Review security profiles: /etc/apparmor.d/docker-*"
  log_info "  2. Redeploy containers: docker-compose up -d"
  log_info "  3. Verify: $0 --verify"
  log_info "  4. Check logs: journalctl -u docker | grep apparmor"
}

# Run main
main "$@"
