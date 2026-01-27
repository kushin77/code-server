# code-server — onboarding + developer

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

<!-- ci-test: trigger security scanners -->

## Contributor Notes

I use VS Code and Copilot to develop. I need a solid solution that solves frequent crashing and inconsistency problems. I often have multiple workspaces and chat sessions open (sometimes 8+). This will run on a physical server with a GPU — use GPU where it helps.

Goals / requirements:

- Keep profiles consistent.
- Enable OAuth for secure access; must follow GCP Landing Zone requirements.
- Public DNS: `elevatediq.ai/code-server` behind OAuth and TLS.
