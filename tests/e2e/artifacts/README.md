# E2E Artifact Standards

Write all run outputs under this directory so they can be collected and compared deterministically.

Expected outputs:
- `e2e-results.json` — machine-readable summary
- `html/` — Playwright HTML report
- `playwright/` — screenshots, traces, and failure captures

Rules:
- Keep artifact paths inside the kit workspace.
- Do not write test outputs to /tmp unless explicitly debugging.
- Treat artifacts as ephemeral unless they are attached to an issue or PR.
