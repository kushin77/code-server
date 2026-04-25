# Code Server Copilot Memory + GitHub Profile

> **Self-cleaning, decision-aware copilot with persistent memory + GitHub awareness, packaged for Code Server**

This extension brings three powerful capabilities to your Code Server environment:

1. **🧠 Self-Cleaning Memory** — Copilot remembers your goals, decisions, and assumptions. Never gets Alzheimer's.
2. **🔍 Deduplication Engine** — Flags repeated suggestions (>85% semantic match) before they happen.
3. **🐙 GitHub Integration** — Scans all repos/issues/PRs daily and feeds them into copilot context.

---

## Installation (4 Steps)

### Step 1: Install the Extension

**Option A: From Marketplace**
```bash
# In Code Server command palette (Ctrl+Shift+P):
> Extensions: Install from VSIX
# Select: copilot-memory-github-profile-1.0.0.vsix
```

**Option B: Manual Install**
```bash
# Download the VSIX from GitHub releases
# Or build from source:
git clone https://github.com/your-org/copilot-memory-profile.git
cd copilot-memory-profile
npm install
npm run package
# Then install: copilot-memory-github-profile-*.vsix
```

**Option C: Direct Copy (Self-Hosted Code Server)**
```bash
mkdir -p ~/.local/share/code-server/extensions
cd ~/.local/share/code-server/extensions
git clone https://github.com/your-org/copilot-memory-profile.git
cd copilot-memory-profile
npm install && npm run compile
# Reload Code Server
```

### Step 2: Set API Keys

Open Code Server **Settings** (Ctrl+,) and search for `copilot-memory`:

```json
{
  "copilot-memory.anthropicApiKey": "sk-ant-xxxx",
  "copilot-memory.githubToken": "ghp_xxxx",
  "copilot-memory.githubOrg": "your-github-org"
}
```

