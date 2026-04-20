# Issue #916 Compliance Evidence Query

Generated at (UTC): 2026-04-20T01:03:49.167013+00:00

## Query used for compliance validation
```sql
SELECT
  session_id,
  username,
  data_profile,
  data_profile_validated,
  status,
  created_at
FROM sessions
WHERE status IN ('running', 'queued')
  AND (
    data_profile NOT IN ('synthetic', 'masked', 'redacted')
    OR data_profile_validated IS NOT TRUE
  );
```

## Query result on sample sessions
- sampleSessionCount: 3
- nonCompliantSessionCount: 0
- launchSchemaEnforced: True
- metadataPersisted: True
- compliant: True

## Approved profiles
- synthetic, masked, redacted

## Artifact paths
- /mnt/c/code-server-enterprise/artifacts/triage/issue-916-sample-sessions.json
- /mnt/c/code-server-enterprise/artifacts/triage/issue-916-compliance-evidence.machine.json

## Relevant code paths
- apps/session-broker/src/session-data-profile.ts
- apps/session-broker/src/index.ts
- apps/session-broker/migrations/001_session_isolation_schema.sql
- apps/frontend/src/pages/EphemeralSessions.tsx
