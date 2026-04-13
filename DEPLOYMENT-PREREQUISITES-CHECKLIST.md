# Deployment Prerequisites Validation Checklist

**Date**: April 13, 2026  
**Status**: 🔍 **VALIDATING PREREQUISITES**  
**Target**: Kubernetes cluster infrastructure readiness

---

## Infrastructure Requirements

### Compute Resources

**Required Hardware per Node**:

```
Control Plane Node (1 required):
├── CPU: 4+ cores (8+ recommended for production)
├── RAM: 8GB+ (16GB+ recommended)
├── Disk: 50GB+ (SSD recommended)
├── Network: 1Gbps+ connectivity
└── OS: Ubuntu 22.04 LTS, CentOS 8+, or RHEL 8+

Worker Nodes (2+ required, 3+ for HA):
├── CPU: 4+ cores (8+ cores recommended)
├── RAM: 8GB+ (16GB+ recommended)
├── Disk: 50GB+ (SSD for etcd, NVMe optimal)
├── Network: 1Gbps+ connectivity
└── OS: Same as control plane
```

**Recommended Deployment Models**:

| Model | Control Nodes | Worker Nodes | Total Cores | Total RAM | Use Case |
|-------|---------------|--------------|------------|-----------|----------|
| **Development** | 1 | 1-2 | 8-12 | 16-24GB | Testing, dev environments |
| **Staging** | 1 | 2-3 | 12-20 | 32-48GB | Pre-production validation |
| **Production** | 3 | 3-5+ | 24-40+ | 64-128GB+ | Enterprise workloads |

### Network Requirements

**Network Configuration**:
- [ ] Pod CIDR: 10.244.0.0/16 (Flannel default)
- [ ] Service CIDR: 10.96.0.0/12 (Kubernetes default)
- [ ] Node subnet: 192.168.1.0/24 (example, adjust per environment)
- [ ] Load balancer IPs: 192.168.1.100-192.168.1.110 (MetalLB)
- [ ] DNS: Resolvable hostnames for all nodes
- [ ] Firewall: Ports 6443, 10250, 2379-2380 open between nodes

**Network Ports Required**:

| Port | Protocol | Component | Purpose |
|------|----------|-----------|---------|
| 6443 | TCP | API Server | Kubernetes API |
| 10250 | TCP | Kubelet | Node communication |
| 10251 | TCP | Scheduler | Service |
| 10252 | TCP | Controller | Service |
| 2379-2380 | TCP | etcd | Cluster state |
| 30000-32767 | TCP/UDP | NodePort | Service access |

### Storage Requirements

**Persistent Volume Options**:

- [ ] **NFS Storage**:
  - NFS server (192.168.1.50 example)
  - NFS share: /data/kubernetes
  - Permissions: 777 (ownership: root:root)
  - Performance: 1Gbps+ network

- [ ] **Block Storage**:
  - iSCSI targets or local LVM
  - 100GB+ available
  - RAID-1 minimum (HA requirement)

- [ ] **Local Storage**:
  - `/mnt/data` on each worker node
  - 50GB+ per node
  - SSDs recommended for performance

**Storage Classes Prerequisites**:
- [ ] At least one storage provider configured
- [ ] Default storage class defined
- [ ] PV provisioner (NFS, iSCSI, or local)
- [ ] Volume snapshots enabled (optional but recommended)

---

## Software Prerequisites

### Kubernetes Tools

**Installed & Verified on All Nodes**:

- [x] **Docker** (or containerd)
  ```bash
  docker --version  # v20.10+
  docker ps  # Verify daemon running
  ```

- [ ] **kubectl**
  ```bash
  kubectl version --client  # v1.26+
  ```

- [ ] **kubeadm**
  ```bash
  kubeadm version  # v1.26+
  ```

- [ ] **kubelet**
  ```bash
  kubelet --version  # v1.26+
  systemctl status kubelet  # Should be active
  ```

- [ ] **kustomize**
  ```bash
  kustomize version  # v5.0+
  ```

- [ ] **helm**
  ```bash
  helm version  # v3.10+
  ```

### System Configuration

**Disable swap on all nodes**:
```bash
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab
```

