# ACTIVE-ACTIVE-IDE-LOAD-BALANCING-734

Purpose:
- Capture the current canonical design constraints and implementation path for issue #734: active-active load balancing for `ide.kushnir.cloud` across `.31` and `.42`.

Issue:
- #734 P1: Design active-active load balancing for code-server IDE traffic across `.31` and `.42`

Context:
- The current production posture is VRRP failover: `.31` is MASTER for VIP `192.168.168.30` and `.42` is BACKUP.
- The new requirement is different: both nodes should participate in normal IDE traffic handling so the system scales for many concurrent code-server users.
- Prior repo artifacts referenced a `95/5` active-active routing policy, but the canonical design doc was lost and the surviving root file became a bridge stub.

Non-Negotiable Constraints:
- Code-server traffic is websocket-heavy and not safely treated as generic stateless HTTP.
- User sessions must remain sticky to a chosen backend for the lifetime of the session, except during explicit drain/failover events.
- Shared workspace/profile state must be safe for concurrent multi-user operation across `.31` and `.42`.
- OAuth ingress must be valid in multi-backend mode; top-level HTTPS reachability alone is not enough.
- One node must be drainable without destructive session loss for unaffected users.

Current Findings:
- `docs/adr/001-containerized-deployment.md` previously claimed code-server scaling was stateless and required no session affinity. That assumption is not valid for the IDE workload.
- `docs/adr/002-oauth2-authentication.md` already notes repeated requests to the same proxy instance are preferred and that shared session backend is required for distributed scenarios.
- `config/haproxy.cfg` already contains sticky-session mechanics, but it is based on `JSESSIONID`, which is not a proven fit for current oauth2-proxy/code-server traffic.
- The April 18 failover drill proved VIP cutover and user-path reachability, but it did not yet prove authenticated editor continuity or balanced multi-user throughput.

Recommended Target Topology:
- Keep VRRP/VIP for fast ownership and node-level failover.
- Introduce active-active request distribution at the IDE ingress layer, not at random backend selection for every request.
- Route authenticated IDE sessions to a selected backend using explicit session affinity.
- Prefer weighted balancing aligned to current operational target:
  - Current target: `50/50` IDE traffic split (`.31`/`.42`).
  - Future tuning: adjust by observed load/error budget as needed.
- Keep portal/API traffic policies separate from IDE traffic because they do not have the same websocket/session profile.

Implementation Slices:
1. Canonical ingress model
- Decision: use HAProxy as the active-active traffic control point for IDE routing policy.
- Sticky routing is enforced in `config/haproxy.cfg` backend `code_server_backend`.
- Caddy remains TLS edge and host routing layer; HAProxy owns weighted distribution and affinity policy.

2. Session affinity contract
- Choose the stable affinity key.
- Candidate sources: oauth2-proxy session cookie, dedicated LB cookie, or header-based affinity from trusted auth edge.
- Reject per-request round robin for IDE/editor traffic.

3. Backend readiness contract
- Replica promotion and balanced routing require healthy `code-server`, `oauth2-proxy`, and ingress state.
- Health checks must reflect real readiness for user traffic, not only container liveness.

4. Drain and maintenance controls
- Add a documented drain mode so a node can stop receiving new IDE sessions while existing ones complete or reconnect safely.
- Integrate drain behavior with failover and deployment workflows.

5. Validation
- Blackbox monitoring: issue #731.
- Replica auth readiness: issue #732.
- Browser/session continuity validation: issue #733.
- Load and concurrency test for balanced IDE traffic: still needed under #734.

Exit Criteria for #734:
- `ide.kushnir.cloud` distributes IDE sessions across `.31` and `.42` during normal operation.
- Session affinity is explicit and validated.
- Auth and websocket behavior remain stable under load-balanced routing.
- One node can be drained or lost without collapsing the IDE service.
- Evidence includes balanced traffic, session continuity, and rollback/drain procedures.

Current Implementation Baseline (April 18, 2026):
- `config/haproxy.cfg` now encodes stage-1 active-active behavior for IDE traffic:
  - weighted split `50/50` (`primary`/`replica`)
  - sticky affinity on oauth2-proxy IDE session cookie `_oauth2_proxy_ide`
  - fallback LB cookie `IDE_NODE` for pre-auth requests
  - backend health checks on `/ping` for oauth2-proxy readiness
  - long-lived tunnel/client/server timeouts for websocket-heavy editor traffic
  - response header `X-LB-Backend` for drill observability

Related Issues:
- #710 epic
- #729 replica ingress ownership and promotion correctness
- #731 blackbox failover path monitoring
- #732 replica oauth2-proxy readiness on `.42`
- #733 Playwright-based authenticated session continuity