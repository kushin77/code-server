# Documentation

**Purpose**: Centralized location for all project documentation, guides, and decision records.

## Structure

```
docs/
├── README.md (this file)
├── ai/ - AI governance, access, contracts, and policy docs
├── adr/ - Architecture Decision Records
├── archives/ - Historical documentation
├── governance/elite-best-practices/ - Canonical elite best-practices SSOT tree
├── ops/ - Runbooks and operational procedures
├── status/ - Proof artifacts, status ledgers, and evidence bundles
├── triage/ - Issue blockers and execution plans
└── structure/ - Documentation SSOT, naming rules, and folder map
```

## Quick Navigation

- **Documentation SSOT**: [structure/README.md](structure/README.md)
- **New to the project?** Start with [structure/README.md](structure/README.md) for the documentation map
- **Want contributor guidance?** See [governance/elite-best-practices/instructions/AGENT-SESSION-COORDINATION.md](governance/elite-best-practices/instructions/AGENT-SESSION-COORDINATION.md)
- **Need architecture decisions?** Check [adr/README.md](adr/README.md)
- **Need operational evidence?** Check [status/README.md](status/README.md)
- **Need recovery steps or runbooks?** Check [ops/README.md](ops/README.md)
- **Need issue blockers or active triage notes?** Check [triage/README.md](triage/README.md)
- **Need elite best-practices navigation?** Check [governance/elite-best-practices/README.md](governance/elite-best-practices/README.md)
- **Need AI contracts or access rules?** Check [ai/README.md](ai/README.md)
- **Need historical records?** Check [archives/README.md](archives/README.md)

## Documentation Standards

All documentation MUST follow the rules in [structure/README.md](structure/README.md):
- One canonical document per topic
- No duplicate guidance across docs
- Use the approved naming convention for issue-backed files and proofs
- Keep new markdown files in the canonical folder for their category
- Root-level markdown files are legacy migration artifacts and should not be added for new work
- Remaining bridge-doc cleanup was completed in #691; any top-level legacy files are compatibility stubs only.

## Adding New Documentation

1. Determine the canonical category first.
2. Check whether a matching doc already exists.
3. Update the existing SSOT instead of creating a duplicate.
4. Create new files in the appropriate category folder.
5. Update this README if the folder map changes.

## Document Categories

### AI / Policy
- Contracts, access policy, and model governance belong in [ai/README.md](ai/README.md).

### Architecture Decisions
- Significant architectural decisions belong in [adr/README.md](adr/README.md).

### Runbooks
- Step-by-step procedures, prerequisites, and rollback guidance belong in [ops/README.md](ops/README.md).

### Status / Proof
- Validation evidence and execution proofs belong in [status/README.md](status/README.md).

### Triage / Blockers
- Open issue blockers and execution notes belong in [triage/README.md](triage/README.md).

### Elite Best Practices
- Canonical index for monorepo, pnpm, shared, SSOT, repo rules, instructions, and naming guidance belongs in [governance/elite-best-practices/README.md](governance/elite-best-practices/README.md).

### Archives
- Historical records and retired artifacts belong in [archives/README.md](archives/README.md).

---

**Last Updated**: April 18, 2026
**Owner**: @akushnir  
**Related**: [GOVERNANCE.md](GOVERNANCE.md) • [structure/README.md](structure/README.md) • [governance/elite-best-practices/README.md](governance/elite-best-practices/README.md)
