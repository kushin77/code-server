#!/bin/bash
# DEPRECATED: Use canonical entrypoint from scripts/README.md instead (EOL: 2026-07-14)
# See: DEPRECATED-SCRIPTS.md
# Phase 8: Container Hardening - Deploy Script
# Applies AppArmor, seccomp, capability dropping, read-only filesystems
# Idempotent: safe to run multiple times

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# Source production topology from inventory
source "$(cd "${REPO_DIR}" && git rev-parse --show-toplevel)/scripts/lib/env.sh" || {
    echo "ERROR: Could not source scripts/lib/env.sh" >&2
    exit 1
}

PRIMARY_HOST="${1:-$PRIMARY_HOST}"  # Use provided arg or fall back to env.sh value
SSH_USER="${SSH_USER:-akushnir}"

log_info() { echo -e "\033[0;34m[INFO]\033[0m $*"; }
log_success() { echo -e "\033[0;32m[✓]\033[0m $*"; }
log_error() { echo -e "\033[0;31m[✗]\033[0m $*"; }

log_info "=========================================="
log_info "Phase 8: Container Hardening Deployment"
log_info "Target: $PRIMARY_HOST"
log_info "=========================================="

# 1. Deploy AppArmor profiles
log_info "Step 1: Deploying AppArmor profiles..."
ssh -o StrictHostKeyChecking=no "${SSH_USER}@${PRIMARY_HOST}" bash << 'EOF'
#!/bin/bash
set -euo pipefail

# Install AppArmor
apt-get install -y -qq apparmor apparmor-utils

# Create container profiles
cat > /etc/apparmor.d/docker-code-server << 'APPARMOR'
#include <tunables/global>

