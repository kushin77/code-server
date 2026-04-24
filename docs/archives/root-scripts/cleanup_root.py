#!/usr/bin/env python3
import os
import shutil
import glob

# Configuration
ROOT_DIR = "."
ARCHIVE_BASE = "docs/archives"

DIRS = {
    "root-markdowns": os.path.join(ARCHIVE_BASE, "root-markdowns"),
    "root-scripts": os.path.join(ARCHIVE_BASE, "root-scripts"),
    "temporary-data": os.path.join(ARCHIVE_BASE, "temporary-data"),
    "logs": os.path.join(ARCHIVE_BASE, "logs"),
    "obsolete-specs": os.path.join(ARCHIVE_BASE, "obsolete-specs"),
}

PROTECTED_FILES = {
    "README.md", "LICENSE", "CONFIG-SSOT-MASTER.md", 
    "DEDUPLICATION-AND-EFFICIENCY-ANALYSIS.md", "copilot-instructions.md",
    "Makefile", "Caddyfile", "docker-compose.yml", "package.json", 
    "tsconfig.json", "pnpm-lock.yaml", "variables.tf", "main.tf",
    "pnpm-workspace.yaml", "Dockerfile"
}

PROTECTED_PATTERNS = [
    ".env*", ".git*", "Makefile.*", "Caddyfile", "docker-compose.yml", "tsconfig.json", "package.json", "pnpm-lock.yaml", "variables.tf", "main.tf"
]

def is_protected(filename):
    if filename in PROTECTED_FILES:
        return True
    if filename.startswith(".env"):
        return True
    if filename.startswith(".git"):
        return True
    # Specific exceptions for orchestration
    if filename == "Caddyfile": return True
    if filename == "docker-compose.yml": return True
    return False

def ensure_dirs():
    for d in DIRS.values():
        if not os.path.exists(d):
            os.makedirs(d)
            print(f"Created {d}")

def move_files():
    files = [f for f in os.listdir(ROOT_DIR) if os.path.isfile(os.path.join(ROOT_DIR, f))]
    
    for f in files:
        if is_protected(f):
            continue
            
        src = os.path.join(ROOT_DIR, f)
        dest = None
        
        # 1. Markdown files
        if f.endswith(".md") and f not in PROTECTED_FILES:
            dest = DIRS["root-markdowns"]
            
        # 2. Scripts
        elif (f.endswith(".sh") or f.endswith(".py")) and f not in PROTECTED_FILES:
            if f != "cleanup_root.py": # Don't move ourselves yet
                dest = DIRS["root-scripts"]
                
        # 3. Temporary data
        elif any(f.startswith(p) for p in ["targets", "epic-", "policy-"]) and f.endswith(".json"):
            dest = DIRS["temporary-data"]
            
        # 4. Logs
        elif f.endswith(".log"):
            dest = DIRS["logs"]
            
        # 5. Obsolete configs
        elif f.startswith("Caddyfile.") or f.startswith("docker-compose.") or f.startswith("oidc-signing-key.") or f == "oauth2-proxy.cfg" or f.endswith(".tpl"):
             # Caddyfile and docker-compose.yml are already filtered by is_protected if they are the main ones
             dest = DIRS["obsolete-specs"]

        if dest:
            print(f"Moving {f} to {dest}")
            shutil.move(src, os.path.join(dest, f))

if __name__ == "__main__":
    ensure_dirs()
    move_files()
