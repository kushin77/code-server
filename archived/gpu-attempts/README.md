# GPU Implementation Attempts

**Purpose**: Historical record of attempts to add GPU support to code-server-enterprise.

## Status

**Current**: GPU support is NOT active in production.

See Phase 21 summary for the latest GPU implementation attempt and why it's archived.

## Contents

This directory contains:
- GPU installation scripts (multiple versions)
- Configuration attempts
- Issue documentation
- Status reports
- Logs and error traces

## Why Archived?

GPU support was attempted in Phase 21 but encountered challenges:
- Hardware capability verification issues
- Driver installation complexity
- Container capability limitations
- Resource allocation concerns

Rather than maintain untested GPU code, it was archived for future reference when GPU support becomes a priority.

---

## If GPU Support is Needed Again

1. Check Phase 21 summary for latest approach
2. Review lessons learned in this directory
3. Start fresh with current best practices
4. Document decisions in `docs/adc/ADR-###-GPU-SUPPORT.md`

---

**Status**: Archived - not actively maintained
**Related**: [../phase-summaries/](../phase-summaries/) • [../../docs/GOVERNANCE.md](../../docs/GOVERNANCE.md)
