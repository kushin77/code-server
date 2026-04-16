-- ═══════════════════════════════════════════════════════════════════
-- Kong Database & User Initialization
-- Consolidates Kong to use primary PostgreSQL instead of separate kong-db
-- ═══════════════════════════════════════════════════════════════════

-- Create Kong database
CREATE DATABASE kong;

-- Create Kong user with password from environment
CREATE USER kong WITH PASSWORD :'kong_password';

-- Grant all privileges on Kong database to Kong user
GRANT ALL PRIVILEGES ON DATABASE kong TO kong;

-- Grant privileges on schemas within Kong database
\connect kong

-- Create public schema (Kong uses this by default)
CREATE SCHEMA IF NOT EXISTS public;

-- Grant schema privileges to Kong user
GRANT USAGE ON SCHEMA public TO kong;
GRANT CREATE ON SCHEMA public TO kong;

-- Allow Kong user to create objects in public schema
GRANT ALL PRIVILEGES ON SCHEMA public TO kong;

-- Ensure Kong user owns the public schema
ALTER SCHEMA public OWNER TO kong;

-- Grant default privileges on future objects
ALTER DEFAULT PRIVILEGES FOR USER kong IN SCHEMA public 
  GRANT ALL PRIVILEGES ON TABLES TO kong;

ALTER DEFAULT PRIVILEGES FOR USER kong IN SCHEMA public 
  GRANT ALL PRIVILEGES ON SEQUENCES TO kong;

ALTER DEFAULT PRIVILEGES FOR USER kong IN SCHEMA public 
  GRANT USAGE, SELECT ON SEQUENCES TO kong;

-- Done
\connect postgres
