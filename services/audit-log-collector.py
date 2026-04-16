#!/usr/bin/env python3
###############################################################################
# AUDIT LOG COLLECTOR - Centralized Event Logging System
# Issue #183: Comprehensive audit logging for compliance
#
# Collects events from all sources (IDE, terminal, git, network, admin)
# and writes to multiple sinks with search/query capability.
#
# Architecture:
#   Event Sources → Log Collector → Multi-Sink Output
#   - Local JSON lines file (audit.jsonl)
#   - Syslog for system integration
#   - Indexed database for fast queries
#
###############################################################################

import json
import logging
import os
import sys
import time
import socket
from datetime import datetime
from pathlib import Path
from typing import Dict, Any, Optional, List
from dataclasses import dataclass, asdict
from enum import Enum
import sqlite3
from pythonjsonlogger import jsonlogger

###############################################################################
# CONFIGURATION
###############################################################################

AUDIT_LOG_DIR = os.environ.get('AUDIT_LOG_DIR', os.path.expanduser('~/.code-server-developers/logs'))
AUDIT_LOG_FILE = os.path.join(AUDIT_LOG_DIR, 'audit.jsonl')
AUDIT_DB_FILE = os.path.join(AUDIT_LOG_DIR, 'audit.db')

os.makedirs(AUDIT_LOG_DIR, exist_ok=True)

# Logging configuration
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler(os.path.join(AUDIT_LOG_DIR, 'collector.log'))
    ]
)
logger = logging.getLogger(__name__)

###############################################################################
# EVENT TYPES & ENUMS
###############################################################################

class EventType(Enum):
    # Session events
    SESSION_START = "SESSION_START"
    SESSION_END = "SESSION_END"
    SESSION_TIMEOUT_WARNING = "SESSION_TIMEOUT_WARNING"
    
    # Authentication events
    AUTH_SUCCESS = "AUTH_SUCCESS"
    AUTH_FAILURE = "AUTH_FAILURE"
    AUTH_INVALID_TOKEN = "AUTH_INVALID_TOKEN"
    
    # Terminal/Shell events
    SHELL_CMD = "SHELL_CMD"
    SHELL_OUTPUT = "SHELL_OUTPUT"
    SHELL_BLOCKED = "SHELL_BLOCKED"
    SHELL_VIOLATION = "SHELL_VIOLATION"
    
    # IDE/File events
    FILE_OPEN = "FILE_OPEN"
    FILE_READ = "FILE_READ"
    FILE_WRITE_ATTEMPT = "FILE_WRITE_ATTEMPT"
    FILE_DELETE_ATTEMPT = "FILE_DELETE_ATTEMPT"
    FILE_SEARCH = "FILE_SEARCH"
    FILE_DOWNLOAD_ATTEMPT = "FILE_DOWNLOAD_ATTEMPT"
    
    # Git events
    GIT_COMMAND = "GIT_COMMAND"
    GIT_PUSH = "GIT_PUSH"
    GIT_PULL = "GIT_PULL"
    GIT_CLONE = "GIT_CLONE"
    GIT_VIOLATION = "GIT_VIOLATION"
    
    # Network events
    TUNNEL_INGRESS = "TUNNEL_INGRESS"
    TUNNEL_EGRESS = "TUNNEL_EGRESS"
    LATENCY_MEASUREMENT = "LATENCY_MEASUREMENT"
    
    # Admin events
    ADMIN_GRANT = "ADMIN_GRANT"
    ADMIN_REVOKE = "ADMIN_REVOKE"
    ADMIN_EXTEND = "ADMIN_EXTEND"
    
    # Security events
    SECURITY_ALERT = "SECURITY_ALERT"
    RATE_LIMIT_EXCEEDED = "RATE_LIMIT_EXCEEDED"

class AccessType(Enum):
    READ = "READ"
    WRITE = "WRITE"
    EXECUTE = "EXECUTE"
    DELETE = "DELETE"

###############################################################################
# EVENT DATACLASS
###############################################################################

@dataclass
class AuditEvent:
    timestamp: str
    event_type: str
    developer_id: str
    ip_address: Optional[str] = None
    
    # Context information
    session_id: Optional[str] = None
    component: Optional[str] = None  # IDE, Terminal, Git, Network, Admin
    
    # Detailed event information
    details: Dict[str, Any] = None
    
    # Status information
    status: str = "success"  # success, blocked, denied, error
    reason: Optional[str] = None
    
    # Metadata
    hostname: Optional[str] = None
    user_agent: Optional[str] = None

###############################################################################
# AUDIT LOG COLLECTOR CLASS
###############################################################################

