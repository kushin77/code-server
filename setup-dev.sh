#!/usr/bin/env bash
set -euo pipefail

echo "Setting up developer environment (minimal checks)"

which python3 >/dev/null 2>&1 || { echo "Please install python3"; exit 1; }
which pip3 >/dev/null 2>&1 || { echo "Please install pip3"; exit 1; }

echo "Installing pre-commit via pip"
# If running inside a Python virtualenv, install into the venv.
if [ -n "${VIRTUAL_ENV-}" ]; then
  pip3 install --upgrade pip setuptools wheel
  pip3 install pre-commit
else
  # For system installs, use --user to avoid requiring sudo.
  pip3 install --user pre-commit
fi

# If pre-commit is already available, skip installation
if command -v pre-commit >/dev/null 2>&1; then
  echo "pre-commit already installed: $(pre-commit --version 2>/dev/null || echo 'version unknown')"
else
  if [ -n "${VIRTUAL_ENV-}" ] || [ "$FORCE_VENV" = "true" ]; then
    python -m pip install --upgrade pip setuptools wheel
    python -m pip install pre-commit
  else
    # For system installs, use --user to avoid requiring sudo.
    pip3 install --user pre-commit
  fi
fi

echo "Installing basic git hooks (idempotent)"
# `pre-commit install` is safe to run multiple times
pre-commit install || true

echo "Check for terraform (optional)"
if which terraform >/dev/null 2>&1; then
  terraform --version
else
  echo "terraform not found — install if you plan to modify IaC"
fi

echo "Setup complete. Run 'pre-commit run --all-files' to verify."
