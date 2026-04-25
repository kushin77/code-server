"""
Multi-Region Database Hot State Replication - Prototype
@governance GOV-002: IaC, immutable, version-controlled
@description Replicates hot workspace state across geographic regions.
             Hot state includes: active session metadata, recent file changes,
             cursor positions, and collaboration presence data.
             Uses an async event-driven model with configurable conflict resolution.
"""

import hashlib
from datetime import datetime
from enum import Enum
from typing import Optional, Dict, Any, List
from pydantic import BaseModel, Field


class ReplicationStatus(str, Enum):
    """Status of a replication event"""
    PENDING = "pending"
    IN_FLIGHT = "in_flight"
    COMMITTED = "committed"
    FAILED = "failed"
    CONFLICTED = "conflicted"
    SKIPPED = "skipped"       # Skipped because replica already has newer version


class ConflictResolution(str, Enum):
    """Conflict resolution strategies"""
    LAST_WRITE_WINS = "last_write_wins"  # Most recent timestamp wins
    ORIGIN_WINS = "origin_wins"          # Primary region always wins
    VECTOR_CLOCK = "vector_clock"        # Logical clock ordering
    MANUAL = "manual"                    # Flag for human review


class HotStateType(str, Enum):
    """Types of hot state that are replicated"""
    SESSION_METADATA = "session_metadata"      # Active session info
    FILE_CHANGE = "file_change"                # Recent file edits
    CURSOR_POSITION = "cursor_position"        # Collaborative cursor state
    PRESENCE = "presence"                      # User online/offline state
    WORKSPACE_LOCK = "workspace_lock"          # File/resource locks
    EXTENSION_STATE = "extension_state"        # Extension runtime state


# TTL for hot state types (after which stale state is pruned)
HOT_STATE_TTL_SECONDS: Dict[HotStateType, int] = {
    HotStateType.SESSION_METADATA: 3600,    # 1 hour
    HotStateType.FILE_CHANGE: 300,          # 5 minutes
    HotStateType.CURSOR_POSITION: 30,       # 30 seconds
    HotStateType.PRESENCE: 60,              # 1 minute
    HotStateType.WORKSPACE_LOCK: 600,       # 10 minutes
    HotStateType.EXTENSION_STATE: 1800,     # 30 minutes
}


class VectorClock(BaseModel):
    """Logical clock for tracking causal ordering across regions"""
    clocks: Dict[str, int] = Field(default_factory=dict)  # region_id -> counter

    def increment(self, region_id: str) -> "VectorClock":
        """Return new clock with region counter incremented (immutable)"""
        new_clocks = dict(self.clocks)
        new_clocks[region_id] = new_clocks.get(region_id, 0) + 1
        return VectorClock(clocks=new_clocks)

    def merge(self, other: "VectorClock") -> "VectorClock":
        """Return clock that is the element-wise max of both (immutable)"""
        all_regions = set(self.clocks) | set(other.clocks)
        merged = {r: max(self.clocks.get(r, 0), other.clocks.get(r, 0)) for r in all_regions}
        return VectorClock(clocks=merged)

    def happens_before(self, other: "VectorClock") -> bool:
        """Returns True if self happened-before other (causal ordering)"""
        all_regions = set(self.clocks) | set(other.clocks)
        dominated = all(self.clocks.get(r, 0) <= other.clocks.get(r, 0) for r in all_regions)
        strictly_less = any(self.clocks.get(r, 0) < other.clocks.get(r, 0) for r in all_regions)
        return dominated and strictly_less


class HotStateRecord(BaseModel):
    """A single hot state record to be replicated"""
    record_id: str                # Unique record identifier
    state_type: HotStateType
    workspace_id: str
    key: str                      # State key within workspace (e.g. file path)
    payload: Dict[str, Any]       # State data (JSON-serializable)
    origin_region: str            # Region that originated this change
    vector_clock: VectorClock
    created_at: datetime = Field(default_factory=datetime.utcnow)
    checksum: str                 # SHA256 of payload for integrity

    @staticmethod
    def make_record_id(workspace_id: str, state_type: str, key: str) -> str:
        raw = f"{workspace_id}:{state_type}:{key}"
        return hashlib.sha256(raw.encode()).hexdigest()[:24]

    class Config:
        use_enum_values = True


