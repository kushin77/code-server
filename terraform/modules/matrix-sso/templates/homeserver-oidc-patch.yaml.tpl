# Patch for homeserver.yaml - Add to existing homeserver.yaml configuration

# Disable traditional registration (SSO only)
registration_allowed: false
enable_registration: false
enable_guest_access: false

# OIDC Provider Configuration
oidc_providers:
  - idp_id: google
    idp_name: "Google Workspace"
    client_id: "${google_client_id}"
    client_secret: "${google_client_secret}"
    discover: true
    issuer: "https://accounts.google.com"
    
    scopes:
      - openid
      - profile
      - email
    
    # User mapping configuration
    user_mapping_provider:
      config:
        # Extract localpart from email before @
        localpart_template: |
          {%- set parts = user.email.split('@') %}
          {%- if parts|length == 2 and parts[1] == '${allowed_domain}' -%}
            {{ parts[0]|replace('.', '_')|replace('-', '_') }}
          {%- else -%}
            {{ raise('Invalid domain or email format') }}
          {%- endif -%}
        
        # Use display name from Google profile
        display_name_template: "{{ user.name }}"
    
    # Attribute-based access control
    attribute_requirements:
      # Enforce hosted domain (hd claim) = kushnir.cloud
      - attribute: hd
        value: "${allowed_domain}"
    
    # Session management
    backchannel_logout_enabled: true
    allow_existing_users: true

# User provisioning on first OIDC login
auto_provision_users: ${auto_provision_users}
sync_displayname_from_oidc: ${sync_display_name}

# Fallback to prevent lockout
fallback_auth_enabled: false

# Admin API for user provisioning
admin_api:
  enabled: true
  # Token must be set via env var SYNAPSE_ADMIN_TOKEN
