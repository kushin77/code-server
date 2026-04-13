# On-Premises Compliance & Security Hardening

## Network Isolation (Air-Gapped Deployments)

### Requirement: No Internet Access

If your on-premises cluster has no internet, pre-load all container images:

```bash
#!/bin/bash
# pre-load-images.sh - Create offline image registry

IMAGES=(
  "postgres:14"
  "redis:7-alpine"
  "prom/prometheus:latest"
  "grafana/grafana:latest"
  "grafana/loki:2.9"
  "jaegertracing/jaeger:latest"
  "busybox:latest"
  "code-server/code-server:latest"
  "code-server/agent-api:latest"
  "code-server/embeddings:latest"
)

# On machine with internet access:
for image in "${IMAGES[@]}"; do
  docker pull $image
  docker save $image | gzip > ${image//\//-}.tar.gz
done

# Transfer tar.gz files to on-premises via USB/network

# On on-premises cluster:
for image in *.tar.gz; do
  docker load < $image
  docker tag ${image%.tar.gz} registry.internal.company.com/${image%.tar.gz}:latest
  docker push registry.internal.company.com/${image%.tar.gz}:latest
done

# Update kustomization to use internal registry
sed -i 's|docker.io/|registry.internal.company.com/|g' kubernetes/overlays/production/kustomization.yaml
```

### Private Container Registry

```bash
# Setup local Docker registry
kubectl create namespace registry

kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: registry
  namespace: registry
spec:
  replicas: 1
  selector:
    matchLabels:
      app: registry
  template:
    metadata:
      labels:
        app: registry
    spec:
      containers:
      - name: registry
        image: registry:2
        ports:
        - containerPort: 5000
        volumeMounts:
        - name: registry-storage
          mountPath: /var/lib/registry
      volumes:
      - name: registry-storage
        persistentVolumeClaim:
          claimName: registry-pvc
EOF
```

## Authentication & Authorization

### RBAC (Role-Based Access Control) - No OAuth

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: code-server-deployer
  namespace: code-server
rules:
- apiGroups: ["apps"]
  resources: ["deployments", "statefulsets"]
  verbs: ["get", "list", "watch", "patch", "update"]
