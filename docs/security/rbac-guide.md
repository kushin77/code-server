# Role-Based Access Control (RBAC) Guide (P1 Priority 6)

## Overview
This document outlines the RBAC strategy used to enforce the principle of least privilege across the Code Server Enterprise environment.

## Policy Engine (OPA)
We use Open Policy Agent (OPA) to manage centralized authorization policies.
- **Policy File**: \opa/policies/rbac.rego- **Roles**:
    - \dmin\: Full access (read, write, delete, admin)
    - \operator\: Operational access (read, write)
    - \iewer\: Read-only access

## Service Level ACLs
### Redis
Redis access is managed via ACL files.
- **Default User**: Restricted by default.
- **Worker User**: Restricted to specific key patterns and command groups.

### PostgreSQL
PostgreSQL uses role-based permissions (GRANT/REVOKE) on a per-schema/table basis.

## Automation
Apply or update RBAC policies:
\\ash
bash scripts/ops/implement-rbac.sh
\
## Compliance
This implementation fulfills GOV-002 requirements for access control and accountability.
