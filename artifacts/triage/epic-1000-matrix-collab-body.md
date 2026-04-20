## P1 EPIC: Matrix-Based Real-Time Collaboration Hub for code-server IDE

### Vision

Implement an enterprise-grade, future-proof collaboration system using Matrix protocol as the sovereign backbone, with bidirectional bridges to Slack, Microsoft Teams, and Google Chat. Integrate a custom code-server sidebar extension for real-time "same-task" presence and one-click actions.

This is the most robust, anti-fragile architecture available in 2026 — providing native IDE awareness while connecting to any enterprise chat ecosystem without vendor lock-in.

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           code-server IDE                                   │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │                      Team Hub Sidebar Extension                       │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────────┐   │  │
│  │  │ Online Users │  │ Same File!   │  │ Quick Actions            │   │  │
│  │  │ • Alice ●    │  │ • Bob (L42)  │  │ [📞 Meet] [💬 Mention]   │   │  │
│  │  │ • Bob ●      │  │ • Carol (L87)│  │ [🎤 Voice] [🔗 Share]    │   │  │
│  │  │ • Carol ○    │  │              │  │                          │   │  │
│  │  └──────────────┘  └──────────────┘  └──────────────────────────┘   │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────┬────────────────────────────────────┘
                                         │
                                         ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                        Presence Sidecar Service                             │
│                    (Node.js + Matrix SDK + WebSocket)                       │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  State Events: { user, file, line, project, timestamp, workspace }  │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└────────────────────────────────────────┬────────────────────────────────────┘
                                         │
                                         ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                     Matrix Homeserver (Element Server Suite Pro)            │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐  ┌─────────────┐  │
│  │ E2EE Rooms    │  │ State Events  │  │ Federation    │  │ Audit Logs  │  │
│  │ & Spaces      │  │ (Presence)    │  │ (Optional)    │  │ & Retention │  │
│  └───────────────┘  └───────────────┘  └───────────────┘  └─────────────┘  │
└────────────────────────────────────────┬────────────────────────────────────┘
                                         │
           ┌─────────────────────────────┼─────────────────────────────┐
           ▼                             ▼                             ▼
┌─────────────────────┐    ┌─────────────────────┐    ┌─────────────────────┐
│   Slack Bridge      │    │   Teams Bridge      │    │  Google Chat Bridge │
│   (Bidirectional)   │    │   (Bidirectional)   │    │   (Bidirectional)   │
└─────────┬───────────┘    └─────────┬───────────┘    └─────────┬───────────┘
          │                          │                          │
          ▼                          ▼                          ▼