**Enable required kernel modules**:
```bash
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter
```

**Set required sysctl parameters**:
```bash
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF

sudo sysctl --system
```

**Container runtime configuration**:
```bash
sudo mkdir -p /etc/docker
cat <<EOF | sudo tee /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF

sudo systemctl daemon-reload
sudo systemctl restart docker
```

### Security Prerequisites

- [ ] **SSH Key Pair** for cluster access
  ```bash
  ssh-keygen -t rsa -b 4096 -f ~/.ssh/k8s-deploy
  ```

- [ ] **TLS Certificates** for cluster
  ```bash
  # Generated automatic by kubeadm, but have backup location
  mkdir -p ~/k8s-certs-backup
  ```

- [ ] **kubeconfig** file location
  ```bash
  mkdir -p ~/.kube
  touch ~/.kube/config
  chmod 600 ~/.kube/config
  ```

- [ ] **Harbor Registry** or Docker Hub credentials (for private images)
  ```bash
  kubectl create secret docker-registry regcred \
    --docker-server=<registry> \
    --docker-username=<user> \
    --docker-password=<pass>
  ```

---

## Pre-Deployment Validation Checklist

### System Checks

- [ ] All nodes powered on and reachable via SSH
  ```bash
  for node in <node-ips>; do ping -c 1 $node; done
  ```

- [ ] Internet connectivity on all nodes
  ```bash
  curl -I https://www.google.com
  ```

- [ ] NTP synchronized on all nodes
  ```bash
  timedatectl status
  ntpstat
  ```

- [ ] Hostname resolution working
  ```bash
  nslookup <control-plane-node>
  ping <worker-node>
  ```

- [ ] No port conflicts
  ```bash
  sudo netstat -tuln | grep -E "6443|10250|2379|2380"
  ```

### Dependency Checks

- [ ] Docker/containerd with correct version
  ```bash
  docker --version | grep -E "20\.|21\.|22\."
  ```

- [ ] kubectl accessible
  ```bash
  which kubectl
  ```

- [ ] kubeadm accessible
  ```bash
  which kubeadm
  ```

- [ ] Swap disabled
  ```bash
  free | grep -i swap  # Should show 0
  ```

- [ ] Required kernel modules loaded
  ```bash
  lsmod | grep -E "overlay|br_netfilter"
  ```

- [ ] sysctl parameters set
  ```bash
  sysctl net.bridge.bridge-nf-call-iptables
  sysctl net.ipv4.ip_forward
  ```

### Network Checks

- [ ] Control plane node IP accessible from all workers
  ```bash
  curl -k https://<control-plane-ip>:6443/api/v1/
  ```

- [ ] Inter-node communication verified
  ```bash
  ssh node2 'ping -c 1 <node1-ip>'
  ```

- [ ] DNS resolution working
  ```bash
  nslookup kubernetes.default
  getent hosts <control-plane-hostname>
  ```

- [ ] Firewall rules allowing required ports
  ```bash
  sudo ufw allow 6443/tcp  # Or firewall-cmd equivalent
  ```

### Storage Checks

- [ ] NFS share accessible (if using NFS)
  ```bash
  sudo mount -t nfs <nfs-server>:/data/kubernetes /mnt/test
  sudo umount /mnt/test
  ```

- [ ] Block storage accessible (if using iSCSI)
  ```bash
  sudo iscsiadm -m node -T <iqn> -p <ip>:3260 --login
  ```

- [ ] Local storage paths writable
  ```bash
  sudo mkdir -p /mnt/data
  sudo touch /mnt/data/test.txt
  sudo rm /mnt/data/test.txt
  ```

---

## Go/No-Go Decision

### Green Light ✅ (Proceed to Deployment)

**All of the following must be true**:

- [x] All nodes powered on and network accessible
- [x] All required software installed and verified
- [x] System configuration completed (swap disabled, kernel modules, sysctl)
- [x] Network connectivity verified between all nodes
- [x] Storage backend accessible and mounted
- [x] DNS resolution working correctly
- [x] No port conflicts detected
- [x] Firewall rules allowing Kubernetes traffic
- [x] SSH access confirmed to all nodes
- [x] Time synchronized across all nodes

