# Phase 13: AI-Powered Operations

**Status**: ✅ Ready
**Focus**: Alert deduplication, runbook guidance, and scaling recommendations

## Objective

Phase 13 turns the shared alert pipeline into an operations advisor that can
deduplicate noisy alerts, recommend the right runbook, and point operators at
the most likely scaling action.

## Deliverables

- `apps/shared/ai_operations.py` - deterministic AI-ops advisor for alerts
- `apps/shared/alert_receiver.py` - integrated AI guidance in alert webhook processing
- `apps/shared/tests/test_ai_operations.py` - focused validation for deduplication and recommendations
- `docs/operations/ai-ops-guide.md` - operator guide for the new workflow

## Coverage

- Alert deduplication by alert/component/severity fingerprint
- Runbook suggestions based on alert annotations and component heuristics
- Predictive scaling recommendations for high-load alerts
- AI guidance surfaced in alert webhook responses
