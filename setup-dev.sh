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

echo "Installing basic git hooks"
pre-commit install || true

echo "Check for terraform (optional)"
if which terraform >/dev/null 2>&1; then
  terraform --version
else
  echo "terraform not found — install if you plan to modify IaC"
fi

echo "Setup complete. Run 'pre-commit run --all-files' to verify."
