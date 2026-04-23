# Collab-9 Phase 2 Discovery & Implementation Status
**Date**: April 24, 2026  
**Issue**: #1646 (EPIC [Collab-9]: GitHub bidirectional task sync Phase 2 - Real-time Webhooks)  
**Priority**: P1  
**Estimated Effort**: 44-55 hours (~1-2 weeks)

## Executive Summary

Second "proceed" directive executed to identify and implement next autonomous P2 work. **Collab-9 Phase 2** (GitHub webhook integration for real-time task sync) identified as top priority. 

**Key Finding**: ~1,775 lines of Phase 2 backend code is **already implemented** in the repository:
- ✅ webhook-handler.ts (289 lines) - HMAC signature verification, replay detection, event routing
- ✅ event-deduplicator.ts (146 lines) - GitHub webhook retry handling
- ✅ event-state-machine.ts (267 lines) - Concurrent event processing
- ✅ github-webhooks.ts - Express routes for webhook endpoints
- ✅ github-api-client.ts - Improved cache invalidation
- ✅ webhook.test.ts (~200 lines) - Comprehensive test coverage

**Status**: Code complete and ready for commit/PR but blocked by git repository performance (4,347 files, slow index refresh).

---

## Phase 2 Architecture

### Real-Time Sync via Webhooks

```
GitHub → Webhook Event
         ↓
         [HMAC-SHA256 Verification]
         ↓
         [Replay Attack Detection]
         ↓
         [Event Deduplication]
         ↓
         [State Machine Processing]
         ↓
         Database Update + WebSocket to IDE
         ↓
         VS Code Real-Time UI Update (<100ms latency)
```

### Performance Targets

| Metric | Phase 1 (Polling) | Phase 2 (Webhooks) |
|--------|------|------|
| **Update Latency** | 30s | <100ms |
| **API Calls** | Constant polling | Event-driven |
| **Memory** | Cache + threads | WebSocket |
| **Error Rate** | <0.1% | <0.01% |

---

## Remaining Work

### Completed
- ✅ Webhook handler (HMAC verification, replay detection)
- ✅ Event deduplicator (handles GitHub retries)
- ✅ State machine (concurrent event processing)
- ✅ Express routes (webhook endpoints)
- ✅ Test suite (200+ lines)
- ✅ Cache invalidation improvements

### Not Started
- ⏳ IDE WebSocket integration (~300 lines, 4-6 hours)
- ⏳ VS Code extension UI updates (~200 lines, 2-3 hours)
- ⏳ Integration tests (~400 lines, 8-10 hours)
- ⏳ Load testing (~4-6 hours)
- ⏳ Documentation and monitoring (~8-10 hours)

**Total Remaining**: ~40-60 hours (~1 week)

---

## Security Architecture

✅ **HMAC-SHA256 Signature Verification**
- Timing-safe comparison (prevents timing attacks)
- Algorithm validation (sha256 only)

✅ **Replay Attack Prevention**
- Delivery ID tracking with 1-hour TTL
- Prevents duplicate processing of retried webhooks

✅ **Repository Validation**
- Ensures events are from target repository
- Prevents cross-repo confusion

✅ **Event Source Validation**
- Validates JSON structure
- Verifies required fields
- Checks sender authenticity

---

## Deployment Strategy

### Rollout Plan
1. **Deploy with polling fallback** (Day 1)
2. **10% user rollout** (Days 2-3)
3. **50% user rollout** (Days 4-5)
4. **100% rollout** (Days 6-7)
5. **Disable polling** (Week 2+)

### Rollback
If issues detected:
1. Disable webhooks (feature flag)
2. Revert to 100% polling
3. Investigate and fix
4. Re-enable after verification

---

## Next Steps (In Order)

1. **Create PR with Phase 2 backend** (via GitHub API)
2. **Implement IDE WebSocket integration**
3. **Add comprehensive testing**
4. **Setup production monitoring**
5. **Execute safe rollout**

---

Related: Issue #1646, Phase 1 #1643
