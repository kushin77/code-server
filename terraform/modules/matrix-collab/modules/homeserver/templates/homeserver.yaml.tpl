server_name: "${server_name}"
public_baseurl: "https://${server_name}/"
report_stats: ${report_stats}

listeners:
  - port: 8008
    tls: false
    type: http
    x_forwarded: true
    resources:
      - names: [client, federation]
        compress: true

database:
  name: psycopg2
  args:
    user: "${postgres_user}"
    password: "${postgres_password}"
    database: "${postgres_dbname}"
    host: "${postgres_host}"
    port: ${postgres_port}
    cp_min: 1
    cp_max: ${postgres_pool_size}

redis:
  enabled: true
  host: "redis"
  port: 6379
  password: ""

password_config:
  enabled: ${password_config_enabled}

registration_enabled: ${registration_allowed}

enable_registration_without_verification: false
enable_guest_access: false

trusted_key_servers:
  - server_name: "matrix.org"

macaroon_secret_key: "${synapse_admin_token}"
form_secret: "${synapse_admin_token}"
signing_key_path: "/data/${server_name}.signing.key"

oidc_providers:
  - idp_id: google
    idp_name: Google
    issuer: "https://accounts.google.com"
    client_id: "${google_client_id}"
    client_secret: "${google_client_secret}"
    scopes: ["openid", "profile", "email"]

log_config: "/data/${server_name}.log.config"

metrics:
  enabled: true
  port: 9090

experimental_features:
  msc4140_enabled: true
  msc3861_enabled: true

max_upload_size: ${max_upload_size}

app_service_config_files: []

turn_uris: []

prometheus:
  enabled: true
  address: "${prometheus_url}"