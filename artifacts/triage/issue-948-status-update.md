Status update for #948 (implementation completed):

Terraform drift detection workflow has been migrated off static state keys to OIDC role auth.

Implemented changes in `.github/workflows/terraform-drift-detection.yml`:
- Added workflow permission: `id-token: write`.
- Added OIDC guard step:
  - Validates `TF_STATE_ROLE_ARN` is present (repo variable or secret).
- Added AWS OIDC auth step:
  - `aws-actions/configure-aws-credentials` with `role-to-assume` from `TF_STATE_ROLE_ARN`.
  - Region sourced from `TF_STATE_AWS_REGION` (fallback `us-east-1`).
- Removed static credential injection from Terraform steps:
  - Deleted `AWS_ACCESS_KEY_ID: ${{ secrets.TF_STATE_ACCESS_KEY }}`
  - Deleted `AWS_SECRET_ACCESS_KEY: ${{ secrets.TF_STATE_SECRET_KEY }}`

Validation evidence:
- Workflow diagnostics show OIDC path is present:
  - `id-token: write`
  - `configure-aws-credentials`
  - `TF_STATE_ROLE_ARN` guard
- No remaining `TF_STATE_ACCESS_KEY` / `TF_STATE_SECRET_KEY` references in this workflow.

Conclusion:
- #948 is ready to close.