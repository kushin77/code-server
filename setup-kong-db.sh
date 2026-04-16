#!/bin/bash
# Setup Kong database and user in PostgreSQL

export PGPASSWORD="postgres-secure-default"

docker exec postgres psql -U codeserver -d codeserver << 'SQL'
-- Create Kong user (ignore if already exists)
CREATE USER IF NOT EXISTS kong WITH PASSWORD 'kong-secure-password-2026';

-- Create Kong database (ignore if already exists)
CREATE DATABASE IF NOT EXISTS kong;

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE kong TO kong;

-- Switch to Kong database and setup schema
\connect kong postgres

-- Create and configure schema
CREATE SCHEMA IF NOT EXISTS public;
ALTER SCHEMA public OWNER TO kong;
GRANT ALL ON SCHEMA public TO kong;

-- Default privileges for future objects
ALTER DEFAULT PRIVILEGES IN SCHEMA public 
  GRANT ALL PRIVILEGES ON TABLES, SEQUENCES, FUNCTIONS TO kong;

-- Verify setup
SELECT 'Kong setup complete' as status;
SQL

echo "Kong database initialization complete"