- apiGroups: [""]
  resources: ["pods", "logs"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: code-server-deployer-binding
  namespace: code-server
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: code-server-deployer
subjects:
- kind: User
  name: "deploy-user@company.com"
  apiGroup: rbac.authorization.k8s.io
```

### Local User Management

```bash
# Create client certificates for on-premises users

# 1. Generate private key
openssl genrsa -out alex.key 2048

# 2. Create certificate signing request
openssl req -new -key alex.key \
  -out alex.csr \
  -subj "/CN=alex/O=engineering"

# 3. Sign with cluster CA
sudo openssl x509 -req -days 365 \
  -in alex.csr \
  -CA /etc/kubernetes/pki/ca.crt \
  -CAkey /etc/kubernetes/pki/ca.key \
  -CAcreateserial \
  -out alex.crt

# 4. Create kubeconfig
kubectl config set-cluster on-prem \
  --certificate-authority=/etc/kubernetes/pki/ca.crt \
  --server=https://192.168.1.100:6443

kubectl config set-credentials alex \
  --client-certificate=alex.crt \
  --client-key=alex.key

kubectl config set-context alex-on-prem \
  --cluster=on-prem \
  --user=alex

# Distribute alex to user (kubeconfig + cert)
```

### Network Policies (Mandatory)

```yaml
# Default deny all traffic
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: code-server
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
---
# Allow code-server to database
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-db
  namespace: code-server
spec:
  podSelector:
    matchLabels:
      app: code-server
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: databases
    ports:
    - protocol: TCP
      port: 5432
---
# Allow ingress from load balancer only
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress
  namespace: code-server
spec:
  podSelector:
    matchLabels:
      app: code-server
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    ports:
    - protocol: TCP
      port: 8080
```

## Secrets Management (No Cloud KMS)

### Local Encryption at Rest

```yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
metadata:
  name: encryption
resources:
- resources:
  - secrets
  providers:
  - aescbc:
      keys:
      - name: key1
        secret: $(head -c 32 /dev/urandom | base64)  # 256-bit key
  - identity: {}
---
# Apply to API server
# --encryption-provider-config=/etc/kubernetes/pki/encryption-config.yaml
```

### Local Secrets Storage

```bash
# Store secrets in local vault on-prem (e.g., HashiCorp Vault)
# Or use sealed-secrets for Kubernetes-native encryption

helm install sealed-secrets \
  sealed-secrets/sealed-secrets \
  --namespace kube-system

# Encrypt a secret
echo -n "my-secret-password" | \
  kubectl create secret generic my-secret --dry-run=client \
  --from-file=password=/dev/stdin -o yaml | \
  kubectl seal -f - > my-secret-sealed.yaml

# Deploy sealed secret
kubectl apply -f my-secret-sealed.yaml
```

## Audit & Compliance

### Kubernetes Audit Logging

```yaml
apiVersion: audit.k8s.io/v1
kind: Policy
metadata:
  name: audit-policy
rules:
- level: Metadata
  omitStages:
  - RequestReceived
  resources:
  - group: ""
    resources: ["secrets"]
  namespaces: ["code-server", "agents", "databases"]
---
# Apply to API server
# --audit-policy-file=/etc/kubernetes/audit-policy.yaml
# --audit-log-path=/var/log/kubernetes/audit.log
# --audit-log-maxage=30
# --audit-log-maxbackup=10
```

### Compliance Checklist

- [ ] No public container registries (all images in private registry)
- [ ] All traffic encrypted in-transit (TLS 1.2+)
- [ ] All data encrypted at rest (etcd + database)
- [ ] RBAC enabled on all kubeconfig contexts
- [ ] Network policies enforcing zero-trust
- [ ] Audit logging enabled and monitored
- [ ] Pod Security Standards enforced
- [ ] No privileged containers without exception
- [ ] All nodes on same security patch level
- [ ] Firewall allows only required ports

## Operating System Hardening

### Ubuntu Node Hardening

```bash
#!/bin/bash
# harden-node.sh

# 1. Update system
apt-get update && apt-get upgrade -y

# 2. Disable unnecessary services
systemctl disable avahi-daemon
systemctl disable cups

# 3. Enable firewall
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp  # SSH
ufw allow 6443/tcp  # Kubernetes API
ufw allow 10250/tcp  # Kubelet
ufw allow 10251/tcp  # Scheduler
ufw allow 10252/tcp  # Controller Manager
ufw enable

# 4. Set file permissions
chmod 600 /etc/ssh/sshd_config
chmod -R 700 /root/.ssh

# 5. Disable root login
sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart sshd

# 6. Enable auditd
apt-get install -y auditd
systemctl enable auditd
systemctl start auditd

# 7. Configure limits
cat >> /etc/security/limits.conf <<EOF
* soft nofile 65536
* hard nofile 65536
* soft nproc 32768
* hard nproc 32768
EOF
```

### Kubernetes API Security

```bash
# 1. TLS for all communication
# Already configured in kubeadm but verify:
kubectl get secret -n kube-system | grep tls

# 2. RBAC enabled
kubectl api-resources | grep rbac

# 3. Pod Security Standard
kubectl label namespace code-server \
  pod-security.kubernetes.io/enforce=restricted

# 4. Admission controllers
# Verify in: kubectl cluster-info dump | grep admission-control
```

## Monitoring Compliance

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: compliance-alerts
  namespace: monitoring
spec:
  groups:
  - name: compliance.rules
    rules:
    - alert: UnencryptedSecret
      expr: |
        increase(apiserver_audit_event_total{verb="create",objectRef_resource="secrets"}[1h]) > 0
      annotations:
        summary: "Unencrypted secret created"

    - alert: PrivilegedContainerRunning
      expr: |
        increase(kubelet_pod_worker_duration_seconds_bucket{container_security_privileged="true"}[1h]) > 0
      annotations:
        summary: "Privileged container detected"

    - alert: RBACViolationAttempt
      expr: |
        increase(apiserver_audit_event_total{verb="create",user_username!="system:*"}[1h]) > 5
      annotations:
        summary: "High rate of RBAC violations"

    - alert: AuditLogNotWriting
      expr: |
        rate(kubelet_pod_worker_duration_seconds_count[5m]) == 0
      for: 10m
      annotations:
        summary: "Audit logging appears to have stopped"
```

## Compliance Reporting

```bash
#!/bin/bash
# compliance-report.sh - Generate monthly compliance report

echo "# Kubernetes Compliance Report - $(date +%Y-%m-%d)" > compliance-report.md

echo "## RBAC Status" >> compliance-report.md
kubectl get rolebindings -A | grep -v system: >> compliance-report.md

echo "## Network Policies" >> compliance-report.md
kubectl get networkpolicies -A >> compliance-report.md

echo "## Audit Log Summary" >> compliance-report.md
grep "audit" /var/log/kubernetes/audit.log | wc -l >> compliance-report.md
grep -i "error" /var/log/kubernetes/audit.log | tail -20 >> compliance-report.md

echo "## Pod Security Violations" >> compliance-report.md
kubectl get pods -A -o json | jq '.items[] | select(.spec.securityContext.privileged == true)' >> compliance-report.md

echo "## Certificate Expiry" >> compliance-report.md
kubeadm certs check-expiration >> compliance-report.md

# Send report
# mail -s "Compliance Report" security@company.com < compliance-report.md
```

---

**Summary**: On-premises deployments require local auth (certificates), network isolation (no cloud), and encrypted secrets at rest. Use sealed-secrets or local Vault for compliance.