class ReplicationEvent(BaseModel):
    """Event published when hot state changes and needs replication"""
    event_id: str
    record: HotStateRecord
    target_regions: List[str]     # Regions that must receive this update
    status: ReplicationStatus = ReplicationStatus.PENDING
    retry_count: int = 0
    max_retries: int = 3
    created_at: datetime = Field(default_factory=datetime.utcnow)
    completed_at: Optional[datetime] = None
    error: Optional[str] = None

    class Config:
        use_enum_values = True


class ReplicationAck(BaseModel):
    """Acknowledgment sent by a replica after applying a replication event"""
    event_id: str
    replica_region: str
    applied: bool
    conflict_detected: bool = False
    conflict_resolution: Optional[ConflictResolution] = None
    applied_at: datetime = Field(default_factory=datetime.utcnow)


class RegionReplicaState(BaseModel):
    """Tracks replication lag and health for a replica region"""
    region_id: str
    last_applied_event_id: Optional[str] = None
    last_applied_at: Optional[datetime] = None
    pending_events: int = 0
    replication_lag_ms: float = 0.0
    is_healthy: bool = True
    consecutive_failures: int = 0


class HotStateReplicationManager:
    """
    Manages hot state replication across geographic regions.

    Design:
    - Origin region writes state change → publishes ReplicationEvent
    - Target replicas receive event → apply or reject based on conflict resolution
    - Conflict resolution: LAST_WRITE_WINS for cursor/presence, VECTOR_CLOCK for file changes
    - Stale state pruned after per-type TTL
    """

    DEFAULT_CONFLICT_RESOLUTION: Dict[HotStateType, ConflictResolution] = {
        HotStateType.SESSION_METADATA: ConflictResolution.LAST_WRITE_WINS,
        HotStateType.FILE_CHANGE: ConflictResolution.VECTOR_CLOCK,
        HotStateType.CURSOR_POSITION: ConflictResolution.LAST_WRITE_WINS,
        HotStateType.PRESENCE: ConflictResolution.LAST_WRITE_WINS,
        HotStateType.WORKSPACE_LOCK: ConflictResolution.ORIGIN_WINS,
        HotStateType.EXTENSION_STATE: ConflictResolution.LAST_WRITE_WINS,
    }

    def __init__(self, local_region: str, target_regions: List[str]):
        self.local_region = local_region
        self.target_regions = target_regions
        self._local_state: Dict[str, HotStateRecord] = {}
        self._replica_states: Dict[str, RegionReplicaState] = {
            r: RegionReplicaState(region_id=r) for r in target_regions
        }
        self._pending_events: List[ReplicationEvent] = []
        self._event_counter = 0

    def publish_state_change(
        self,
        workspace_id: str,
        state_type: HotStateType,
        key: str,
        payload: Dict[str, Any],
    ) -> ReplicationEvent:
        """
        Record a local state change and create replication event.
        Call this when local state changes and must be propagated.
        """
        record_id = HotStateRecord.make_record_id(workspace_id, state_type, key)

        # Increment vector clock for this region
        existing = self._local_state.get(record_id)
        prev_clock = existing.vector_clock if existing else VectorClock()
        new_clock = prev_clock.increment(self.local_region)

        checksum = hashlib.sha256(
            str(sorted(payload.items())).encode()
        ).hexdigest()[:16]

        record = HotStateRecord(
            record_id=record_id,
            state_type=state_type,
            workspace_id=workspace_id,
            key=key,
            payload=payload,
            origin_region=self.local_region,
            vector_clock=new_clock,
            checksum=checksum,
        )

        self._local_state[record_id] = record

        self._event_counter += 1
        event = ReplicationEvent(
            event_id=f"{self.local_region}-{self._event_counter:08d}",
            record=record,
            target_regions=list(self.target_regions),
        )
        self._pending_events.append(event)
        return event

    def apply_remote_event(self, event: ReplicationEvent) -> ReplicationAck:
        """
        Apply an inbound replication event from another region.
        Resolves conflicts according to per-type policy.
        """
        record = event.record
        record_id = record.record_id
        state_type = HotStateType(record.state_type)
        resolution = self.DEFAULT_CONFLICT_RESOLUTION[state_type]

        existing = self._local_state.get(record_id)

        if existing is None:
            # No local record — apply unconditionally
            self._local_state[record_id] = record
            self._update_replica_state(record.origin_region, event.event_id)
            return ReplicationAck(
                event_id=event.event_id,
                replica_region=self.local_region,
                applied=True,
            )

        # Conflict check
        conflict = self._has_conflict(existing, record, resolution)

        if not conflict:
            # Remote is strictly newer — apply it
            merged_clock = existing.vector_clock.merge(record.vector_clock)
            applied_record = record.copy(update={"vector_clock": merged_clock})
            self._local_state[record_id] = applied_record
            self._update_replica_state(record.origin_region, event.event_id)
            return ReplicationAck(
                event_id=event.event_id,
                replica_region=self.local_region,
                applied=True,
            )

        # Conflict: resolve per policy
        winner = self._resolve_conflict(existing, record, resolution)
        merged_clock = existing.vector_clock.merge(record.vector_clock)
        resolved = winner.copy(update={"vector_clock": merged_clock})
        self._local_state[record_id] = resolved

        return ReplicationAck(
            event_id=event.event_id,
            replica_region=self.local_region,
            applied=True,
            conflict_detected=True,
            conflict_resolution=resolution,
        )

    def get_pending_events(self) -> List[ReplicationEvent]:
        """Return events not yet acknowledged by all targets"""
        return [e for e in self._pending_events if e.status == ReplicationStatus.PENDING]

    def acknowledge_event(self, ack: ReplicationAck):
        """Mark event as committed after receiving replica ack"""
        for event in self._pending_events:
            if event.event_id == ack.event_id:
                # Remove from target list; mark committed when all acked
                if ack.replica_region in event.target_regions:
                    event.target_regions.remove(ack.replica_region)
                if not event.target_regions:
                    event.status = ReplicationStatus.COMMITTED
                    event.completed_at = datetime.utcnow()
                break

    def get_state(self, workspace_id: str, state_type: HotStateType, key: str) -> Optional[HotStateRecord]:
        """Look up current hot state record"""
        record_id = HotStateRecord.make_record_id(workspace_id, state_type, key)
        record = self._local_state.get(record_id)
        if record is None:
            return None
        # Check TTL
        ttl = HOT_STATE_TTL_SECONDS[state_type]
        age = (datetime.utcnow() - record.created_at).total_seconds()
        return record if age < ttl else None

    def prune_stale_state(self) -> int:
        """Remove expired hot state records (run periodically)"""
        stale_keys = []
        for record_id, record in self._local_state.items():
            state_type = HotStateType(record.state_type)
            ttl = HOT_STATE_TTL_SECONDS[state_type]
            age = (datetime.utcnow() - record.created_at).total_seconds()
            if age >= ttl:
                stale_keys.append(record_id)
        for key in stale_keys:
            del self._local_state[key]
        return len(stale_keys)

    def get_replica_states(self) -> List[RegionReplicaState]:
        return list(self._replica_states.values())

    def _has_conflict(
        self,
        local: HotStateRecord,
        remote: HotStateRecord,
        resolution: ConflictResolution,
    ) -> bool:
        """Returns True if there is a genuine conflict requiring resolution"""
        if resolution == ConflictResolution.VECTOR_CLOCK:
            # Conflict if neither happened-before the other
            lb = local.vector_clock.happens_before(remote.vector_clock)
            rb = remote.vector_clock.happens_before(local.vector_clock)
            return not lb and not rb
        # For time-based strategies, conflict if timestamps are extremely close (<1ms)
        delta = abs((local.created_at - remote.created_at).total_seconds())
        return delta < 0.001

    def _resolve_conflict(
        self,
        local: HotStateRecord,
        remote: HotStateRecord,
        resolution: ConflictResolution,
    ) -> HotStateRecord:
        """Choose winner of conflicting records"""
        if resolution == ConflictResolution.LAST_WRITE_WINS:
            return remote if remote.created_at >= local.created_at else local
        if resolution == ConflictResolution.ORIGIN_WINS:
            return local if local.origin_region == self.local_region else remote
        # VECTOR_CLOCK: pick the one with higher sum of clock values as tiebreak
        local_sum = sum(local.vector_clock.clocks.values())
        remote_sum = sum(remote.vector_clock.clocks.values())
        return remote if remote_sum >= local_sum else local

    def _update_replica_state(self, region: str, event_id: str):
        if region in self._replica_states:
            state = self._replica_states[region]
            state.last_applied_event_id = event_id
            state.last_applied_at = datetime.utcnow()
