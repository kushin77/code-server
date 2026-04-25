"""
Alembic Migration - Advanced Authentication Schema
Issue #1345 Week 4: Advanced Features

Tables:
- user_sessions: Session tracking
- user_devices: Device information
- refresh_tokens: Refresh token management
- user_mfa: MFA configuration
- recovery_codes: MFA backup codes
- password_reset_requests: Password reset tracking
- email_change_requests: Email change verification
- login_events: Login audit trail
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID, JSON


def upgrade():
    """Create advanced authentication schema tables"""
    
    # User Sessions
    op.create_table(
        'user_sessions',
        sa.Column('id', UUID(as_uuid=True), server_default=sa.func.gen_random_uuid(), nullable=False),
        sa.Column('user_id', UUID(as_uuid=True), nullable=False),
        sa.Column('device_id', sa.String(255), nullable=False),
        sa.Column('device_name', sa.String(255)),
        sa.Column('device_type', sa.String(32)),
        sa.Column('os', sa.String(64)),
        sa.Column('browser', sa.String(64)),
        sa.Column('ip_address', sa.String(45)),
        sa.Column('user_agent', sa.Text),
        sa.Column('refresh_token_id', UUID(as_uuid=True), nullable=True),
        sa.Column('created_at', sa.DateTime, default=sa.func.now(), nullable=False),
        sa.Column('last_activity', sa.DateTime, default=sa.func.now()),
        sa.Column('revoked_at', sa.DateTime, nullable=True),
        sa.ForeignKeyConstraint(['user_id'], ['users.id']),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_user_sessions_user_id', 'user_sessions', ['user_id'])
    op.create_index('ix_user_sessions_device_id', 'user_sessions', ['device_id'])
    op.create_index('ix_user_sessions_revoked_at', 'user_sessions', ['revoked_at'])
    op.create_index('ix_user_sessions_user_device', 'user_sessions', ['user_id', 'device_id'])
    
    # User Devices
    op.create_table(
        'user_devices',
        sa.Column('id', UUID(as_uuid=True), server_default=sa.func.gen_random_uuid(), nullable=False),
        sa.Column('user_id', UUID(as_uuid=True), nullable=False),
        sa.Column('device_id', sa.String(255), nullable=False),
        sa.Column('device_name', sa.String(255), nullable=False),
        sa.Column('device_type', sa.String(32)),
        sa.Column('os', sa.String(64)),
        sa.Column('browser', sa.String(64)),
        sa.Column('ip_address', sa.String(45)),
        sa.Column('user_agent', sa.Text),
        sa.Column('is_current', sa.Boolean, default=False),
        sa.Column('created_at', sa.DateTime, default=sa.func.now(), nullable=False),
        sa.Column('last_seen', sa.DateTime),
        sa.ForeignKeyConstraint(['user_id'], ['users.id']),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_user_devices_user_id', 'user_devices', ['user_id'])
    
    # Refresh Tokens
    op.create_table(
        'refresh_tokens',
        sa.Column('id', UUID(as_uuid=True), server_default=sa.func.gen_random_uuid(), nullable=False),
        sa.Column('user_id', UUID(as_uuid=True), nullable=False),
        sa.Column('token_hash', sa.String(255), nullable=False),
        sa.Column('device_id', sa.String(255)),
        sa.Column('ip_address', sa.String(45)),
        sa.Column('created_at', sa.DateTime, default=sa.func.now(), nullable=False),
        sa.Column('expires_at', sa.DateTime, nullable=False),
        sa.Column('revoked_at', sa.DateTime),
        sa.ForeignKeyConstraint(['user_id'], ['users.id']),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('token_hash', name='uq_refresh_tokens_hash'),
    )
    op.create_index('ix_refresh_tokens_user_id', 'refresh_tokens', ['user_id'])
    op.create_index('ix_refresh_tokens_expires_at', 'refresh_tokens', ['expires_at'])
    op.create_index('ix_refresh_tokens_revoked_at', 'refresh_tokens', ['revoked_at'])
    
    # User MFA
    op.create_table(
        'user_mfa',
        sa.Column('id', UUID(as_uuid=True), server_default=sa.func.gen_random_uuid(), nullable=False),
        sa.Column('user_id', UUID(as_uuid=True), nullable=False),
        sa.Column('method', sa.String(32), nullable=False),
        sa.Column('secret', sa.String(255)),
        sa.Column('phone_number', sa.String(20)),
        sa.Column('created_at', sa.DateTime, default=sa.func.now(), nullable=False),
        sa.Column('verified_at', sa.DateTime),
        sa.Column('last_used', sa.DateTime),
        sa.Column('backup_codes_remaining', sa.Integer, default=0),
        sa.ForeignKeyConstraint(['user_id'], ['users.id']),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_user_mfa_user_id', 'user_mfa', ['user_id'])
    op.create_index('ix_user_mfa_user_id_method', 'user_mfa', ['user_id', 'method'])
    
    # Recovery Codes
    op.create_table(
        'recovery_codes',
        sa.Column('id', UUID(as_uuid=True), server_default=sa.func.gen_random_uuid(), nullable=False),
        sa.Column('user_id', UUID(as_uuid=True), nullable=False),
        sa.Column('code_hash', sa.String(255), nullable=False),
        sa.Column('created_at', sa.DateTime, default=sa.func.now(), nullable=False),
        sa.Column('used_at', sa.DateTime),
        sa.ForeignKeyConstraint(['user_id'], ['users.id']),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_recovery_codes_user_id', 'recovery_codes', ['user_id'])
    op.create_index('ix_recovery_codes_used_at', 'recovery_codes', ['used_at'])
    
    # Password Reset Requests
    op.create_table(
        'password_reset_requests',
        sa.Column('id', UUID(as_uuid=True), server_default=sa.func.gen_random_uuid(), nullable=False),
        sa.Column('user_id', UUID(as_uuid=True), nullable=False),
        sa.Column('token', sa.String(255), nullable=False),
        sa.Column('created_at', sa.DateTime, default=sa.func.now(), nullable=False),
        sa.Column('expires_at', sa.DateTime, nullable=False),
        sa.Column('used_at', sa.DateTime),
        sa.ForeignKeyConstraint(['user_id'], ['users.id']),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('token', name='uq_password_reset_token'),
    )
    op.create_index('ix_password_reset_user_id', 'password_reset_requests', ['user_id'])
    op.create_index('ix_password_reset_token', 'password_reset_requests', ['token'])
    op.create_index('ix_password_reset_expires_at', 'password_reset_requests', ['expires_at'])
    
    # Email Change Requests
    op.create_table(
        'email_change_requests',
        sa.Column('id', UUID(as_uuid=True), server_default=sa.func.gen_random_uuid(), nullable=False),
        sa.Column('user_id', UUID(as_uuid=True), nullable=False),
        sa.Column('new_email', sa.String(255), nullable=False),
        sa.Column('token', sa.String(255), nullable=False),
        sa.Column('created_at', sa.DateTime, default=sa.func.now(), nullable=False),
        sa.Column('expires_at', sa.DateTime, nullable=False),
        sa.Column('verified_at', sa.DateTime),
        sa.ForeignKeyConstraint(['user_id'], ['users.id']),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('token', name='uq_email_change_token'),
    )
    op.create_index('ix_email_change_user_id', 'email_change_requests', ['user_id'])
    op.create_index('ix_email_change_token', 'email_change_requests', ['token'])
    
    # Login Events
    op.create_table(
        'login_events',
        sa.Column('id', UUID(as_uuid=True), server_default=sa.func.gen_random_uuid(), nullable=False),
        sa.Column('user_id', UUID(as_uuid=True), nullable=False),
        sa.Column('success', sa.Boolean, nullable=False),
        sa.Column('reason', sa.String(255)),
        sa.Column('ip_address', sa.String(45)),
        sa.Column('user_agent', sa.Text),
        sa.Column('device_id', sa.String(255)),
        sa.Column('mfa_method_used', sa.String(32)),
        sa.Column('created_at', sa.DateTime, default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id']),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_login_events_user_id', 'login_events', ['user_id'])
    op.create_index('ix_login_events_created_at', 'login_events', ['created_at'])
    op.create_index('ix_login_events_user_id_created', 'login_events', ['user_id', 'created_at'])


def downgrade():
    """Drop advanced authentication schema tables"""
    op.drop_table('login_events')
    op.drop_table('email_change_requests')
    op.drop_table('password_reset_requests')
    op.drop_table('recovery_codes')
    op.drop_table('user_mfa')
    op.drop_table('refresh_tokens')
    op.drop_table('user_devices')
    op.drop_table('user_sessions')
