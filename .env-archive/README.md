# Legacy .env Files Archive (Phase 3 Cleanup)

This directory contains legacy environment configuration files that have been superseded by the Phase 3 SSOT consolidation.

## Archived Files

- `.env.base` - Merged into `.env/_common/defaults`
- `.env.consolidated` - Redundant merged view (replaced by `.env/_common/defaults`)
- `.env.merged` - Redundant merged view (replaced by `.env/_common/defaults`)

## Migration Path

These files are no longer used. All their configuration has been consolidated into:
- `.env/_common/defaults` - SSOT for all 41 shared variables
- `.env/private/overrides` - Private environment-specific values
- `.env/air-gapped/overrides` - Air-gapped environment-specific values

## Safe to Delete

These files can be safely deleted after confirming no scripts depend on them directly.

See: `.env/_common/README.md` for current configuration structure.

---
Date: April 30, 2026
