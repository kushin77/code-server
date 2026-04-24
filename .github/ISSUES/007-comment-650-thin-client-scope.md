Proposed update for `#650`:

The current epic covers org-wide auth and policy baseline well, but it is still missing one architectural requirement that needs to be explicit before implementation continues: code-server should be treated as a thin client and enforcement surface, while the admin portal remains the global control plane for user identity, entitlement, session lifecycle, and workspace policy.

Why this needs to live under `#650`:
- It turns the auth/policy baseline into a platform contract instead of a collection of local hardening tasks.
- It prevents repo-local or instance-local access logic from reappearing inside code-server.
- It aligns the current epic with the earlier portal split in `#385` and the identity foundation in `#388`.

Proposed child issue:
- `Treat code-server as a thin client with admin-portal-managed identity, session, and policy control`

Suggested additions to `#650` scope:
- Admin portal is the system of record for human identity, entitlements, and session state.
- Code-server consumes signed portal-issued identity/policy assertions.
- Global session revocation and user suspension propagate into active IDE sessions.
- Workspace policy, repository access, and tool/extension allowlists are enforced centrally across all repos.
- Audit correlation links portal decisions to code-server enforcement and user session effects.

This should remain a child of `#650`, not a separate epic, because it depends on the same baseline work but adds the missing control-plane boundary.