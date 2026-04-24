# Phase 1 Execution Steps - PostgreSQL Streaming Replication Setup

**Status**: Ready to execute with manual SQL commands

**Database Confirmed**: ✅ Operational as user `codeserver`
- Host: 192.168.168.31
- User: codeserver
- Database: codeserver
- Version: PostgreSQL 15.17

---

## Step 1: Create Replicator User

Execute on PRIMARY host (192.168.168.31):

```bash
docker exec postgres psql -U codeserver -d codeserver << 'EOF'
CREATE USER replicator WITH REPLICATION PASSWORD 'replicator-secure-password';
GRANT CONNECT ON DATABASE codeserver TO replicator;
EOF
```

Verify:
```bash
docker exec postgres psql -U codeserver -d codeserver -c "SELECT usename, userepl FROM pg_user WHERE usename = 'replicator';"
```

Expected output:
```
 usename  | userepl 
----------+---------
 replicator | t
```

---

## Step 2: Configure Primary PostgreSQL for Replication

Update PostgreSQL configuration on PRIMARY (192.168.168.31):

```bash
docker exec postgres psql -U codeserver -d codeserver << 'EOF'
-- Enable WAL streaming
ALTER SYSTEM SET wal_level = replica;
ALTER SYSTEM SET max_wal_senders = 3;
ALTER SYSTEM SET max_replication_slots = 3;
ALTER SYSTEM SET hot_standby = on;
ALTER SYSTEM SET hot_standby_feedback = on;
ALTER SYSTEM SET wal_keep_size = '1GB';

-- Create replication slot
SELECT pg_create_physical_replication_slot('replica_slot');
EOF
```

Restart PostgreSQL:
```bash
docker restart postgres
docker ps | grep postgres  # Wait for healthy status (30s)
```

Verify:
```bash
docker exec postgres psql -U codeserver -d codeserver -c "SELECT slot_name, slot_type, active FROM pg_replication_slots;"
```

---

## Step 3: Configure Replica Host (192.168.168.42)

On REPLICA host, prepare base backup:

```bash
ssh akushnir@192.168.168.42 'bash -lc "
  cd code-server-enterprise
  
  # Stop PostgreSQL on replica
  docker stop postgres pgbouncer 2>/dev/null
  
  # Remove data directory (will be replaced by base backup)
  docker exec postgres rm -rf /var/lib/postgresql/data/pgdata/* 2>/dev/null || true
  
  # Take base backup from primary
  docker run --rm \
    -v postgres-data:/var/lib/postgresql/data \
    --network code-server-enterprise_net-app \
    postgres:15-alpine \
    pg_basebackup \
      -h 192.168.168.31 \
      -D /var/lib/postgresql/data/pgdata \
      -U replicator \
      -W \
      -v \
      -P \
      -R \
      --wal-method=stream \
      --slot=replica_slot
"'
```

---

## Step 4: Create Standby Configuration on Replica

On REPLICA host (192.168.168.42):

```bash
docker exec postgres bash -c 'cat > /var/lib/postgresql/data/pgdata/standby.signal << EOF
# This file signals PostgreSQL to start in standby/read-only mode
EOF
'
```

---

## Step 5: Start Replica and Verify Replication

On REPLICA host:

```bash
docker start postgres pgbouncer
sleep 30

# Verify standby is receiving from primary
docker exec postgres psql -U codeserver -d codeserver -c "SELECT * FROM pg_stat_wal_receiver;"
```

Expected output: One row showing active WAL receiver connected to primary

---

## Step 6: Monitor Replication Lag

On PRIMARY host:

```bash
# Check replication status
docker exec postgres psql -U codeserver -d codeserver -c "SELECT usename, client_addr, state, write_lag, flush_lag, replay_lag FROM pg_stat_replication;"

# Monitor lag continuously
watch -n 1 'ssh akushnir@192.168.168.31 "docker exec postgres psql -U codeserver -d codeserver -c \"SELECT EXTRACT(EPOCH FROM (NOW() - pg_last_xact_replay_timestamp())) as replication_lag_seconds;\""'
```

Target: lag < 100ms (0.1 seconds)

---

## Step 7: Test Replication (Data Flows Primary → Replica)

On PRIMARY:

```bash
docker exec postgres psql -U codeserver -d codeserver << 'EOF'
CREATE TABLE replication_test (id SERIAL, message TEXT, created_at TIMESTAMP DEFAULT NOW());
INSERT INTO replication_test (message) VALUES ('Test insert at ' || NOW());
EOF
```

On REPLICA (verify data appears):

```bash
docker exec postgres psql -U codeserver -d codeserver -c "SELECT * FROM replication_test ORDER BY id DESC LIMIT 5;"
```

Expected: Same data as primary within < 100ms

---

## Status

| Step | Command | Status |
|------|---------|--------|
| 1 | Create replicator user | ⏳ Manual required |
| 2 | Configure primary for replication | ⏳ Manual required |
| 3 | Prepare base backup on replica | ⏳ Manual required |
| 4 | Create standby.signal on replica | ⏳ Manual required |
| 5 | Start replica and verify | ⏳ Manual required |
| 6 | Monitor replication lag | ⏳ Verify lag < 100ms |
| 7 | Test replication | ⏳ Verify data flows |

---

## Notes

- Database credentials: user=`codeserver`, password=`postgres-secure-default`
- Replication credentials: user=`replicator`, password=`replicator-secure-password`
- Replication slot: `replica_slot` (manages WAL retention)
- Primary: 192.168.168.31
- Replica: 192.168.168.42

---

## Success Criteria

- ✅ Replication slot created and active on primary
- ✅ Replication user has REPLICATION privilege
- ✅ Replica receives WAL from primary
- ✅ Replication lag < 100ms
- ✅ Data replicates within 100ms
- ✅ WAL files accumulating on primary

Once complete, proceed to Phase 2 (Automated Backup Strategy).
