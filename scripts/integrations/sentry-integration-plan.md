# Sentry Integration Implementation Plan
## Issue #1308: [Collab-9.6] Sentry integration

### Requirements
1. **Error Browsing**: Display errors from Sentry in a sidebar panel
2. **Stack Frame Navigation**: Click on stack frame → jump to source file and line
3. **Blame Information**: Show git blame for the line with the error
4. **AI-Assisted Fix**: 'Fix with AI' action that uses Copilot to suggest fixes for the error

### Architecture

```
├── sentry-integration-api.js          # REST API for error fetching and processing
├── sentry-integration-service.js      # Service logic for Sentry SDK interaction
├── sentry-integration-panel.js        # VS Code WebView panel for UI
├── sentry-error-analyzer.js           # AI-powered error analysis and fix suggestions
└── sentry-integration-test.js         # Integration tests
```

### Implementation Phases

#### Phase 1: Core Integration (Priority 1)
- [ ] Initialize Sentry SDK in code-server backend
- [ ] Create REST API endpoint: `GET /api/sentry/errors`
- [ ] Fetch recent errors for authenticated user's projects
- [ ] Error model: `{ id, title, level, firstSeen, lastSeen, count, culprit, stackTrace[] }`

#### Phase 2: WebView Panel (Priority 1)
- [ ] Create VS Code extension panel for Sentry errors
- [ ] Display error list with pagination
- [ ] Stack trace explorer with frame details
- [ ] Source file link integration

#### Phase 3: Source Navigation & Blame (Priority 2)
- [ ] Click handler for stack frames
- [ ] Parse file path and line number from Sentry data
- [ ] Jump to file in editor
- [ ] Fetch git blame for the line
- [ ] Display blame author, commit message, date

#### Phase 4: AI-Assisted Fixes (Priority 2)
- [ ] Extract error context (stack trace, error message, code snippet)
- [ ] Call Copilot API with context
- [ ] Generate fix suggestion
- [ ] Display suggestion in editor as CodeLens action
- [ ] Allow one-click apply or manual review

### API Endpoints

```bash
GET /api/sentry/errors?limit=50&offset=0&project=all
  Response: { errors: [...], total, hasMore }

GET /api/sentry/errors/:errorId
  Response: { error, stackTrace, userFeedback[], relatedErrors[] }

POST /api/sentry/ai-fix
  Body: { errorId, stackFrame, stackTrace }
  Response: { suggestion, confidence, reasoning }

POST /api/sentry/resolve/:errorId
  Body: { resolution: 'fixed' | 'ignored' }
  Response: { status, message }
```

### Environment Variables Required
- `SENTRY_AUTH_TOKEN`: API token for server-side access
- `SENTRY_ORG_SLUG`: Organization slug
- `SENTRY_PROJECT_SLUG`: Project slug(s) - comma-separated for multi-project
- `SENTRY_DSN`: Client DSN for error reporting (optional, for KC IDE errors)

### Dependencies
- `@sentry/node`: ^7.100.0 (backend SDK)
- `@sentry/tracing`: ^7.100.0 (performance monitoring)
- `@vscode/webview-ui-toolkit`: ^1.2.0 (UI components)
- `js-git`: ^0.7.0 (git blame access)

### Success Criteria
1. ✅ Fetch errors from Sentry API
2. ✅ Display errors in VS Code sidebar
3. ✅ Navigate to source lines with git blame
4. ✅ AI-powered fix suggestions with one-click apply
5. ✅ Resolve errors directly from IDE
6. ✅ E2E test with real Sentry data

### Timeline
- Phase 1: 2 hours (API + initial UI)
- Phase 2: 1.5 hours (WebView panel)
- Phase 3: 2 hours (Navigation + blame)
- Phase 4: 3 hours (AI integration + testing)
- **Total: ~8.5 hours development**

### Risk Mitigation
- **Rate limiting**: Implement caching (5-min TTL) for error lists
- **Performance**: Lazy-load stack traces, paginate results
- **Security**: Validate project access, use API tokens scoped to organization
- **Errors in errors**: Handle Sentry API failures gracefully
