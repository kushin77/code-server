#!/usr/bin/env python3
# @file apps/extensions/shared-clipboard/storage.py
# @module ide/shared-clipboard
# @description P3-1080 Phase 2: SQLite storage for clipboard history
# @governance GOV-002: All clipboard state immutable and versioned

import sqlite3
import json
from datetime import datetime, timedelta
from typing import List, Optional, Dict, Any
from pathlib import Path
import logging
import hashlib

from apps._shared.python.logging import get_logger

logger = get_logger(__name__)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class ClipboardStorage:
    """SQLite backend for clipboard history persistence"""
    
    def __init__(self, db_path: str):
        self.db_path = db_path
        self.conn = None
        self._init_db()
    
    def _init_db(self):
        """Initialize database schema (idempotent)"""
        Path(self.db_path).parent.mkdir(parents=True, exist_ok=True)
        self.conn = sqlite3.connect(self.db_path)
        self.conn.row_factory = sqlite3.Row
        
        cursor = self.conn.cursor()
        
        # Check if tables already exist
        cursor.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='clipboard_entries'"
        )
        if cursor.fetchone():
            logger.info("Database already initialized")
            return
        
        # Create main clipboard table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS clipboard_entries (
                id TEXT PRIMARY KEY,
                content TEXT NOT NULL,
                timestamp TEXT NOT NULL,
                user_id TEXT NOT NULL,
                file_name TEXT,
                language TEXT,
                tags TEXT,
                shared BOOLEAN DEFAULT 0,
                shared_with TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                content_hash TEXT NOT NULL UNIQUE
            )
        """)
        
        # Create index for efficient queries
        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_clipboard_user_time
            ON clipboard_entries(user_id, timestamp DESC)
        """)
        
        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_clipboard_shared
            ON clipboard_entries(shared, timestamp DESC)
        """)
        
        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_clipboard_tags
            ON clipboard_entries(tags)
        """)
        
        # Create audit log table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS clipboard_audit (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                clip_id TEXT NOT NULL,
                action TEXT NOT NULL,
                user_id TEXT NOT NULL,
                timestamp TEXT NOT NULL,
                changes TEXT,
                FOREIGN KEY (clip_id) REFERENCES clipboard_entries(id)
            )
        """)
        
        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_audit_clip_id
            ON clipboard_audit(clip_id, timestamp DESC)
        """)
        
        self.conn.commit()
        logger.info(f"Initialized clipboard database at {self.db_path}")
    
    def add_entry(
        self,
        content: str,
        user_id: str,
        file_name: Optional[str] = None,
        language: Optional[str] = None,
        tags: Optional[List[str]] = None
    ) -> str:
        """Add a clipboard entry (idempotent via content hash)"""
        entry_id = self._generate_id()
        now = datetime.utcnow().isoformat() + "Z"
        
        # Calculate content hash to prevent duplicates
        content_hash = hashlib.sha256(content.encode()).hexdigest()
        
        # Check if identical content already exists (deduplication)
        cursor = self.conn.cursor()
        cursor.execute(
            "SELECT id FROM clipboard_entries WHERE content_hash = ?",
            (content_hash,)
        )
        existing = cursor.fetchone()
        if existing:
            logger.info(f"Content already exists: {existing['id']}")
            return existing['id']
        
        tags_json = json.dumps(tags or [])
        
        cursor.execute("""
            INSERT INTO clipboard_entries
            (id, content, timestamp, user_id, file_name, language, tags, 
             created_at, updated_at, content_hash)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            entry_id, content, now, user_id, file_name, language,
            tags_json, now, now, content_hash
        ))
        
        # Log audit event
        self._log_audit(entry_id, "created", user_id, None)
        
        self.conn.commit()
        logger.info(f"Added clipboard entry: {entry_id}")
        
        return entry_id
    
    def get_entries(
        self,
        user_id: Optional[str] = None,
        shared_only: bool = False,
        tags: Optional[List[str]] = None,
        limit: int = 50,
        offset: int = 0
    ) -> List[Dict[str, Any]]:
        """Retrieve clipboard entries with filtering"""
        cursor = self.conn.cursor()
        
        query = "SELECT * FROM clipboard_entries WHERE 1=1"
        params = []
        
        if user_id:
            query += " AND user_id = ?"
            params.append(user_id)
        
        if shared_only:
            query += " AND shared = 1"
        
        query += " ORDER BY timestamp DESC LIMIT ? OFFSET ?"
        params.extend([limit, offset])
        
        cursor.execute(query, params)
        rows = cursor.fetchall()
        
        entries = []
        for row in rows:
            entry = dict(row)
            entry['tags'] = json.loads(entry['tags'] or '[]')
            
            # Filter by tags if specified
            if tags and not any(t in entry['tags'] for t in tags):
                continue
            
            entries.append(entry)
        
        return entries
    
    def get_entry_by_id(self, entry_id: str) -> Optional[Dict[str, Any]]:
        """Get specific clipboard entry by ID"""
        cursor = self.conn.cursor()
        cursor.execute("SELECT * FROM clipboard_entries WHERE id = ?", (entry_id,))
        row = cursor.fetchone()
        
        if not row:
            return None
        
        entry = dict(row)
        entry['tags'] = json.loads(entry['tags'] or '[]')
        return entry
    
    def share_entry(self, entry_id: str, shared_with: List[str]) -> bool:
        """Mark entry as shared with specific users"""
        cursor = self.conn.cursor()
        now = datetime.utcnow().isoformat() + "Z"
        
        shared_json = json.dumps(shared_with)
        cursor.execute("""
            UPDATE clipboard_entries
            SET shared = 1, shared_with = ?, updated_at = ?
            WHERE id = ?
        """, (shared_json, now, entry_id))
        
        # Get user who owns this entry
        cursor.execute("SELECT user_id FROM clipboard_entries WHERE id = ?", (entry_id,))
        row = cursor.fetchone()
        if row:
            self._log_audit(entry_id, "shared", row['user_id'], {"shared_with": shared_with})
        
        self.conn.commit()
        return cursor.rowcount > 0
    
    def delete_entry(self, entry_id: str, user_id: str) -> bool:
        """Delete clipboard entry (immutable: marks as deleted, not purged)"""
        cursor = self.conn.cursor()
        
        # Verify ownership
        cursor.execute("SELECT user_id FROM clipboard_entries WHERE id = ?", (entry_id,))
        row = cursor.fetchone()
        if not row or row['user_id'] != user_id:
            logger.warning(f"Unauthorized delete attempt on {entry_id}")
            return False
        
        # Mark as deleted (soft delete for auditability)
        now = datetime.utcnow().isoformat() + "Z"
        cursor.execute("""
            UPDATE clipboard_entries
            SET content = '', updated_at = ?
            WHERE id = ?
        """, (now, entry_id))
        
        self._log_audit(entry_id, "deleted", user_id, None)
        self.conn.commit()
        return cursor.rowcount > 0
    
    def add_tags(self, entry_id: str, new_tags: List[str]) -> bool:
        """Add tags to clipboard entry"""
        entry = self.get_entry_by_id(entry_id)
        if not entry:
            return False
        
        # Merge tags
        merged_tags = list(set(entry['tags'] + new_tags))
        
        cursor = self.conn.cursor()
        now = datetime.utcnow().isoformat() + "Z"
        
        cursor.execute("""
            UPDATE clipboard_entries
            SET tags = ?, updated_at = ?
            WHERE id = ?
        """, (json.dumps(merged_tags), now, entry_id))
        
        self._log_audit(entry_id, "tags_added", entry['user_id'], {"tags": new_tags})
        self.conn.commit()
        return cursor.rowcount > 0
    
    def search(self, query: str, user_id: Optional[str] = None, limit: int = 50) -> List[Dict[str, Any]]:
        """Full-text search across clipboard content"""
        cursor = self.conn.cursor()
        
        search_query = "%" + query + "%"
        sql = "SELECT * FROM clipboard_entries WHERE content LIKE ?"
        params = [search_query]
        
        if user_id:
            sql += " AND (user_id = ? OR shared = 1)"
            params.append(user_id)
        
        sql += " ORDER BY timestamp DESC LIMIT ?"
        params.append(limit)
        
        cursor.execute(sql, params)
        rows = cursor.fetchall()
        
        entries = []
        for row in rows:
            entry = dict(row)
            entry['tags'] = json.loads(entry['tags'] or '[]')
            entries.append(entry)
        
        return entries
    
    def get_audit_log(self, entry_id: str) -> List[Dict[str, Any]]:
        """Get audit trail for clipboard entry"""
        cursor = self.conn.cursor()
        cursor.execute("""
            SELECT id, clip_id, action, user_id, timestamp, changes
            FROM clipboard_audit
            WHERE clip_id = ?
            ORDER BY timestamp DESC
        """, (entry_id,))
        
        return [dict(row) for row in cursor.fetchall()]
    
    def cleanup_old_entries(self, days: int = 90):
        """Clean up entries older than specified days (idempotent)"""
        cutoff = (datetime.utcnow() - timedelta(days=days)).isoformat() + "Z"
        
        cursor = self.conn.cursor()
        cursor.execute("""
            UPDATE clipboard_entries
            SET content = ''
            WHERE timestamp < ? AND shared = 0
        """, (cutoff,))
        
        self.conn.commit()
        logger.info(f"Cleaned up entries older than {days} days: {cursor.rowcount} rows")
    
    def _generate_id(self) -> str:
        """Generate unique entry ID"""
        import uuid
        return f"clip-{uuid.uuid4().hex[:12]}"
    
    def _log_audit(
        self,
        clip_id: str,
        action: str,
        user_id: str,
        changes: Optional[Dict[str, Any]]
    ):
        """Log audit event for clipboard operation"""
        cursor = self.conn.cursor()
        now = datetime.utcnow().isoformat() + "Z"
        changes_json = json.dumps(changes) if changes else None
        
        cursor.execute("""
            INSERT INTO clipboard_audit (clip_id, action, user_id, timestamp, changes)
            VALUES (?, ?, ?, ?, ?)
        """, (clip_id, action, user_id, now, changes_json))

if __name__ == "__main__":
    storage = ClipboardStorage("/tmp/clipboard.db")
    
    # Test
    logger.info("\n=== Clipboard Storage Tests ===")
    
    clip1 = storage.add_entry(
        content="def hello():\n    logger.info('Hello, world!')",
        user_id="user-123",
        language="python",
        tags=["function", "example"]
    )
    logger.info(f"\n1. Added entry: {clip1}")
    
    clip2 = storage.add_entry(
        content="SELECT * FROM users WHERE active = true",
        user_id="user-456",
        language="sql",
        tags=["query"]
    )
    logger.info(f"2. Added entry: {clip2}")
    
    # Retrieve
    entries = storage.get_entries(limit=10)
    logger.info(f"\n3. Retrieved {len(entries)} entries")
    
    # Share
    storage.share_entry(clip1, ["user-456"])
    logger.info(f"4. Shared entry {clip1}")
    
    # Search
    results = storage.search("hello", limit=10)
    logger.info(f"5. Search found {len(results)} results")
    
    # Audit
    audit = storage.get_audit_log(clip1)
    logger.info(f"6. Audit trail: {len(audit)} events")