class AuditLogCollector:
    """Centralized audit log collection and storage"""
    
    def __init__(self):
        self.log_file = AUDIT_LOG_FILE
        self.db_file = AUDIT_DB_FILE
        self._init_database()
        self._setup_json_logging()
    
    def _init_database(self):
        """Initialize SQLite database for indexed searching"""
        conn = sqlite3.connect(self.db_file)
        cursor = conn.cursor()
        
        # Create audit events table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS audit_events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT NOT NULL,
                event_type TEXT NOT NULL,
                developer_id TEXT NOT NULL,
                ip_address TEXT,
                session_id TEXT,
                component TEXT,
                status TEXT,
                reason TEXT,
                details TEXT,
                hostname TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        
        # Create indexes for fast queries
        cursor.execute('CREATE INDEX IF NOT EXISTS idx_timestamp ON audit_events(timestamp)')
        cursor.execute('CREATE INDEX IF NOT EXISTS idx_developer_id ON audit_events(developer_id)')
        cursor.execute('CREATE INDEX IF NOT EXISTS idx_event_type ON audit_events(event_type)')
        cursor.execute('CREATE INDEX IF NOT EXISTS idx_status ON audit_events(status)')
        cursor.execute('CREATE INDEX IF NOT EXISTS idx_component ON audit_events(component)')
        
        conn.commit()
        conn.close()
        
        logger.info(f"Database initialized: {self.db_file}")
    
    def _setup_json_logging(self):
        """Setup JSON logging to file"""
        file_handler = logging.FileHandler(self.log_file)
        formatter = jsonlogger.JsonFormatter(
            '%(timestamp)s %(event_type)s %(developer_id)s %(status)s'
        )
        file_handler.setFormatter(formatter)
        
        json_logger = logging.getLogger('audit_json')
        json_logger.addHandler(file_handler)
        json_logger.setLevel(logging.INFO)
        
        self.json_logger = json_logger
    
    def log_event(self, event: AuditEvent) -> None:
        """Log an audit event to all sinks"""
        
        # Add hostname if not present
        if not event.hostname:
            event.hostname = socket.gethostname()
        
        # Write to JSON lines file
        event_dict = asdict(event)
        event_dict['details'] = json.dumps(event.details) if event.details else None
        
        with open(self.log_file, 'a') as f:
            f.write(json.dumps(event_dict) + '\n')
        
        # Write to database for indexing
        self._write_to_db(event)
        
        # Write to syslog
        self._write_to_syslog(event)
        
        logger.info(f"Event logged: {event.event_type} by {event.developer_id}")
    
    def _write_to_db(self, event: AuditEvent) -> None:
        """Write event to SQLite database"""
        conn = sqlite3.connect(self.db_file)
        cursor = conn.cursor()
        
        cursor.execute('''
            INSERT INTO audit_events (
                timestamp, event_type, developer_id, ip_address, session_id,
                component, status, reason, details, hostname
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            event.timestamp,
            event.event_type,
            event.developer_id,
            event.ip_address,
            event.session_id,
            event.component,
            event.status,
            event.reason,
            json.dumps(event.details) if event.details else None,
            event.hostname
        ))
        
        conn.commit()
        conn.close()
    
    def _write_to_syslog(self, event: AuditEvent) -> None:
        """Write event to syslog for system integration"""
        import syslog
        
        message = f"{event.event_type}: {event.developer_id} - {event.status}"
        if event.reason:
            message += f" ({event.reason})"
        
        try:
            syslog.syslog(syslog.LOG_AUDIT, message)
        except Exception as e:
            logger.error(f"Failed to write to syslog: {e}")
    
    def query_events(
        self,
        developer_id: Optional[str] = None,
        event_type: Optional[str] = None,
        start_time: Optional[str] = None,
        end_time: Optional[str] = None,
        status: Optional[str] = None,
        limit: int = 100
    ) -> List[Dict[str, Any]]:
        """Query audit events from database"""
        
        try:
            with sqlite3.connect(self.db_file) as conn:
                conn.row_factory = sqlite3.Row
                cursor = conn.cursor()
                
                query = "SELECT * FROM audit_events WHERE 1=1"
                params = []
                
                if developer_id:
                    query += " AND developer_id = ?"
                    params.append(developer_id)
                
                if event_type:
                    query += " AND event_type = ?"
                    params.append(event_type)
                
                if start_time:
                    query += " AND timestamp >= ?"
                    params.append(start_time)
                
                if end_time:
                    query += " AND timestamp <= ?"
                    params.append(end_time)
                
                if status:
                    query += " AND status = ?"
                    params.append(status)
                
                query += " ORDER BY timestamp DESC LIMIT ?"
                params.append(limit)
                
                cursor.execute(query, params)
                results = [dict(row) for row in cursor.fetchall()]
                
            return results
        except sqlite3.Error as e:
            logger.error(f"Database error querying audit events: {e}")
            return []
    
    def get_compliance_summary(
        self,
        developer_id: str,
        days: int = 7
    ) -> Dict[str, Any]:
        """Generate compliance summary for a developer"""
        
        try:
            with sqlite3.connect(self.db_file) as conn:
                conn.row_factory = sqlite3.Row
                
                # Calculate start time
                start_timestamp = datetime.now()
                start_timestamp = start_timestamp.replace(hour=0, minute=0, second=0, microsecond=0)
                start_time = start_timestamp.isoformat()
                
                # Get events
                events = self.query_events(
                    developer_id=developer_id,
                    start_time=start_time,
                    limit=10000
                )
                
                # Calculate statistics
                total_events = len(events)
                blocked_events = sum(1 for e in events if e['status'] == 'blocked')
                violations = sum(1 for e in events if e['status'] == 'denied')
                
                event_types = {}
                for event in events:
                    event_type = event['event_type']
                    event_types[event_type] = event_types.get(event_type, 0) + 1
                
                return {
                    'developer_id': developer_id,
                    'period_days': days,
                    'total_events': total_events,
                    'blocked_events': blocked_events,
                    'violations': violations,
                    'event_types': event_types,
                    'compliance_score': 100 - (violations * 5),  # 5 points per violation
                    'status': 'compliant' if violations == 0 else 'violations_detected'
                }
        except sqlite3.Error as e:
            logger.error(f"Database error in compliance summary: {e}")
            return {
                'developer_id': developer_id,
                'period_days': days,
                'error': str(e),
                'status': 'error'
            }

###############################################################################
# GLOBAL COLLECTOR INSTANCE
###############################################################################

_collector = None

def get_collector() -> AuditLogCollector:
    """Get or create the global audit log collector"""
    global _collector
    if _collector is None:
        _collector = AuditLogCollector()
    return _collector

###############################################################################
# CONVENIENCE FUNCTIONS
###############################################################################

def log_session_start(developer_id: str, ip_address: str, browser: str = None) -> None:
    """Log a session start event"""
    event = AuditEvent(
        timestamp=datetime.utcnow().isoformat(),
        event_type=EventType.SESSION_START.value,
        developer_id=developer_id,
        ip_address=ip_address,
        component="Session",
        details={'browser': browser} if browser else {},
        status="success"
    )
    get_collector().log_event(event)

def log_shell_command(developer_id: str, cwd: str, command: str, blocked: bool = False) -> None:
    """Log a shell command execution"""
    event_type = EventType.SHELL_BLOCKED.value if blocked else EventType.SHELL_CMD.value
    status = "blocked" if blocked else "success"
    
    event = AuditEvent(
        timestamp=datetime.utcnow().isoformat(),
        event_type=event_type,
        developer_id=developer_id,
        component="Terminal",
        details={'cwd': cwd, 'command': command},
        status=status
    )
    get_collector().log_event(event)

def log_file_access(developer_id: str, file_path: str, access_type: str) -> None:
    """Log file access event"""
    access_map = {
        'read': EventType.FILE_READ.value,
        'write': EventType.FILE_WRITE_ATTEMPT.value,
        'delete': EventType.FILE_DELETE_ATTEMPT.value,
        'download': EventType.FILE_DOWNLOAD_ATTEMPT.value
    }
    
    event_type = access_map.get(access_type, EventType.FILE_READ.value)
    
    event = AuditEvent(
        timestamp=datetime.utcnow().isoformat(),
        event_type=event_type,
        developer_id=developer_id,
        component="IDE",
        details={'file': file_path, 'access_type': access_type},
        status="success"
    )
    get_collector().log_event(event)

def log_git_operation(developer_id: str, operation: str, repo: str, branch: str = None, status: str = "success") -> None:
    """Log git operation"""
    git_ops = {
        'push': EventType.GIT_PUSH.value,
        'pull': EventType.GIT_PULL.value,
        'clone': EventType.GIT_CLONE.value,
    }
    
    event_type = git_ops.get(operation, EventType.GIT_COMMAND.value)
    
    event = AuditEvent(
        timestamp=datetime.utcnow().isoformat(),
        event_type=event_type,
        developer_id=developer_id,
        component="Git",
        details={'operation': operation, 'repo': repo, 'branch': branch},
        status=status
    )
    get_collector().log_event(event)

def log_admin_action(admin_id: str, action: str, developer_id: str, duration_days: int = None) -> None:
    """Log admin action"""
    action_map = {
        'grant': EventType.ADMIN_GRANT.value,
        'revoke': EventType.ADMIN_REVOKE.value,
        'extend': EventType.ADMIN_EXTEND.value,
    }
    
    event_type = action_map.get(action, EventType.ADMIN_GRANT.value)
    
    event = AuditEvent(
        timestamp=datetime.utcnow().isoformat(),
        event_type=event_type,
        developer_id=admin_id,
        component="Admin",
        details={'action': action, 'target_developer': developer_id, 'duration_days': duration_days},
        status="success"
    )
    get_collector().log_event(event)

###############################################################################
# MAIN
###############################################################################

if __name__ == "__main__":
    # Test the audit logger
    collector = get_collector()
    
    # Log some test events
    log_session_start("alice@example.com", "203.0.113.45", "Chrome 125.0")
    log_shell_command("alice@example.com", "/home/dev/code", "ls -la")
    log_file_access("alice@example.com", "src/main.py", "read")
    log_git_operation("alice@example.com", "push", "code-server", "feature-x", "success")
    log_admin_action("admin@home.local", "grant", "alice@example.com", 7)
    
    # Query events
    events = collector.query_events(developer_id="alice@example.com", limit=10)
    print(f"Found {len(events)} events for alice@example.com")
    
    # Get compliance summary
    summary = collector.get_compliance_summary("alice@example.com", days=7)
    print(f"Compliance score: {summary['compliance_score']}")
