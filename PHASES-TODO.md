
## Q3 Roadmap Transition: Post-Observability
- [x] [P1] Deploy Qdrant Cluster for Organizational Memory (Phase 6 Kickoff) — 2-node cluster with replication_factor=2; bootstrap: scripts/phase6/deploy-qdrant-cluster.sh
- [x] [P1] Infrastructure: Provision k3s Cluster for Phase 4 Migration
  — k3s (2-node: server=192.168.168.31, agent=192.168.168.42); provisioner: `scripts/ops/provision-k3s-cluster.sh`
  — Helm chart: `helm/code-server-enterprise/` (values.phase4-k8s.yaml); copilot-engine service added
  — cert-manager + metrics-server installed for TLS and HPA
  — Run: `DRY_RUN=true ./scripts/ops/provision-k3s-cluster.sh` to validate, then remove DRY_RUN to execute
- [x] [P2] Standardize Documentation using unified link-checker (Tech Debt)
  — unified checker entrypoint: `scripts/ci/check-doc-links.sh`
  — CI: `.github/workflows/documentation-governance.yml` uses unified checker with fail-on-broken-link semantics
