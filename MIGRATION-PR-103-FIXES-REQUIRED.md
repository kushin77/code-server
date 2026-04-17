# PR #103 Merge Blockers - Fixes Required

PR #103 in kushin77/ollama is ready for merge but has 6 unresolved review comments from Copilot that must be addressed.

## Blocking Issues

### 1. INTEGRATION.md - Line 17
**Issue**: References `../ollama/backend` in NPM workspace config, but backend isn't deployed yet

**Fix**: Update the workspace reference to only include the extension:
```json
{
  "workspaces": [
    "backend",
    "../ollama/extensions/ollama-chat"
  ],
  "dependencies": {
    "ollama-chat": "workspace:*"
  }
}
```

**File to change**: `INTEGRATION.md` line 15-20

---

### 2. README.md - Line 115
**Issue**: VS Code extension install instructions are incorrect

**Current**: `code --install-extension ./dist`
**Should be**: Uses `vsce` to package and install

**Fix**:
```bash
npm run compile                # Production build
npx @vscode/vsce package       # Create .vsix package  
code --install-extension ./*.vsix  # Install packaged extension in VS Code
```

**File to change**: `README.md` lines 115-118

---

### 3. extensions/ollama-chat/package.json - Line 95
**Issue**: Test script references wrong path

**Current**: `"test": "node ./out/test/runTest.js"`
**Should be**: Placeholder since tests aren't set up yet

**Fix**:
```json
"test": "echo \"No tests configured for ollama-chat yet.\""
```

**File to change**: `extensions/ollama-chat/package.json` line 95

---

### 4. MIGRATION.md - Line 32
**Issue**: Spelling error

**Current**: `"Icludes:"`
**Fix**: `"Includes:"`

**File to change**: `MIGRATION.md` line 32

---

### 5. MIGRATION.md - Line 171
**Issue**: References `bash scripts/ollama-init.sh --help` but the script isn't in this PR

**Current**:
```bash
bash scripts/ollama-init.sh --help
```

**Fix**: Remove this line since scripts are in backend services, not as standalone files

**File to change**: `MIGRATION.md` lines 169-171 - Remove the scripts testing section

---

### 6. README.md - Line 136
**Issue**: References benchmark script that doesn't exist

**Current**: `node scripts/benchmark-retrieval.mjs`

**Fix**: Remove this line - benchmarking is in backend/src/services/ai/__tests__/

**File to change**: `README.md` line 136 - Remove the benchmark command

---

## How to Fix

1. **Clone kushin77/ollama**:
```bash
git clone https://github.com/kushin77/ollama.git
cd ollama
git checkout feat/migrate-from-code-server
```

2. **Make the 6 fixes** listed above

3. **Commit the fixes**:
```bash
git add INTEGRATION.md README.md extensions/ollama-chat/package.json MIGRATION.md
git commit -m "fix: resolve Copilot review comments on PR #103

- Fix INTEGRATION.md workspace config references
- Fix README.md VS Code extension install instructions
- Fix package.json test script path
- Fix spelling: Icludes → Includes
- Remove references to non-existent scripts
"
```

4. **Push to the branch**:
```bash
git push origin feat/migrate-from-code-server
```

5. **CI checks**: The `validate-landing-zone` check may still fail. This is a separate infrastructure validation that may require environment setup or can be bypassed if not critical for this PR.

6. **Request approval**: Merge PR #103 once CI passes

---

## Success Criteria

Once merged, verify:
- ✅ PR #103 merged to kushin77/ollama main
- ✅ All 1,830+ LOC present in repo
- ✅ All 40+ tests pass
- ✅ Extension builds: `cd extensions/ollama-chat && npm run compile`
- ✅ Backend builds: `cd backend && npm run build`
- ✅ Backend tests pass: `cd backend && npm test`

---

## Next Steps After Merge

1. **Phase 4**: Update code-server-enterprise to reference kushin77/ollama
2. **Phase 5**: Remove duplicate code from code-server-enterprise
3. **Phase 6**: Deploy to production with new architecture

---

Generated: 2026-04-17
Migration Status: Code Complete, Pending Review & Merge
