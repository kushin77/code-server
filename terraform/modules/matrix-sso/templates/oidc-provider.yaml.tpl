# Synapse OIDC Provider Configuration
# Configured for Google OAuth 2.0 with domain restriction
# This config should be merged with homeserver.yaml

oidc_providers:
  - idp_id: ${client_id == "" ? "google" : "google"}
    idp_name: "Google Workspace"
    
    # Google OAuth 2.0 Configuration
    client_id: "${client_id}"
    client_secret: "${client_secret}"
    
    # OpenID Connect Discovery
    discover: true
    issuer: "${issuer}"
    
    # OIDC Scopes
    scopes:
      - openid
      - profile
      - email
    
    # User mapping: Extract localpart from email prefix
    user_mapping_provider:
      module: "synapse.handlers.oidc.DefaultOIDCMappingProvider"
      config:
        # Map email prefix to Matrix localpart (before @ symbol)
        # Example: alice@kushnir.cloud → alice
        localpart_template: "{{ user.email.split('@')[0] }}"
        
        # Use display name from Google profile
        display_name_template: "{{ user.name }}"
        
        # Map email domain for validation
        email_template: "{{ user.email }}"
    
    # Attribute configuration
    attribute_requirements:
      # Enforce domain restriction at OIDC provider level
      # Only allow ${allowed_domain} users
      - attribute: hd
        value: "${allowed_domain}"
    
    # Session and callback configuration
    backchannel_logout_enabled: true
    allow_existing_users: true

# User provisioning policy
# When a user logs in via OIDC for the first time:
user_provisioning:
  enabled: ${auto_provision}
  
  # Automatically create Matrix account on first login
  auto_create_users: ${auto_provision}
  
  # Update display name from OIDC profile
  update_profile_on_login: ${sync_display_name}
  
  # Sync full name as display name
  sync_displayname: ${sync_display_name}
  
  # Avatar sync (optional, Phase 2)
  sync_avatar: false

# Domain restriction enforcement
# Reject login attempts from users outside ${allowed_domain}
oidc_domain_restriction: "${allowed_domain}"

# Admin token for user provisioning API calls
# Set via environment: SYNAPSE_ADMIN_TOKEN
# Used by post-login hooks for account setup
admin_api_token_from_env: "SYNAPSE_ADMIN_TOKEN"
