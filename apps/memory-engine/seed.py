#!/usr/bin/env python3
# @file apps/memory-engine/seed.py
# @module infrastructure/memory-engine
# @description P3-1562 Phase 2: Seed Qdrant with historical incident data and runbooks
# @governance GOV-002: Historical seeding ensures organizational memory is comprehensive

import json
import os
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Any
import hashlib

from qdrant_client import QdrantMemoryClient, MemoryDocument
from embedder import OllamaEmbedder

from apps._shared.python.config import get_config

from apps._shared.python.logging import get_logger

logger = get_logger(__name__)


class OrganizationalMemorySeeder:
    """Seed Qdrant vector database with historical data"""

    def __init__(self, repo_root: str = "."):
        self.repo_root = Path(repo_root)
        config = get_config()
        self.qdrant_host = config.get("QDRANT_HOST", "localhost")
        self.qdrant_port = config.get_int("QDRANT_PORT", 6333)
        self.ollama_host = config.get("OLLAMA_HOST", "http://ollama:11434")
        self.seed_log = self.repo_root / "artifacts/seeding-log.jsonl"
        self.seed_log.parent.mkdir(parents=True, exist_ok=True)

        self._qdrant = QdrantMemoryClient(host=self.qdrant_host, port=self.qdrant_port)
        self._embedder = OllamaEmbedder(
            ollama_host=self.ollama_host,
            model=config.get("EMBED_MODEL", "nomic-embed-text"),
        )

    def _log_entry(self, action: str, status: str, details: Dict[str, Any]):
        """Log seeding action"""
        entry = {
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "action": action,
            "status": status,
            **details,
        }
        with open(self.seed_log, "a") as f:
            f.write(json.dumps(entry) + "\n")
        logger.info(f"[{entry['timestamp']}] {action}: {status}")

    def _embed_and_store(self, collection: str, title: str, content: str, source_url: str = None, tags: List[str] = None) -> bool:
        """Embed text and store in Qdrant. Returns True on success."""
        embedding = self._embedder.generate_embedding(f"{title}\n\n{content}")
        if not embedding:
            return False
        doc = MemoryDocument(
            id=MemoryDocument.generate_id(content),
            title=title,
            content=content[:2000],  # store summary slice
            collection=collection,
            source_url=source_url,
            tags=tags or [],
            embedding=embedding,
        )
        return self._qdrant.store_document(collection, doc)

    def seed_github_incidents(self) -> int:
        """Ingest GitHub issues labeled as incidents via GitHub API."""
        self._log_entry("github_incidents_seed", "started", {})
        import urllib.request, urllib.error

        config = get_config()
        repo = config.get("GITHUB_REPO", "kushin77/code-server")
        token = config.get("GITHUB_TOKEN", "")
        count = 0
        try:
            page = 1
            while True:
                url = (
                    f"https://api.github.com/repos/{repo}/issues"
                    f"?state=closed&labels=incident,P0&per_page=50&page={page}"
                )
                req = urllib.request.Request(url)
                req.add_header("Accept", "application/vnd.github.v3+json")
                if token:
                    req.add_header("Authorization", f"token {token}")
                try:
                    with urllib.request.urlopen(req, timeout=15) as resp:
                        issues = json.loads(resp.read())
                except urllib.error.URLError:
                    break  # offline — skip gracefully
                if not issues:
                    break
                for issue in issues:
                    body = (issue.get("body") or "").strip()
                    if not body:
                        continue
                    ok = self._embed_and_store(
                        collection="incidents",
                        title=issue.get("title", "Untitled incident"),
                        content=body,
                        source_url=issue.get("html_url"),
                        tags=["github-issue", "incident"],
                    )
                    if ok:
                        count += 1
                page += 1
        except Exception as e:
            self._log_entry("github_incidents_seed", "error", {"error": str(e)})

        self._log_entry("github_incidents_seed", "completed", {"count": count})
        return count

    def seed_runbooks(self) -> int:
        """Ingest runbook markdown files from docs/runbooks/."""
        self._log_entry("runbooks_seed", "started", {})

        runbook_dir = self.repo_root / "docs/runbooks"
        if not runbook_dir.exists():
            self._log_entry("runbooks_seed", "skipped", {"reason": "runbook_dir_not_found"})
            return 0

        count = 0
        for runbook_file in runbook_dir.glob("**/*.md"):
            try:
                content = runbook_file.read_text(encoding="utf-8", errors="ignore")
                ok = self._embed_and_store(
                    collection="runbooks",
                    title=runbook_file.stem.replace("-", " ").replace("_", " "),
                    content=content,
                    tags=["runbook"],
                )
                if ok:
                    count += 1
            except Exception as e:
                logger.error(f"processing {runbook_file}: {e}")

        self._log_entry("runbooks_seed", "completed", {"count": count})
        return count

    def seed_pr_descriptions(self) -> int:
        """Ingest recent PR descriptions from GitHub API."""
        self._log_entry("pr_descriptions_seed", "started", {})
        import urllib.request, urllib.error

        config = get_config()
        repo = config.get("GITHUB_REPO", "kushin77/code-server")
        token = config.get("GITHUB_TOKEN", "")
        count = 0
        try:
            page = 1
            while page <= 5:  # cap at 250 PRs (5 pages × 50)
                url = (
                    f"https://api.github.com/repos/{repo}/pulls"
                    f"?state=closed&per_page=50&page={page}"
                )
                req = urllib.request.Request(url)
                req.add_header("Accept", "application/vnd.github.v3+json")
                if token:
                    req.add_header("Authorization", f"token {token}")
                try:
                    with urllib.request.urlopen(req, timeout=15) as resp:
                        prs = json.loads(resp.read())
                except urllib.error.URLError:
                    break
                if not prs:
                    break
                for pr in prs:
                    body = (pr.get("body") or "").strip()
                    if not body:
                        continue
                    ok = self._embed_and_store(
                        collection="pr_descriptions",
                        title=pr.get("title", "Untitled PR"),
                        content=body,
                        source_url=pr.get("html_url"),
                        tags=["pull-request"],
                    )
                    if ok:
                        count += 1
                page += 1
        except Exception as e:
            self._log_entry("pr_descriptions_seed", "error", {"error": str(e)})

        self._log_entry("pr_descriptions_seed", "completed", {"count": count})
        return count

    def seed_session_documents(self) -> int:
        """Ingest session completion documents from artifacts/."""
        self._log_entry("session_docs_seed", "started", {})

        artifacts_dir = self.repo_root / "artifacts"
        if not artifacts_dir.exists():
            self._log_entry("session_docs_seed", "skipped", {"reason": "artifacts_dir_not_found"})
            return 0

        count = 0
        for doc_file in list(artifacts_dir.glob("*SESSION*.md")) + list(artifacts_dir.glob("*FINAL*.md")):
            try:
                content = doc_file.read_text(encoding="utf-8", errors="ignore")
                ok = self._embed_and_store(
                    collection="retrospectives",
                    title=doc_file.stem.replace("-", " "),
                    content=content,
                    tags=["session-doc", "retrospective"],
                )
                if ok:
                    count += 1
            except Exception as e:
                logger.error(f"processing {doc_file}: {e}")

        self._log_entry("session_docs_seed", "completed", {"count": count})
        return count

    def verify_collections(self) -> bool:
        """Ensure all required Qdrant collections exist."""
        self._log_entry("collection_verification", "started", {})

        collections = [
            "incidents",
            "runbooks",
            "pr_descriptions",
            "retrospectives",
            "agent_learnings",
        ]

        for collection in collections:
            try:
                self._qdrant.ensure_collection(collection)
            except Exception as e:
                self._log_entry("collection_verification", "error", {"collection": collection, "error": str(e)})
                return False

        self._log_entry("collection_verification", "completed", {"collections": collections})
        return True

    def generate_seeding_report(self, total: int = 0) -> Dict[str, Any]:
        """Generate seeding completion report"""
        report = {
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "status": "completed",
            "seeding_log": str(self.seed_log),
            "collections_initialized": 5,
            "total_documents_seeded": total,
        }

        report_file = self.repo_root / "artifacts/seeding-report.json"
        with open(report_file, "w") as f:
            json.dump(report, f, indent=2)

        return report

    def run_full_seeding(self) -> Dict[str, Any]:
        """Execute complete seeding pipeline"""
        logger.info("\n=== Organizational Memory Seeding ===")

        # Ensure collections exist in Qdrant
        if not self.verify_collections():
            logger.info("ERROR: Qdrant collections not initialized")
            return {"status": "failed", "reason": "collections_not_found"}

        # Seed data sources
        incident_count = self.seed_github_incidents()
        runbook_count = self.seed_runbooks()
        pr_count = self.seed_pr_descriptions()
        session_count = self.seed_session_documents()

        total = incident_count + runbook_count + pr_count + session_count

        report = self.generate_seeding_report(total=total)
        report["total_documents_seeded"] = total

        logger.info(f"\n=== Seeding Complete ===")
        logger.info(f"Total documents seeded: {total}")
        logger.info(f"Report: {report}")

        return report


if __name__ == "__main__":
    import sys

    repo_root = sys.argv[1] if len(sys.argv) > 1 else "."
    seeder = OrganizationalMemorySeeder(repo_root)
    result = seeder.run_full_seeding()
    sys.exit(0 if result.get("status") == "completed" else 1)
