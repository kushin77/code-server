# Browser Automation Fallback Policy

Primary engine:
- Playwright drives the deterministic browser suite.

Fallback engine:
- Puppeteer may be used only when Playwright is unavailable or blocked by environment setup.

Rules:
- Keep the Playwright path first and preferred.
- Use the fallback only for local recovery or temporary compatibility gaps.
- Keep both engines pointed at the same deterministic fixture and artifact layout.
