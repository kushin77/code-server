# GitHub API Stability Audit Report

**Generated**: 2026-04-24 21:07:58 UTC  
**Total gh CLI Calls**: 8  
**Status**: ⚠️ NEEDS_REMEDIATION

## Findings

❌ 4 gh issue/pr calls missing --repo flag (may cause ambiguity)
⚠️ 8 gh calls may lack retry logic for 429/403 errors
ℹ️ Using GITHUB_TOKEN (fine-grained tokens recommended for reduced scope)
⚠️ No GitHub token found (GH_TOKEN or GITHUB_TOKEN env var)
✅ Unified issue creation script found
⚠️ 1 direct 'gh issue create' calls found in workflows (consolidate to unified script)


## Issues Requiring Action

- **github-api-missing-repo-flag**: 4 gh calls missing --repo flag
- **github-api-consolidate-issue-creation**: Consolidate direct gh issue create calls to unified script


## Recommendations

1. **Token Scopes**: Use fine-grained personal access tokens (not classic PAT)
   - Scopes needed: `repo`, `issues`, `pull-requests`, `workflows`
   
2. **Retry Logic**: All gh CLI calls should retry on 429/403
   - Implement exponential backoff (1s, 2s, 4s)
   - Max 3 retries
   
3. **Rate Limit Monitoring**: 
   - Alert when < 100 requests remaining
   - Track in Prometheus
   - Set dashboard
   
4. **Unified Issue Creation**:
   - All `gh issue create` calls go through `scripts/_common/issue-create-unified.sh`
   - Enforced via CI guard

5. **Testing**:
   - Test token validity before CI runs
   - Simulate rate limit scenarios

