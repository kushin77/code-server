## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_local"></a> [local](#provider\_local) | 2.8.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_core"></a> [core](#module\_core) | ./modules/core | n/a |
| <a name="module_data"></a> [data](#module\_data) | ./modules/data | n/a |
| <a name="module_dns"></a> [dns](#module\_dns) | ./modules/dns | n/a |
| <a name="module_failover"></a> [failover](#module\_failover) | ./modules/failover | n/a |
| <a name="module_monitoring"></a> [monitoring](#module\_monitoring) | ./modules/monitoring | n/a |
| <a name="module_networking"></a> [networking](#module\_networking) | ./modules/networking | n/a |
| <a name="module_security"></a> [security](#module\_security) | ./modules/security | n/a |

## Resources

| Name | Type |
|------|------|
| [local_file.grafana_slo_dashboard](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.instrumentation_library](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.jaeger_compose](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.jaeger_config](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.jaeger_monitoring](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.kong_config](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.kong_prometheus_config](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.loki_compose](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.loki_config](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.loki_monitoring](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.otel_collector_config](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.prometheus_optimization](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.promtail_config](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.slo_rules](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_acme_email"></a> [acme\_email](#input\_acme\_email) | Email for ACME certificate registration | `string` | `"admin@kushnir.cloud"` | no |
| <a name="input_acme_provider"></a> [acme\_provider](#input\_acme\_provider) | ACME TLS certificate provider (letsencrypt/zerossl) | `string` | `"letsencrypt"` | no |
| <a name="input_acme_renewal_days_before_expiry"></a> [acme\_renewal\_days\_before\_expiry](#input\_acme\_renewal\_days\_before\_expiry) | Days before expiry to renew ACME certificate | `number` | `30` | no |
| <a name="input_alert_severity_critical_enabled"></a> [alert\_severity\_critical\_enabled](#input\_alert\_severity\_critical\_enabled) | Enable critical severity alerts | `bool` | `true` | no |
| <a name="input_alert_severity_high_enabled"></a> [alert\_severity\_high\_enabled](#input\_alert\_severity\_high\_enabled) | Enable high severity alerts | `bool` | `true` | no |
| <a name="input_alert_severity_medium_enabled"></a> [alert\_severity\_medium\_enabled](#input\_alert\_severity\_medium\_enabled) | Enable medium severity alerts | `bool` | `true` | no |
| <a name="input_alertmanager_cpu_limit"></a> [alertmanager\_cpu\_limit](#input\_alertmanager\_cpu\_limit) | AlertManager container CPU limit | `string` | `"0.25"` | no |
| <a name="input_alertmanager_memory_limit"></a> [alertmanager\_memory\_limit](#input\_alertmanager\_memory\_limit) | AlertManager container memory limit | `string` | `"256m"` | no |
| <a name="input_alertmanager_port"></a> [alertmanager\_port](#input\_alertmanager\_port) | AlertManager port | `number` | `9093` | no |
| <a name="input_alertmanager_version"></a> [alertmanager\_version](#input\_alertmanager\_version) | AlertManager version | `string` | `"v0.26.0"` | no |
| <a name="input_allowed_email_addresses"></a> [allowed\_email\_addresses](#input\_allowed\_email\_addresses) | Email addresses allowed to access via Cloudflare Access | `list(string)` | <pre>[<br>  "alex@kushnir.cloud"<br>]</pre> | no |
| <a name="input_audit_log_retention_days"></a> [audit\_log\_retention\_days](#input\_audit\_log\_retention\_days) | Security audit log retention (days) | `number` | `90` | no |
| <a name="input_backup_compression_enabled"></a> [backup\_compression\_enabled](#input\_backup\_compression\_enabled) | Enable backup compression | `bool` | `true` | no |
| <a name="input_backup_method"></a> [backup\_method](#input\_backup\_method) | Backup method (pg\_basebackup/pgbackrest/wal-g) | `string` | `"pg_basebackup"` | no |
| <a name="input_backup_retention_days"></a> [backup\_retention\_days](#input\_backup\_retention\_days) | Backup retention period (days) | `number` | `30` | no |
| <a name="input_backup_schedule_cron"></a> [backup\_schedule\_cron](#input\_backup\_schedule\_cron) | Backup schedule in cron format | `string` | `"0 2 * * *"` | no |
| <a name="input_backup_storage_backend"></a> [backup\_storage\_backend](#input\_backup\_storage\_backend) | Backup storage (local/s3/minio) | `string` | `"minio"` | no |
| <a name="input_brotli_compression"></a> [brotli\_compression](#input\_brotli\_compression) | Enable Brotli compression | `bool` | `true` | no |
| <a name="input_cache_level"></a> [cache\_level](#input\_cache\_level) | Cloudflare cache level | `string` | `"cache_everything"` | no |
| <a name="input_caddy_cpu_limit"></a> [caddy\_cpu\_limit](#input\_caddy\_cpu\_limit) | Caddy container CPU limit | `string` | `"0.25"` | no |
| <a name="input_caddy_http_port"></a> [caddy\_http\_port](#input\_caddy\_http\_port) | Caddy HTTP port | `number` | `80` | no |
| <a name="input_caddy_https_port"></a> [caddy\_https\_port](#input\_caddy\_https\_port) | Caddy HTTPS port | `number` | `443` | no |
| <a name="input_caddy_memory_limit"></a> [caddy\_memory\_limit](#input\_caddy\_memory\_limit) | Caddy container memory limit | `string` | `"256m"` | no |
| <a name="input_caddy_version"></a> [caddy\_version](#input\_caddy\_version) | Caddy reverse proxy version | `string` | `"2.7.6"` | no |
| <a name="input_cloudflare_account_id"></a> [cloudflare\_account\_id](#input\_cloudflare\_account\_id) | Cloudflare Account ID (numeric) | `string` | n/a | yes |
| <a name="input_cloudflare_api_token"></a> [cloudflare\_api\_token](#input\_cloudflare\_api\_token) | Cloudflare API token for zone management | `string` | n/a | yes |
| <a name="input_cloudflare_dns_proxy_enabled"></a> [cloudflare\_dns\_proxy\_enabled](#input\_cloudflare\_dns\_proxy\_enabled) | Enable Cloudflare DNS proxy (orange cloud) | `bool` | `true` | no |
| <a name="input_cloudflare_enabled"></a> [cloudflare\_enabled](#input\_cloudflare\_enabled) | Enable Cloudflare tunnel and CDN | `bool` | `true` | no |
| <a name="input_cloudflare_tunnel_cname"></a> [cloudflare\_tunnel\_cname](#input\_cloudflare\_tunnel\_cname) | Cloudflare tunnel CNAME endpoint (e.g., {uuid}.cfargotunnel.com) | `string` | `""` | no |
| <a name="input_cloudflare_tunnel_token"></a> [cloudflare\_tunnel\_token](#input\_cloudflare\_tunnel\_token) | Cloudflare Tunnel authentication token (injected from Vault at deploy time) | `string` | `""` | no |
| <a name="input_cloudflare_waf_enabled"></a> [cloudflare\_waf\_enabled](#input\_cloudflare\_waf\_enabled) | Enable Cloudflare WAF | `bool` | `true` | no |
| <a name="input_cloudflare_zone_id"></a> [cloudflare\_zone\_id](#input\_cloudflare\_zone\_id) | Cloudflare Zone ID for kushnir.cloud | `string` | n/a | yes |
| <a name="input_code_server_password"></a> [code\_server\_password](#input\_code\_server\_password) | Code-Server authentication password (minimum 12 characters, must contain uppercase, lowercase, numbers, symbols) | `string` | n/a | yes |
| <a name="input_code_server_version"></a> [code\_server\_version](#input\_code\_server\_version) | code-server base image version (must match codercom/code-server tags) | `string` | `"4.115.0"` | no |
| <a name="input_config_dir"></a> [config\_dir](#input\_config\_dir) | Configuration directory (by default, project root) | `string` | `"."` | no |
| <a name="input_container_image_scan_enabled"></a> [container\_image\_scan\_enabled](#input\_container\_image\_scan\_enabled) | Enable container image scanning | `bool` | `true` | no |
| <a name="input_coredns_cpu_limit"></a> [coredns\_cpu\_limit](#input\_coredns\_cpu\_limit) | CoreDNS container CPU limit | `string` | `"0.25"` | no |
| <a name="input_coredns_memory_limit"></a> [coredns\_memory\_limit](#input\_coredns\_memory\_limit) | CoreDNS container memory limit | `string` | `"128m"` | no |
| <a name="input_coredns_port"></a> [coredns\_port](#input\_coredns\_port) | CoreDNS DNS port | `number` | `53` | no |
| <a name="input_coredns_version"></a> [coredns\_version](#input\_coredns\_version) | CoreDNS version | `string` | `"1.10.1"` | no |
| <a name="input_deploy_host"></a> [deploy\_host](#input\_deploy\_host) | Deployment host (same as deployment\_host) | `string` | `"192.168.168.31"` | no |
| <a name="input_deploy_user"></a> [deploy\_user](#input\_deploy\_user) | Deployment user (same as deployment\_user) | `string` | `"akushnir"` | no |
| <a name="input_deployment_host"></a> [deployment\_host](#input\_deployment\_host) | SSH host for production deployment (IP or FQDN). Change this to scale/migrate infrastructure. | `string` | `"192.168.168.31"` | no |
| <a name="input_deployment_port"></a> [deployment\_port](#input\_deployment\_port) | SSH port for production deployment | `number` | `22` | no |
| <a name="input_deployment_user"></a> [deployment\_user](#input\_deployment\_user) | SSH user for production deployment | `string` | `"akushnir"` | no |
| <a name="input_disaster_recovery_enabled"></a> [disaster\_recovery\_enabled](#input\_disaster\_recovery\_enabled) | Enable disaster recovery procedures | `bool` | `true` | no |
| <a name="input_dns_failover_enabled"></a> [dns\_failover\_enabled](#input\_dns\_failover\_enabled) | Enable automatic DNS failover | `bool` | `true` | no |
| <a name="input_dns_failover_health_check_interval"></a> [dns\_failover\_health\_check\_interval](#input\_dns\_failover\_health\_check\_interval) | DNS failover health check interval (seconds) | `number` | `30` | no |
| <a name="input_dns_failover_threshold"></a> [dns\_failover\_threshold](#input\_dns\_failover\_threshold) | Failed checks before failover | `number` | `3` | no |
| <a name="input_dns_ttl_default"></a> [dns\_ttl\_default](#input\_dns\_ttl\_default) | Default DNS TTL (seconds) | `number` | `300` | no |
| <a name="input_dns_ttl_short"></a> [dns\_ttl\_short](#input\_dns\_ttl\_short) | Short DNS TTL for failover (seconds) | `number` | `60` | no |
| <a name="input_dnssec_enabled"></a> [dnssec\_enabled](#input\_dnssec\_enabled) | Enable DNSSEC for domain | `bool` | `true` | no |
| <a name="input_docker_context"></a> [docker\_context](#input\_docker\_context) | Docker context to use (e.g., 'default' or 'desktop-linux' on Docker Desktop) | `string` | `"default"` | no |
| <a name="input_docker_host"></a> [docker\_host](#input\_docker\_host) | Docker daemon socket URI (e.g., unix:///var/run/docker.sock or tcp://docker:2375) | `string` | `"unix:///var/run/docker.sock"` | no |
| <a name="input_domain"></a> [domain](#input\_domain) | Root domain for deployment (used by oauth2-proxy for OIDC redirect) | `string` | `"ide.kushnir.cloud"` | no |
| <a name="input_domain_primary"></a> [domain\_primary](#input\_domain\_primary) | Primary domain name | `string` | `"kushnir.cloud"` | no |
| <a name="input_domain_secondary"></a> [domain\_secondary](#input\_domain\_secondary) | Secondary domain for failover | `string` | `"code-server.kushnir.cloud"` | no |
| <a name="input_enable_apparmor"></a> [enable\_apparmor](#input\_enable\_apparmor) | Enable AppArmor security profiles | `bool` | `true` | no |
| <a name="input_enable_cross_region_replication"></a> [enable\_cross\_region\_replication](#input\_enable\_cross\_region\_replication) | Enable cross-region backup replication | `bool` | `false` | no |
| <a name="input_enable_dns_dnssec"></a> [enable\_dns\_dnssec](#input\_enable\_dns\_dnssec) | Enable DNSSEC signing | `bool` | `true` | no |
| <a name="input_enable_dns_rate_limiting"></a> [enable\_dns\_rate\_limiting](#input\_enable\_dns\_rate\_limiting) | Enable DNS query rate limiting | `bool` | `true` | no |
| <a name="input_enable_hot_standby"></a> [enable\_hot\_standby](#input\_enable\_hot\_standby) | Enable hot standby mode (read replica) | `bool` | `true` | no |
| <a name="input_enable_https"></a> [enable\_https](#input\_enable\_https) | Enable HTTPS/TLS (managed by Caddy with ACME) | `bool` | `true` | no |
| <a name="input_enable_ollama"></a> [enable\_ollama](#input\_enable\_ollama) | Enable Ollama local LLM service | `bool` | `true` | no |
| <a name="input_enable_policy_enforcement"></a> [enable\_policy\_enforcement](#input\_enable\_policy\_enforcement) | Enable OPA policy enforcement | `bool` | `true` | no |
| <a name="input_enable_rate_limiting"></a> [enable\_rate\_limiting](#input\_enable\_rate\_limiting) | Enable Kong rate limiting | `bool` | `true` | no |
| <a name="input_enable_replication"></a> [enable\_replication](#input\_enable\_replication) | Enable PostgreSQL replication | `bool` | `true` | no |
| <a name="input_enable_runtime_monitoring"></a> [enable\_runtime\_monitoring](#input\_enable\_runtime\_monitoring) | Enable Falco runtime security monitoring | `bool` | `true` | no |
| <a name="input_enable_seccomp"></a> [enable\_seccomp](#input\_enable\_seccomp) | Enable seccomp system call filtering | `bool` | `true` | no |
| <a name="input_enable_secret_management"></a> [enable\_secret\_management](#input\_enable\_secret\_management) | Enable Vault secret management | `bool` | `true` | no |
| <a name="input_enable_selinux"></a> [enable\_selinux](#input\_enable\_selinux) | Enable SELinux (if available on OS) | `bool` | `false` | no |
| <a name="input_enable_service_discovery"></a> [enable\_service\_discovery](#input\_enable\_service\_discovery) | Enable CoreDNS service discovery | `bool` | `true` | no |
| <a name="input_enable_synchronous_replication"></a> [enable\_synchronous\_replication](#input\_enable\_synchronous\_replication) | Enable synchronous replication (waits for replica ACK) | `bool` | `false` | no |
| <a name="input_enable_tls_termination"></a> [enable\_tls\_termination](#input\_enable\_tls\_termination) | Enable TLS termination on Caddy | `bool` | `true` | no |
| <a name="input_enable_workspace_mount"></a> [enable\_workspace\_mount](#input\_enable\_workspace\_mount) | Enable mounting local workspace into code-server | `bool` | `true` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name (production, staging, development) | `string` | `"production"` | no |
| <a name="input_failover_auto_enabled"></a> [failover\_auto\_enabled](#input\_failover\_auto\_enabled) | Enable automatic failover | `bool` | `true` | no |
| <a name="input_failover_timeout_seconds"></a> [failover\_timeout\_seconds](#input\_failover\_timeout\_seconds) | Failover timeout (seconds) | `number` | `300` | no |
| <a name="input_falco_cpu_limit"></a> [falco\_cpu\_limit](#input\_falco\_cpu\_limit) | Falco container CPU limit | `string` | `"0.5"` | no |
| <a name="input_falco_memory_limit"></a> [falco\_memory\_limit](#input\_falco\_memory\_limit) | Falco container memory limit | `string` | `"512m"` | no |
| <a name="input_falco_mode"></a> [falco\_mode](#input\_falco\_mode) | Falco execution mode (modern-bpf/legacy) | `string` | `"modern-bpf"` | no |
| <a name="input_falco_version"></a> [falco\_version](#input\_falco\_version) | Falco runtime security engine version | `string` | `"0.37.1"` | no |
| <a name="input_github_token"></a> [github\_token](#input\_github\_token) | GitHub Personal Access Token (optional, for higher Copilot rate limits) | `string` | `""` | no |
| <a name="input_godaddy_api_key"></a> [godaddy\_api\_key](#input\_godaddy\_api\_key) | GoDaddy API key | `string` | `""` | no |
| <a name="input_godaddy_api_secret"></a> [godaddy\_api\_secret](#input\_godaddy\_api\_secret) | GoDaddy API secret | `string` | `""` | no |
| <a name="input_godaddy_enabled"></a> [godaddy\_enabled](#input\_godaddy\_enabled) | Enable GoDaddy DNS failover | `bool` | `true` | no |
| <a name="input_google_client_id"></a> [google\_client\_id](#input\_google\_client\_id) | Google OAuth2 Client ID (from GCP Console OAuth2.0 credentials - required for production) | `string` | n/a | yes |
| <a name="input_google_client_secret"></a> [google\_client\_secret](#input\_google\_client\_secret) | Google OAuth2 Client Secret (from GCP Console OAuth2.0 credentials - required for production) | `string` | n/a | yes |
| <a name="input_grafana_admin_user"></a> [grafana\_admin\_user](#input\_grafana\_admin\_user) | Grafana admin username | `string` | `"admin"` | no |
| <a name="input_grafana_cpu_limit"></a> [grafana\_cpu\_limit](#input\_grafana\_cpu\_limit) | Grafana container CPU limit | `string` | `"0.5"` | no |
| <a name="input_grafana_memory_limit"></a> [grafana\_memory\_limit](#input\_grafana\_memory\_limit) | Grafana container memory limit | `string` | `"512m"` | no |
| <a name="input_grafana_port"></a> [grafana\_port](#input\_grafana\_port) | Grafana HTTP port | `number` | `3000` | no |
| <a name="input_grafana_version"></a> [grafana\_version](#input\_grafana\_version) | Grafana version | `string` | `"10.2.3"` | no |
| <a name="input_host_ip"></a> [host\_ip](#input\_host\_ip) | IP address of deployment host (for multi-host scaling) | `string` | `"192.168.168.31"` | no |
| <a name="input_hot_standby_enabled_failover"></a> [hot\_standby\_enabled\_failover](#input\_hot\_standby\_enabled\_failover) | Enable hot standby mode on replica | `bool` | `true` | no |
| <a name="input_http3_enabled"></a> [http3\_enabled](#input\_http3\_enabled) | Enable HTTP/3 (QUIC) protocol | `bool` | `true` | no |
| <a name="input_is_primary"></a> [is\_primary](#input\_is\_primary) | Is this the primary deployment (true) or replica/standby (false)? | `bool` | `true` | no |
| <a name="input_jaeger_cpu_limit"></a> [jaeger\_cpu\_limit](#input\_jaeger\_cpu\_limit) | Jaeger container CPU limit | `string` | `"0.5"` | no |
| <a name="input_jaeger_memory_limit"></a> [jaeger\_memory\_limit](#input\_jaeger\_memory\_limit) | Jaeger container memory limit | `string` | `"1g"` | no |
| <a name="input_jaeger_otlp_port"></a> [jaeger\_otlp\_port](#input\_jaeger\_otlp\_port) | Jaeger OTLP receiver port | `number` | `4317` | no |
| <a name="input_jaeger_port"></a> [jaeger\_port](#input\_jaeger\_port) | Jaeger UI port | `number` | `16686` | no |
| <a name="input_jaeger_version"></a> [jaeger\_version](#input\_jaeger\_version) | Jaeger distributed tracing version | `string` | `"1.50"` | no |
| <a name="input_kong_admin_port"></a> [kong\_admin\_port](#input\_kong\_admin\_port) | Kong admin API port (loopback only) | `number` | `8001` | no |
| <a name="input_kong_cpu_limit"></a> [kong\_cpu\_limit](#input\_kong\_cpu\_limit) | Kong container CPU limit | `string` | `"0.5"` | no |
| <a name="input_kong_memory_limit"></a> [kong\_memory\_limit](#input\_kong\_memory\_limit) | Kong container memory limit | `string` | `"512m"` | no |
| <a name="input_kong_postgres_version"></a> [kong\_postgres\_version](#input\_kong\_postgres\_version) | Kong database version | `string` | `"15"` | no |
| <a name="input_kong_proxy_port"></a> [kong\_proxy\_port](#input\_kong\_proxy\_port) | Kong proxy HTTP port | `number` | `8000` | no |
| <a name="input_kong_proxy_ssl_port"></a> [kong\_proxy\_ssl\_port](#input\_kong\_proxy\_ssl\_port) | Kong proxy HTTPS port | `number` | `8443` | no |
| <a name="input_kong_rate_limit_auth_minute"></a> [kong\_rate\_limit\_auth\_minute](#input\_kong\_rate\_limit\_auth\_minute) | Kong rate limit on auth endpoints (requests per minute) | `number` | `10` | no |
| <a name="input_kong_rate_limit_hour"></a> [kong\_rate\_limit\_hour](#input\_kong\_rate\_limit\_hour) | Kong global rate limit (requests per hour) | `number` | `1000` | no |
| <a name="input_kong_rate_limit_minute"></a> [kong\_rate\_limit\_minute](#input\_kong\_rate\_limit\_minute) | Kong global rate limit (requests per minute) | `number` | `60` | no |
| <a name="input_kong_version"></a> [kong\_version](#input\_kong\_version) | Kong API Gateway version | `string` | `"3.4.0-alpine"` | no |
| <a name="input_load_balancing_algorithm"></a> [load\_balancing\_algorithm](#input\_load\_balancing\_algorithm) | Load balancing algorithm (round\_robin/least\_conn/random/ip\_hash) | `string` | `"round_robin"` | no |
| <a name="input_log_level"></a> [log\_level](#input\_log\_level) | Logging level across all services | `string` | `"info"` | no |
| <a name="input_loki_cpu_limit"></a> [loki\_cpu\_limit](#input\_loki\_cpu\_limit) | Loki container CPU limit | `string` | `"0.5"` | no |
| <a name="input_loki_memory_limit"></a> [loki\_memory\_limit](#input\_loki\_memory\_limit) | Loki container memory limit | `string` | `"1g"` | no |
| <a name="input_loki_port"></a> [loki\_port](#input\_loki\_port) | Loki port | `number` | `3100` | no |
| <a name="input_loki_version"></a> [loki\_version](#input\_loki\_version) | Loki log aggregation version | `string` | `"2.9.5"` | no |
| <a name="input_max_wal_senders"></a> [max\_wal\_senders](#input\_max\_wal\_senders) | Maximum WAL sender connections | `number` | `10` | no |
| <a name="input_oauth2_proxy_cookie_secret"></a> [oauth2\_proxy\_cookie\_secret](#input\_oauth2\_proxy\_cookie\_secret) | OAuth2-Proxy cookie encryption secret (must be exactly 16, 24, or 32 bytes when decoded from base64; generate: openssl rand -base64 32) | `string` | n/a | yes |
| <a name="input_ollama_default_model"></a> [ollama\_default\_model](#input\_ollama\_default\_model) | Default model for Ollama inference (pulled on startup) | `string` | `"llama2:70b-chat"` | no |
| <a name="input_ollama_num_gpu"></a> [ollama\_num\_gpu](#input\_ollama\_num\_gpu) | Number of GPUs for Ollama (0 = CPU only) | `number` | `0` | no |
| <a name="input_ollama_num_threads"></a> [ollama\_num\_threads](#input\_ollama\_num\_threads) | Number of CPU threads for Ollama (0 = auto) | `number` | `8` | no |
| <a name="input_opa_cpu_limit"></a> [opa\_cpu\_limit](#input\_opa\_cpu\_limit) | OPA container CPU limit | `string` | `"0.25"` | no |
| <a name="input_opa_memory_limit"></a> [opa\_memory\_limit](#input\_opa\_memory\_limit) | OPA container memory limit | `string` | `"256m"` | no |
| <a name="input_opa_port"></a> [opa\_port](#input\_opa\_port) | OPA HTTP port | `number` | `8181` | no |
| <a name="input_opa_version"></a> [opa\_version](#input\_opa\_version) | Open Policy Agent version | `string` | `"0.58.0"` | no |
| <a name="input_patroni_enabled"></a> [patroni\_enabled](#input\_patroni\_enabled) | Enable Patroni for PostgreSQL HA | `bool` | `true` | no |
| <a name="input_patroni_version"></a> [patroni\_version](#input\_patroni\_version) | Patroni version | `string` | `"3.0"` | no |
| <a name="input_pgbouncer_connect_timeout"></a> [pgbouncer\_connect\_timeout](#input\_pgbouncer\_connect\_timeout) | PgBouncer connection timeout (seconds) | `number` | `15` | no |
| <a name="input_pgbouncer_pool_mode"></a> [pgbouncer\_pool\_mode](#input\_pgbouncer\_pool\_mode) | PgBouncer pool mode (session/transaction/statement) | `string` | `"transaction"` | no |
| <a name="input_pgbouncer_pool_size"></a> [pgbouncer\_pool\_size](#input\_pgbouncer\_pool\_size) | PgBouncer connection pool size | `number` | `25` | no |
| <a name="input_pgbouncer_port"></a> [pgbouncer\_port](#input\_pgbouncer\_port) | PgBouncer port | `number` | `6432` | no |
| <a name="input_pgbouncer_version"></a> [pgbouncer\_version](#input\_pgbouncer\_version) | PgBouncer version | `string` | `"1.20"` | no |
| <a name="input_point_in_time_recovery_days"></a> [point\_in\_time\_recovery\_days](#input\_point\_in\_time\_recovery\_days) | Point-in-time recovery window (days) | `number` | `7` | no |
| <a name="input_postgres_password"></a> [postgres\_password](#input\_postgres\_password) | PostgreSQL password | `string` | `"changeme"` | no |
| <a name="input_postgres_user"></a> [postgres\_user](#input\_postgres\_user) | PostgreSQL username | `string` | `"postgres"` | no |
| <a name="input_primary_host_ip"></a> [primary\_host\_ip](#input\_primary\_host\_ip) | Primary host IP address for service discovery | `string` | `"192.168.168.31"` | no |
| <a name="input_prometheus_cpu_limit"></a> [prometheus\_cpu\_limit](#input\_prometheus\_cpu\_limit) | Prometheus container CPU limit | `string` | `"1.0"` | no |
| <a name="input_prometheus_memory_limit"></a> [prometheus\_memory\_limit](#input\_prometheus\_memory\_limit) | Prometheus container memory limit | `string` | `"2g"` | no |
| <a name="input_prometheus_port"></a> [prometheus\_port](#input\_prometheus\_port) | Prometheus metrics port | `number` | `9090` | no |
| <a name="input_prometheus_retention"></a> [prometheus\_retention](#input\_prometheus\_retention) | Prometheus data retention period | `string` | `"30d"` | no |
| <a name="input_prometheus_version"></a> [prometheus\_version](#input\_prometheus\_version) | Prometheus version | `string` | `"v2.48.0"` | no |
| <a name="input_promtail_version"></a> [promtail\_version](#input\_promtail\_version) | Promtail version (immutable) | `string` | `"2.9.4"` | no |
| <a name="input_redis_cpu_limit"></a> [redis\_cpu\_limit](#input\_redis\_cpu\_limit) | Redis container CPU limit | `string` | `"0.5"` | no |
| <a name="input_redis_memory_limit_container"></a> [redis\_memory\_limit\_container](#input\_redis\_memory\_limit\_container) | Redis container memory limit | `string` | `"512m"` | no |
| <a name="input_redis_persistence_enabled"></a> [redis\_persistence\_enabled](#input\_redis\_persistence\_enabled) | Enable Redis persistence (AOF/RDB) | `bool` | `true` | no |
| <a name="input_redis_sentinel_down_after_ms"></a> [redis\_sentinel\_down\_after\_ms](#input\_redis\_sentinel\_down\_after\_ms) | Sentinel marks replica down after (ms) | `number` | `30000` | no |
| <a name="input_redis_sentinel_enabled"></a> [redis\_sentinel\_enabled](#input\_redis\_sentinel\_enabled) | Enable Redis Sentinel for HA | `bool` | `true` | no |
| <a name="input_redis_sentinel_port"></a> [redis\_sentinel\_port](#input\_redis\_sentinel\_port) | Redis Sentinel port | `number` | `26379` | no |
| <a name="input_redis_sentinel_quorum"></a> [redis\_sentinel\_quorum](#input\_redis\_sentinel\_quorum) | Sentinel quorum size | `number` | `2` | no |
| <a name="input_replica_host_ip"></a> [replica\_host\_ip](#input\_replica\_host\_ip) | Replica standby host IP (on-prem) | `string` | `"192.168.168.42"` | no |
| <a name="input_replication_slot_enabled"></a> [replication\_slot\_enabled](#input\_replication\_slot\_enabled) | Enable PostgreSQL replication slots | `bool` | `true` | no |
| <a name="input_replication_slot_name"></a> [replication\_slot\_name](#input\_replication\_slot\_name) | Replication slot name | `string` | `"replica_slot"` | no |
| <a name="input_rpo_target_seconds"></a> [rpo\_target\_seconds](#input\_rpo\_target\_seconds) | Recovery Point Objective (seconds) | `number` | `60` | no |
| <a name="input_rto_target_minutes"></a> [rto\_target\_minutes](#input\_rto\_target\_minutes) | Recovery Time Objective (minutes) | `number` | `15` | no |
| <a name="input_security_email"></a> [security\_email](#input\_security\_email) | Email for security notifications (CAA, DMARC records) | `string` | `"security@kushnir.cloud"` | no |
| <a name="input_slo_target_availability"></a> [slo\_target\_availability](#input\_slo\_target\_availability) | Service availability SLO target (percentage) | `number` | `99.9` | no |
| <a name="input_slo_target_error_rate"></a> [slo\_target\_error\_rate](#input\_slo\_target\_error\_rate) | Service error rate SLO target (percentage) | `number` | `0.1` | no |
| <a name="input_slo_target_latency_p99"></a> [slo\_target\_latency\_p99](#input\_slo\_target\_latency\_p99) | Service latency P99 SLO target (milliseconds) | `number` | `500` | no |
| <a name="input_ssh_private_key"></a> [ssh\_private\_key](#input\_ssh\_private\_key) | SSH private key path for deployment | `string` | `"~/.ssh/id_rsa"` | no |
| <a name="input_ssl_mode"></a> [ssl\_mode](#input\_ssl\_mode) | SSL/TLS encryption mode (off, flexible, full, strict) | `string` | `"strict"` | no |
| <a name="input_synchronous_replica_count"></a> [synchronous\_replica\_count](#input\_synchronous\_replica\_count) | Number of replicas to wait for in sync replication | `number` | `1` | no |
| <a name="input_tls_version_minimum"></a> [tls\_version\_minimum](#input\_tls\_version\_minimum) | Minimum TLS version (1.2 or 1.3) | `string` | `"1.3"` | no |
| <a name="input_tunnel_name_prefix"></a> [tunnel\_name\_prefix](#input\_tunnel\_name\_prefix) | Tunnel name prefix for Cloudflare tunnel | `string` | `"code-server"` | no |
| <a name="input_vault_api_addr"></a> [vault\_api\_addr](#input\_vault\_api\_addr) | Vault API address for cluster communication | `string` | `"https://vault.kushnir.cloud:8200"` | no |
| <a name="input_vault_auto_unseal_enabled"></a> [vault\_auto\_unseal\_enabled](#input\_vault\_auto\_unseal\_enabled) | Enable auto-unseal for Vault (requires KMS or HTTPS seal for on-prem) | `bool` | `false` | no |
| <a name="input_vault_cluster_addr"></a> [vault\_cluster\_addr](#input\_vault\_cluster\_addr) | Vault cluster address (HA communication) | `string` | `"https://192.168.168.31:8201"` | no |
| <a name="input_vault_default_lease_ttl"></a> [vault\_default\_lease\_ttl](#input\_vault\_default\_lease\_ttl) | Default lease duration (in hours) for Vault tokens | `number` | `24` | no |
| <a name="input_vault_ha_enabled"></a> [vault\_ha\_enabled](#input\_vault\_ha\_enabled) | Enable HA mode for Vault (requires >= 2 instances) | `bool` | `true` | no |
| <a name="input_vault_log_level"></a> [vault\_log\_level](#input\_vault\_log\_level) | Vault log level (trace, debug, info, warn, err) | `string` | `"info"` | no |
| <a name="input_vault_max_lease_ttl"></a> [vault\_max\_lease\_ttl](#input\_vault\_max\_lease\_ttl) | Maximum lease duration (in hours) for Vault tokens | `number` | `768` | no |
| <a name="input_vault_postgres_db"></a> [vault\_postgres\_db](#input\_vault\_postgres\_db) | PostgreSQL database for Vault storage backend | `string` | `"vault"` | no |
| <a name="input_vault_postgres_password"></a> [vault\_postgres\_password](#input\_vault\_postgres\_password) | PostgreSQL password for Vault storage backend | `string` | `""` | no |
| <a name="input_vault_postgres_user"></a> [vault\_postgres\_user](#input\_vault\_postgres\_user) | PostgreSQL user for Vault storage backend | `string` | `"vault"` | no |
| <a name="input_vault_tls_cert_pem"></a> [vault\_tls\_cert\_pem](#input\_vault\_tls\_cert\_pem) | Vault TLS certificate (PEM format). If empty, self-signed will be generated. | `string` | `""` | no |
| <a name="input_vault_tls_key_pem"></a> [vault\_tls\_key\_pem](#input\_vault\_tls\_key\_pem) | Vault TLS private key (PEM format). If empty, self-signed will be generated. | `string` | `""` | no |
| <a name="input_vulnerability_scan_enabled"></a> [vulnerability\_scan\_enabled](#input\_vulnerability\_scan\_enabled) | Enable automated vulnerability scanning | `bool` | `true` | no |
| <a name="input_waf_enabled"></a> [waf\_enabled](#input\_waf\_enabled) | Enable Cloudflare WAF custom rules | `bool` | `true` | no |
| <a name="input_wal_keep_size"></a> [wal\_keep\_size](#input\_wal\_keep\_size) | WAL segments to keep (GB) | `number` | `10` | no |
| <a name="input_wal_level"></a> [wal\_level](#input\_wal\_level) | PostgreSQL WAL level (minimal/replica/logical) | `string` | `"replica"` | no |
| <a name="input_workspace_path"></a> [workspace\_path](#input\_workspace\_path) | Local filesystem path for workspace volume mount | `string` | `"./workspace"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_alertmanager_url"></a> [alertmanager\_url](#output\_alertmanager\_url) | URL to AlertManager alerts dashboard (internal network, no HTTPS) |
| <a name="output_all_dns_records"></a> [all\_dns\_records](#output\_all\_dns\_records) | All DNS records from inventory |
| <a name="output_code_server_url"></a> [code\_server\_url](#output\_code\_server\_url) | URL to access code-server via oauth2-proxy with HTTPS and authentication |
| <a name="output_config_directory"></a> [config\_directory](#output\_config\_directory) | Configuration directory containing docker-compose.yml and configs |
| <a name="output_deployment_host_ip"></a> [deployment\_host\_ip](#output\_deployment\_host\_ip) | IP address of the primary deployment host for SSH access and direct operations |
| <a name="output_deployment_summary"></a> [deployment\_summary](#output\_deployment\_summary) | Summary of deployment endpoints and access points |
| <a name="output_deployment_user"></a> [deployment\_user](#output\_deployment\_user) | SSH user for accessing deployment host |
| <a name="output_dns_providers"></a> [dns\_providers](#output\_dns\_providers) | Configured DNS providers |
| <a name="output_dns_zones"></a> [dns\_zones](#output\_dns\_zones) | Configured DNS zones |
| <a name="output_domain_name"></a> [domain\_name](#output\_domain\_name) | Primary domain used for oauth2-proxy OIDC redirect URIs and certificate provisioning |
| <a name="output_grafana_slo_dashboard_url"></a> [grafana\_slo\_dashboard\_url](#output\_grafana\_slo\_dashboard\_url) | n/a |
| <a name="output_grafana_url"></a> [grafana\_url](#output\_grafana\_url) | URL to Grafana observability dashboard (internal network, no HTTPS, default: admin/admin123) |
| <a name="output_inventory_primary_host_ip"></a> [inventory\_primary\_host\_ip](#output\_inventory\_primary\_host\_ip) | Primary host IP from inventory (P2 #364) |
| <a name="output_inventory_replica_host_ip"></a> [inventory\_replica\_host\_ip](#output\_inventory\_replica\_host\_ip) | Replica host IP from inventory (P2 #364) |
| <a name="output_inventory_service_endpoints"></a> [inventory\_service\_endpoints](#output\_inventory\_service\_endpoints) | Service endpoints computed from inventory |
| <a name="output_inventory_ssh_strings"></a> [inventory\_ssh\_strings](#output\_inventory\_ssh\_strings) | SSH connection strings for all hosts |
| <a name="output_inventory_storage_ip"></a> [inventory\_storage\_ip](#output\_inventory\_storage\_ip) | Storage/NAS IP from inventory |
| <a name="output_inventory_virtual_ip"></a> [inventory\_virtual\_ip](#output\_inventory\_virtual\_ip) | Virtual IP for failover from inventory (P2 #365) |
| <a name="output_jaeger_agent_endpoint"></a> [jaeger\_agent\_endpoint](#output\_jaeger\_agent\_endpoint) | Jaeger agent endpoint (UDP) |
| <a name="output_jaeger_otlp_grpc_endpoint"></a> [jaeger\_otlp\_grpc\_endpoint](#output\_jaeger\_otlp\_grpc\_endpoint) | OpenTelemetry gRPC collector endpoint |
| <a name="output_jaeger_otlp_http_endpoint"></a> [jaeger\_otlp\_http\_endpoint](#output\_jaeger\_otlp\_http\_endpoint) | OpenTelemetry HTTP collector endpoint |
| <a name="output_jaeger_slo_targets"></a> [jaeger\_slo\_targets](#output\_jaeger\_slo\_targets) | n/a |
| <a name="output_jaeger_ui_url"></a> [jaeger\_ui\_url](#output\_jaeger\_ui\_url) | Jaeger UI endpoint |
| <a name="output_jaeger_url"></a> [jaeger\_url](#output\_jaeger\_url) | URL to Jaeger distributed tracing (internal network, no HTTPS) |
| <a name="output_kong_admin_api"></a> [kong\_admin\_api](#output\_kong\_admin\_api) | Kong Admin API endpoint |
| <a name="output_kong_proxy_http"></a> [kong\_proxy\_http](#output\_kong\_proxy\_http) | Kong proxy HTTP endpoint |
| <a name="output_kong_proxy_https"></a> [kong\_proxy\_https](#output\_kong\_proxy\_https) | Kong proxy HTTPS endpoint |
| <a name="output_kong_slo_targets"></a> [kong\_slo\_targets](#output\_kong\_slo\_targets) | n/a |
| <a name="output_konga_dashboard_url"></a> [konga\_dashboard\_url](#output\_konga\_dashboard\_url) | Konga Dashboard URL |
| <a name="output_local_configuration"></a> [local\_configuration](#output\_local\_configuration) | Computed local configuration |
| <a name="output_loki_api_url"></a> [loki\_api\_url](#output\_loki\_api\_url) | Loki API endpoint |
| <a name="output_loki_query_endpoint"></a> [loki\_query\_endpoint](#output\_loki\_query\_endpoint) | Loki query endpoint |
| <a name="output_loki_slo_targets"></a> [loki\_slo\_targets](#output\_loki\_slo\_targets) | n/a |
| <a name="output_phase_4_validation"></a> [phase\_4\_validation](#output\_phase\_4\_validation) | Phase 4 validation result - all 7 modules composed |
| <a name="output_postgresql_host"></a> [postgresql\_host](#output\_postgresql\_host) | PostgreSQL hostname (internal Docker network reference) |
| <a name="output_primary_domain"></a> [primary\_domain](#output\_primary\_domain) | Primary domain name |
| <a name="output_primary_host"></a> [primary\_host](#output\_primary\_host) | n/a |
| <a name="output_prometheus_retention"></a> [prometheus\_retention](#output\_prometheus\_retention) | n/a |
| <a name="output_prometheus_slo_rules_url"></a> [prometheus\_slo\_rules\_url](#output\_prometheus\_slo\_rules\_url) | n/a |
| <a name="output_prometheus_url"></a> [prometheus\_url](#output\_prometheus\_url) | URL to Prometheus metrics dashboard (internal network, no HTTPS) |
| <a name="output_promtail_metrics_endpoint"></a> [promtail\_metrics\_endpoint](#output\_promtail\_metrics\_endpoint) | Promtail metrics endpoint |
| <a name="output_redis_host"></a> [redis\_host](#output\_redis\_host) | Redis hostname (internal Docker network reference) |
| <a name="output_replica_host"></a> [replica\_host](#output\_replica\_host) | n/a |
| <a name="output_slo_targets"></a> [slo\_targets](#output\_slo\_targets) | n/a |
