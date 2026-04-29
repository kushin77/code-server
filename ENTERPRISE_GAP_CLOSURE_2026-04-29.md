# Enterprise Gap Closure - April 29, 2026

## Summary

Closed the previously identified missing-service gap by bringing online:
- `code-server-appsmith`
- `code-server-testing`
- `code-server-control-plane`

These services are now running on both hosts:
- `192.168.168.31` (primary)
- `192.168.168.42` (replica)

## Verification

Runtime checks confirm all three containers are running on both hosts.

Primary check result:
- `code-server-appsmith: running`
- `code-server-testing: running`
- `code-server-control-plane: running`

Replica check result:
- `code-server-appsmith: running`
- `code-server-testing: running`
- `code-server-control-plane: running`

## Repo Changes

- Added buildable minimal service scaffold for `testing-service`:
  - `apps/testing-service/Dockerfile`
  - `apps/testing-service/main.py`
  - `apps/testing-service/requirements.txt`
- Updated enterprise compose to include `appsmith` and align control-plane image:
  - `docker-compose.enterprise.yml`

## Deployment Notes

- `control-plane` required host-port remap during live host deployment due `8082` collision on one host.
- Live runtime deployment used host-local overlay file (`~/docker-compose.enterprise-missing.yml`) to avoid disturbing stable services while closing only the identified gap.
