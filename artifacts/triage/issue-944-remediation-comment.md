Remediation complete with evidence.

Implemented:
- Added LF contributor policy guidance in docs/status/CONTRIBUTING.md (LF-only, guard command, renormalize workflow).
- Captured fresh Linux-native guard evidence artifact:
  - artifacts/triage/linux-native-no-windows-content-report.log

Validation:
- Command: bash scripts/ci/check-no-windows-content.sh
- Result: [INFO] No Windows-specific content detected

DoD status:
- [x] scripts/ci/check-no-windows-content.sh passes in clean Linux path
- [x] No CRLF findings in tracked active code/workflow/config files
- [x] LF policy documented in contributor guidance
- [x] Parent #885 updated with closure evidence and linkage (this comment + close note)

Closing as complete.
