# Security Review Inline Annotations

**Purpose**: Document the editor-side security review workflow that surfaces SAST-style findings as inline VS Code diagnostics.

## Overview

The Ollama Chat extension now includes a security review command that scans the active file for common security smells and renders the findings directly in the editor.

This keeps the workflow lightweight and collaborative:

- findings appear inline in the Problems panel and editor gutter
- the scan is local and deterministic
- the command can be run on demand or refreshed on save
- the chat participant can be used to discuss the findings and suggested fixes

## Command

- `Ollama: Security Review Current File`
- Command id: `ollama.securityReviewCurrentFile`

## What It Flags

Current SAST-style annotations cover:

- `eval()` usage
- `dangerouslySetInnerHTML`
- `innerHTML = ...`
- direct shell execution via `exec()` / `execSync()`
- hardcoded credentials such as passwords, tokens, secrets, and API keys
- insecure `http://` endpoints in security-sensitive integrations

## Operational Flow

1. Open a file in VS Code.
2. Run the security review command.
3. Review inline diagnostics.
4. Fix the code or ask the Ollama chat participant for remediation guidance.
5. Re-run the command or save the file to refresh the annotations.

## Notes

- Diagnostics are kept in a dedicated collection named `ollamaSecurityReview`.
- The scanner is intentionally heuristic-based so it stays fast and works offline.
- This is a review aid, not a substitute for Semgrep, dependency scanning, or PR-level human review.
