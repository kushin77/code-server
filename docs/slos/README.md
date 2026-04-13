# Service Level Objectives (SLOs)

This directory documents **Service Level Objectives** for all production services.

**Without SLOs, you're not running engineering — you're gambling.**

---

## SLO Framework

Every production service must define:

### **SLI** (Service Level Indicator)
What we **measure**. Examples:
- Percentage of successful requests (HTTP 2xx/3xx)
- API response latency (P99)
- Service availability (heartbeat)
- Feature correctness (tests passing in production)

### **SLO** (Service Level Objective)
What we **target**. Examples:
- 99.9% successful requests
- P99 latency < 500ms
- 99.5% uptime
- 0 correctness violations

### **Error Budget**
How much **failure is acceptable**.

Formula: `Error Budget = (100% - SLO%) × Total Time

Example: 99.9% SLO on a 30-day month
- Error budget: 0.1% × (30 days × 24 hours × 60 minutes) = **43.2 minutes**
- Once you've consumed error budget, **you must reduce risk** (stop new rollouts, focus on stability)

### **SLD** (Service Level Directive/SLA)
What we **promise to users**. Typically 1% less than SLO.

Example: 99.9% SLO may promise 99.89% SLA.

---

## When to Create an SLO

For every service that:
- ✅ Impacts production workflow
- ✅ Has external users or dependencies
- ✅ Runs 24/7 or during business hours
- ✅ Requires on-call suppor

Do NOT create for:
- Internal utilities with infrequent use
- Batch jobs with no availability requirements
- Development-only services

---

## Elite SLO Practices

### 1. Base SLOs on User Experience
Not internal metrics. Users care about:
- "Can I log in and access my code?"
- "How fast does my code complete?"
- "Did my changes apply successfully?"

### 2. Make SLOs Achievable but Demanding
- SLO too loose: Doesn't drive reliability investmen
- SLO too tight: Constantly consuming error budget, no room for innovation
- Sweet spot: 99.5% - 99.99% depending on service criticality

### 3. Use Error Budget for Release Decisions
- High error budget: Can deploy new features, accept more risk
- Low error budget: Freeze deployments, focus on stability
- This is data-driven risk managemen

### 4. Alert on SLO Violation, Not Symptom
- ❌ Alert on "CPU > 80%" (might not matter if latency is fine)
- ✅ Alert on "P99 latency > SLO target" (user-facing)

### 5. Blame Humans, Not Systems
When SLO missed:
- ✅ "We deployed a bug that increased latency"
- ❌ "The database was slow" (not blameless, but doesn't identify fix)

Incident postmortems must identify **human decision** that led to outage.

### 6. SLOs Drive On-Call Sizing
Number of on-call engineers = (downtime × response time) / (acceptable hours on-call)

If your SLO is unachievable with current on-call team, you have a staffing problem.

---

## SLO Evolution

As service matures:

| Phase | SLO | Rationale |
|-------|-----|----------|
| **Beta (Launch)** | 99.0% | Early product, expect issues |
| **Early Prod (Months 1-3)** | 99.5% | Building reliability infrastructure |
| **Stable Prod (Months 3+)** | 99.9% | Proven, expected to be stable |
| **Critical (Year 1+)** | 99.95%+ | Mission-critical, high customer impact |

---

## Reference Documents

- [Google SRE Book: Chap 4 - Service Level Objectives](https://sre.google/books/)
- [Betsy Beyer et al. - SLO Best Practices](https://sre.google/resources/practices-and-processes/service-level-objectives/)

---

## SLO Registry

| Service | SLO | Owner | Dashboard | Status |
|---------|-----|-------|-----------|--------|
| [code-server](code-server.md) | 99.5% | @kushin77 | [Grafana](link) | ✅ Active |
