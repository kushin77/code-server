# terraform/environments/private/terraform.tfvars
# Local development environment configuration for code-server-enterprise
# Managed by Terraform - do not edit manually

apex_domain     = "kushnir.local"
primary_host    = "192.168.168.31"
replica_host    = "192.168.168.42"
nas_host        = "192.168.168.56"
registry_url    = "localhost:5000"
admin_email     = "admin@kushnir.local"
deployment_mode = "private"
aws_region      = "us-east-1"
environment     = "production"
kubeconfig_path = "~/.kube/config"
