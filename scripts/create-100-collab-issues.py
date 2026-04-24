#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Create 100 collaboration platform enhancement issues on GitHub using REST API."""
import json
import urllib.request
import urllib.error
import sys
import io

# Fix Windows console encoding issue (charmap -> UTF-8)
if sys.stdout.encoding and sys.stdout.encoding.lower() in ('cp1252', 'charmap', 'ascii'):
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
import os
import sys
import time

# Configuration
REPO_OWNER = "kushin77"
REPO_NAME = "code-server"
GITHUB_TOKEN = os.getenv("GITHUB_TOKEN")  # Must be set as env var
API_URL = "https://api.github.com"

# All 100 issues
ISSUES = [
    ("EPIC [Collab-1]: Real-Time Co-Editing Engine", "P1,enhancement,collaboration", "Implement CRDT-based concurrent file editing with sub-100ms sync latency using Yjs library. Support unlimited concurrent editors with automatic conflict resolution."),
    ("[Collab-1.1]: Cursor presence broadcast", "P1,enhancement,collaboration", "Show remote user cursors inline with names and colors. Updates < 50ms. Works with 5+ concurrent users."),
    ("[Collab-1.2]: Collaborative undo/redo", "P1,enhancement,collaboration", "Branching undo/redo tree where each user can undo only their own changes. Preserve other users' work."),
    ("[Collab-1.3]: 3-way merge conflict resolver", "P1,enhancement,collaboration", "Interactive 3-way diff editor for merge conflicts with one-click resolution actions and audit logging."),
    ("[Collab-1.4]: Session hand-off protocol", "P2,enhancement,collaboration", "Transfer live workspace ownership to another user. Preserve all state: files, terminals, debug sessions."),
    ("[Collab-1.5]: Workspace forking", "P2,enhancement,collaboration", "Instantly fork workspace for exploratory coding. Copy files, git HEAD, env. Garbage-collect after TTL."),
    ("[Collab-1.6]: File advisory locks", "P2,enhancement,collaboration", "Soft locking for binary assets. Checkout/release UX. Auto-expire after 30 min inactivity."),
    ("[Collab-1.7]: 'What changed while away' summary", "P2,enhancement,collaboration", "Show contexual summary of file changes since user last visited. LLM summarization for > 20 files."),
    ("[Collab-1.8]: Shared clipboard", "P3,enhancement,collaboration", "Sync copied text across all session participants. 20-entry history. Credential blocking."),
    ("[Collab-1.9]: Collaborative debugging", "P1,enhancement,collaboration", "Share debug session: set breakpoints, inspect vars, step through code together. DAP proxy relay."),
    
    ("EPIC [Collab-2]: Inline Communication", "P1,enhancement,collaboration", "GitHub PR-style comment threads on live source code. Thread per function. Persistent across refactors."),
    ("[Collab-2.1]: Voice channel in IDE", "P1,enhancement,collaboration", "WebRTC voice in sidebar panel. LiveKit SFU backend. < 60ms latency. Noise cancellation."),
    ("[Collab-2.2]: Screen share + annotations", "P1,enhancement,collaboration", "Share screen with drawing/pointer annotations. Synced via CRDT. Presenter sees audience cursors."),
    ("[Collab-2.3]: Async video messages", "P2,enhancement,collaboration", "Record ≤5min video anchored to code location. Auto-delete after 30d. MinIO storage."),
    ("[Collab-2.4]: Shared AI Copilot context", "P1,enhancement,collaboration", "Expose shared LLM chat context. Both users see same conversation thread. Per-turn author tags."),
    ("[Collab-2.5]: @mention system", "P2,enhancement,collaboration", "Type @username in comments. Deep links to code location. Notifications via Matrix. Digest emails."),
    ("[Collab-2.6]: Code review request flow", "P1,enhancement,collaboration", "Request review from IDE without GitHub tab. Priority, context note. Reviewer gets badge + notification."),
    ("[Collab-2.7]: Thread-per-function discussions", "P2,enhancement,collaboration", "Persistent discussion thread per symbol. Survives refactors via FQN tracking. Full-text searchable."),
    ("[Collab-2.8]: Meeting mode with DND", "P3,enhancement,collaboration", "Auto-detect voice room join → pause notifications. Show 📞 indicator. Queue non-urgent alerts."),
    ("[Collab-2.9]: Async standup AI summaries", "P2,enhancement,collaboration", "Auto-generate daily summaries from commits/reviews. Post to Matrix at 9 AM. User approval window."),
    
    ("EPIC [Collab-3]: AI-Augmented Collab", "P1,enhancement,collaboration,ai", "ML-powered conflict prediction, expertise routing, session knowledge extraction into wiki."),
    ("[Collab-3.1]: Conflict prediction", "P1,enhancement,collaboration,ai", "Warn before merge: 'Alice editing same function - save soon'. Risk score 0-100."),
    ("[Collab-3.2]: Pair programming AI copilot", "P1,enhancement,collaboration,ai", "Context-aware AI knowing both users' edits. Shared context injection. Dedup suggestions."),
    ("[Collab-3.3]: Expertise heatmap", "P2,enhancement,collaboration,ai", "File/function-level expertise from git blame. 'Alex (72%), Bob (18%)'. One-click find expert."),
    ("[Collab-3.4]: Session hand-off notes", "P2,enhancement,collaboration,ai", "AI drafts context for next developer on session end. Done/in-progress/blocked/next. Post to issue."),
    ("[Collab-3.5]: Shared prompt library", "P2,enhancement,collaboration,ai", "Team-shared LLM prompts versioned in DB. Auto-suggest by context. Usage counts + ratings."),
    ("[Collab-3.6]: LLM wiki extraction", "P2,enhancement,collaboration,ai", "Mine sessions for reusable knowledge. Embed with nomic, semantic search in pgvector."),
    ("[Collab-3.7]: AI reviewer router", "P2,enhancement,collaboration,ai", "Auto-assign review based on expertise + workload + timezone. Score explanation shown."),
    ("[Collab-3.8]: Debug session AI", "P1,enhancement,collaboration,ai", "Observe breakpoints/vars. Suggest root causes, fix approaches, relevant docs."),
    ("[Collab-3.9]: Auto test generation", "P2,enhancement,collaboration,ai", "After bug-fix session, AI generates Jest tests. Review in diff before commit."),
    
    ("EPIC [Collab-4]: Presence & Awareness", "P1,enhancement,collaboration", "Real-time team radar: who editing what, timezone, availability, expertise heatmap."),
    ("[Collab-4.1]: Rich presence system", "P1,enhancement,collaboration", "Show file, function, task, custom status per user. Redis persistence 4h TTL."),
    ("[Collab-4.2]: Flow state detection", "P2,enhancement,collaboration", "Auto-detect deep focus (40+ WPM, no switch, 5+ min). Queue pings. Deliver on exit."),
    ("[Collab-4.3]: Timezone overlays", "P3,enhancement,collaboration", "Show local time + working hours. Async warning: 'Its 11 PM for Bob'. Best-overlap meeting slot finder."),
    ("[Collab-4.4]: Calendar integration", "P2,enhancement,collaboration", "OAuth2 Google Cal/Outlook. Show free/busy. 'In meeting until 3 PM' on presence card."),
    ("[Collab-4.5]: Activity feed", "P2,enhancement,collaboration", "Live stream: commits, PRs, deploys, test flakes. Filterable. Deep links. 7d history."),
    ("[Collab-4.6]: Smart notification routing", "P2,enhancement,collaboration", "IDE (if online) → Slack (if away) → Matrix (if in meeting, queue). No duplication. User routes."),
    ("[Collab-4.7]: 'Borrow a brain' help queue", "P2,enhancement,collaboration", "Async help: flag code + question. AI enriches. Route to expert. SLA tracking (2h urgent, 1d normal)."),
    ("[Collab-4.8]: Code ownership graph", "P2,enhancement,collaboration", "D3 visualization of file ownership. Highlight bus-factor-1 files. Contributor heatmap."),
    ("[Collab-4.9]: Team health dashboard", "P2,enhancement,collaboration", "Flow time, pair freq, review latency, AI utilization, collab index. Weekly digest."),
    
    ("EPIC [Collab-5]: Session Management", "P1,infrastructure,collaboration", "Recording, templates, hibernation, quotas, guest access, preview envs, snapshots."),
    ("[Collab-5.1]: Session recording", "P1,enhancement,collaboration", "Record: files, terminal, debug, chat. Playback at 0.5-10x. Export to video. Share via URL. 90d auto-delete."),
    ("[Collab-5.2]: Workspace templates", "P1,enhancement,collaboration", "Provision complete env < 30s. Pinned extensions, settings, devcontainer, env schema. Git-managed."),
    ("[Collab-5.3]: Session hibernation", "P1,enhancement,collaboration", "CRIU checkpoint idle workspaces. Wake < 5s. Save 80% RAM. Preserve files, terminals, debug state."),
    ("[Collab-5.4]: Resource quotas", "P1,enhancement,collaboration", "cgroups enforce: CPU, RAM, disk I/O, bandwidth. Quota tiers: Small/Med/Large. Real-time usage display."),
    ("[Collab-5.5]: Guest sessions", "P2,enhancement,collaboration", "Time-limited read-only links. Scoped paths. Auto-expire. Audit activity. No account needed."),
    ("[Collab-5.6]: Session cost tracking", "P3,enhancement,collaboration", "CPU-h, RAM-GB-h, storage-GB-d, GPU-h tracking. Monthly report per user/project. Budget alerts."),
    ("[Collab-5.7]: Hot workspace switching", "P1,enhancement,collaboration", "Switch between active workspaces < 200ms. State preserved via IndexedDB. 5 max concurrent."),
    ("[Collab-5.8]: PR preview environments", "P1,enhancement,collaboration", "Push branch → auto-provision preview (frontend+backend+DB). Destroy on merge/close + 1h grace."),
    ("[Collab-5.9]: Session snapshots", "P1,enhancement,collaboration", "Full-fidelity snapshots: files, layout, terminals, debug, extensions. Restore in < 10s. 10-version history."),
    
    ("EPIC [Collab-6]: Security & Compliance", "P0,security,collaboration", "Zero-trust, DLP, isolation, audit, E2EE, commit signing, IP allowlist, ephemeral creds."),
    ("[Collab-6.1]: Zero-trust network access", "P0,security,collaboration", "mTLS between all services. 24h cert rotation. Iptables egress policy. Connection audit logs."),
    ("[Collab-6.2]: Code egress DLP", "P0,security,collaboration", "Real-time terminal output scanning. Regex + NLP PII detection. Redact AWS keys, SSN, CC#. Alert on match."),
    ("[Collab-6.3]: gVisor workspace isolation", "P0,security,collaboration", "Untrusted workspaces run in gVisor sandbox. Immune to runc escapes (CVE-2019-5736). < 15% overhead."),
    ("[Collab-6.4]: Immutable audit log", "P1,security,collaboration", "SOC2-grade: every file r/w/delete captured. Append-only table. 2yr retention. Hash chain tamper detection."),
    ("[Collab-6.5]: E2EE collaboration messages", "P1,security,collaboration", "Megolm E2EE via Matrix SDK. Server sees ciphertext only. Forward secrecy. Key backup in Vault."),
    ("[Collab-6.6]: Git commit signing", "P1,security,collaboration", "gitsign (keyless via Sigstore). 24h cert TTL. CI rejects unsigned on main. Public transparency log."),
    ("[Collab-6.7]: IP allowlist per workspace", "P2,security,collaboration", "Restrict access to CIDR ranges. 403 on violation. Admin override. Audit logged."),
    ("[Collab-6.8]: Ephemeral credentials", "P1,security,collaboration", "Vault dynamic secrets: DB, cloud tokens. Auto-rotated per session. Revoked on session end."),
    ("[Collab-6.9]: Forensics recording mode", "P2,security,collaboration", "Compliance mode: terminal I/O + file ops + network tcpdump. Signed archives. 1yr retention."),
    
    ("EPIC [Collab-7]: Developer Experience", "P2,enhancement,collaboration", "Keyboard manager, extension registry, auto-config, API explorer, DB browser, profiler."),
    ("[Collab-7.1]: Keyboard shortcut manager", "P2,enhancement,collaboration", "Org-default profiles + personal overrides. Clash detection. Team sync. Quick-switch command."),
    ("[Collab-7.2]: Private extension registry", "P1,enhancement,collaboration", "Open VSIX backend. Org extensions, blocklist, version pinning. CI publishing. < 30s install."),
    ("[Collab-7.3]: Smart workspace auto-config", "P1,enhancement,collaboration", "Detect project type (pkg.json, go.mod, etc). Auto-install extensions, configure debugger, linters."),
    ("[Collab-7.4]: Embedded API explorer", "P2,enhancement,collaboration", "REST/GraphQL builder in IDE. OpenAPI import. Env var injection. Response diff. Shared history."),
    ("[Collab-7.5]: Database browser", "P2,enhancement,collaboration", "PostgreSQL, Redis, SQLite support. Schema browser, query editor, auto-complete. Result export CSV/JSON."),
    ("[Collab-7.6]: Dependency impact graph", "P2,enhancement,collaboration", "D3 force graph: show dependents of any module. Blast radius score. Circular dep detection."),
    ("[Collab-7.7]: IDE performance profiler", "P2,enhancement,collaboration", "Per-extension overhead: startup, activation, latency. Health score. Disable slow extensions."),
    ("[Collab-7.8]: Onboarding wizard", "P1,enhancement,collaboration", "10min setup: git, SSH, cloud login, clone, build, verify. Steps auto-runnable with manual fallback."),
    ("[Collab-7.9]: Status bar team metrics", "P3,enhancement,collaboration", "Tiles: open PRs for me, CI status for branch, active incidents, team online count. Clickable deep links."),
    
    ("EPIC [Collab-8]: Observability", "P1,infrastructure,observability", "Distributed tracing, SLOs, health monitoring, funnel analytics, incident correlation, forecasting."),
    ("[Collab-8.1]: End-to-end distributed tracing", "P1,enhancement,observability", "OTel instrumentation of all collab events. Jaeger export. p99 latency queryable per event type."),
    ("[Collab-8.2]: SLO/SLA dashboard", "P1,enhancement,observability", "Define: sync < 100ms p99, presence < 500ms p99. Error budget burn tracking. 30d trend."),
    ("[Collab-8.3]: WebSocket health monitoring", "P1,enhancement,observability", "Per-connection: latency, jitter, packet loss. Quality score 0-100. Auto-reconnect with backoff."),
    ("[Collab-8.4]: Funnel analytics", "P2,enhancement,observability", "Onboarding funnel: invite → link → account → session join → edit → 7d streak. Conversion % tracking."),
    ("[Collab-8.5]: Incident correlation", "P1,enhancement,observability", "SLO breach → auto-correlate with deploys, config changes, restarts. Timeline in incident summary."),
    ("[Collab-8.6]: Capacity forecasting", "P2,enhancement,observability", "Time-series regression on: sessions/day, CPU, memory. Forecast 30/60/90d. Alert before breach."),
    ("[Collab-8.7]: Session replay timeline", "P2,enhancement,observability", "Grafana: all events for historical session. Deployments overlaid. Click event → full JSON."),
    ("[Collab-8.8]: Access pattern anomaly detection", "P1,security,observability", "ML baseline: login time, files accessed, session duration. Isolation Forest scoring. Alert on drift."),
    ("[Collab-8.9]: DORA metrics dashboard", "P2,enhancement,observability", "Deployment freq, lead time, change failure %, MTTR. 12w trend. Elite/High/Med/Low tier benchmark."),
    
    ("EPIC [Collab-9]: Integrations", "P1,enhancement,collaboration", "GitHub Issues, Linear/Jira, Slack, CI/CD, Figma, Sentry, feature flags, PagerDuty, Jaeger APM."),
    ("[Collab-9.1]: GitHub Issues ↔ IDE panel", "P1,enhancement,collaboration", "Browse, filter, create, comment, assign. Link to session → auto-comment on close. No static PAT (OIDC)."),
    ("[Collab-9.2]: Linear/Jira linking", "P2,enhancement,collaboration", "Search + link tickets. Auto-inject context (AC, linked PRs) into Copilot. Auto-branch naming."),
    ("[Collab-9.3]: Slack slash commands", "P1,enhancement,collaboration", "'/code-review @alice src/auth.ts' → shared session. Post link to channel with context + expiry."),
    ("[Collab-9.4]: CI/CD status sidebar", "P1,enhancement,collaboration", "Live pipeline: job status, logs, test results. DAG visualization. Tail logs in IDE. Re-run jobs."),
    ("[Collab-9.5]: Figma embed", "P2,enhancement,collaboration", "Render frames in WebView. Design token inspector vs CSS vars. Comment sync Figma ↔ IDE."),
    ("[Collab-9.6]: Sentry integration", "P1,enhancement,collaboration", "Browse errors. Click stack frame → jump to line with blame. 'Fix with AI' action for diagnosis."),
    ("[Collab-9.7]: Feature flag panel", "P2,enhancement,collaboration", "Unleash integration. Toggle flags for session. Code lens: flag annotations. Flag history."),
    ("[Collab-9.8]: PagerDuty → auto-open files", "P1,enhancement,collaboration", "Incident fires → workspace pre-loads relevant files (from recent deploys + stacks). Auto-notify on-call."),
    ("[Collab-9.9]: Jaeger APM integration", "P1,enhancement,collaboration", "Click slow span in trace → jump to code. Semantic conventions: code.function, code.filepath."),
    
    ("EPIC [Collab-10]: Scale & Performance", "P1,infrastructure,performance", "WebSocket gateway 10k sessions, CRDT compaction, delta sync, network migration, edge relays."),
    ("[Collab-10.1]: WebSocket gateway cluster", "P1,infrastructure,performance", "3-node relay behind HAProxy. Consistent hash routing (session_id). Redis Pub/Sub fan-out. k6 test 1k pairs."),
    ("[Collab-10.2]: CRDT compaction", "P1,infrastructure,performance", "Snapshot + truncate ops when log > 10MB or age > 7d. Non-blocking. New clients get snapshot + incremental."),
    ("[Collab-10.3]: Selective delta sync", "P1,infrastructure,performance", "State vector exchange. Send only missing ops (O(change) not O(doc)). LZ4 compress. < 100 bytes per 1-char edit."),
    ("[Collab-10.4]: Network migration", "P1,infrastructure,performance", "WiFi → 4G: buffer ops, reconnect < 3s, zero loss. Session token stable across IP changes."),
    ("[Collab-10.5]: Edge relay nodes", "P2,infrastructure,performance", "Lightweight relays at geographic edges. GeoDNS routing. < 50ms global latency. Stateless forward to primary."),
    ("[Collab-10.6]: session-broker horizontal scale", "P1,infrastructure,performance", "Multiple instances, consistent hashing, Redis-backed state. k6 test: 3 instances balanced load."),
    ("[Collab-10.7]: Multi-region deployment", "P3,infrastructure,performance", "Region-specific databases. Data residency enforcement. Cross-region access blocked. GDPR compliance."),
    ("[Collab-10.8]: Message compression < 1 KB", "P2,infrastructure,performance", "Delta encoding (cursor), LZ4 compress (ops), message batching (5ms). Typing op < 100 bytes."),
    ("[Collab-10.9]: Hot-standby failover", "P1,infrastructure,performance", "Standby receives all ops, < 1s failover. Zero loss (checksum verified). Auto-reconnect within 2s."),
]

