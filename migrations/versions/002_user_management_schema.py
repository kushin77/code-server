"""
Alembic Migration - User Models and Email Management
Issue #1345 Week 2: User Management from OAuth providers

Usage:
  alembic upgrade head
  alembic downgrade -1
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID, JSON


def upgrade():
    """Create user management schema tables"""
    
    # User Accounts
    op.create_table(
        'users',
        sa.Column('id', UUID(as_uuid=True), server_default=sa.func.gen_random_uuid(), nullable=False),
        sa.Column('email', sa.String(255), nullable=False),
        sa.Column('name', sa.String(255), nullable=False),
        sa.Column('avatar_url', sa.String(512), nullable=True),
        sa.Column('status', sa.String(32), default='pending_verification'),
        sa.Column('email_verified', sa.Boolean, default=False),
        sa.Column('email_verified_at', sa.DateTime, nullable=True),
        sa.Column('last_verified_email', sa.String(255), nullable=True),
        sa.Column('bio', sa.Text, nullable=True),
        sa.Column('company', sa.String(255), nullable=True),
        sa.Column('location', sa.String(255), nullable=True),
        sa.Column('website', sa.String(512), nullable=True),
        sa.Column('locale', sa.String(16), default='en_US'),
        sa.Column('timezone', sa.String(32), default='UTC'),
        sa.Column('preferences', JSON, default=dict),
        sa.Column('created_at', sa.DateTime, default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime, default=sa.func.now(), onupdate=sa.func.now(), nullable=False),
        sa.Column('last_login_at', sa.DateTime, nullable=True),
        sa.Column('last_login_ip', sa.String(45), nullable=True),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('email', name='uq_users_email'),
    )
    op.create_index('ix_users_email', 'users', ['email'])
    op.create_index('ix_users_email_verified', 'users', ['email', 'email_verified'])
    op.create_index('ix_users_created_at', 'users', ['created_at'])
    
    # User Profiles (Extended Information)
    op.create_table(
        'user_profiles',
        sa.Column('id', UUID(as_uuid=True), server_default=sa.func.gen_random_uuid(), nullable=False),
        sa.Column('user_id', UUID(as_uuid=True), nullable=False),
        sa.Column('display_name', sa.String(255), nullable=True),
        sa.Column('bio', sa.Text, nullable=True),
        sa.Column('avatar_url', sa.String(512), nullable=True),
        sa.Column('profile_url', sa.String(512), nullable=True),
        sa.Column('job_title', sa.String(255), nullable=True),
        sa.Column('company', sa.String(255), nullable=True),
        sa.Column('industry', sa.String(128), nullable=True),
        sa.Column('country', sa.String(128), nullable=True),
        sa.Column('city', sa.String(128), nullable=True),
        sa.Column('timezone', sa.String(32), nullable=True),
        sa.Column('phone_number', sa.String(20), nullable=True),
        sa.Column('phone_verified', sa.Boolean, default=False),
        sa.Column('social_links', JSON, default=dict),
        sa.Column('is_public', sa.Boolean, default=True),
        sa.Column('show_email', sa.Boolean, default=False),
        sa.Column('created_at', sa.DateTime, default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime, default=sa.func.now(), onupdate=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id']),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('user_id', name='uq_user_profiles_user_id'),
    )
    
    # Email Change Requests (Verification for email changes)
    op.create_table(
        'email_change_requests',
        sa.Column('id', UUID(as_uuid=True), server_default=sa.func.gen_random_uuid(), nullable=False),
        sa.Column('user_id', UUID(as_uuid=True), nullable=False),
        sa.Column('old_email', sa.String(255), nullable=False),
        sa.Column('new_email', sa.String(255), nullable=False),
        sa.Column('verification_token', sa.String(256), nullable=False),
        sa.Column('is_verified', sa.Boolean, default=False),
        sa.Column('created_at', sa.DateTime, default=sa.func.now(), nullable=False),
        sa.Column('expires_at', sa.DateTime, nullable=False),
        sa.Column('verified_at', sa.DateTime, nullable=True),
        sa.ForeignKeyConstraint(['user_id'], ['users.id']),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('verification_token', name='uq_email_change_token'),
    )
    op.create_index('ix_email_change_user_id', 'email_change_requests', ['user_id'])
    op.create_index('ix_email_change_verification_token', 'email_change_requests', ['verification_token'])
    
    # User Activity Logs (Security & Auditing)
    op.create_table(
        'user_activity_logs',
        sa.Column('id', UUID(as_uuid=True), server_default=sa.func.gen_random_uuid(), nullable=False),
        sa.Column('user_id', UUID(as_uuid=True), nullable=False),
        sa.Column('activity_type', sa.String(64), nullable=False),
        sa.Column('activity_description', sa.Text, nullable=True),
        sa.Column('status', sa.String(32), default='success'),
        sa.Column('ip_address', sa.String(45), nullable=True),
        sa.Column('user_agent', sa.String(512), nullable=True),
        sa.Column('country', sa.String(128), nullable=True),
        sa.Column('metadata', JSON, default=dict),
        sa.Column('created_at', sa.DateTime, default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id']),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_user_activity_user_id', 'user_activity_logs', ['user_id'])
    op.create_index('ix_user_activity_type', 'user_activity_logs', ['activity_type'])
    op.create_index('ix_user_activity_created', 'user_activity_logs', ['user_id', 'created_at'])


def downgrade():
    """Drop user management schema tables"""
    op.drop_table('user_activity_logs')
    op.drop_table('email_change_requests')
    op.drop_table('user_profiles')
    op.drop_table('users')
