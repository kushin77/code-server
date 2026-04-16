# Code Server Enterprise - Documentation Index

**Last Updated:** April 21, 2026  
**Owner:** Infrastructure Team  
**Status:** Production

---

## 📚 Documentation Structure

This directory contains comprehensive documentation for the code-server-enterprise platform. Documentation is organized by category for easy discovery and maintenance.

### Quick Navigation

| Category | Purpose | Location |
|----------|---------|----------|
| **Architecture** | System design, component diagrams, data flow | [./architecture/](./architecture/) |
| **Deployment** | Deployment procedures, environment setup, runbooks | [./deployment/](./deployment/) |
| **Guides** | How-to guides, tutorials, best practices | [./guides/](./guides/) |
| **Operations** | Operational procedures, monitoring, troubleshooting | [./operations/](./operations/) |
| **Production** | Production deployment guides, SLOs, incident response | [./production/](./production/) |
| **Runbooks** | Incident response, troubleshooting, recovery procedures | [./runbooks/](./runbooks/) |
| **Standards** | Development standards, coding guidelines, policies | [./standards/](./standards/) |

---

## 🚀 Getting Started

### For New Team Members
1. Start with **[Getting Started Guide](./guides/getting-started.md)**
2. Review **[Architecture Overview](./architecture/overview.md)**
3. Read **[Production Deployment Guide](./production/deployment-guide.md)**

### For Operators
1. Read **[Operations Guide](./operations/operations-guide.md)**
2. Check **[Monitoring Setup](./operations/monitoring.md)**
3. Review **[Runbooks](./runbooks/)** for common issues

### For Developers
1. Review **[Development Standards](./standards/development.md)**
2. Check **[Architecture Decisions](./architecture/adrs.md)**
3. Read relevant **[Guides](./guides/)**

---

## 🔄 Deployment Scripts

The project includes unified deployment scripts for easy infrastructure management:

### Unix/Linux/WSL
```bash
./deploy.sh --help           # Show usage
./deploy.sh local validate   # Validate configuration
./deploy.sh remote status    # Check remote status
./deploy.sh remote apply     # Deploy to production
```

### Windows
```batch
deploy.bat --help            # Show usage
deploy.bat local validate    # Validate configuration
deploy.bat remote status     # Check remote status
```

See [Deployment Guide](./production/deployment-guide.md) for details.

---

## 📊 Key Metrics & SLOs

- **Availability Target:** 99.99%
- **P99 Latency Target:** <100ms
- **Error Rate Target:** <0.1%
- **Test Coverage Target:** 95%+
- **MTTR Target:** <30 minutes

See [SLOs Documentation](./production/slos.md) for detailed definitions and tracking.

---

## 🔐 Security

All documentation includes security considerations. For security-specific guidance, see:
- [Security Guidelines](./standards/security.md)
- [Pre-Deployment Security Checklist](./production/security-checklist.md)
- [Incident Response - Security](./runbooks/security-incidents.md)

---

## 🤝 Contributing

When contributing documentation:
1. Follow [Documentation Standards](./standards/documentation.md)
2. Use proper Markdown formatting
3. Include examples where applicable
4. Link to related documentation
5. Keep content current and accurate

---

## 📞 Support

For questions or issues with documentation:
- Review existing documentation in relevant categories
- Check [Runbooks](./runbooks/) for troubleshooting
- Contact the Infrastructure Team
- Create an issue in the repository

---

## 📝 Recent Updates

- **April 21, 2026** - Documentation structure consolidated and enhanced
- **April 15, 2026** - Production standards finalized
- **April 14, 2026** - Initial documentation framework

---

## License & Ownership

- **Owner:** Infrastructure Team
- **Last Updated:** April 21, 2026
- **Status:** Production
- **License:** Internal Use Only

---

**For operational support and deployment assistance, refer to [Operations Guide](./operations/operations-guide.md) and [Deployment Guide](./production/deployment-guide.md).**

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
