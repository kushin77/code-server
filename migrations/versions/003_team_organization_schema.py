"""
Alembic Migration - Team and Organization Schema
Issue #1345 Week 3: Team Management

Usage:
  alembic upgrade head
  alembic downgrade -1
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID, JSON


def upgrade():
    """Create team and organization schema tables"""
    
    # Organizations
    op.create_table(
        'organizations',
        sa.Column('id', UUID(as_uuid=True), server_default=sa.func.gen_random_uuid(), nullable=False),
        sa.Column('name', sa.String(255), nullable=False),
        sa.Column('slug', sa.String(255), nullable=False),
        sa.Column('description', sa.Text, nullable=True),
        sa.Column('logo_url', sa.String(512), nullable=True),
        sa.Column('website_url', sa.String(512), nullable=True),
        sa.Column('plan', sa.String(32), default='free'),
        sa.Column('max_teams', sa.Integer, default=3),
        sa.Column('max_members', sa.Integer, default=5),
        sa.Column('owner_id', UUID(as_uuid=True), nullable=False),
        sa.Column('settings', JSON, default=dict),
        sa.Column('created_at', sa.DateTime, default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime, default=sa.func.now(), onupdate=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(['owner_id'], ['users.id']),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('slug', name='uq_organizations_slug'),
    )
    op.create_index('ix_organizations_slug', 'organizations', ['slug'])
    op.create_index('ix_organizations_owner_id', 'organizations', ['owner_id'])
    
    # Teams
    op.create_table(
        'teams',
        sa.Column('id', UUID(as_uuid=True), server_default=sa.func.gen_random_uuid(), nullable=False),
        sa.Column('organization_id', UUID(as_uuid=True), nullable=False),
        sa.Column('name', sa.String(255), nullable=False),
        sa.Column('slug', sa.String(255), nullable=False),
        sa.Column('description', sa.Text, nullable=True),
        sa.Column('avatar_url', sa.String(512), nullable=True),
        sa.Column('status', sa.String(32), default='active'),
        sa.Column('owner_id', UUID(as_uuid=True), nullable=False),
        sa.Column('settings', JSON, default=dict),
        sa.Column('created_at', sa.DateTime, default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime, default=sa.func.now(), onupdate=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(['organization_id'], ['organizations.id']),
        sa.ForeignKeyConstraint(['owner_id'], ['users.id']),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_teams_org_id_slug', 'teams', ['organization_id', 'slug'])
    op.create_index('ix_teams_owner_id', 'teams', ['owner_id'])
    
    # Team Members
    op.create_table(
        'team_members',
        sa.Column('id', UUID(as_uuid=True), server_default=sa.func.gen_random_uuid(), nullable=False),
        sa.Column('team_id', UUID(as_uuid=True), nullable=False),
        sa.Column('user_id', UUID(as_uuid=True), nullable=False),
        sa.Column('role', sa.String(32), default='developer'),
        sa.Column('custom_permissions', JSON, default=dict),
        sa.Column('invited_at', sa.DateTime, default=sa.func.now(), nullable=False),
        sa.Column('joined_at', sa.DateTime, nullable=True),
        sa.Column('created_at', sa.DateTime, default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime, default=sa.func.now(), onupdate=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(['team_id'], ['teams.id']),
        sa.ForeignKeyConstraint(['user_id'], ['users.id']),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_team_members_team_id_user_id', 'team_members', ['team_id', 'user_id'])
    op.create_index('ix_team_members_user_id', 'team_members', ['user_id'])
    
    # Organization Members
    op.create_table(
        'organization_members',
        sa.Column('id', UUID(as_uuid=True), server_default=sa.func.gen_random_uuid(), nullable=False),
        sa.Column('organization_id', UUID(as_uuid=True), nullable=False),
        sa.Column('user_id', UUID(as_uuid=True), nullable=False),
        sa.Column('role', sa.String(32), default='developer'),
        sa.Column('invited_at', sa.DateTime, default=sa.func.now(), nullable=False),
        sa.Column('joined_at', sa.DateTime, nullable=True),
        sa.Column('created_at', sa.DateTime, default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime, default=sa.func.now(), onupdate=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(['organization_id'], ['organizations.id']),
        sa.ForeignKeyConstraint(['user_id'], ['users.id']),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_org_members_org_id_user_id', 'organization_members', ['organization_id', 'user_id'])
    
    # Team Invitations
    op.create_table(
        'team_invitations',
        sa.Column('id', UUID(as_uuid=True), server_default=sa.func.gen_random_uuid(), nullable=False),
        sa.Column('team_id', UUID(as_uuid=True), nullable=False),
        sa.Column('invited_by_id', UUID(as_uuid=True), nullable=False),
        sa.Column('invitee_email', sa.String(255), nullable=False),
        sa.Column('user_id', UUID(as_uuid=True), nullable=True),
        sa.Column('role', sa.String(32), default='developer'),
        sa.Column('token', sa.String(256), nullable=False),
        sa.Column('created_at', sa.DateTime, default=sa.func.now(), nullable=False),
        sa.Column('expires_at', sa.DateTime, nullable=False),
        sa.Column('accepted_at', sa.DateTime, nullable=True),
        sa.Column('declined_at', sa.DateTime, nullable=True),
        sa.ForeignKeyConstraint(['team_id'], ['teams.id']),
        sa.ForeignKeyConstraint(['invited_by_id'], ['users.id']),
        sa.ForeignKeyConstraint(['user_id'], ['users.id']),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('token', name='uq_team_invitations_token'),
    )
    op.create_index('ix_team_invitations_token', 'team_invitations', ['token'])


def downgrade():
    """Drop team and organization schema tables"""
    op.drop_table('team_invitations')
    op.drop_table('organization_members')
    op.drop_table('team_members')
    op.drop_table('teams')
    op.drop_table('organizations')