**If all green, proceed to Phase 1: Infrastructure Init**

### Red Light 🛑 (Stop and Resolve)

**If any of these are true, resolve before proceeding**:

- [ ] Any node unreachable or offline
- [ ] Missing required software (kubectl, kubeadm, docker)
- [ ] Network connectivity issues
- [ ] Storage backend not accessible
- [ ] DNS resolution failing
- [ ] Port conflicts detected
- [ ] Firewall blocking required ports
- [ ] Swap still enabled
- [ ] System time not synchronized
- [ ] SSH access issues

**Troubleshooting Resources**:
- See `docs/runbooks/CRITICAL-SERVICE-DOWN.md` for diagnostics
- Check `docs/ON-PREMISES-COMPLIANCE-SECURITY.md` for security issues
- Review `kubernetes/README.md` for Kubernetes-specific help

---

## Environment Configuration

### Node Inventory (Example)

```
Control Plane Nodes (HA):
├── k8s-control-1: 192.168.1.10
├── k8s-control-2: 192.168.1.11
└── k8s-control-3: 192.168.1.12

Worker Nodes:
├── k8s-worker-1: 192.168.1.20
├── k8s-worker-2: 192.168.1.21
├── k8s-worker-3: 192.168.1.22
└── k8s-worker-4: 192.168.1.23

Load Balancer (VRRP/IP):
└── k8s-api-lb: 192.168.1.100 (VIP)

Storage:
├── NFS: 192.168.1.50:/data/kubernetes
└── Backup: Network attached storage
```

### Configuration Files

**Create kubeadm config** (`kubeadm-config.yml`):
```yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: v1.27.0
controlPlaneEndpoint: k8s-api-lb:6443
networking:
  podSubnet: 10.244.0.0/16
  serviceSubnet: 10.96.0.0/12
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
nodeRegistration:
  name: k8s-control-1
  taints:
    - key: node-role.kubernetes.io/control-plane
      effect: NoSchedule
localAPIEndpoint:
  advertiseAddress: 192.168.1.10
  bindPort: 6443
```

---

## Final Checklist Before Deployment

| Item | Status | Notes |
|------|--------|-------|
| All nodes online | ⬜ | |
| Docker/containerd running | ⬜ | |
| kubectl accessible | ⬜ | |
| kubeadm accessible | ⬜ | |
| kustomize installed | ⬜ | |
| Swap disabled | ⬜ | |
| Kernel modules loaded | ⬜ | |
| sysctl parameters set | ⬜ | |
| Network connectivity verified | ⬜ | |
| DNS resolution working | ⬜ | |
| Firewall rules configured | ⬜ | |
| Storage accessible | ⬜ | |
| SSH keys generated | ⬜ | |
| kubeconfig prepared | ⬜ | |
| Backup location ready | ⬜ | |
| Team standing by | ⬜ | |
| Deployment runbook reviewed | ⬜ | |

---

## Deployment Commitment

Once all checklist items are verified:

**Sign-off**:
- [ ] Infrastructure Lead: _________________ Date: _______
- [ ] Operations Lead: _________________ Date: _______
- [ ] Security Lead: _________________ Date: _______

**Approval for Deployment**: _________________

---

**Status**: 🔍 **PREREQUISITES VALIDATION IN PROGRESS**  
**Target Completion**: April 13, 2026 (end of shift)  
**Next Step**: Begin Phase 1 - Kubernetes Cluster Init

---

## Quick Reference Commands

```bash
# Validate node readiness
for node in 192.168.1.{10..23}; do
  echo "Checking $node..."
  ssh ubuntu@$node 'systemctl status docker && kubelet --version'
done

# Check system requirements
free -h && df -h && lsmod | grep overlay

# Validate network
ping 192.168.1.100 && nslookup kubernetes.default

# Test storage
mount -t nfs 192.168.1.50:/data/kubernetes /mnt/test

# All-in-one validation script
./scripts/validate-prerequisites.sh
```

---

*Generated: April 13, 2026*  
*Document Version: 1.0*  
*Status: ACTIVE - Deployment Phase 3*
