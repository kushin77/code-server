#!/usr/bin/env node
/**
 * @file scripts/remediation/fix-1707-remove-stale-js.mjs
 * @description Remove stale .js files causing test failures in Issue #1707
 * 
 * Execution: node ./fix-1707-remove-stale-js.mjs
 * Idempotent: Safe to run multiple times
 */

import { execSync } from 'child_process';
import fs from 'fs-extra';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, '../../');

const STALE_FILES = [
    'apps/session-broker/src/__tests__/session-sandbox.test.js',
    'apps/extensions/team-hub/test/team-hub.test.js',
    'apps/frontend/src/utils/__tests__/ws-session-handoff.test.js',
    'apps/frontend/src/utils/__tests__/workspaceTemplates.test.js',
    'apps/frontend/src/utils/__tests__/workspaceSessionPersistence.test.js',
    'apps/frontend/src/utils/__tests__/workspaceProfiles.test.js',
    'apps/frontend/src/utils/__tests__/symbolDiscussions.test.js',
    'apps/frontend/src/utils/__tests__/session-sync.test.js',
    'apps/frontend/src/utils/__tests__/session-keepalive.test.js',
    'apps/frontend/src/utils/__tests__/session-indexeddb-store.test.js',
    'apps/frontend/src/utils/__tests__/resourceQuotaDashboard.test.js',
    'apps/frontend/src/utils/__tests__/repoHomeData.test.js',
    'apps/frontend/src/utils/__tests__/multiRepoRollout.test.js',
    'apps/frontend/src/utils/__tests__/multiRepoPolicy.test.js',
    'apps/frontend/src/utils/__tests__/debugSessionInsights.test.js',
    'apps/frontend/src/utils/__tests__/debugCollaboration.test.js',
    'apps/frontend/src/utils/__tests__/collaborationMetrics.test.js',
    'apps/frontend/src/utils/__tests__/auth-sw-register.test.js',
    'apps/frontend/src/services/__tests__/workspace-switcher.test.js',
    'apps/frontend/src/services/session-snapshot/__tests__/session-snapshot.test.js',
    'apps/session-broker/src/session-sandbox.js',
];

async function removeStaleFiles() {
    console.log('🧹 P2-1707: Removing stale .js transpiled artifacts...\n');
    
    let removed = 0;
    let skipped = 0;
    
    for (const file of STALE_FILES) {
        const filePath = path.join(REPO_ROOT, file);
        const tsFile = file.replace(/\.js$/, '.ts');
        const tsPath = path.join(REPO_ROOT, tsFile);
        
        if (fs.existsSync(filePath)) {
            if (fs.existsSync(tsPath)) {
                console.log(`✓ Removing: ${file}`);
                try {
                    // Stage removal in git
                    execSync(`git rm --cached --force "${filePath}"`, {
                        cwd: REPO_ROOT,
                        stdio: 'pipe'
                    });
                    // Physical removal
                    fs.removeSync(filePath);
                    removed++;
                } catch (e) {
                    // Continue if git rm fails (file might not be tracked)
                    fs.removeSync(filePath);
                    removed++;
                }
            } else {
                console.log(`⊘ Skipping: ${file} (no .ts equivalent)`);
                skipped++;
            }
        }
    }
    
    console.log(`\n✅ Cleanup complete!`);
    console.log(`   Removed: ${removed} files`);
    console.log(`   Skipped: ${skipped} files`);
    
    // Stage and commit
    console.log(`\n📝 Creating commit...`);
    try {
        const status = execSync('git status --porcelain', { cwd: REPO_ROOT }).toString();
        if (status.trim().length > 0) {
            execSync('git add -A', { cwd: REPO_ROOT });
            const commitMsg = `fix(P2-1707): Remove stale .js transpiled artifacts

- Removed ${removed} .js files that have .ts equivalents
- Prevents vitest mock path resolution failures  
- Fixes backend-integration test suite
- Keeps .ts files as single source of truth`;
            
            execSync(`git commit -m "${commitMsg}"`, {
                cwd: REPO_ROOT,
                stdio: 'pipe'
            });
            console.log('✓ Commit created');
        } else {
            console.log('ℹ No changes to commit');
        }
    } catch (e) {
        console.log('⚠ Git operations completed with notices (may be expected)');
    }
}

removeStaleFiles().catch(err => {
    console.error('❌ Error:', err.message);
    process.exit(1);
});
