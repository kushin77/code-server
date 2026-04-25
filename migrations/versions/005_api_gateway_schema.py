"""
Alembic Migration - API Gateway Schema
Issue #1345 Week 5: API Gateway Integration

Tables:
- api_keys: API keys for programmatic access
- quota_usage: Quota usage tracking
- quota_warnings: Quota warning alerts
- rate_limit_records: Rate limit event logging
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID, JSON


def upgrade():
    """Create API gateway schema tables"""
    
    # API Keys
    op.create_table(
        'api_keys',
        sa.Column('id', UUID(as_uuid=True), server_default=sa.func.gen_random_uuid(), nullable=False),
        sa.Column('user_id', UUID(as_uuid=True), nullable=False),
        sa.Column('name', sa.String(255), nullable=False),
        sa.Column('key_hash', sa.String(255), nullable=False),
        sa.Column('scopes', JSON, default=list),
        sa.Column('created_at', sa.DateTime, default=sa.func.now(), nullable=False),
        sa.Column('last_used', sa.DateTime, nullable=True),
        sa.Column('revoked_at', sa.DateTime, nullable=True),
        sa.Column('expires_at', sa.DateTime, nullable=False),
        sa.Column('ip_whitelist', JSON, nullable=True),
        sa.Column('user_agent_pattern', sa.String(255), nullable=True),
        sa.ForeignKeyConstraint(['user_id'], ['users.id']),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('key_hash', name='uq_api_keys_hash'),
    )
    op.create_index('ix_api_keys_user_id', 'api_keys', ['user_id'])
    op.create_index('ix_api_keys_key_hash', 'api_keys', ['key_hash'])
    op.create_index('ix_api_keys_revoked_at', 'api_keys', ['revoked_at'])
    
    # Quota Usage
    op.create_table(
        'quota_usage',
        sa.Column('id', UUID(as_uuid=True), server_default=sa.func.gen_random_uuid(), nullable=False),
        sa.Column('owner_type', sa.String(32), nullable=False),
        sa.Column('owner_id', UUID(as_uuid=True), nullable=False),
        sa.Column('resource_type', sa.String(64), nullable=False),
        sa.Column('quota_limit', sa.Integer, nullable=False),
        sa.Column('current_usage', sa.Integer, default=0),
        sa.Column('period_start', sa.DateTime, nullable=False),
        sa.Column('period_end', sa.DateTime, nullable=False),
        sa.Column('warning_sent_at', sa.DateTime, nullable=True),
        sa.Column('created_at', sa.DateTime, default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime, default=sa.func.now(), onupdate=sa.func.now()),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_quota_usage_owner_type_id', 'quota_usage', ['owner_type', 'owner_id'])
    op.create_index('ix_quota_usage_resource_period', 'quota_usage', ['resource_type', 'period_start', 'period_end'])
    
    # Quota Warnings
    op.create_table(
        'quota_warnings',
        sa.Column('id', UUID(as_uuid=True), server_default=sa.func.gen_random_uuid(), nullable=False),
        sa.Column('quota_usage_id', UUID(as_uuid=True), nullable=False),
        sa.Column('warning_level', sa.Integer, nullable=False),
        sa.Column('sent_at', sa.DateTime, default=sa.func.now(), nullable=False),
        sa.Column('acknowledged_at', sa.DateTime, nullable=True),
        sa.ForeignKeyConstraint(['quota_usage_id'], ['quota_usage.id']),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_quota_warnings_sent_at', 'quota_warnings', ['sent_at'])
    
    # Rate Limit Records
    op.create_table(
        'rate_limit_records',
        sa.Column('id', UUID(as_uuid=True), server_default=sa.func.gen_random_uuid(), nullable=False),
        sa.Column('user_id', UUID(as_uuid=True), nullable=True),
        sa.Column('api_key_id', UUID(as_uuid=True), nullable=True),
        sa.Column('limit_type', sa.String(32), nullable=False),
        sa.Column('identifier', sa.String(255), nullable=False),
        sa.Column('limit', sa.Integer, nullable=False),
        sa.Column('exceeded', sa.Boolean, default=False),
        sa.Column('ip_address', sa.String(45)),
        sa.Column('user_agent', sa.Text),
        sa.Column('endpoint', sa.String(255)),
        sa.Column('method', sa.String(10)),
        sa.Column('created_at', sa.DateTime, default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id']),
        sa.ForeignKeyConstraint(['api_key_id'], ['api_keys.id']),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_rate_limit_records_user_id', 'rate_limit_records', ['user_id'])
    op.create_index('ix_rate_limit_records_created_at', 'rate_limit_records', ['created_at'])
    op.create_index('ix_rate_limit_records_user_created', 'rate_limit_records', ['user_id', 'created_at'])


def downgrade():
    """Drop API gateway schema tables"""
    op.drop_table('rate_limit_records')
    op.drop_table('quota_warnings')
    op.drop_table('quota_usage')
    op.drop_table('api_keys')
