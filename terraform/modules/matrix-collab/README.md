# Matrix Collaboration Hub Terraform Module

Complete Matrix homeserver deployment with Element web client, chat platform bridges, presence sidecar, and VoIP/video conferencing.

## Features

- **Synapse Homeserver**: Full Matrix homeserver with OIDC authentication
- **Element Web**: Web-based Matrix client
- **Bridges**: Slack, Microsoft Teams, and Google Chat integration
- **Presence Sidecar**: Real-time user presence updates
- **Element Call**: VoIP and video conferencing (optional)
- **PostgreSQL**: Dedicated database for Synapse
- **Redis**: Session caching and presence data
- **Monitoring**: Prometheus metrics integration

## Prerequisites

- Docker and Docker Compose
- Terraform >= 1.0
- Existing Redis and PostgreSQL instances (or deploy via docker provider)
- Google OAuth credentials for OIDC (optional)

## Usage

### Basic Deployment

```hcl
module "matrix_collab" {
  source = "./modules/matrix-collab"

  environment             = "prod"
  matrix_domain           = "matrix.example.com"
  apex_domain             = "example.com"
  google_client_id        = var.google_client_id
  google_client_secret    = var.google_client_secret
  redis_url               = "redis://redis:6379"
  prometheus_url          = "http://prometheus:9090"
  
  enable_slack_bridge     = true
  enable_teams_bridge     = false
  enable_element_call     = false
  
  tags = {
    project = "matrix-collab"
    owner   = "platform-team"
  }
}
```

### Full Stack with All Features

```hcl
module "matrix_collab" {
  source = "./modules/matrix-collab"

  environment              = "prod"
  matrix_domain            = "matrix.example.com"
  apex_domain              = "example.com"
  google_client_id         = var.google_client_id
  google_client_secret     = var.google_client_secret
  synapse_admin_token      = random_password.synapse_admin.result
  redis_url                = module.redis.url
  prometheus_url           = "http://prometheus:9090"
  
  enable_slack_bridge      = true
  enable_teams_bridge      = true
  enable_google_chat_bridge = true
  enable_presence_sidecar  = true
  enable_element_call      = true
  
  synapse_max_upload_size  = 104857600  # 100MB
  synapse_db_pool_size     = 50
  
  tags = {
    project     = "matrix-collab"
    owner       = "platform-team"
    environment = "production"
  }
}
```

## Module Outputs

```hcl
# Access deployment outputs
output "matrix_homeserver" {
  value = module.matrix_collab.homeserver_url
}

output "element_client" {
  value = module.matrix_collab.element_url
}

output "call_service" {
  value = try(module.matrix_collab.element_call_url, "disabled")
}
```

## Variables

### Core Configuration

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `environment` | string | Deployment environment | "prod" |
| `matrix_domain` | string | Matrix homeserver domain | Required |
| `apex_domain` | string | Apex domain | Required |
| `google_client_id` | string | Google OAuth client ID | "" |
| `google_client_secret` | string | Google OAuth secret | "" |
| `synapse_admin_token` | string | Synapse admin token | "" |
| `redis_url` | string | Redis connection string | "redis://redis:6379" |
| `prometheus_url` | string | Prometheus metrics URL | "http://prometheus:9090" |

### Feature Flags

| Variable | Type | Default |
|----------|------|---------|
| `enable_slack_bridge` | bool | true |
| `enable_teams_bridge` | bool | false |
| `enable_google_chat_bridge` | bool | false |
| `enable_presence_sidecar` | bool | true |
| `enable_element_call` | bool | false |

### Tuning

| Variable | Type | Default | Notes |
|----------|------|---------|-------|
| `synapse_max_upload_size` | number | 52428800 | 50MB in bytes |
| `synapse_db_pool_size` | number | 25 | Connection pool size |
| `postgres_version` | string | "15" | PostgreSQL version |
| `docker_image_synapse` | string | "matrixdotorg/synapse:latest" | |
| `docker_image_element` | string | "vectorim/element-web:latest" | |

## Acceptance Criteria

- [x] Root module orchestrates all components
- [x] Homeserver module deploys Synapse with OIDC
- [x] Bridge modules for Slack/Teams/Google Chat
- [x] Presence sidecar module
- [x] Element Call module (optional)
- [x] Variables for all secrets (no hardcoded values)
- [x] Outputs for URLs, connection strings
- [x] `terraform apply` deploys full stack from scratch
- [x] `terraform destroy` cleanly removes all resources
- [x] State stored in existing Terraform backend
- [x] Documentation: README.md with usage examples

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Matrix Collab Hub                         │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │   Element    │  │   Element    │  │ Presence     │       │
│  │   Web        │  │   Call       │  │ Sidecar      │       │
│  │   (Port 80)  │  │   (Port 3000)│  │ (Port 9000)  │       │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘       │
│         │                  │                  │                │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Synapse Homeserver (Port 8008)                      │   │
│  │  - OIDC Authentication (Google)                      │   │
│  │  - Admin API                                         │   │
│  │  - Metrics Export (Prometheus)                       │   │
│  └──────────┬───────────────────────────────────────────┘   │
│             │                                                  │
│  ┌──────────┴──────────────────────────────────────────┐   │
│  │  Bridges                                             │   │
│  │  ├─ Slack Bridge (Port 8082)                        │   │
│  │  ├─ Teams Bridge (Port 8083)                        │   │
│  │  └─ Google Chat Bridge (Port 8084)                  │   │
│  └─────────────────────────────────────────────────────┘   │
│             │                                                  │
│  ┌──────────┴──────────────────────────────────────────┐   │
│  │  Data Layer                                          │   │
│  │  ├─ PostgreSQL 15 (Port 5433)                       │   │
│  │  └─ Redis 7 (Port 6379)                             │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

## Deployment Steps

1. **Initialize Terraform**:
```bash
cd terraform
terraform init
```

2. **Plan Deployment**:
```bash
terraform plan -out=plan.tfplan
```

3. **Apply Configuration**:
```bash
terraform apply plan.tfplan
```

4. **Verify Services**:
```bash
docker ps | grep -E "synapse|element|bridge"
curl https://matrix.example.com/_matrix/client/versions
```

5. **Post-Deployment Setup**:
   - Register admin user
   - Configure room federation
   - Set up bridge credentials
   - Enable presence sidecar

## Security Considerations

- **Secrets Management**: Use environment variables or Terraform Cloud for sensitive values
- **OIDC Only**: Disable native login in production
- **Network**: Place behind reverse proxy with TLS termination
- **Database**: Use strong passwords, consider encryption
- **Backups**: Regular PostgreSQL backups are essential
- **Monitoring**: Monitor Prometheus metrics for anomalies

## Troubleshooting

### Synapse won't start
```bash
docker logs synapse-homeserver
# Check PostgreSQL connectivity
docker logs synapse-postgres
```

### Bridge connection failures
- Verify admin token
- Check homeserver URL accessibility
- Review bridge credentials

### Presence sidecar errors
- Ensure Redis is accessible
- Check network connectivity to homeserver
- Monitor Redis memory usage

## Cost Estimation

Approximate monthly costs:
- Synapse container: ~$10-20
- Element container: ~$5-10
- PostgreSQL database: ~$15-30
- Redis cache: ~$5-10
- Network egress: ~$10-50
- **Total**: ~$45-120/month

## Support & Contributing

See main repository for contribution guidelines and support contacts.

## License

Same as parent project (kushin77/code-server)
