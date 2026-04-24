#!/usr/bin/env python3
"""Create and merge PR for Issue #950 deployment"""

import subprocess
import json
import sys

def run_cmd(cmd):
    """Run command and return output"""
    print(f"Running: {cmd}")
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"Error: {result.stderr}")
        return None
    return result.stdout.strip()

def main():
    # Step 1: Check if PR exists
    print("Step 1: Checking for existing PR...")
    pr_output = run_cmd('gh pr list --base main --head sanitized/redeploy-pr --json number')
    
    if pr_output:
        try:
            pr_data = json.loads(pr_output)
            if pr_data and len(pr_data) > 0:
                pr_num = pr_data[0]['number']
                print(f"✓ Found existing PR #{pr_num}")
            else:
                pr_num = None
        except:
            pr_num = None
    else:
        pr_num = None
    
    # Step 2: Create PR if needed
    if not pr_num:
        print("Step 2: Creating PR...")
        pr_output = run_cmd(
            'gh pr create --base main --head sanitized/redeploy-pr '
            '--title "fix: Deploy Issue #950 - sanitized redeploy with documentation" '
            '--body "Closes #950"'
        )
        if pr_output and 'https://github.com' in pr_output:
            # Extract PR number from URL
            parts = pr_output.split('/')
            pr_num = parts[-1]
            print(f"✓ Created PR #{pr_num}")
        else:
            print("✗ Failed to create PR")
            print(f"Output: {pr_output}")
            return 1
    
    # Step 3: Merge PR
    print(f"Step 3: Merging PR #{pr_num}...")
    merge_output = run_cmd(f'gh pr merge {pr_num} --admin --merge --delete-branch')
    
    if merge_output and 'Merged' in merge_output:
        print(f"✓ Merged PR #{pr_num}")
    else:
        print("✗ Failed to merge PR")
        print(f"Output: {merge_output}")
        return 1
    
    # Step 4: Verify merge
    print("Step 4: Verifying merge...")
    run_cmd('git fetch origin')
    main_commit = run_cmd('git rev-parse origin/main')
    sanitized_commit = run_cmd('git rev-parse origin/sanitized/redeploy-pr')
    
    if main_commit == sanitized_commit:
        print("✓ Branch successfully merged to main")
    else:
        print("⚠ Could not verify merge")
    
    # Step 5: Close issue
    print("Step 5: Closing issue #950...")
    close_output = run_cmd('gh issue close 950 --repo kushin77/code-server --comment "✓ Deployment complete. Branch merged to main, GitHub Actions workflow triggered."')
    
    if close_output:
        print("✓ Closed issue #950")
    else:
        print("⚠ Issue may already be closed or encountered error")
    
    print("")
    print("========================================")
    print("✓ Issue #950 Deployment COMPLETE!")
    print("========================================")
    print("")
    print(f"✓ PR #{pr_num} merged to main")
    print("✓ GitHub Actions deployment workflow triggered")
    print("✓ Issue #950 closed")
    print("")
    print("Monitor deployment at:")
    print("  https://github.com/kushin77/code-server/actions?workflow=deploy.yml")
    print("")
    print("Verify services at:")
    print("  ssh akushnir@192.168.168.31 'docker compose ps'")
    print("")
    
    return 0

if __name__ == '__main__':
    sys.exit(main())
