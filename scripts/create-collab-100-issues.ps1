# ⚠️  GOVERNANCE NOTE (Rule 10 - Linux-Native Only)
# This is a Windows PowerShell script. The repository runs EXCLUSIVELY on Linux.
# This script should be converted to bash or removed in future refactoring.
# For now, it's kept as a Windows development utility only.
# NOT PART OF PRODUCTION INFRASTRUCTURE - Use only for local Windows dev environment
#

$REPO = "kushin77/code-server"

$ISSUES = @(
    @{ title = "EPIC [Collab-1]: Real-Time Co-Editing Engine"; labels = "P1,enhancement,collaboration"; body = "CRDT-based concurrent file editing with Yjs. Sub-100ms sync latency. Unlimited concurrent editors." },
    @{ title = "[Collab-1.1]: Cursor presence broadcast"; labels = "P1,enhancement,collaboration"; body = "Show remote cursors inline. < 50ms updates. Works with 5+ users." },
    @{ title = "[Collab-1.2]: Collaborative undo/redo"; labels = "P1,enhancement,collaboration"; body = "Per-user undo/redo tree. User A undo doesn't affect B's work." },
    @{ title = "[Collab-1.3]: 3-way merge conflict resolver"; labels = "P1,enhancement,collaboration"; body = "3-pane diff editor for merge conflicts. One-click resolution actions." },
    @{ title = "[Collab-1.4]: Session hand-off protocol"; labels = "P2,enhancement,collaboration"; body = "Transfer workspace ownership. Preserve all state." },
    @{ title = "[Collab-1.5]: Workspace forking"; labels = "P2,enhancement,collaboration"; body = "Instant fork for exploratory coding. Auto-GC after TTL." },
    @{ title = "[Collab-1.6]: File advisory locks"; labels = "P2,enhancement,collaboration"; body = "Soft locks for binary assets. Auto-expire after 30min." },
    @{ title = "[Collab-1.7]: What changed while away"; labels = "P2,enhancement,collaboration"; body = "Summary of changes since user left. LLM summaries for > 20 files." },
    @{ title = "[Collab-1.8]: Shared clipboard"; labels = "P3,enhancement,collaboration"; body = "Sync copied text. 20-entry history. Credential blocking." },
    @{ title = "[Collab-1.9]: Collaborative debugging"; labels = "P1,enhancement,collaboration"; body = "Share debug session. Set breakpoints together. DAP proxy." },
    @{ title = "EPIC [Collab-2]: Inline Communication"; labels = "P1,enhancement,collaboration"; body = "PR-style comment threads on live code. Per-function discussions." },
    @{ title = "[Collab-2.1]: Voice channel in IDE"; labels = "P1,enhancement,collaboration"; body = "WebRTC voice sidebar. LiveKit SFU. < 60ms latency." },
    @{ title = "[Collab-2.2]: Screen share + annotations"; labels = "P1,enhancement,collaboration"; body = "Screen share with drawing. Synced via CRDT." },
    @{ title = "[Collab-2.3]: Async video messages"; labels = "P2,enhancement,collaboration"; body = "Record video anchored to code. MinIO storage. Auto-delete 30d." },
    @{ title = "[Collab-2.4]: Shared AI Copilot context"; labels = "P1,enhancement,collaboration"; body = "Expose shared LLM chat context. Both users see conversation." },
    @{ title = "[Collab-2.5]: @mention system"; labels = "P2,enhancement,collaboration"; body = "Type @username. Deep links to code. Notifications via Matrix." },
    @{ title = "[Collab-2.6]: Code review request flow"; labels = "P1,enhancement,collaboration"; body = "Request review from IDE. Priority + context note." },
    @{ title = "[Collab-2.7]: Thread-per-function discussions"; labels = "P2,enhancement,collaboration"; body = "Persistent discussions per symbol. Survives refactors." },
    @{ title = "[Collab-2.8]: Meeting mode with DND"; labels = "P3,enhancement,collaboration"; body = "Auto-DND when in voice call. Queue notifications." },
    @{ title = "[Collab-2.9]: Async standup AI summaries"; labels = "P2,enhancement,collaboration"; body = "AI-generated daily summaries. Post to Matrix at 9 AM." },
    @{ title = "EPIC [Collab-3]: AI-Augmented Collaboration"; labels = "P1,enhancement,collaboration,ai"; body = "Conflict prediction, expertise routing, knowledge extraction." },
    @{ title = "[Collab-3.1]: Conflict prediction"; labels = "P1,enhancement,collaboration,ai"; body = "Warn before merge: 'Alice editing same function'." },
    @{ title = "[Collab-3.2]: Pair programming AI copilot"; labels = "P1,enhancement,collaboration,ai"; body = "Context-aware AI knowing both users' edits." },
    @{ title = "[Collab-3.3]: Expertise heatmap"; labels = "P2,enhancement,collaboration,ai"; body = "File-level expertise from git blame." },
    @{ title = "[Collab-3.4]: Session hand-off notes"; labels = "P2,enhancement,collaboration,ai"; body = "AI drafts context for next developer." },
    @{ title = "[Collab-3.5]: Shared prompt library"; labels = "P2,enhancement,collaboration,ai"; body = "Team-shared LLM prompts. Auto-suggest." },
    @{ title = "[Collab-3.6]: LLM wiki extraction"; labels = "P2,enhancement,collaboration,ai"; body = "Mine sessions for reusable knowledge." },
    @{ title = "[Collab-3.7]: AI reviewer router"; labels = "P2,enhancement,collaboration,ai"; body = "Auto-assign review by expertise + workload." },
    @{ title = "[Collab-3.8]: Debug session AI"; labels = "P1,enhancement,collaboration,ai"; body = "Suggest root causes from debug state." },
    @{ title = "[Collab-3.9]: Auto test generation"; labels = "P2,enhancement,collaboration,ai"; body = "Generate tests from bug-fix sessions." },
    @{ title = "EPIC [Collab-4]: Presence & Awareness"; labels = "P1,enhancement,collaboration"; body = "Team radar. Who's doing what. Timezone. Expertise." },
    @{ title = "[Collab-4.1]: Rich presence system"; labels = "P1,enhancement,collaboration"; body = "Show file, function, task, status per user." },
    @{ title = "[Collab-4.2]: Flow state detection"; labels = "P2,enhancement,collaboration"; body = "Detect deep focus. Queue pings. Deliver on exit." },
    @{ title = "[Collab-4.3]: Timezone overlays"; labels = "P3,enhancement,collaboration"; body = "Show local time + working hours per user." },
    @{ title = "[Collab-4.4]: Calendar integration"; labels = "P2,enhancement,collaboration"; body = "OAuth Google Cal/Outlook. Show free/busy." },
    @{ title = "[Collab-4.5]: Activity feed"; labels = "P2,enhancement,collaboration"; body = "Stream: commits, PRs, deploys, test flakes." },
    @{ title = "[Collab-4.6]: Smart notification routing"; labels = "P2,enhancement,collaboration"; body = "IDE → Slack → Matrix. No duplication." },
    @{ title = "[Collab-4.7]: Borrow a brain help queue"; labels = "P2,enhancement,collaboration"; body = "Async help routing to experts with SLA." },
    @{ title = "[Collab-4.8]: Code ownership graph"; labels = "P2,enhancement,collaboration"; body = "D3 visualization of file ownership." },
    @{ title = "[Collab-4.9]: Team health dashboard"; labels = "P2,enhancement,collaboration"; body = "Flow time, pair freq, review latency metrics." },
    @{ title = "EPIC [Collab-5]: Session Management"; labels = "P1,infrastructure,collaboration"; body = "Recording, templates, hibernation, quotas, guests." },
    @{ title = "[Collab-5.1]: Session recording"; labels = "P1,enhancement,collaboration"; body = "Record files, terminal, debug, chat. Playback at variable speed." },
    @{ title = "[Collab-5.2]: Workspace templates"; labels = "P1,enhancement,collaboration"; body = "Provision env < 30s. Pinned extensions + settings." },
    @{ title = "[Collab-5.3]: Session hibernation"; labels = "P1,enhancement,collaboration"; body = "CRIU checkpoint. Wake < 5s. Save 80% RAM." },
    @{ title = "[Collab-5.4]: Resource quotas"; labels = "P1,enhancement,collaboration"; body = "cgroups enforce CPU, RAM, disk, bandwidth." },
    @{ title = "[Collab-5.5]: Guest sessions"; labels = "P2,enhancement,collaboration"; body = "Time-limited read-only links. Scoped paths." },
    @{ title = "[Collab-5.6]: Session cost tracking"; labels = "P3,enhancement,collaboration"; body = "CPU-h, RAM-GB-h, storage-GB-d tracking." },
    @{ title = "[Collab-5.7]: Hot workspace switching"; labels = "P1,enhancement,collaboration"; body = "Switch between workspaces < 200ms." },
    @{ title = "[Collab-5.8]: PR preview environments"; labels = "P1,enhancement,collaboration"; body = "Push branch → auto-provision preview." },
    @{ title = "[Collab-5.9]: Session snapshots"; labels = "P1,enhancement,collaboration"; body = "Full-fidelity snapshots. Restore < 10s." },
    @{ title = "EPIC [Collab-6]: Security & Compliance"; labels = "P0,security,collaboration"; body = "Zero-trust, DLP, isolation, audit, E2EE, signing." },
    @{ title = "[Collab-6.1]: Zero-trust network access"; labels = "P0,security,collaboration"; body = "mTLS between services. 24h cert rotation." },
    @{ title = "[Collab-6.2]: Code egress DLP"; labels = "P0,security,collaboration"; body = "Terminal output scanning. Redact secrets." },
    @{ title = "[Collab-6.3]: gVisor workspace isolation"; labels = "P0,security,collaboration"; body = "gVisor sandbox for untrusted workspaces." },
    @{ title = "[Collab-6.4]: Immutable audit log"; labels = "P1,security,collaboration"; body = "SOC2-grade file audit. Append-only table." },
    @{ title = "[Collab-6.5]: E2EE collaboration messages"; labels = "P1,security,collaboration"; body = "Megolm E2EE. Server sees ciphertext only." },
    @{ title = "[Collab-6.6]: Git commit signing"; labels = "P1,security,collaboration"; body = "gitsign keyless signing via Sigstore." },
    @{ title = "[Collab-6.7]: IP allowlist per workspace"; labels = "P2,security,collaboration"; body = "Restrict access to CIDR ranges." },
    @{ title = "[Collab-6.8]: Ephemeral credentials"; labels = "P1,security,collaboration"; body = "Vault dynamic secrets. Auto-rotated per session." },
    @{ title = "[Collab-6.9]: Forensics recording mode"; labels = "P2,security,collaboration"; body = "Terminal + file + network capture. Signed archives." },
    @{ title = "EPIC [Collab-7]: Developer Experience"; labels = "P2,enhancement,collaboration"; body = "Shortcuts, registry, auto-config, API explorer, DB browser." },
    @{ title = "[Collab-7.1]: Keyboard shortcut manager"; labels = "P2,enhancement,collaboration"; body = "Org profiles + personal overrides. Team sync." },
    @{ title = "[Collab-7.2]: Private extension registry"; labels = "P1,enhancement,collaboration"; body = "Open VSIX. Org extensions + blocklist." },
    @{ title = "[Collab-7.3]: Smart workspace auto-config"; labels = "P1,enhancement,collaboration"; body = "Detect project type. Auto-install extensions." },
    @{ title = "[Collab-7.4]: Embedded API explorer"; labels = "P2,enhancement,collaboration"; body = "REST/GraphQL builder. OpenAPI import." },
    @{ title = "[Collab-7.5]: Database browser"; labels = "P2,enhancement,collaboration"; body = "PostgreSQL, Redis, SQLite. Query editor." },
    @{ title = "[Collab-7.6]: Dependency impact graph"; labels = "P2,enhancement,collaboration"; body = "D3 graph showing dependents. Blast radius." },
    @{ title = "[Collab-7.7]: IDE performance profiler"; labels = "P2,enhancement,collaboration"; body = "Per-extension overhead. Health score." },
    @{ title = "[Collab-7.8]: Onboarding wizard"; labels = "P1,enhancement,collaboration"; body = "10min setup: git, SSH, cloud, clone, build." },
    @{ title = "[Collab-7.9]: Status bar team metrics"; labels = "P3,enhancement,collaboration"; body = "Tiles: PRs, CI, incidents, team online." },
    @{ title = "EPIC [Collab-8]: Observability"; labels = "P1,infrastructure,observability"; body = "Tracing, SLOs, health, funnels, correlation, forecasting." },
    @{ title = "[Collab-8.1]: End-to-end distributed tracing"; labels = "P1,enhancement,observability"; body = "OTel instrumentation. Jaeger export." },
    @{ title = "[Collab-8.2]: SLO/SLA dashboard"; labels = "P1,enhancement,observability"; body = "sync < 100ms p99. Error budget tracking." },
    @{ title = "[Collab-8.3]: WebSocket health monitoring"; labels = "P1,enhancement,observability"; body = "Latency, jitter, loss. Quality score 0-100." },
    @{ title = "[Collab-8.4]: Funnel analytics"; labels = "P2,enhancement,observability"; body = "Onboarding funnel. Conversion % tracking." },
    @{ title = "[Collab-8.5]: Incident correlation"; labels = "P1,enhancement,observability"; body = "SLO breach → correlate with deploys." },
    @{ title = "[Collab-8.6]: Capacity forecasting"; labels = "P2,enhancement,observability"; body = "Time-series forecasting. 30/60/90d predictions." },
    @{ title = "[Collab-8.7]: Session replay timeline"; labels = "P2,enhancement,observability"; body = "Grafana timeline of all events per session." },
    @{ title = "[Collab-8.8]: Access pattern anomaly detection"; labels = "P1,security,observability"; body = "ML baseline + Isolation Forest scoring." },
    @{ title = "[Collab-8.9]: DORA metrics dashboard"; labels = "P2,enhancement,observability"; body = "Deployment freq, lead time, CFR, MTTR." },
    @{ title = "EPIC [Collab-9]: Integrations Hub"; labels = "P1,enhancement,collaboration"; body = "GitHub, Linear, Slack, CI/CD, Figma, Sentry, flags, PagerDuty." },
    @{ title = "[Collab-9.1]: GitHub Issues IDE panel"; labels = "P1,enhancement,collaboration"; body = "Browse, create, comment, assign issues." },
    @{ title = "[Collab-9.2]: Linear/Jira linking"; labels = "P2,enhancement,collaboration"; body = "Link tickets. Auto-inject context." },
    @{ title = "[Collab-9.3]: Slack slash commands"; labels = "P1,enhancement,collaboration"; body = "'/code-review @alice' → shared session." },
    @{ title = "[Collab-9.4]: CI/CD status sidebar"; labels = "P1,enhancement,collaboration"; body = "Live pipeline with logs + re-run actions." },
    @{ title = "[Collab-9.5]: Figma embed"; labels = "P2,enhancement,collaboration"; body = "Render frames. Design token inspection." },
    @{ title = "[Collab-9.6]: Sentry integration"; labels = "P1,enhancement,collaboration"; body = "Browse errors. Click trace → code line." },
    @{ title = "[Collab-9.7]: Feature flag panel"; labels = "P2,enhancement,collaboration"; body = "Unleash integration. Toggle flags per session." },
    @{ title = "[Collab-9.8]: PagerDuty → auto-open files"; labels = "P1,enhancement,collaboration"; body = "Incident fires → pre-load relevant files." },
    @{ title = "[Collab-9.9]: Jaeger APM integration"; labels = "P1,enhancement,collaboration"; body = "Click span → jump to code location." },
    @{ title = "EPIC [Collab-10]: Scale & Performance"; labels = "P1,infrastructure,performance"; body = "WebSocket gateway, CRDT compaction, delta sync, failover." },
    @{ title = "[Collab-10.1]: WebSocket gateway cluster"; labels = "P1,infrastructure,performance"; body = "3-node relay. Consistent hashing." },
    @{ title = "[Collab-10.2]: CRDT compaction"; labels = "P1,infrastructure,performance"; body = "Snapshot + truncate ops. Non-blocking." },
    @{ title = "[Collab-10.3]: Selective delta sync"; labels = "P1,infrastructure,performance"; body = "State vectors. O(change) not O(doc)." },
    @{ title = "[Collab-10.4]: Network migration"; labels = "P1,infrastructure,performance"; body = "WiFi → 4G: reconnect < 3s. Zero loss." },
    @{ title = "[Collab-10.5]: Edge relay nodes"; labels = "P2,infrastructure,performance"; body = "Geographic edge relays. < 50ms global latency." },
    @{ title = "[Collab-10.6]: session-broker horizontal scale"; labels = "P1,infrastructure,performance"; body = "Multiple instances. Consistent hashing." },
    @{ title = "[Collab-10.7]: Multi-region deployment"; labels = "P3,infrastructure,performance"; body = "Region-specific DBs. Data residency." },
    @{ title = "[Collab-10.8]: Message compression < 1 KB"; labels = "P2,infrastructure,performance"; body = "Delta + LZ4 compress + batching." },
    @{ title = "[Collab-10.9]: Hot-standby failover"; labels = "P1,infrastructure,performance"; body = "Standby receives all ops. < 1s failover." }
)

Write-Host "Creating $($ISSUES.Count) collaboration enhancement issues on $REPO"
Write-Host "=" * 80

$created = 0
$failed = 0

foreach ($i in 0..($ISSUES.Count - 1)) {
    $issue = $ISSUES[$i]
    $title = $issue.title
    $labels = $issue.labels -split ","
    $body = $issue.body
    
    $index = $i + 1
    Write-Host -NoNewline ("[{0:000}/{1}] {2,-50} ... " -f $index, $ISSUES.Count, $title.Substring(0, [Math]::Min(50, $title.Length)))
    
    # Build gh command
    $cmd = @("issue", "create", "--repo", $REPO, "--title", $title, "--body", $body)
    foreach ($label in $labels) {
        $cmd += @("--label", $label.Trim())
    }
    
    try {
        $output = & gh @cmd 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓"
            $created++
        } else {
            Write-Host "✗"
            $failed++
        }
    } catch {
        Write-Host "✗"
        $failed++
    }
    
    # Rate limiting
    Start-Sleep -Milliseconds 200
}

Write-Host "=" * 80
Write-Host "Done: $created/$($ISSUES.Count) successful"
exit $(if ($failed -le $ISSUES.Count * 0.1) { 0 } else { 1 })
