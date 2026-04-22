locals {
  common_tags = merge(
    var.tags,
    {
      module      = "matrix-collab"
      environment = var.environment
      region      = var.region
      managed_by  = "terraform"
    }
  )
}

# Homeserver module - Synapse with OIDC
module "homeserver" {
  source = "./modules/homeserver"

  environment           = var.environment
  region                = var.region
  matrix_domain         = var.matrix_domain
  apex_domain           = var.apex_domain
  google_client_id      = var.google_client_id
  google_client_secret  = var.google_client_secret
  synapse_admin_token   = var.synapse_admin_token
  redis_url             = var.redis_url
  prometheus_url        = var.prometheus_url
  
  docker_image          = var.docker_image_synapse
  postgres_version      = var.postgres_version
  max_upload_size       = var.synapse_max_upload_size
  db_pool_size          = var.synapse_db_pool_size

  tags = local.common_tags
}

# Element web client
module "element" {
  source = "./modules/element"

  environment    = var.environment
  matrix_domain  = var.matrix_domain
  apex_domain    = var.apex_domain
  homeserver_url = module.homeserver.homeserver_url
  docker_image   = var.docker_image_element

  tags = local.common_tags
}

# Bridge modules
module "bridges" {
  count  = (var.enable_slack_bridge || var.enable_teams_bridge || var.enable_google_chat_bridge) ? 1 : 0
  source = "./modules/bridges"

  environment              = var.environment
  matrix_domain            = var.matrix_domain
  homeserver_url           = module.homeserver.homeserver_url
  synapse_admin_token      = var.synapse_admin_token
  
  enable_slack_bridge      = var.enable_slack_bridge
  enable_teams_bridge      = var.enable_teams_bridge
  enable_google_chat_bridge = var.enable_google_chat_bridge
  
  primary_chat_platform    = var.primary_chat_platform

  tags = local.common_tags
}

# Presence sidecar for real-time status
module "presence_sidecar" {
  count  = var.enable_presence_sidecar ? 1 : 0
  source = "./modules/presence-sidecar"

  environment      = var.environment
  matrix_domain    = var.matrix_domain
  homeserver_url   = module.homeserver.homeserver_url
  synapse_admin_token = var.synapse_admin_token
  redis_url        = var.redis_url
  prometheus_url   = var.prometheus_url

  tags = local.common_tags
}

# Element Call for VoIP/video conferencing
module "element_call" {
  count  = var.enable_element_call ? 1 : 0
  source = "./modules/element-call"

  environment      = var.environment
  apex_domain      = var.apex_domain
  homeserver_url   = module.homeserver.homeserver_url

  tags = local.common_tags
}
