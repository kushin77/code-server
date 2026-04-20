## P1: Terraform IaC Modules for Full Collaboration Stack

### Summary

Create comprehensive Terraform modules for declarative deployment of the entire Matrix collaboration stack, enabling one-command rollout and reproducible infrastructure.

### Module Structure

```
terraform/modules/
├── matrix-collab/
│   ├── main.tf           # Root module orchestrating all components
│   ├── variables.tf      # Input variables
│   ├── outputs.tf        # Output values
│   └── modules/
│       ├── homeserver/   # Matrix Synapse/Dendrite
│       ├── bridges/      # Slack, Teams, Google Chat bridges
│       ├── presence/     # Presence sidecar service
│       ├── element-call/ # LiveKit + Element Call
│       ├── extension/    # code-server extension config
│       └── observability/# Prometheus/Grafana for Matrix
```

### Root Module

```hcl
# terraform/modules/matrix-collab/main.tf

variable "environment" {
  description = "Deployment environment (dev/staging/prod)"
  type        = string
}

variable "matrix_domain" {
  description = "Matrix homeserver domain"
  type        = string
  default     = "matrix.kushnir.cloud"
}

variable "primary_chat_platform" {
  description = "Primary chat platform to bridge (slack/teams/google)"
  type        = string
  default     = "slack"
}

# Matrix Homeserver
module "homeserver" {
  source = "./modules/homeserver"
  
  domain            = var.matrix_domain
  database_url      = module.postgres.connection_url
  federation_enabled = false
  
  oidc_config = {
    provider    = "google"
    client_id   = var.google_client_id
    client_secret = var.google_client_secret
    allowed_domain = "kushnir.cloud"
  }
}

# Chat Bridges
module "slack_bridge" {
  source = "./modules/bridges/slack"
  count  = var.primary_chat_platform == "slack" ? 1 : 0
  
  homeserver_url    = module.homeserver.url
  slack_bot_token   = var.slack_bot_token
  slack_client_id   = var.slack_client_id
  slack_client_secret = var.slack_client_secret
}

module "teams_bridge" {
  source = "./modules/bridges/teams"
  count  = var.primary_chat_platform == "teams" ? 1 : 0
  
  homeserver_url     = module.homeserver.url
  azure_tenant_id    = var.azure_tenant_id
  azure_client_id    = var.azure_client_id
  azure_client_secret = var.azure_client_secret
}

# Presence Sidecar
module "presence" {
  source = "./modules/presence"
  
  homeserver_url = module.homeserver.url
  redis_url      = var.redis_url
  replicas       = var.environment == "prod" ? 2 : 1
}

# Element Call (optional)
module "element_call" {
  source = "./modules/element-call"
  count  = var.enable_element_call ? 1 : 0
  
  homeserver_url = module.homeserver.url
  livekit_secret = var.livekit_secret
}

# Observability
module "matrix_observability" {
  source = "./modules/observability"
  
  prometheus_url = var.prometheus_url
  grafana_url    = var.grafana_url
  alert_slack_webhook = var.alert_slack_webhook
}
```

### Homeserver Module

```hcl
# terraform/modules/matrix-collab/modules/homeserver/main.tf

resource "docker_container" "synapse" {
  name  = "synapse"
  image = "matrixdotorg/synapse:latest"
  
  volumes {
    host_path      = "/data/synapse"
    container_path = "/data"
  }
  
  env = [
    "SYNAPSE_SERVER_NAME=${var.domain}",
    "SYNAPSE_REPORT_STATS=no",
  ]
  
  ports {
    internal = 8008
    external = 8008
  }
  
  networks_advanced {
    name = "net-app"
  }
  
  healthcheck {
    test     = ["CMD", "curl", "-f", "http://localhost:8008/health"]
    interval = "30s"
    timeout  = "10s"
    retries  = 3
  }
}

# Generate homeserver.yaml from template
resource "local_file" "homeserver_config" {
  filename = "/data/synapse/homeserver.yaml"
  content  = templatefile("${path.module}/templates/homeserver.yaml.tpl", {
    server_name    = var.domain
    database_url   = var.database_url
    oidc_config    = var.oidc_config
    federation     = var.federation_enabled
  })
}
```

