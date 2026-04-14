# Documentation

**Purpose**: Centralized location for all project documentation, guides, and decision records.

## Structure

```
docs/
├── README.md (this file)
├── GOVERNANCE.md - Repository rules and governance standards
├── guides/ - Operational and technical guides
├── adc/ - Architecture Decision Records (ADRs)
├── runbooks/ - Operational procedures and playbooks
└── archived/ - Historical documentation
```

## Quick Navigation

- **New to the project?** Start with [../README.md](../README.md) for overview
- **Want to contribute?** See [../CONTRIBUTING.md](../CONTRIBUTING.md)
- **Deploying infrastructure?** See [guides/DEPLOYMENT.md](guides/DEPLOYMENT.md)
- **Troubleshooting issues?** See [guides/TROUBLESHOOTING.md](guides/TROUBLESHOOTING.md)
- **Understanding architecture?** See [adc/](adc/)
- **Running operations?** See [runbooks/](runbooks/)

## Documentation Standards

All documentation MUST follow standards in [GOVERNANCE.md](GOVERNANCE.md#documentation-requirements):
- Markdown format with GitHub-flavored syntax
- Table of Contents for files > 100 lines
- Relative links to related files
- Examples where applicable
- Prerequisites/dependencies listed
- Last updated date and author

## Adding New Documentation

1. Determine category: guides/, adc/, runbooks/, or archived/
2. Create file in appropriate directory
3. Follow header template in [CODE-QUALITY-STANDARDS.md](CODE-QUALITY-STANDARDS.md)
4. Update this README if creating new section
5. Link from related sections

## Document Categories

### Guides (how-to, tutorials)
- Deployment procedures
- Local development setup
- Troubleshooting common issues
- Feature-specific guides

### Architecture Decision Records (ADRs)
- Significant architectural decisions
- Rationale and alternatives considered
- Format: ADR-###-TITLE.md

### Runbooks (operational procedures)
- Step-by-step procedures
- Prerequisites and verification
- Rollback procedures
- Troubleshooting

### Archived (historical records)
- Old phase summaries
- Deprecated configurations
- Historical reference materials

---

**Last Updated**: April 14, 2026  
**Owner**: @akushnir  
**Related**: [GOVERNANCE.md](GOVERNANCE.md) • [../CONTRIBUTING.md](../CONTRIBUTING.md)