**How to get keys:**
- **Anthropic API**: [api.anthropic.com/keys](https://api.anthropic.com/keys) (grab your API key)
- **GitHub Token**: [github.com/settings/tokens](https://github.com/settings/tokens) → "Fine-grained tokens" → create one with **repo (read-only)** + **issues/PRs read**

### Step 3: Open Copilot View

Click the **Copilot Memory** icon in the Activity Bar (left sidebar), or press **Ctrl+Shift+C**.

You'll see three panels:
- **Chat** — Talk to copilot
- **Memory State** — Active goals, decisions, blockers
- **GitHub Status** — Repos, issues, PRs from your last scan

### Step 4: Initial GitHub Scan (Optional)

Press **Ctrl+Shift+G** or run command **"Copilot: Refresh GitHub Status"** to scan your repos.

This is optional — the extension will auto-scan daily at 00:00 UTC.

---

## Quick Start: Example Conversation

**You:** "How should I structure the conflict resolution engine for GitPeak?"

**Copilot:** [Injects memory context] "I see you're working on GitPeak #789. Here's my recommendation..."

**You:** "Now I need to update the GTM playbook."

**Copilot:** ⚠️ **Domain switch flagged.** "Switching from code → sales. Your GitPeak goal is still active. Continue in parallel?"

**You:** "Yes, continue in parallel. Update the LinkedIn template."

**Copilot:** [Locks decision: "Parallel work on code + sales"] "For LinkedIn, I'd recommend..."

**You:** "Actually, how should I structure the conflict resolver?"

**Copilot:** ⚠️ **Duplicate flagged** (92% match). "I already suggested this earlier. Want me to expand on implementation details?"

---

## Features

### ✅ Self-Cleaning Memory
- **Never repeats suggestions** — semantic deduplication (>85% threshold)
- **Locks decisions** — once accepted, future advice respects locked choices
- **Flags contradictions** — surfaces conflicts before offering conflicting guidance
- **Tracks assumptions** — states them upfront, corrects when wrong

### ✅ GitHub Integration
- **Daily scan** (configurable cron, default 00:00 UTC)
- **All repos, issues, PRs** scanned and categorized
- **Copilot knows your roadmap** — references GitHub issue #123 without you re-explaining
- **Blocker visibility** — surfaces cross-repo dependencies automatically
- **Technical debt tracking** — logs TODOs, deprecated patterns, security flags

### ✅ Code Server Features
- **Keyboard shortcuts** — Ctrl+Shift+C (chat), Ctrl+Shift+G (GitHub scan)
- **Command palette** — search "Copilot" for all commands
- **Export/Import memory** — share memory across devices or teams
- **Memory backends** — in-memory (default), Redis, or PostgreSQL

---

## Commands

| Command | Shortcut | Description |
|---------|----------|-------------|
| **Copilot: Open Chat** | Ctrl+Shift+C | Open copilot chat panel |
| **Copilot: Refresh GitHub Status** | Ctrl+Shift+G | Scan GitHub repos/issues immediately |
| **Copilot: Show Memory State** | — | Export current memory as JSON in editor |
| **Copilot: Export Memory** | — | Save memory to file (for backup/sharing) |
| **Copilot: Import Memory** | — | Load memory from file |
| **Copilot: Clear Memory** | — | Reset all memory (cannot undo) |

---

## Configuration

### Required Settings
```json
{
  "copilot-memory.anthropicApiKey": "sk-ant-xxxx",
  "copilot-memory.githubToken": "ghp_xxxx",
  "copilot-memory.githubOrg": "your-github-org"
}
```

### Optional Settings
```json
{
  "copilot-memory.scanSchedule": "0 0 * * *",              // Cron for daily scan (default: 00:00 UTC)
  "copilot-memory.memoryBackend": "memory",                // "memory" | "redis" | "postgresql"
  "copilot-memory.redisUrl": "redis://localhost:6379",     // If backend is redis
  "copilot-memory.postgresUrl": "postgresql://...",        // If backend is postgresql
  "copilot-memory.deduplicationThreshold": 0.85,           // Semantic similarity threshold (0-1)
  "copilot-memory.autoLockDecisions": true,                // Auto-lock decisions after acceptance
  "copilot-memory.enableTelemetry": false                  // Send anonymous metrics
}
```

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Code Server Extension                     │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  Activity Bar View (Left Sidebar)                            │
│  ├─ Chat Panel (webview)                                     │
│  ├─ Memory State Panel (webview)                             │
│  └─ GitHub Status Panel (webview)                            │
│                                                               │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  Core Engines (TypeScript)                                   │
│  ├─ CopilotMemoryEngine                                      │
│  │  ├─ Claude API calls (Sonnet 4)                           │
│  │  ├─ Memory persistence (in-memory / Redis / PostgreSQL)   │
│  │  └─ Dedup check + contradiction detection                │
│  │                                                            │
│  ├─ GitHubScannerService                                     │
│  │  ├─ GitHub GraphQL queries                                │
│  │  ├─ Daily cron job scheduling                             │
│  │  └─ Goal synthesis (repos → session goals)                │
│  │                                                            │
│  └─ Commands                                                  │
│     ├─ startChat, scanGitHub, showMemoryState                │
│     ├─ exportMemory, importMemory, clearMemory               │
│     └─ (all trigger engine methods or webview updates)       │
│                                                               │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  Data Stores                                                  │
│  ├─ In-Memory: session_goals, contradiction_log, etc.        │
│  ├─ Redis (optional): persistent cache for scaling           │
│  └─ PostgreSQL (optional): durable multi-user setup          │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

---

## Memory Persistence

### Backend: In-Memory (Default)
- ✅ **Pros**: No setup, fast, perfect for single-user
- ❌ **Cons**: Lost on restart

### Backend: Redis
- ✅ **Pros**: Persistent, fast, multi-device sync
- ❌ **Cons**: Requires Redis server

**Setup:**
```bash
# Install Redis (macOS)
brew install redis
redis-server

# Or Docker
docker run -d -p 6379:6379 redis:latest

# Configure Code Server
# In settings: copilot-memory.memoryBackend = "redis"
#              copilot-memory.redisUrl = "redis://localhost:6379"
```

### Backend: PostgreSQL
- ✅ **Pros**: Most durable, audit trail, multi-user/team
- ❌ **Cons**: Requires database setup

**Setup:**
```bash
# Create database
createdb copilot_memory

# Configure Code Server
# In settings: copilot-memory.memoryBackend = "postgresql"
#              copilot-memory.postgresUrl = "postgresql://user:pass@localhost/copilot_memory"
```

---

## Team Sharing

### Option 1: Export/Import Memory
```bash
# User A: Export memory
# Command Palette > "Copilot: Export Memory" → saves to file

# User B: Import memory
# Command Palette > "Copilot: Import Memory" → loads from file
# Now User B has User A's entire memory
```

### Option 2: Redis Backend (Shared Cache)
```json
{
  "copilot-memory.memoryBackend": "redis",
  "copilot-memory.redisUrl": "redis://shared-redis-host:6379"
}
```
All team members connect to same Redis → shared memory, shared GitHub context.

### Option 3: PostgreSQL + RBAC (Enterprise)
Deploy PostgreSQL with role-based access control (RBAC) for multi-team setup:
```sql
CREATE ROLE team_a WITH LOGIN PASSWORD 'xxx';
GRANT SELECT, INSERT ON copilot_memory_goals TO team_a;
```

---

## Troubleshooting

### "Anthropic API key not set"
- **Fix**: Set `copilot-memory.anthropicApiKey` in Code Server settings
- Check: `echo $ANTHROPIC_API_KEY` (env var works too)

### "GitHub scan failing: rate limited"
- **Cause**: GitHub allows 5000 points/hour for GraphQL. Large orgs (50+ repos) may hit this.
- **Fix**: Increase scan interval (scan less frequently) or split into smaller scans

### "Memory not persisting across restarts"
- **Cause**: Using in-memory backend
- **Fix**: Switch to Redis or PostgreSQL: `copilot-memory.memoryBackend = "redis"`

### "Copilot responses are generic"
- **Cause**: Memory not being injected into system prompt
- **Fix**: Run "Copilot: Show Memory State" to verify goals are being recorded

---

## Development

### Build from Source
```bash
git clone https://github.com/your-org/copilot-memory-profile.git
cd copilot-memory-profile
npm install
npm run compile       # Dev build
npm run watch        # Watch mode
npm run package      # Create VSIX for distribution
```

### Testing
```bash
npm run test

# Or run Code Server extension host in debug mode:
code-server --install-extension ./copilot-memory-github-profile-1.0.0.vsix --force
```

### Contributing
1. Fork the repo
2. Create feature branch (`git checkout -b feat/your-feature`)
3. Test locally
4. Submit PR with description of changes

---

## License

MIT © [Your Name/Org]

---

## Support

- **Issues**: [GitHub Issues](https://github.com/your-org/copilot-memory-profile/issues)
- **Discussions**: [GitHub Discussions](https://github.com/your-org/copilot-memory-profile/discussions)
- **Email**: support@your-org.com

---

## Roadmap

- [ ] Web-based memory dashboard (view all goals, decisions, blockers)
- [ ] Mobile app (iOS/Android) for remote copilot access
- [ ] OpenAI/Claude model switching
- [ ] Voice input for copilot chat
- [ ] Slack/Discord integration
- [ ] Team collaboration features (shared memory, @mentions)
- [ ] Memory encryption at rest
- [ ] Audit logging for compliance

---

## Credits

Built with:
- [Claude (Anthropic)](https://anthropic.com)
- [Code Server](https://coder.com/docs/code-server)
- [GitHub GraphQL API](https://docs.github.com/en/graphql)