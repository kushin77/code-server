# Architecture Decision Records (ADRs)

This directory contains all **significant architectural decisions** made in the code-server repository.

ADRs serve as:
- **Design documentation** — Why we chose a particular approach
- **Rationale repository** — Reasoning, tradeoffs, alternatives considered
- **Historical context** — Why decisions were made (helps avoid re-litigating old decisions)
- **Onboarding tool** — New engineers understand the architecture

---

## What Requires an ADR?

Create an ADR for:

✅ New service architecture  
✅ Technology selection (database, messaging, framework)  
✅ Infrastructure topology changes  
✅ Security boundary changes  
✅ Major refactoring with design implications  
✅ Scalability architecture changes  
✅ Multi-service integration patterns  

Do NOT require ADR for:
- Bug fixes
- Performance optimizations (unless requiring architectural changes)
- Documentation updates
- Dependency upgrades
- Minor refactoring

---

## ADR Naming Convention

```
NNN-[kebab-case-title].md
```

Examples:
- `001-containerized-deployment.md`
- `002-oauth2-proxy-authentication.md`
- `003-terraform-remote-state.md`

**NNN** = Sequential number (001, 002, 003...)  
**Title** = Descriptive, lowercase, hyphens only

---

## ADR Lifecycle

1. **Draft** — Author creates ADR in PR, marked as `[DRAFT]`
2. **Review** — Team reviews, discusses tradeoffs
3. **Accepted** — Approved and merged
4. **Superseded** — Replaced by newer ADR (link both)
5. **Deprecated** — No longer relevant (mark clearly)

---

## How to Create an ADR

1. Copy [TEMPLATE.md](TEMPLATE.md)
2. Fill in all sections (no skipping)
3. Include security implications
4. Include scaling implications
5. Discuss alternatives considered
6. Open PR with title: `[ADR] NNN: [Title]`
7. Address review feedback
8. Merge when approved

---

## When ADRs Become Obsolete

If superseded, create a new ADR and reference it:

```markdown
## Status
Superseded by [ADR-005: New Architecture](005-new-architecture.md)
```

Keep old ADRs for historical context. They're immutable records.

---

## Example ADRs in This Repo

- [ADR-001: Containerized Code-Server Deployment](001-containerized-deployment.md)
- [ADR-002: OAuth2 Proxy for Authentication](002-oauth2-authentication.md)
- [ADR-003: Terraform for Infrastructure](003-terraform-infrastructure.md)

---

## Enforcement

- **Architectural changes without ADR = PR blocked**
- **Missing security/scaling implications = Request changes**
- **ADRs inform code review** — Violations of documented decisions are noted

Elite teams document their architectural thinking. This is how we stay coherent at scale.