┌─────────────────────┐    ┌─────────────────────┐    ┌─────────────────────┐
│   Slack Workspace   │    │   Microsoft Teams   │    │  Google Workspace   │
└─────────────────────┘    └─────────────────────┘    └─────────────────────┘
```

### Why Matrix Protocol (2026 Standard)

| Benefit | Description |
|---------|-------------|
| **Vendor Neutral** | Decentralized like email for chat. Own your data. No single-vendor risk. |
| **Future Proof** | Bridges to Slack/Teams/Google Chat today, any future platform via Matrix spec |
| **Enterprise Ready** | E2EE by default, SSO (SAML/OIDC), SCIM, audit logs, SOC 2/HIPAA/GDPR |
| **Programmable Presence** | Matrix state events give "currently editing X" visibility across all bridges |
| **Self-Hosted or Managed** | Element Matrix Services or fully self-hosted for sovereignty |
| **Fallback Native** | Element web/desktop/mobile always available if bridges down |

### Component Stack

| Layer | Component | Key Capabilities | Enterprise Controls |
|-------|-----------|------------------|---------------------|
| **Core Backend** | Matrix Homeserver (Element Server Suite Pro) | E2EE rooms/spaces, state events, federation, bridges | Audit logging, retention, air-gapped |
| **Real-Time Presence** | Sidecar (Node.js + Matrix SDK) | "User X on file Y, line Z" on file change | Role-based access, encryption |
| **code-server Extension** | Custom Webview Sidebar | Live team list + file awareness + quick actions | Secure token storage, SSO flow |
| **Chat Ecosystem** | Bidirectional Bridges | Slack ↔ Matrix, Teams ↔ Matrix, Google Chat ↔ Matrix | Message history sync, @mentions preserved |
| **Video** | Google Meet (primary) + Element Call | Instant Meet links posted to room | Compliance recording options |
| **Identity** | Existing IdP | Google Workspace, Okta, Azure AD, SAML/SCIM | Just-in-time provisioning |

### User Experience (Native Feel)

1. **Sidebar "Team Hub" Panel**
   - Shows online users + current file/project
   - Green highlight = "same file as you!"
   - Real-time updates via WebSocket

2. **One-Click Actions**
   - `@mention in Slack/Teams/Chat` → Posts to bridged room
   - `Start Google Meet` → Creates Meet link, posts to room
   - `Join voice call` → Element Call or bridged platform
   - `Share workspace link` → Generates shareable session URL

3. **Cross-Platform Sync**
   - Everything stays in sync across Slack/Teams/Google Chat via bridges
   - Native Matrix client (Element) always available as fallback

### Implementation Roadmap

| Phase | Timeline | Deliverables |
|-------|----------|--------------|
| **PoC** | Week 1 | Matrix homeserver + one bridge (Slack) + minimal sidebar extension |
| **Core** | Week 2-3 | Full SSO/SCIM, presence sidecar, Google Meet integration |
| **Scale** | Week 4 | Full IaC, all bridges, production deployment |
| **Rollout** | Week 5+ | Phased pilot → org-wide with zero downtime |

### Child Issues

Created via this EPIC:

| Issue | Title | Priority |
|-------|-------|----------|
| #TBD | Design Matrix Homeserver architecture and deployment strategy | P1 |
| #TBD | Implement code-server Team Hub sidebar extension | P1 |
| #TBD | Deploy real-time presence sidecar service | P1 |
| #TBD | Configure Slack bidirectional bridge | P1 |
| #TBD | Configure Microsoft Teams bidirectional bridge | P2 |
| #TBD | Configure Google Chat bidirectional bridge | P2 |
| #TBD | Integrate Google Meet one-click creation | P1 |
| #TBD | Element Call (MatrixRTC) fallback integration | P2 |
| #TBD | SSO/SCIM integration with existing IdP | P1 |
| #TBD | Terraform IaC modules for full collaboration stack | P1 |
| #TBD | Observability integration (Prometheus/Grafana for Matrix) | P2 |
| #TBD | Admin & governance tooling (space templates, moderation, retention) | P2 |
| #TBD | Air-gapped deployment configuration for regulated environments | P3 |

### IaC Requirements

```hcl
# terraform/modules/matrix-collab/
#
# Modules to create:
# - matrix-homeserver (Element Server Suite Pro or self-hosted Synapse)
# - matrix-bridges (Slack, Teams, Google Chat)
# - presence-sidecar (Cloud Run / GKE / self-hosted)
# - code-server-extension (pre-built .vsix baked into Docker image)
# - google-meet-api (API scopes for Meet link creation)
# - observability (Prometheus/Grafana export for Matrix)
```

### Definition of Done (EPIC Level)

- [ ] Matrix homeserver deployed and operational
- [ ] code-server Team Hub extension installed in all IDE instances
- [ ] Real-time presence showing "same file" awareness
- [ ] At least one bridge (Slack or Teams) fully operational
- [ ] Google Meet one-click creation working
- [ ] SSO integrated with existing IdP (Google Workspace)
- [ ] Full Terraform IaC for reproducible deployment
- [ ] Documentation: architecture, runbooks, user guide
- [ ] Production rollout to pilot team

### Cross-References

- Related: #954 (HA EPIC) - Matrix must integrate with HA architecture
- Related: #982 (QA EPIC) - E2E tests for collaboration features
- Related: #967 (Audit EPIC) - Security review of Matrix deployment
- Related: #965 (Observability) - Matrix metrics integration

### Open Questions (To Resolve in Child Issues)

1. **Primary chat platform today?** Slack / Google Workspace / Teams / Hybrid
2. **Team size & expected growth?** Impacts scaling decisions
3. **Self-hosted vs managed?** Element Server Suite Pro vs self-hosted Synapse
4. **Compliance needs?** SOC2, HIPAA, air-gapped requirements
5. **Existing IaC setup?** Integration with current Terraform/K8s

### Success Metrics

| Metric | Target |
|--------|--------|
| Extension adoption | 80%+ of active IDE users within 30 days |
| Presence latency | <500ms for "same file" updates |
| Bridge reliability | 99.9% message delivery |
| User satisfaction | NPS >50 for collaboration features |
