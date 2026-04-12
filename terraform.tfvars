# Terraform variables file for code-server enterprise deployment

code_server_password = "enterprise-secure-password-$(date +%s)"
code_server_version  = "latest"
caddy_version        = "latest"
enable_https         = true
log_level            = "info"
config_dir           = "."
