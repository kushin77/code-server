# Database Optimization Script
# Week 5 Phase 5.2.1: Database Indexing & Query Optimization
# This migration adds strategic indexes to improve query performance

import asyncio
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
from log import get_logger

logger = get_logger(__name__)

# Migration DDL
OPTIMIZATION_MIGRATION = """
-- Task 5.2.1.1: Add Strategic Indexes for User Queries
CREATE INDEX IF NOT EXISTS ix_users_team_id 
  ON users(team_id);

CREATE INDEX IF NOT EXISTS ix_users_created_at 
  ON users(created_at);

CREATE INDEX IF NOT EXISTS ix_users_is_active 
  ON users(is_active);

CREATE INDEX IF NOT EXISTS ix_users_team_id_is_active 
  ON users(team_id, is_active);

CREATE INDEX IF NOT EXISTS ix_users_created_at_team_id 
  ON users(created_at, team_id);

-- Task 5.2.1.2: Add Strategic Indexes for Team Queries
CREATE INDEX IF NOT EXISTS ix_teams_organization_id 
  ON teams(organization_id);

CREATE INDEX IF NOT EXISTS ix_teams_created_at 
  ON teams(created_at);

CREATE INDEX IF NOT EXISTS ix_teams_organization_id_created_at 
  ON teams(organization_id, created_at);

-- Task 5.2.1.3: Add Strategic Indexes for Permission Queries
CREATE INDEX IF NOT EXISTS ix_permissions_user_id 
  ON permissions(user_id);

CREATE INDEX IF NOT EXISTS ix_permissions_role_id 
  ON permissions(role_id);

CREATE INDEX IF NOT EXISTS ix_permissions_team_id 
  ON permissions(team_id);

CREATE INDEX IF NOT EXISTS ix_permissions_user_id_team_id 
  ON permissions(user_id, team_id);

CREATE INDEX IF NOT EXISTS ix_permissions_role_id_team_id 
  ON permissions(role_id, team_id);

-- Task 5.2.1.4: Add Indexes for Session Queries
CREATE INDEX IF NOT EXISTS ix_sessions_user_id 
  ON sessions(user_id);

CREATE INDEX IF NOT EXISTS ix_sessions_expires_at 
  ON sessions(expires_at);

CREATE INDEX IF NOT EXISTS ix_sessions_user_id_expires_at 
  ON sessions(user_id, expires_at);

-- Task 5.2.1.5: Enable Slow Query Logging
ALTER SYSTEM SET log_min_duration_statement = 100;
ALTER SYSTEM SET log_statement = 'all';

SELECT pg_reload_conf();

-- Verification queries
SELECT 
  schemaname,
  tablename,
  indexname
FROM pg_indexes
WHERE tablename IN ('users', 'teams', 'permissions', 'sessions')
ORDER BY tablename, indexname;

-- Query performance statistics (requires pg_stat_statements extension)
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

SELECT 
  query,
  calls,
  total_time,
  mean_time,
  max_time
FROM pg_stat_statements
WHERE query NOT LIKE '%pg_stat_statements%'
ORDER BY mean_time DESC
LIMIT 20;
"""

async def run_optimization_migration(database_url: str):
    """Execute database optimization migration"""
    engine = create_async_engine(database_url, echo=False)
    
    try:
        async with engine.begin() as conn:
            logger.info("Starting database optimization migration...")
            
            # Execute the migration
            for statement in OPTIMIZATION_MIGRATION.split(';'):
                statement = statement.strip()
                if statement:
                    try:
                        logger.info(f"Executing: {statement[:80]}...")
                        await conn.execute(text(statement))
                    except Exception as e:
                        if "already exists" in str(e):
                            logger.info(f"Index already exists, skipping")
                        else:
                            logger.error(f"Error executing statement: {e}")
                            raise
            
            logger.info("Database optimization migration completed successfully")
            
    finally:
        await engine.dispose()

# Connection Pool Optimization Settings
CONNECTION_POOL_CONFIG = {
    "pool_size": 20,  # Increased from 5
    "max_overflow": 40,  # Increased from 10
    "pool_recycle": 3600,  # Recycle connections every hour
    "pool_pre_ping": True,  # Verify connections are alive
}

if __name__ == "__main__":
    import os
    
    database_url = os.getenv(
        "DATABASE_URL",
        "postgresql+asyncpg://postgres:postgres@localhost:5432/auth_db"
    )
    
    asyncio.run(run_optimization_migration(database_url))
