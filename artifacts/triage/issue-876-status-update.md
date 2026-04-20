Status update for #876 (Cloudflare Access + WARP zero-trust):

I added and ran a repeatable verifier for admin endpoint exposure:
- Script: `scripts/ci/verify-cloudflare-admin-access.sh`
- Report: `artifacts/triage/cloudflare-admin-access-verify.md`

Latest live probe summary (unauthenticated):
- `/grafana/` -> `302` redirect to oauth2 start
- `/prometheus/` -> `302` redirect to oauth2 start
- `/alertmanager/` -> `302` redirect to oauth2 start
- `/jaeger/` -> `302` redirect to oauth2 start

Interpretation:
- Positive: admin routes are not publicly open (`200`) and are blocked/challenged.
- Important caveat: redirects currently classify as `oauth2_proxy`, not explicit Cloudflare Access challenge (`/cdn-cgi/access`).

Current closure status:
- Keep #876 OPEN.
- This update narrows what remains:
  1. Verify/admin routes enforced specifically by Cloudflare Access policy (not only oauth2-proxy redirects)
  2. Verify WARP device posture enforcement for admin access
  3. Verify Cloudflare Access audit log enablement/retention
  4. Verify CI/CD service-token usage and TTL controls

This keeps evidence concrete and avoids claiming Cloudflare Access completion before edge-policy proof is captured.