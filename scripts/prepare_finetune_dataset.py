#!/usr/bin/env python3
"""
Prepare fine-tuning dataset from git commit history.
Outputs JSONL suitable for instruction-tuning (task + response pairs).
Usage: python3 scripts/prepare_finetune_dataset.py [--repo-path .] [--out finetune_data.jsonl]
"""
import argparse, json, subprocess, sys
from pathlib import Path

def get_commits(repo: str, max_commits: int = 500) -> list[dict]:
    result = subprocess.run(
        ["git", "log", f"--max-count={max_commits}", "--format=%H||%s||%b"],
        capture_output=True, text=True, cwd=repo
    )
    commits = []
    for line in result.stdout.strip().split("\n"):
        parts = line.split("||", 2)
        if len(parts) >= 2:
            commits.append({"hash": parts[0], "subject": parts[1], "body": parts[2] if len(parts) > 2 else ""})
    return commits

def get_diff(repo: str, commit_hash: str) -> str:
    result = subprocess.run(
        ["git", "show", "--stat", "--unified=3", commit_hash],
        capture_output=True, text=True, cwd=repo
    )
    return result.stdout[:4096]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-path", default=".", help="Path to git repo")
    parser.add_argument("--out", default="finetune_data.jsonl", help="Output JSONL file")
    parser.add_argument("--max-commits", type=int, default=200)
    args = parser.parse_args()

    commits = get_commits(args.repo_path, args.max_commits)
    print(f"Found {len(commits)} commits", file=sys.stderr)

    out = Path(args.out)
    written = 0
    with out.open("w", encoding="utf-8") as f:
        for c in commits:
            if not c["subject"].strip():
                continue
            diff = get_diff(args.repo_path, c["hash"])
            if not diff.strip():
                continue
            record = {
                "instruction": "Describe what the following code change does and why.",
                "input": diff,
                "output": f"{c['subject']}\n\n{c['body']}".strip(),
            }
            f.write(json.dumps(record, ensure_ascii=False) + "\n")
            written += 1

    print(f"Written {written} records to {out}", file=sys.stderr)

if __name__ == "__main__":
    main()
