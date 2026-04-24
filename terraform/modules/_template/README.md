# Terraform Module Template

Use this directory as the starting point for a new Terraform module.

## Rules

- Keep inputs explicit and environment-agnostic.
- Merge shared labels/tags instead of redefining them.
- Avoid hidden defaults that depend on local shell state.
- Add outputs only for values that are consumed by another module or deployment step.

## Typical Workflow

1. Copy the `_template` directory to a new module name.
2. Replace `module_name` and the placeholder comments in `main.tf`.
3. Add the module to the root Terraform stack.
4. Run `terraform fmt` and `terraform validate`.
5. Add CI coverage if the module is reused elsewhere.