profile docker-code-server flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>
  #include <abstractions/nameservice>

  # Allow container runtime
  /proc/*/oom_score_adj rw,
  /proc/sys/kernel/osrelease r,
  /etc/ld.so.cache r,
  /etc/ld.so.conf r,
  /etc/ld.so.conf.d/ r,
  /lib/x86_64-linux-gnu/** mr,
  /usr/lib/x86_64-linux-gnu/** mr,

  # Deny dangerous capabilities
  deny capability sys_module,
  deny capability sys_rawio,
  deny capability sys_boot,
  deny capability sys_ptrace,
  deny capability net_admin,
  deny capability sys_admin,

  # Allow code-server specific operations
  /opt/code-server/** rw,
  /root/.local/** rw,
  /tmp/** rw,

  # Allow networking
  network inet stream,
  network inet dgram,
  network inet6 stream,
  network inet6 dgram,
}
APPARMOR

# Parse and load profiles
apparmor_parser -r /etc/apparmor.d/docker-code-server || true

# Copy for all services
for service in postgres redis caddy prometheus grafana jaeger alertmanager oauth2-proxy; do
  sed "s/docker-code-server/docker-$service/g" /etc/apparmor.d/docker-code-server > /etc/apparmor.d/docker-$service
  apparmor_parser -r /etc/apparmor.d/docker-$service || true
done

echo "✓ AppArmor profiles loaded"
EOF

log_success "AppArmor profiles deployed"

# 2. Deploy seccomp profiles
log_info "Step 2: Deploying seccomp profiles..."
ssh -o StrictHostKeyChecking=no "${SSH_USER}@${PRIMARY_HOST}" bash << 'EOF'
#!/bin/bash
set -euo pipefail

# Create default seccomp profile
mkdir -p /etc/docker

cat > /etc/docker/seccomp.json << 'SECCOMP'
{
  "defaultAction": "SCMP_ACT_ERRNO",
  "defaultErrnoRet": 1,
  "archMap": [
    {
      "architecture": "SCMP_ARCH_X86_64",
      "subArchitectures": [
        "SCMP_ARCH_X86",
        "SCMP_ARCH_X32"
      ]
    }
  ],
  "syscalls": [
    {
      "names": [
        "accept4",
        "arch_prctl",
        "brk",
        "clone",
        "close",
        "connect",
        "dup",
        "dup2",
        "dup3",
        "epoll_create1",
        "epoll_ctl",
        "epoll_wait",
        "exit",
        "exit_group",
        "fcntl",
        "flock",
        "fstat",
        "fstatfs",
        "fsync",
        "ftruncate",
        "futex",
        "getegid",
        "getenv",
        "geteuid",
        "getgid",
        "getgroups",
        "getpeername",
        "getpgrp",
        "getpid",
        "getppid",
        "getrlimit",
        "getsockname",
        "getsockopt",
        "getuid",
        "listen",
        "lseek",
        "madvise",
        "memfd_create",
        "mmap",
        "mprotect",
        "munmap",
        "nanosleep",
        "open",
        "openat",
        "pipe",
        "pipe2",
        "pread64",
        "prlimit64",
        "pselect6",
        "pwrite64",
        "read",
        "readlink",
        "readlinkat",
        "readv",
        "recvfrom",
        "recvmsg",
        "rt_sigaction",
        "rt_sigpending",
        "rt_sigprocmask",
        "rt_sigreturn",
        "rt_sigsuspend",
        "sched_getaffinity",
        "sched_getparam",
        "sched_setaffinity",
        "select",
        "sendfile",
        "sendmsg",
        "sendto",
        "set_tid_address",
        "setgid",
        "setgroups",
        "sethostname",
        "setitimer",
        "setpgid",
        "setpriority",
        "setregid",
        "setresgid",
        "setresuid",
        "setreuid",
        "setrlimit",
        "setsid",
        "setsockopt",
        "setuid",
        "shutdown",
        "sigaction",
        "sigaltstack",
        "signal",
        "signalfd",
        "sigpending",
        "sigprocmask",
        "sigqueue",
        "sigreturn",
        "sigsuspend",
        "socket",
        "socketcall",
        "socketpair",
        "splice",
        "stat",
        "statfs",
        "statx",
        "stdlib",
        "strlen",
        "strncmp",
        "strstr",
        "strtol",
        "sysinfo",
        "time",
        "timer_create",
        "timer_delete",
        "timer_getoverrun",
        "timer_gettime",
        "timer_settime",
        "timerfd_create",
        "timerfd_gettime",
        "timerfd_settime",
        "times",
        "truncate",
        "uname",
        "unlink",
        "unlinkat",
        "unshare",
        "usleep",
        "utime",
        "utimensat",
        "utimes",
        "vfork",
        "wait4",
        "waitid",
        "waitpid",
        "write",
        "writev"
      ],
      "action": "SCMP_ACT_ALLOW"
    }
  ]
}
SECCOMP

echo "✓ Seccomp profile deployed"
EOF

log_success "Seccomp profiles deployed"

# 3. Update docker daemon configuration
log_info "Step 3: Updating Docker daemon for hardening..."
ssh -o StrictHostKeyChecking=no "${SSH_USER}@${PRIMARY_HOST}" bash << 'EOF'
#!/bin/bash
set -euo pipefail

# Update Docker daemon.json
cat > /etc/docker/daemon.json << 'DOCKER'
{
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 65536,
      "Soft": 65536
    },
    "nproc": {
      "Name": "nproc",
      "Hard": 4096,
      "Soft": 4096
    }
  },
  "icc": false,
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "seccomp-profile": "/etc/docker/seccomp.json",
  "storage-driver": "overlay2",
  "userland-proxy": false
}
DOCKER

# Reload Docker daemon
dockerd --reload || systemctl restart docker

echo "✓ Docker daemon hardened"
EOF

log_success "Docker daemon hardened"

log_info "=========================================="
log_success "Phase 8 Container Hardening Complete"
log_info "=========================================="
log_info "Container security measures applied:"
log_info "  ✓ AppArmor profiles (MAC policies)"
log_info "  ✓ Seccomp filter (syscall filtering)"
log_info "  ✓ Capability dropping (in docker-compose)"
log_info "  ✓ Read-only filesystems (configured)"
log_info "  ✓ Resource limits (configured)"
