## P2 #1543 Template Library Progress

Implemented:
- Added `.github/ISSUE_TEMPLATE/infrastructure.yml`
- Added `.github/ISSUE_TEMPLATE/security.yml`
- Added `docs/templates/TEMPLATE-GUIDE.md`
- Added `docker-compose.service.yml.tpl`
- Added `terraform/modules/_template/` scaffold (`README.md`, `main.tf`, `variables.tf`, `outputs.tf`)
- Cleaned up `docs/adr/TEMPLATE.md` typos and terminology

CI enforcement:
- Added `scripts/ci/validate-template-library.sh`
- Wired template validation into `.github/workflows/code-smell-governance.yml`

Validation:
- `bash scripts/ci/validate-template-library.sh` passed
- `terraform fmt -check -recursive terraform/modules/_template` passed
