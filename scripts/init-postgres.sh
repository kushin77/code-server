#!/bin/bash
# Initialize PostgreSQL for Appsmith and Backstage
# Run automatically on PostgreSQL container startup

set -e

echo "Initializing Appsmith database..."
psql -U postgres <<-EOSQL
  CREATE DATABASE appsmith OWNER postgres;
  CREATE DATABASE backstage OWNER postgres;
  
  -- Create Appsmith user
  CREATE USER appsmith WITH PASSWORD 'appsmith';
  ALTER ROLE appsmith SET client_encoding TO 'utf8';
  ALTER ROLE appsmith SET default_transaction_isolation TO 'read committed';
  ALTER ROLE appsmith SET default_transaction_deferrable TO on;
  ALTER ROLE appsmith SET default_timezone TO 'UTC';
  GRANT ALL PRIVILEGES ON DATABASE appsmith TO appsmith;
  
  -- Create Backstage user  
  CREATE USER backstage WITH PASSWORD 'backstage';
  ALTER ROLE backstage SET client_encoding TO 'utf8';
  ALTER ROLE backstage SET default_transaction_isolation TO 'read committed';
  ALTER ROLE backstage SET default_transaction_deferrable TO on;
  ALTER ROLE backstage SET default_timezone TO 'UTC';
  GRANT ALL PRIVILEGES ON DATABASE backstage TO backstage;
EOSQL

echo "✅ Appsmith and Backstage databases initialized"
