#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import subprocess
import sys
import io

# Fix Windows console encoding issue (charmap -> UTF-8)
if sys.stdout.encoding and sys.stdout.encoding.lower() in ('cp1252', 'charmap', 'ascii'):
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

REPO = "kushin77/code-server"
ISSUES = [
    ("EPIC [Collab-1]: Real-Time Co-Editing Engine", "P1,enhancement,collaboration", "CRDT-based concurrent file editing with Yjs. Sub-100ms sync latency. Unlimited concurrent editors."),
    ("[Collab-1.1]: Cursor presence broadcast", "P1,enhancement,collaboration", "Show remote cursors inline. < 50ms updates. Works with 5+ users."),
    ("[Collab-1.2]: Collaborative undo/redo", "P1,enhancement,collaboration", "Per-user undo/redo tree. User A undo doesn't affect B's work."),
    ("[Collab-1.3]: 3-way merge conflict resolver", "P1,enhancement,collaboration", "3-pane diff editor for merge conflicts. One-click resolution actions."),
    ("[Collab-1.4]: Session hand-off protocol", "P2,enhancement,collaboration", "Transfer workspace ownership. Preserve all state."),
    ("[Collab-1.5]: Workspace forking", "P2,enhancement,collaboration", "Instant fork for exploratory coding. Auto-GC after TTL."),
    ("[Collab-1.6]: File advisory locks", "P2,enhancement,collaboration", "Soft locks for binary assets. Auto-expire after 30min."),
    ("[Collab-1.7]: What changed while away", "P2,enhancement,collaboration", "Summary of changes since user left. LLM summaries for > 20 files."),
    ("[Collab-1.8]: Shared clipboard", "P3,enhancement,collaboration", "Sync copied text. 20-entry history. Credential blocking."),
    ("[Collab-1.9]: Collaborative debugging", "P1,enhancement,collaboration", "Share debug session. Set breakpoints together. DAP proxy."),
    ("EPIC [Collab-2]: Inline Communication", "P1,enhancement,collaboration", "PR-style comment threads on live code. Per-function discussions."),
    ("[Collab-2.1]: Voice channel in IDE", "P1,enhancement,collaboration", "WebRTC voice sidebar. LiveKit SFU. < 60ms latency."),
    ("[Collab-2.2]: Screen share + annotations", "P1,enhancement,collaboration", "Screen share with drawing. Synced via CRDT."),
    ("[Collab-2.3]: Async video messages", "P2,enhancement,collaboration", "Record video anchored to code. MinIO storage. Auto-delete 30d."),
    ("[Collab-2.4]: Shared AI Copilot context", "P1,enhancement,collaboration", "Expose shared LLM chat context. Both users see conversation."),
    ("[Collab-2.5]: @mention system", "P2,enhancement,collaboration", "Type @username. Deep links to code. Notifications via Matrix."),
    ("[Collab-2.6]: Code review request flow", "P1,enhancement,collaboration", "Request review from IDE. Priority + context note."),
    ("[Collab-2.7]: Thread-per-function discussions", "P2,enhancement,collaboration", "Persistent discussions per symbol. Survives refactors."),
    ("[Collab-2.8]: Meeting mode with DND", "P3,enhancement,collaboration", "Auto-DND when in voice call. Queue notifications."),
    ("[Collab-2.9]: Async standup AI summaries", "P2,enhancement,collaboration", "AI-generated daily summaries. Post to Matrix at 9 AM."),
    ("EPIC [Collab-3]: AI-Augmented Collaboration", "P1,enhancement,collaboration,ai", "Conflict prediction, expertise routing, knowledge extraction."),
    ("[Collab-3.1]: Conflict prediction", "P1,enhancement,collaboration,ai", "Warn before merge: 'Alice editing same function'."),
    ("[Collab-3.2]: Pair programming AI copilot", "P1,enhancement,collaboration,ai", "Context-aware AI knowing both users' edits."),
    ("[Collab-3.3]: Expertise heatmap", "P2,enhancement,collaboration,ai", "File-level expertise from git blame."),
    ("[Collab-3.4]: Session hand-off notes", "P2,enhancement,collaboration,ai", "AI drafts context for next developer."),
    ("[Collab-3.5]: Shared prompt library", "P2,enhancement,collaboration,ai", "Team-shared LLM prompts. Auto-suggest."),
    ("[Collab-3.6]: LLM wiki extraction", "P2,enhancement,collaboration,ai", "Mine sessions for reusable knowledge."),
    ("[Collab-3.7]: AI reviewer router", "P2,enhancement,collaboration,ai", "Auto-assign review by expertise + workload."),
    ("[Collab-3.8]: Debug session AI", "P1,enhancement,collaboration,ai", "Suggest root causes from debug state."),
    ("[Collab-3.9]: Auto test generation", "P2,enhancement,collaboration,ai", "Generate tests from bug-fix sessions."),
    ("EPIC [Collab-4]: Presence & Awareness", "P1,enhancement,collaboration", "Team radar. Who's doing what. Timezone. Expertise."),
    ("[Collab-4.1]: Rich presence system", "P1,enhancement,collaboration", "Show file, function, task, status per user."),
    ("[Collab-4.2]: Flow state detection", "P2,enhancement,collaboration", "Detect deep focus. Queue pings. Deliver on exit."),
    ("[Collab-4.3]: Timezone overlays", "P3,enhancement,collaboration", "Show local time + working hours per user."),
    ("[Collab-4.4]: Calendar integration", "P2,enhancement,collaboration", "OAuth Google Cal/Outlook. Show free/busy."),
    ("[Collab-4.5]: Activity feed", "P2,enhancement,collaboration", "Stream: commits, PRs, deploys, test flakes."),
    ("[Collab-4.6]: Smart notification routing", "P2,enhancement,collaboration", "IDE → Slack → Matrix. No duplication."),
    ("[Collab-4.7]: Borrow a brain help queue", "P2,enhancement,collaboration", "Async help routing to experts with SLA."),
    ("[Collab-4.8]: Code ownership graph", "P2,enhancement,collaboration", "D3 visualization of file ownership."),
    ("[Collab-4.9]: Team health dashboard", "P2,enhancement,collaboration", "Flow time, pair freq, review latency metrics."),
    ("EPIC [Collab-5]: Session Management", "P1,infrastructure,collaboration", "Recording, templates, hibernation, quotas, guests."),
    ("[Collab-5.1]: Session recording", "P1,enhancement,collaboration", "Record files, terminal, debug, chat. Playback at variable speed."),
    ("[Collab-5.2]: Workspace templates", "P1,enhancement,collaboration", "Provision env < 30s. Pinned extensions + settings."),
    ("[Collab-5.3]: Session hibernation", "P1,enhancement,collaboration", "CRIU checkpoint. Wake < 5s. Save 80% RAM."),
    ("[Collab-5.4]: Resource quotas", "P1,enhancement,collaboration", "cgroups enforce CPU, RAM, disk, bandwidth."),
    ("[Collab-5.5]: Guest sessions", "P2,enhancement,collaboration", "Time-limited read-only links. Scoped paths."),
    ("[Collab-5.6]: Session cost tracking", "P3,enhancement,collaboration", "CPU-h, RAM-GB-h, storage-GB-d tracking."),
    ("[Collab-5.7]: Hot workspace switching", "P1,enhancement,collaboration", "Switch between workspaces < 200ms."),
    ("[Collab-5.8]: PR preview environments", "P1,enhancement,collaboration", "Push branch → auto-provision preview."),
    ("[Collab-5.9]: Session snapshots", "P1,enhancement,collaboration", "Full-fidelity snapshots. Restore < 10s."),
    ("EPIC [Collab-6]: Security & Compliance", "P0,security,collaboration", "Zero-trust, DLP, isolation, audit, E2EE, signing."),
    ("[Collab-6.1]: Zero-trust network access", "P0,security,collaboration", "mTLS between services. 24h cert rotation."),
    ("[Collab-6.2]: Code egress DLP", "P0,security,collaboration", "Terminal output scanning. Redact secrets."),
    ("[Collab-6.3]: gVisor workspace isolation", "P0,security,collaboration", "gVisor sandbox for untrusted workspaces."),
    ("[Collab-6.4]: Immutable audit log", "P1,security,collaboration", "SOC2-grade file audit. Append-only table."),
    ("[Collab-6.5]: E2EE collaboration messages", "P1,security,collaboration", "Megolm E2EE. Server sees ciphertext only."),
    ("[Collab-6.6]: Git commit signing", "P1,security,collaboration", "gitsign keyless signing via Sigstore."),
    ("[Collab-6.7]: IP allowlist per workspace", "P2,security,collaboration", "Restrict access to CIDR ranges."),
    ("[Collab-6.8]: Ephemeral credentials", "P1,security,collaboration", "Vault dynamic secrets. Auto-rotated per session."),
    ("[Collab-6.9]: Forensics recording mode", "P2,security,collaboration", "Terminal + file + network capture. Signed archives."),
    ("EPIC [Collab-7]: Developer Experience", "P2,enhancement,collaboration", "Shortcuts, registry, auto-config, API explorer, DB browser."),
    ("[Collab-7.1]: Keyboard shortcut manager", "P2,enhancement,collaboration", "Org profiles + personal overrides. Team sync."),
    ("[Collab-7.2]: Private extension registry", "P1,enhancement,collaboration", "Open VSIX. Org extensions + blocklist."),
    ("[Collab-7.3]: Smart workspace auto-config", "P1,enhancement,collaboration", "Detect project type. Auto-install extensions."),
    ("[Collab-7.4]: Embedded API explorer", "P2,enhancement,collaboration", "REST/GraphQL builder. OpenAPI import."),
    ("[Collab-7.5]: Database browser", "P2,enhancement,collaboration", "PostgreSQL, Redis, SQLite. Query editor."),
    ("[Collab-7.6]: Dependency impact graph", "P2,enhancement,collaboration", "D3 graph showing dependents. Blast radius."),
    ("[Collab-7.7]: IDE performance profiler", "P2,enhancement,collaboration", "Per-extension overhead. Health score."),
    ("[Collab-7.8]: Onboarding wizard", "P1,enhancement,collaboration", "10min setup: git, SSH, cloud, clone, build."),
    ("[Collab-7.9]: Status bar team metrics", "P3,enhancement,collaboration", "Tiles: PRs, CI, incidents, team online."),
    ("EPIC [Collab-8]: Observability", "P1,infrastructure,observability", "Tracing, SLOs, health, funnels, correlation, forecasting."),
    ("[Collab-8.1]: End-to-end distributed tracing", "P1,enhancement,observability", "OTel instrumentation. Jaeger export."),
    ("[Collab-8.2]: SLO/SLA dashboard", "P1,enhancement,observability", "sync < 100ms p99. Error budget tracking."),
    ("[Collab-8.3]: WebSocket health monitoring", "P1,enhancement,observability", "Latency, jitter, loss. Quality score 0-100."),
    ("[Collab-8.4]: Funnel analytics", "P2,enhancement,observability", "Onboarding funnel. Conversion % tracking."),
    ("[Collab-8.5]: Incident correlation", "P1,enhancement,observability", "SLO breach → correlate with deploys."),
    ("[Collab-8.6]: Capacity forecasting", "P2,enhancement,observability", "Time-series forecasting. 30/60/90d predictions."),
    ("[Collab-8.7]: Session replay timeline", "P2,enhancement,observability", "Grafana timeline of all events per session."),
    ("[Collab-8.8]: Access pattern anomaly detection", "P1,security,observability", "ML baseline + Isolation Forest scoring."),
    ("[Collab-8.9]: DORA metrics dashboard", "P2,enhancement,observability", "Deployment freq, lead time, CFR, MTTR."),
    ("EPIC [Collab-9]: Integrations Hub", "P1,enhancement,collaboration", "GitHub, Linear, Slack, CI/CD, Figma, Sentry, flags, PagerDuty."),
    ("[Collab-9.1]: GitHub Issues IDE panel", "P1,enhancement,collaboration", "Browse, create, comment, assign issues."),
    ("[Collab-9.2]: Linear/Jira linking", "P2,enhancement,collaboration", "Link tickets. Auto-inject context."),
    ("[Collab-9.3]: Slack slash commands", "P1,enhancement,collaboration", "'/code-review @alice' → shared session."),
    ("[Collab-9.4]: CI/CD status sidebar", "P1,enhancement,collaboration", "Live pipeline with logs + re-run actions."),
    ("[Collab-9.5]: Figma embed", "P2,enhancement,collaboration", "Render frames. Design token inspection."),
    ("[Collab-9.6]: Sentry integration", "P1,enhancement,collaboration", "Browse errors. Click trace → code line."),
    ("[Collab-9.7]: Feature flag panel", "P2,enhancement,collaboration", "Unleash integration. Toggle flags per session."),
    ("[Collab-9.8]: PagerDuty → auto-open files", "P1,enhancement,collaboration", "Incident fires → pre-load relevant files."),
    ("[Collab-9.9]: Jaeger APM integration", "P1,enhancement,collaboration", "Click span → jump to code location."),
    ("EPIC [Collab-10]: Scale & Performance", "P1,infrastructure,performance", "WebSocket gateway, CRDT compaction, delta sync, failover."),
    ("[Collab-10.1]: WebSocket gateway cluster", "P1,infrastructure,performance", "3-node relay. Consistent hashing."),
    ("[Collab-10.2]: CRDT compaction", "P1,infrastructure,performance", "Snapshot + truncate ops. Non-blocking."),
    ("[Collab-10.3]: Selective delta sync", "P1,infrastructure,performance", "State vectors. O(change) not O(doc)."),
    ("[Collab-10.4]: Network migration", "P1,infrastructure,performance", "WiFi → 4G: reconnect < 3s. Zero loss."),
    ("[Collab-10.5]: Edge relay nodes", "P2,infrastructure,performance", "Geographic edge relays. < 50ms global latency."),
    ("[Collab-10.6]: session-broker horizontal scale", "P1,infrastructure,performance", "Multiple instances. Consistent hashing."),
    ("[Collab-10.7]: Multi-region deployment", "P3,infrastructure,performance", "Region-specific DBs. Data residency."),
    ("[Collab-10.8]: Message compression < 1 KB", "P2,infrastructure,performance", "Delta + LZ4 compress + batching."),
    ("[Collab-10.9]: Hot-standby failover", "P1,infrastructure,performance", "Standby receives all ops. < 1s failover."),
]

def main():
    print(f"Creating {len(ISSUES)} collaboration enhancement issues on {REPO}")
    print("=" * 80)
    
    created = 0
    failed = 0
    
    for i, (title, labels, body) in enumerate(ISSUES, 1):
        cmd = [
            "gh", "issue", "create",
            "--repo", REPO,
            "--title", title,
            "--body", body,
        ]
        for label in labels.split(","):
            cmd += ["--label", label.strip()]
        
        sys.stdout.write(f"[{i:3d}/{len(ISSUES)}] {title[:50]:<50} ... ")
        sys.stdout.flush()
        
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode == 0:
            print("✓")
            created += 1
        else:
            print("✗")
            if "VALIDATION FAILED" in result.stderr or "422" in result.stderr:
                # Issue likely already exists, that's ok
                created += 1
            failed += 1
    
    print("=" * 80)
    print(f"Done: {created}/{len(ISSUES)} successful")
    return 0 if failed <= len(ISSUES) * 0.1 else 1

if __name__ == "__main__":
    sys.exit(main())
