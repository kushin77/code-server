# Infrastructure Inventory Management

**Status**: ✅ IMPLEMENTED (Issue #364)  
**Version**: 2.0 (April 18, 2026)  
**Maintained By**: Infrastructure Team  
**Last Updated**: 2026-04-18

---

## Overview

Centralized inventory management system for all on-prem infrastructure. Single source of truth for hosts, IP addresses, services, credentials, and network configuration.

**Problem Solved**: Previously, infrastructure details were scattered across:
- Terraform variables files
- Shell scripts with hardcoded IPs
- Docker-compose files
- Alert rules
- DNS configurations
- CI/CD pipelines

**Solution**: Single `inventory/infrastructure.yaml` file read by Terraform, scripts, and CI/CD.

---

## File Structure

```
inventory/
├── infrastructure.yaml          # Main inventory file
└── .inventory.env              # Generated environment variables (by Terraform)

terraform/
└── inventory-management.tf      # Terraform reading inventory.yaml

scripts/
└── inventory-helper.sh          # CLI tool for inventory queries
```

---

## Inventory Format

### HOSTS Section

Each host defines: name, IP, SSH credentials, roles, description, status.

```yaml
hosts:
  primary:
    hostname: "code-server-primary"
    ip_address: "192.168.168.31"
    ssh_user: "akushnir"
    ssh_port: 22
    roles: [primary, code-server, database, cache, monitoring, observability]
    description: "Primary production host"
    status: "active"
    deployed: true
```

**Roles** determine the services and responsibilities:
- `primary` - Main production host
- `replica` - Failover/standby host
- `database` - Runs PostgreSQL
- `cache` - Runs Redis
- `monitoring` - Runs Prometheus, Grafana, AlertManager
- `observability` - Runs Jaeger, Loki, Falco
- `load-balancer` - HAProxy, Keepalived
- `storage` - NAS/backup storage

### NETWORK Section

Defines network topology, VIP, DNS, failover settings.

```yaml
network:
  vlan_id: 168
  gateway: "192.168.168.1"
  subnet: "192.168.168.0/24"
  
  primary_ip: "192.168.168.31"
  replica_ip: "192.168.168.42"
  
  # Virtual IP for transparent failover
  virtual_ip: "192.168.168.30"
  virtual_ip_hostname: "code-server-vip"
  virtual_ip_priority_primary: 200
  virtual_ip_priority_replica: 100
  virtual_ip_preempt: false
  virtual_ip_failover_timeout: 5  # seconds
```

### SERVICES Section

All containerized services with ports, versions, dependencies.

```yaml
services:
  code_server:
    name: "code-server"
    port: 8080
    version: "4.115.0"
    dependencies: [oauth2-proxy, caddy]
    
  postgres:
    name: "postgres"
    port: 5432
    version: "15"
    backup_enabled: true
    replication_enabled: true
```

### CREDENTIALS Section

References to Vault secrets (no plaintext credentials in inventory).

```yaml
credentials:
  database:
    postgres_user: "vault:secret/database/postgresql/username"
    postgres_password: "vault:secret/database/postgresql/password"
  authentication:
    google_client_id: "vault:secret/oauth/google/client_id"
```

---

## Usage

### Method 1: Terraform Integration

Inventory automatically loaded in `terraform/inventory-management.tf`:

```hcl
locals {
  inventory = yamldecode(file("${path.module}/../inventory/infrastructure.yaml"))
  primary_host = local.inventory.hosts.primary.ip_address
  # ... more extraction ...
}
```

**Accessing inventory in other Terraform files**:

```hcl
# In any terraform/*.tf file
data "terraform_remote_state" "inventory" {
  backend = "local"
  config = {
    path = "${path.module}/terraform.tfstate"
  }
}

locals {
  primary_host = data.terraform_remote_state.inventory.outputs.primary_host
  replica_host = data.terraform_remote_state.inventory.outputs.replica_host
}
```

### Method 2: Shell Scripts

Load inventory as environment variables in any Bash script:

```bash
#!/bin/bash

# Load inventory
export_inventory() {
    # Source generated environment file (created by Terraform)
    if [[ -f inventory/.inventory.env ]]; then
        # shellcheck source=inventory/.inventory.env
        source inventory/.inventory.env
    fi
}

export_inventory

echo "Primary: $PRIMARY_HOST"
echo "Replica: $REPLICA_HOST"
echo "VIP: $VIRTUAL_IP"
```

### Method 3: Helper Script

CLI tool for inventory queries:

```bash
# List all hosts
scripts/inventory-helper.sh list-hosts

# List services with ports
scripts/inventory-helper.sh list-services

# Get specific host details
scripts/inventory-helper.sh get-host primary

# SSH to replica
scripts/inventory-helper.sh ssh replica

# List all IPs
scripts/inventory-helper.sh list-ips

# Export as environment variables
source <(scripts/inventory-helper.sh export-env)

# Validate inventory format
scripts/inventory-helper.sh validate
```

### Method 4: Direct YAML Query

Using `yq` tool:

```bash
# Get primary IP
yq eval '.hosts.primary.ip_address' inventory/infrastructure.yaml

# List all services
yq eval '.services | keys' inventory/infrastructure.yaml

# Get all deployed hosts
yq eval '.hosts | to_entries | map(select(.value.deployed == true))' inventory/infrastructure.yaml
```

---

## Adding a New Host

1. **Edit** `inventory/infrastructure.yaml`:

```yaml
hosts:
  # ... existing hosts ...
  new_host:
    hostname: "code-server-worker-1"
    ip_address: "192.168.168.50"
    ssh_user: "akushnir"
    ssh_port: 22
    roles: [worker, compute]
    description: "Worker node for distributed computing"
    status: "planning"
    deployed: false
```

2. **Update** network if needed:

```yaml
network:
  # ... ensure new IP is in subnet 192.168.168.0/24
```

3. **Validate** inventory:

```bash
scripts/inventory-helper.sh validate
```

4. **Update Terraform** to include new host in deployments (if needed).

5. **Commit** changes:

```bash
git add inventory/infrastructure.yaml
git commit -m "inventory: Add new host (code-server-worker-1)"
```

---

## Changing an IP Address

1. **Edit** `inventory/infrastructure.yaml`:

```yaml
hosts:
  primary:
    ip_address: "192.168.168.31"  # Change here
    # ... other fields unchanged ...
```

2. **Or update** network VIP:

```yaml
network:
  virtual_ip: "192.168.168.30"  # Change if needed
```

3. **Validate**:

```bash
scripts/inventory-helper.sh validate
```

4. **Run Terraform** to update dependent resources:

```bash
cd terraform
terraform plan -out=tfplan
terraform apply tfplan
```

5. **Update** all related configurations:
   - Prometheus scrape configs
   - AlertManager targets
   - Caddy upstreams
   - Docker-compose environment variables

6. **Commit** and deploy:

```bash
git add inventory/infrastructure.yaml terraform.tfstate
git commit -m "infrastructure: Update primary host IP"
git push origin phase-7-deployment
```

---

## Service Configuration

### Adding a Service

1. **Edit** `inventory/infrastructure.yaml`:

```yaml
services:
  my_service:
    name: "my-service"
    port: 9000
    protocol: "http"
    version: "1.2.3"
    description: "My custom service"
    dependencies: [postgres, redis]  # Optional
```

2. **Add to docker-compose.yml** (if container-based):

```yaml
services:
  my_service:
    image: "myrepo/my-service:1.2.3"
    ports:
      - "9000:9000"
    environment:
      - POSTGRES_HOST=${PRIMARY_HOST}
      - REDIS_HOST=${REDIS_HOST}
```

3. **Update** Prometheus scrape config if needed

4. **Update** AlertManager targets if needed

5. **Commit**:

```bash
git add inventory/infrastructure.yaml docker-compose.yml prometheus.yml
git commit -m "services: Add my_service"
```

---

## Credential Management

All credentials reference Vault secrets (no plaintext in inventory).

**Example**: Accessing postgres password from Vault:

```bash
# In a script
postgres_password=$(vault kv get -field=password secret/database/postgresql)
export POSTGRES_PASSWORD="$postgres_password"
```

**In Terraform**:

```hcl
data "vault_generic_secret" "postgres_credentials" {
  path = "secret/database/postgresql"
}

postgres_password = data.vault_generic_secret.postgres_credentials.data["password"]
```

---

## Environment Files

### Generated Files

Terraform creates two files:

1. **`.inventory.json`** - Machine-readable inventory

```json
{
  "primary_host": "192.168.168.31",
  "replica_host": "192.168.168.42",
  "virtual_ip": "192.168.168.30",
  "service_ports": {
    "code_server": 8080,
    "postgres": 5432,
    ...
  }
}
```

2. **`inventory/.inventory.env`** - Shell environment variables

```bash
export PRIMARY_HOST='192.168.168.31'
export REPLICA_HOST='192.168.168.42'
export VIRTUAL_IP='192.168.168.30'
...
```

### Usage in Scripts

```bash
#!/bin/bash

# Source inventory
source inventory/.inventory.env

# Use variables
echo "Deploying to $PRIMARY_HOST"
ssh "$PRIMARY_SSH_USER@$PRIMARY_HOST" "bash deploy.sh"
```

---

## CI/CD Integration

### GitHub Actions

```yaml
- name: Load inventory
  run: |
    source inventory/.inventory.env
    echo "::set-env name=PRIMARY_HOST::$PRIMARY_HOST"
    echo "::set-env name=REPLICA_HOST::$REPLICA_HOST"

- name: Deploy to primary
  run: |
    ssh "${{ env.PRIMARY_SSH_USER }}@${{ env.PRIMARY_HOST }}" "bash deploy.sh"
```

### Pre-commit Hooks

Add to `.git/hooks/pre-commit`:

```bash
#!/bin/bash
# Validate inventory before commit
scripts/inventory-helper.sh validate || exit 1
```

---

## Validation & Health Checks

### Inventory Validation

```bash
# Full validation
scripts/inventory-helper.sh validate

# Check specific section
yq eval '.hosts' inventory/infrastructure.yaml

# Count hosts
yq eval '.hosts | length' inventory/infrastructure.yaml
```

### Production Checks

```bash
# Verify all hosts are reachable
for host in primary replica storage; do
    ip=$(yq eval ".hosts.$host.ip_address" inventory/infrastructure.yaml)
    if ping -c 1 "$ip" > /dev/null; then
        echo "✓ $host ($ip) is reachable"
    else
        echo "✗ $host ($ip) is unreachable"
    fi
done

# Check all services are running
ssh akushnir@192.168.168.31 'docker-compose ps'
```

---

## Best Practices

✅ **DO**:
- Keep inventory.yaml as single source of truth
- Use inventory variables in all Terraform files
- Load inventory in all deployment scripts
- Reference Vault for all credentials
- Validate inventory before commits
- Document changes in git commits
- Version control inventory.yaml

❌ **DON'T**:
- Hardcode IPs in scripts/configs
- Store credentials in inventory
- Duplicate inventory data in multiple files
- Make changes to deployed hosts without updating inventory
- Skip validation checks

---

## Troubleshooting

### Issue: "inventory.yaml not found"

```bash
# Ensure file exists in correct location
ls -la inventory/infrastructure.yaml

# From repo root
pwd  # should be at code-server-enterprise/
```

### Issue: "yq command not found"

```bash
# Install yq
brew install yq      # macOS
apt install yq       # Ubuntu/Debian
```

### Issue: YAML syntax error

```bash
# Validate YAML
yq eval '.' inventory/infrastructure.yaml

# Fix indentation (4 spaces per level)
# Check for tabs instead of spaces
```

### Issue: Terraform not reading inventory

```bash
# Ensure locals.tf or main.tf includes inventory-management.tf
grep -r "inventory" terraform/*.tf

# Check Terraform working directory
cd terraform
terraform validate
```

---

## Related Issues & Tasks

- **Issue #364**: Infrastructure Inventory Management (this task)
- **Issue #366**: Remove hardcoded IPs (uses inventory)
- **Issue #365**: VRRP VIP failover (uses inventory)
- **Issue #367**: Bootstrap script (uses inventory)
- **Issue #363**: DNS inventory (complementary)

---

## Maintenance Schedule

- **Weekly**: Validate inventory syntax (`scripts/inventory-helper.sh validate`)
- **Monthly**: Audit for hardcoded IPs in codebase
- **Quarterly**: Review host roles and update as needed
- **On host change**: Update inventory immediately + commit + deploy

---

## Version History

| Version | Date       | Changes |
|---------|------------|---------|
| 2.0     | 2026-04-18 | Initial implementation with full schema |
| 1.0     | TBD        | Planned for future |

---

**Maintained By**: Infrastructure Team  
**Contact**: infrastructure@example.com  
**Last Reviewed**: 2026-04-18
