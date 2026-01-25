# code-server — onboarding + developer guide

## CI Status

- CI Validate: ![CI Validate](https://github.com/kushin77/code-server/actions/workflows/ci-validate.yml/badge.svg?branch=main)
- Security Scans (scheduled): ![Security Scans](https://github.com/kushin77/code-server/actions/workflows/security.yml/badge.svg?branch=main)

## Run CI checks locally

We use `pre-commit`, `tflint` (optional), and `scripts/validate.sh` for validation.

Install dependencies locally and run:

```bash
# Install pre-commit
pip3 install --user pre-commit
pre-commit install

# Run local validation
./scripts/validate.sh
```

To run GitHub Actions locally for debugging, consider using `act`:

```bash
brew install act || true
act -j validate
```

## Security token

Add `SNYK_TOKEN` to repository secrets to enable full scheduled security scans.
