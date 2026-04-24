-- PostgreSQL initialization for Air-Gapped Deployment
-- Creates all databases and schemas needed for Matrix + Code-Server stack

-- Create synapse database and user
CREATE DATABASE synapse_db;
CREATE USER synapse WITH PASSWORD :'POSTGRES_PASSWORD';
ALTER ROLE synapse WITH CREATEDB;
GRANT ALL PRIVILEGES ON DATABASE synapse_db TO synapse;

-- Connect to synapse database for initialization
\connect synapse_db postgres

-- Create synapse schema
CREATE SCHEMA IF NOT EXISTS synapse;
GRANT ALL PRIVILEGES ON SCHEMA synapse TO synapse;

-- Create other required schemas
CREATE SCHEMA IF NOT EXISTS public;
GRANT ALL PRIVILEGES ON SCHEMA public TO synapse;

-- Set default search path for synapse user
ALTER USER synapse SET search_path TO synapse, public;

-- Connection limits (prevents accidental DoS)
ALTER USER synapse CONNECTION LIMIT 100;
ALTER USER postgres CONNECTION LIMIT 50;

-- Ensure proper encoding (UTF-8 for international support)
ALTER DATABASE synapse_db SET client_encoding = 'UTF-8';

-- Optimize for moderate workloads on this hardware
ALTER DATABASE synapse_db SET max_connections = 1000;
ALTER DATABASE synapse_db SET shared_buffers = 256MB;
ALTER DATABASE synapse_db SET effective_cache_size = 1GB;
ALTER DATABASE synapse_db SET work_mem = 4MB;
ALTER DATABASE synapse_db SET maintenance_work_mem = 64MB;

-- Enable logging for debugging (access via docker logs)
ALTER SYSTEM SET log_statement = 'all';
ALTER SYSTEM SET log_min_duration_statement = 5000;  -- Log queries taking >5s
ALTER SYSTEM SET log_connections = on;
ALTER SYSTEM SET log_disconnections = on;

-- Vacuum configuration (prevent table bloat)
ALTER DATABASE synapse_db SET autovacuum = on;
ALTER DATABASE synapse_db SET autovacuum_naptime = 10s;
ALTER DATABASE synapse_db SET autovacuum_vacuum_threshold = 1000;

-- Audit logging (optional)
-- CREATE EXTENSION IF NOT EXISTS pgaudit;
-- CREATE ROLE auditor;
-- GRANT SELECT ON ALL TABLES IN SCHEMA public TO auditor;

-- Create backup role (for pg_dump)
CREATE ROLE backup WITH NOLOGIN;
GRANT CONNECT ON DATABASE synapse_db TO backup;
GRANT USAGE ON SCHEMA synapse TO backup;
GRANT SELECT ON ALL TABLES IN SCHEMA synapse TO backup;

-- Close connection to synapse_db
\connect postgres postgres

-- Create additional databases if needed for monitoring/logging (optional)
-- CREATE DATABASE monitoring;
-- CREATE DATABASE backups;

-- Final verification
SELECT datname FROM pg_database WHERE datname = 'synapse_db';
SELECT usename FROM pg_user WHERE usename = 'synapse';

-- Grant privileges (explicit for clarity)
GRANT ALL PRIVILEGES ON DATABASE synapse_db TO synapse;

-- Log completion
\echo 'Air-Gapped PostgreSQL initialization complete'
\echo 'Databases created: synapse_db'
\echo 'Users created: synapse, backup'
\echo 'Network isolation: Recommended - internal network only'
