# Quick Reference: GitHub Issues Summary

## Issues Created (April 15, 2026)

### EPIC #411 — Master Orchestration
https://github.com/kushin77/code-server/issues/411
- 5-phase implementation plan (May 1-31)
- 290 engineering hours across 4 teams
- $58k budget + $500-1k hardware
- Dependencies + resource allocation

### Child Issues

#### #410 — Baselines & Monitoring (START HERE)
https://github.com/kushin77/code-server/issues/410
- **Week 1 (May 1-7)**: Collect April baselines
- **Week 5 (May 29-31)**: Collect May data + report
- Infrastructure, container, app, end-to-end baselines
- Prometheus exporters + Grafana dashboards
- Monthly reports + ROI analysis

#### #408 — Network 10G (CRITICAL PATH)
https://github.com/kushin77/code-server/issues/408
- **Week 2 (May 8-14)**: Network optimization
- iperf3 baseline (verify 10G)
- Jumbo frames (MTU 9000)
- NIC bonding (active-backup or LACP)
- **Target**: 125 MB/s → 1 GB/s (8x)

#### #407 — NAS NVME Cache
https://github.com/kushin77/code-server/issues/407
- **Week 3 (May 15-21)**: Storage optimization
- 3-tier cache (NAS NVME + local SSD + Redis)
- NAS failover automation
- Cache sync (local → NAS async)
- **Target**: Model load 320s → 60s (5.3x)

#### #409 — Redis HA (Sentinel)
https://github.com/kushin77/code-server/issues/409
- **Week 4 (May 22-28)**: Redis resilience
- 3-node Sentinel cluster
- Persistence (AOF + RDB)
- Replication (<100ms lag)
- **Target**: Manual failover → <5s automated

---

## Success Metrics (April → May 2026)

| Metric | April | May Target | Gain |
|--------|---|---|---|
| **Network throughput** | 125 MB/s | 1 GB/s | **8x** |
| **Model load (40 GB)** | 320s | 60s | **5.3x** |
| **Ollama p99 latency** | 1.2s | 0.5s | **2.4x** |
| **Redis failover** | Manual | <5s | **HA** |
| **Cache hit rate** | N/A | >75% | **New** |
| **Monitoring** | Basic | Full | **Data-driven** |

---

## Implementation Sequence

1. **#410 (Baselines)** — May 1-7 — Non-blocking, start immediately
2. **#408 (Network 10G)** — May 8-14 — Critical path, enables storage
3. **#407 (NAS Cache)** — May 15-21 — After network verified
4. **#409 (Redis HA)** — May 22-28 — Parallel with #407 if possible
5. **#410 (Validation)** — May 29-31 — Measure improvements

---

## Files in Repository

**Summary Document**: `IaC-REVIEW-GITHUB-ISSUES-SUMMARY.md`  
**Session Notes**: `/memories/session/iac-review-github-issues-created.md`

---

## Key Points

✅ **Production-ready**: All designs follow production-first mandate  
✅ **Zero downtime**: Changes deployable in seconds, rollback <60s  
✅ **Measurable**: Baseline-driven, SLO-tracked, ROI-justified  
✅ **Non-intrusive**: Monitoring only first, then deployment  
✅ **Team-oriented**: 4 teams, clear phase dependencies, parallel execution  

---

## Contact

Questions about the issues? Review the full GitHub issue descriptions or the comprehensive summary doc in the repository.

Status: **READY FOR TEAM ASSIGNMENT**  
Target Start: **May 1, 2026**  
Target Completion: **May 31, 2026**
