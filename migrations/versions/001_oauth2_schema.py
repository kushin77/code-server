"""
Alembic Migration - OAuth2 Authorization Server Schema
Issue #1545: Enterprise SSO Portal - Week 1

Usage:
  alembic upgrade head
  alembic downgrade -1
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID, ENUM, JSON


def upgrade():
    """Create OAuth2 schema tables"""
    
    # OAuth Provider Configuration
    op.create_table(
        'oauth_providers',
        sa.Column('id', UUID(as_uuid=True), server_default=sa.func.gen_random_uuid(), nullable=False),
        sa.Column('provider_type', sa.String(64), nullable=False),
        sa.Column('client_id', sa.String(255), nullable=False),
        sa.Column('client_secret', sa.String(512), nullable=False),
        sa.Column('auth_url', sa.String(512), nullable=False),
        sa.Column('token_url', sa.String(512), nullable=False),
        sa.Column('user_info_url', sa.String(512), nullable=False),
        sa.Column('redirect_uri', sa.String(512), nullable=False),
        sa.Column('scopes', JSON, nullable=False),
        sa.Column('enabled', sa.Boolean, default=True),
        sa.Column('auto_provision_users', sa.Boolean, default=True),
        sa.Column('require_email_verified', sa.Boolean, default=True),
        sa.Column('created_at', sa.DateTime, default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime, default=sa.func.now(), onupdate=sa.func.now(), nullable=False),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('provider_type', name='uq_oauth_provider_type'),
    )
    op.create_index('ix_oauth_providers_client_id', 'oauth_providers', ['client_id'])
    
    # Authorization Codes
    op.create_table(
        'oauth_authorization_codes',
        sa.Column('id', UUID(as_uuid=True), server_default=sa.func.gen_random_uuid(), nullable=False),
        sa.Column('code', sa.String(256), nullable=False),
        sa.Column('user_id', UUID(as_uuid=True), nullable=False),
        sa.Column('client_id', sa.String(255), nullable=False),
        sa.Column('redirect_uri', sa.String(512), nullable=False),
        sa.Column('scope', sa.String(1024), nullable=False),
        sa.Column('code_challenge', sa.String(128), nullable=True),
        sa.Column('code_challenge_method', sa.String(16), nullable=True),
        sa.Column('is_used', sa.Boolean, default=False),
        sa.Column('created_at', sa.DateTime, default=sa.func.now(), nullable=False),
        sa.Column('expires_at', sa.DateTime, nullable=False),
        sa.Column('used_at', sa.DateTime, nullable=True),
        sa.Column('ip_address', sa.String(45), nullable=True),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('code', name='uq_oauth_auth_code'),
    )
    op.create_index('ix_oauth_authorization_codes_code', 'oauth_authorization_codes', ['code'])
    op.create_index('ix_oauth_authorization_codes_user_id', 'oauth_authorization_codes', ['user_id'])
    op.create_index('ix_oauth_authorization_codes_expires_at', 'oauth_authorization_codes', ['expires_at'])
    
    # OAuth Tokens
    op.create_table(
        'oauth_tokens',
        sa.Column('id', UUID(as_uuid=True), server_default=sa.func.gen_random_uuid(), nullable=False),
        sa.Column('token', sa.Text, nullable=False),
        sa.Column('user_id', UUID(as_uuid=True), nullable=False),
        sa.Column('client_id', sa.String(255), nullable=False),
        sa.Column('token_type', sa.String(32), nullable=False),
        sa.Column('created_at', sa.DateTime, default=sa.func.now(), nullable=False),
        sa.Column('expires_at', sa.DateTime, nullable=False),
        sa.Column('revoked', sa.Boolean, default=False),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_oauth_tokens_token', 'oauth_tokens', ['token'])
    op.create_index('ix_oauth_tokens_user_id', 'oauth_tokens', ['user_id'])
    op.create_index('ix_oauth_tokens_expires_at', 'oauth_tokens', ['expires_at'])
    
    # OAuth Connections
    op.create_table(
        'oauth_connections',
        sa.Column('id', UUID(as_uuid=True), server_default=sa.func.gen_random_uuid(), nullable=False),
        sa.Column('user_id', UUID(as_uuid=True), nullable=False),
        sa.Column('provider_id', UUID(as_uuid=True), nullable=False),
        sa.Column('provider_user_id', sa.String(255), nullable=False),
        sa.Column('access_token', sa.Text, nullable=True),
        sa.Column('refresh_token', sa.Text, nullable=True),
        sa.Column('id_token', sa.Text, nullable=True),
        sa.Column('scope', sa.String(1024), nullable=False),
        sa.Column('provider_email', sa.String(255), nullable=True),
        sa.Column('provider_name', sa.String(255), nullable=True),
        sa.Column('provider_avatar_url', sa.String(512), nullable=True),
        sa.Column('provider_raw_data', JSON, nullable=True),
        sa.Column('is_primary', sa.Boolean, default=False),
        sa.Column('created_at', sa.DateTime, default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime, default=sa.func.now(), onupdate=sa.func.now(), nullable=False),
        sa.Column('last_used', sa.DateTime, nullable=True),
        sa.ForeignKeyConstraint(['provider_id'], ['oauth_providers.id']),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('provider_id', 'provider_user_id', name='uq_provider_user'),
    )
    op.create_index('ix_oauth_connections_user_id', 'oauth_connections', ['user_id'])
    op.create_index('ix_oauth_connections_provider_id', 'oauth_connections', ['provider_id'])
    
    # OAuth Clients
    op.create_table(
        'oauth_clients',
        sa.Column('id', UUID(as_uuid=True), server_default=sa.func.gen_random_uuid(), nullable=False),
        sa.Column('client_id', sa.String(255), nullable=False),
        sa.Column('client_secret', sa.String(512), nullable=False),
        sa.Column('client_name', sa.String(255), nullable=False),
        sa.Column('client_description', sa.Text, nullable=True),
        sa.Column('redirect_uris', JSON, nullable=False),
        sa.Column('allowed_scopes', JSON, nullable=False),
        sa.Column('grant_types', JSON, nullable=False),
        sa.Column('require_auth', sa.Boolean, default=True),
        sa.Column('require_pkce', sa.Boolean, default=True),
        sa.Column('token_endpoint_auth_method', sa.String(32), default='client_secret_basic'),
        sa.Column('logo_url', sa.String(512), nullable=True),
        sa.Column('owner_id', UUID(as_uuid=True), nullable=False),
        sa.Column('organization_id', UUID(as_uuid=True), nullable=True),
        sa.Column('enabled', sa.Boolean, default=True),
        sa.Column('created_at', sa.DateTime, default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime, default=sa.func.now(), onupdate=sa.func.now(), nullable=False),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('client_id', name='uq_oauth_client_id'),
    )
    op.create_index('ix_oauth_clients_client_id', 'oauth_clients', ['client_id'])
    op.create_index('ix_oauth_clients_owner_id', 'oauth_clients', ['owner_id'])
    
    # Audit Log
    op.create_table(
        'oauth_audit_logs',
        sa.Column('id', UUID(as_uuid=True), server_default=sa.func.gen_random_uuid(), nullable=False),
        sa.Column('event_type', sa.String(64), nullable=False),
        sa.Column('status', sa.String(32), nullable=False),
        sa.Column('user_id', UUID(as_uuid=True), nullable=True),
        sa.Column('client_id', sa.String(255), nullable=True),
        sa.Column('provider', sa.String(64), nullable=True),
        sa.Column('scope', sa.String(1024), nullable=True),
        sa.Column('ip_address', sa.String(45), nullable=True),
        sa.Column('user_agent', sa.String(512), nullable=True),
        sa.Column('error_message', sa.Text, nullable=True),
        sa.Column('metadata', JSON, nullable=True),
        sa.Column('created_at', sa.DateTime, default=sa.func.now(), nullable=False),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_oauth_audit_logs_event_type', 'oauth_audit_logs', ['event_type'])
    op.create_index('ix_oauth_audit_logs_user_id', 'oauth_audit_logs', ['user_id'])
    op.create_index('ix_oauth_audit_logs_created_at', 'oauth_audit_logs', ['created_at'])


def downgrade():
    """Drop OAuth2 schema tables"""
    op.drop_table('oauth_audit_logs')
    op.drop_table('oauth_clients')
    op.drop_table('oauth_connections')
    op.drop_table('oauth_tokens')
    op.drop_table('oauth_authorization_codes')
    op.drop_table('oauth_providers')
