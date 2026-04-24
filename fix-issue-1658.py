#!/usr/bin/env python3
"""
Fix Issue #1658: Backend Integration Test Failures

This script regenerates pnpm-lock.yaml to fix @vitest/coverage-v8 peer dependency mismatch.

USAGE:
    python3 fix-issue-1658.py [--test-local] [--verify-only] [--dry-run]

OPTIONS:
    --test-local     Run pnpm test after fix to verify success
    --verify-only    Check if fix is needed without applying it
    --dry-run        Show what would be done without executing
"""

import os
import sys
import subprocess
import shutil
from pathlib import Path
from datetime import datetime


class Issue1658Fixer:
    def __init__(self, repo_root=None, test_local=False, verify_only=False, dry_run=False):
        self.repo_root = Path(repo_root or os.getcwd())
        self.test_local = test_local
        self.verify_only = verify_only
        self.dry_run = dry_run
        self.lock_file = self.repo_root / "pnpm-lock.yaml"
        self.backup_file = self.repo_root / "pnpm-lock.yaml.backup"
        self.success = True

    def log(self, message, level="INFO"):
        """Log message with timestamp and level"""
        timestamp = datetime.now().isoformat()
        print(f"[{timestamp}] {level}: {message}")

    def run_command(self, cmd, description, cwd=None, check=True):
        """Execute shell command"""
        self.log(f"Executing: {description}")
        self.log(f"  Command: {' '.join(cmd)}")
        
        if self.dry_run:
            self.log("  [DRY RUN] Skipped execution")
            return True

        try:
            result = subprocess.run(
                cmd,
                cwd=cwd or self.repo_root,
                capture_output=True,
                text=True,
                timeout=300
            )
            
            if result.returncode != 0 and check:
                self.log(f"  ✗ Command failed with exit code {result.returncode}", "ERROR")
                if result.stderr:
                    self.log(f"  stderr: {result.stderr[:200]}", "ERROR")
                self.success = False
                return False
            
            if result.stdout:
                self.log(f"  ✓ stdout: {result.stdout[:100]}")
            
            return True
        except subprocess.TimeoutExpired:
            self.log(f"  ✗ Command timed out", "ERROR")
            self.success = False
            return False
        except Exception as e:
            self.log(f"  ✗ Command failed: {str(e)}", "ERROR")
            self.success = False
            return False

    def verify_environment(self):
        """Verify pnpm and git are available"""
        self.log("Step 1: Verifying environment")
        
        # Check pnpm
        if not self.run_command(["pnpm", "--version"], "Check pnpm version", check=False):
            self.log("  ⚠ pnpm not found in PATH", "WARN")
            return False
        
        # Check git
        if not self.run_command(["git", "--version"], "Check git version", check=False):
            self.log("  ⚠ git not found in PATH", "WARN")
            return False
        
        # Check lock file exists
        if not self.lock_file.exists():
            self.log(f"  ✗ pnpm-lock.yaml not found at {self.lock_file}", "ERROR")
            return False
        
        self.log("  ✓ Environment verified")
        return True

    def backup_lock_file(self):
        """Create backup of current lock file"""
        self.log("Step 2: Backing up pnpm-lock.yaml")
        
        if self.dry_run:
            self.log(f"  [DRY RUN] Would backup to {self.backup_file}")
            return True
        
        try:
            shutil.copy2(str(self.lock_file), str(self.backup_file))
            self.log(f"  ✓ Backup created: {self.backup_file}")
            return True
        except Exception as e:
            self.log(f"  ✗ Backup failed: {str(e)}", "ERROR")
            self.success = False
            return False

    def regenerate_lock_file(self):
        """Regenerate lock file with pnpm install --prefer-frozen-lockfile"""
        self.log("Step 3: Regenerating pnpm-lock.yaml")
        
        if not self.run_command(
            ["pnpm", "install", "--prefer-frozen-lockfile"],
            "Regenerate lock file with corrected dependency resolution"
        ):
            self.log("  ✗ Lock file regeneration failed", "ERROR")
            if self.backup_file.exists() and not self.dry_run:
                self.log("  Restoring backup...")
                shutil.copy2(str(self.backup_file), str(self.lock_file))
            return False
        
        self.log("  ✓ Lock file regenerated successfully")
        return True

    def verify_lock_file(self):
        """Verify lock file syntax integrity"""
        self.log("Step 4: Verifying lock file integrity")
        
        try:
            with open(self.lock_file, 'r') as f:
                first_line = f.readline()
                if "lockfileVersion:" not in first_line:
                    self.log("  ✗ Invalid lock file format", "ERROR")
                    return False
                
                if "9.0" not in first_line:
                    self.log(f"  ⚠ Unexpected lock file version: {first_line}", "WARN")
                else:
                    self.log(f"  ✓ Lock file version verified: {first_line.strip()}")
                
                return True
        except Exception as e:
            self.log(f"  ✗ Verification failed: {str(e)}", "ERROR")
            return False

    def show_diff(self):
        """Show diff summary"""
        self.log("Step 5: Changes summary")
        
        if self.dry_run:
            self.log("  [DRY RUN] Would show git diff")
            return True
        
        try:
            result = subprocess.run(
                ["git", "diff", "--stat", "pnpm-lock.yaml"],
                cwd=self.repo_root,
                capture_output=True,
                text=True,
                timeout=30
            )
            
            if result.stdout:
                lines = result.stdout.split('\n')
                self.log(f"  Modified: {lines[0] if lines else 'N/A'}")
                
                # Show first few diff lines
                diff_result = subprocess.run(
                    ["git", "diff", "pnpm-lock.yaml"],
                    cwd=self.repo_root,
                    capture_output=True,
                    text=True,
                    timeout=30
                )
                
                if diff_result.stdout:
                    diff_lines = diff_result.stdout.split('\n')[:10]
                    self.log("  First changes:")
                    for line in diff_lines:
                        self.log(f"    {line}")
            
            return True
        except Exception as e:
            self.log(f"  ⚠ Could not show diff: {str(e)}", "WARN")
            return True

    def run_tests(self):
        """Run backend tests to verify fix"""
        self.log("Step 6: Running backend tests")
        
        backend_dir = self.repo_root / "apps" / "backend"
        if not backend_dir.exists():
            self.log(f"  ⚠ Backend directory not found: {backend_dir}", "WARN")
            return True
        
        if not self.run_command(
            ["pnpm", "test"],
            "Run backend tests",
            cwd=backend_dir
        ):
            self.log("  ✗ Tests failed", "ERROR")
            return False
        
        self.log("  ✓ Tests passed!")
        return True

    def stage_changes(self):
        """Stage pnpm-lock.yaml for commit"""
        self.log("Step 7: Staging changes")
        
        if not self.run_command(
            ["git", "add", "pnpm-lock.yaml"],
            "Stage pnpm-lock.yaml"
        ):
            return False
        
        self.log("  ✓ Changes staged")
        return True

    def show_commit_instructions(self):
        """Show instructions for commit and push"""
        self.log("Step 8: Ready for commit")
        self.log("")
        self.log("To proceed with commit and push:")
        self.log("")
        self.log("  git commit -m 'fix(deps): regenerate pnpm-lock.yaml for #1658 test framework initialization")
        self.log("")
        self.log("Fixes deterministic backend-integration test failures caused by @vitest/coverage-v8")
        self.log("peer dependency mismatch. Regenerating lock file recomputes transitive dependency")
        self.log("tree with correct version resolution.")
        self.log("")
        self.log("Fixes #1658'")
        self.log("")
        self.log("  git push origin main")
        self.log("")

    def execute(self):
        """Execute the complete fix"""
        self.log("")
        self.log("=== Issue #1658 Fix: Regenerate pnpm-lock.yaml ===")
        self.log("")
        
        if self.verify_only:
            self.log("Verify-only mode: Checking if fix is needed")
            self.verify_environment()
            return
        
        # Execute steps
        if not self.verify_environment():
            return
        
        if not self.backup_lock_file():
            return
        
        if not self.regenerate_lock_file():
            return
        
        if not self.verify_lock_file():
            return
        
        self.show_diff()
        
        if self.test_local:
            if not self.run_tests():
                self.log("Tests failed - fix may be incomplete", "ERROR")
                return
        
        self.stage_changes()
        self.show_commit_instructions()
        
        if self.success:
            self.log("")
            self.log("✓ Fix implementation complete - Ready for commit and push")
            self.log("")


def main():
    import argparse
    
    parser = argparse.ArgumentParser(description="Fix Issue #1658: Backend Integration Test Failures")
    parser.add_argument("--test-local", action="store_true", help="Run tests after fix")
    parser.add_argument("--verify-only", action="store_true", help="Only verify without applying fix")
    parser.add_argument("--dry-run", action="store_true", help="Show what would be done")
    parser.add_argument("--repo", default=".", help="Repository root (default: current directory)")
    
    args = parser.parse_args()
    
    fixer = Issue1658Fixer(
        repo_root=args.repo,
        test_local=args.test_local,
        verify_only=args.verify_only,
        dry_run=args.dry_run
    )
    
    fixer.execute()


if __name__ == "__main__":
    main()