def create_issue(owner, repo, title, labels_str, body):
    """Create a GitHub issue via REST API."""
    url = f"{API_URL}/repos/{owner}/{repo}/issues"
    labels = [l.strip() for l in labels_str.split(",")]
    
    payload = {
        "title": title,
        "body": body,
        "labels": labels,
    }
    
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode('utf-8'),
        headers={
            "Authorization": f"token {GITHUB_TOKEN}",
            "Accept": "application/vnd.github.v3+json",
            "Content-Type": "application/json",
        },
        method="POST"
    )
    
    try:
        with urllib.request.urlopen(req) as response:
            result = json.loads(response.read().decode('utf-8'))
            return result.get("html_url"), None
    except urllib.error.HTTPError as e:
        error_body = e.read().decode('utf-8')
        return None, error_body

def main():
    if not GITHUB_TOKEN:
        print("ERROR: GITHUB_TOKEN environment variable not set")
        print("Set it with: export GITHUB_TOKEN=<your-github-pat>")
        sys.exit(1)
    
    print(f"Creating {len(ISSUES)} collaboration enhancement issues")
    print("=" * 80)
    
    created = 0
    failed = 0
    
    for i, (title, labels, body) in enumerate(ISSUES, 1):
        sys.stdout.write(f"[{i:3d}/{len(ISSUES)}] Creating: {title[:60]:<60} ... ")
        sys.stdout.flush()
        
        url, error = create_issue(REPO_OWNER, REPO_NAME, title, labels, body)
        
        if url:
            print(f"✓ {url}")
            created += 1
        else:
            print(f"✗ FAILED")
            if error:
                print(f"         {error[:100]}")
            failed += 1
        
        time.sleep(0.5)  # Rate limit: GitHub allows 5000 requests/hour
    
    print("=" * 80)
    print(f"Done: {created} created, {failed} failed out of {len(ISSUES)} total")
    
    if failed == 0:
        print("✓ All issues created successfully!")
        return 0
    else:
        print(f"✗ {failed} issues failed to create")
        return 1

if __name__ == "__main__":
    sys.exit(main())
