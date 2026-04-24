-- Create replication user for PostgreSQL streaming replication
CREATE USER replicator WITH REPLICATION PASSWORD 'replicator-secure-pwd';
GRANT CONNECT ON DATABASE codeserver TO replicator;

-- Verify user was created
SELECT usename, usesuper, userepl FROM pg_user WHERE usename = 'replicator';
