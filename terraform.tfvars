# Terraform variables file for code-server enterprise deployment
# NOTE: This Terraform config manages metadata/locals only.
#       The live container stack is managed by docker-compose.yml.

code_server_password = "enterprise-secure-password"
code_server_version  = "4.115.0"
caddy_version        = "2.7.6"
enable_https         = true
log_level            = "info"
config_dir           = "."