### Docker Compose Template

```hcl
# terraform/modules/matrix-collab/templates/docker-compose.matrix.yml.tpl

version: "3.8"

services:
  synapse:
    image: matrixdotorg/synapse:${synapse_version}
    container_name: synapse
    restart: unless-stopped
    volumes:
      - synapse-data:/data
    environment:
      SYNAPSE_SERVER_NAME: ${server_name}
    ports:
      - "8008:8008"
    networks:
      - net-app
      - net-data
    depends_on:
      - postgres

  ${include_slack_bridge ? "slack-bridge:" : ""}
  ${include_slack_bridge ? "  image: dock.mau.dev/mautrix/slack:latest" : ""}
  ...

  presence-sidecar:
    image: ${presence_image}
    container_name: presence-sidecar
    restart: unless-stopped
    environment:
      MATRIX_HOMESERVER_URL: http://synapse:8008
      MATRIX_ACCESS_TOKEN: ${presence_bot_token}
    ports:
      - "8089:8089"
    networks:
      - net-app

volumes:
  synapse-data:

networks:
  net-app:
    external: true
  net-data:
    external: true
```

### One-Command Deployment

```bash
# Deploy full collaboration stack

# 1. Set variables
export TF_VAR_primary_chat_platform="slack"
export TF_VAR_slack_bot_token="xoxb-..."
export TF_VAR_google_client_id="..."
export TF_VAR_google_client_secret="..."

# 2. Apply Terraform
cd terraform/modules/matrix-collab
terraform init
terraform apply -auto-approve

# 3. Deploy code-server extension
ansible-playbook deploy-extensions.yml
```

### Variables File

```hcl
# terraform/modules/matrix-collab/variables.tf

variable "environment" {
  type = string
}

variable "matrix_domain" {
  type    = string
  default = "matrix.kushnir.cloud"
}

variable "primary_chat_platform" {
  type    = string
  default = "slack"
  validation {
    condition     = contains(["slack", "teams", "google"], var.primary_chat_platform)
    error_message = "Must be slack, teams, or google."
  }
}

variable "google_client_id" {
  type      = string
  sensitive = true
}

variable "google_client_secret" {
  type      = string
  sensitive = true
}

variable "slack_bot_token" {
  type      = string
  sensitive = true
  default   = ""
}

variable "enable_element_call" {
  type    = bool
  default = false
}

variable "redis_url" {
  type    = string
  default = "redis://redis:6379"
}
```

### Acceptance Criteria

- [ ] Root module `matrix-collab` orchestrates all components
- [ ] Homeserver module deploys Synapse with OIDC
- [ ] Bridge modules for Slack/Teams/Google Chat
- [ ] Presence sidecar module
- [ ] Element Call module (optional)
- [ ] Variables for all secrets (no hardcoded values)
- [ ] Outputs for URLs, connection strings
- [ ] `terraform apply` deploys full stack from scratch
- [ ] `terraform destroy` cleanly removes all resources
- [ ] State stored in existing Terraform backend
- [ ] Documentation: README.md with usage examples

### Integration with Existing IaC

```hcl
# terraform/main.tf (existing)

module "matrix_collab" {
  source = "./modules/matrix-collab"
  
  environment           = var.environment
  matrix_domain         = "matrix.${var.apex_domain}"
  primary_chat_platform = var.primary_chat_platform
  google_client_id      = var.google_client_id
  google_client_secret  = var.google_client_secret
  redis_url             = module.redis.url
  prometheus_url        = module.prometheus.url
}
```

### Dependencies

- Requires: #1001 (Architecture decisions)
- Blocks: All other Matrix deployments

### Parent

EPIC #TBD (Matrix Collaboration Hub)
