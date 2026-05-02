"""
threat_intelligence_correlation.py — Phase 54: Threat Intelligence Correlation Engine
Enriches phase-score signals with threat intelligence context, correlates
Indicators of Compromise (IOCs) across multiple feed sources, and produces
a prioritized threat feed for downstream Phase 52/53 orchestration.
"""
from __future__ import annotations

import hashlib
import uuid
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Callable, Dict, List, Optional, Set, Tuple


# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------


class IOCType(Enum):
    IP           = "ip"
    DOMAIN       = "domain"
    HASH_MD5     = "hash_md5"
    HASH_SHA256  = "hash_sha256"
    URL          = "url"
    CVE          = "cve"
    RULE_SID     = "rule_sid"


class FeedConfidence(Enum):
    HIGH   = "high"    # ≥ 0.80
    MEDIUM = "medium"  # ≥ 0.50
    LOW    = "low"     # < 0.50


class ThreatCategory(Enum):
    MALWARE     = "malware"
    PHISHING    = "phishing"
    RANSOMWARE  = "ransomware"
    APT         = "apt"
    BOTNET      = "botnet"
    VULNERABILITY = "vulnerability"
    POLICY      = "policy"
    UNKNOWN     = "unknown"


class CorrelationStrength(Enum):
    CONFIRMED  = "confirmed"    # same IOC in 3+ feeds
    PROBABLE   = "probable"     # same IOC in 2 feeds
    CANDIDATE  = "candidate"    # single-feed IOC


# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------


@dataclass
class IOCRecord:
    """A single Indicator of Compromise entry from a feed."""
    ioc_id: str
    ioc_type: IOCType
    value: str
    source_feed: str
    confidence: float          # 0.0-1.0
    category: ThreatCategory = ThreatCategory.UNKNOWN
    tags: List[str] = field(default_factory=list)
    first_seen: datetime = field(default_factory=datetime.utcnow)
    last_seen: datetime = field(default_factory=datetime.utcnow)

    @property
    def feed_confidence(self) -> FeedConfidence:
        if self.confidence >= 0.80:
            return FeedConfidence.HIGH
        if self.confidence >= 0.50:
            return FeedConfidence.MEDIUM
        return FeedConfidence.LOW

    @property
    def normalized_key(self) -> str:
        """Canonical key for correlation across feeds."""
        return f"{self.ioc_type.value}:{self.value.strip().lower()}"


@dataclass
class CorrelatedThreat:
    """
    Result of correlating the same IOC across multiple feed sources.
    Strength reflects how many independent sources confirmed the IOC.
    """
    threat_id: str
    normalized_key: str
    ioc_type: IOCType
    value: str
    sources: List[str]          # feed names that reported this IOC
    records: List[IOCRecord]    # original records
    category: ThreatCategory = ThreatCategory.UNKNOWN
    strength: CorrelationStrength = CorrelationStrength.CANDIDATE
    max_confidence: float = 0.0
    tags: List[str] = field(default_factory=list)
    correlated_at: datetime = field(default_factory=datetime.utcnow)

    @property
    def priority_score(self) -> float:
        """
        Priority score 0-25 (higher = more urgent).
        Combines source count, confidence, and strength.
        """
        source_factor = min(len(self.sources) / 3.0, 1.0)  # up to 3 sources max
        strength_map = {
            CorrelationStrength.CONFIRMED: 1.0,
            CorrelationStrength.PROBABLE:  0.67,
            CorrelationStrength.CANDIDATE: 0.33,
        }
        strength_factor = strength_map[self.strength]
        raw = (source_factor * 0.4 + self.max_confidence * 0.4 + strength_factor * 0.2)
        return round(raw * 25.0, 2)

    @property
    def phase54_contribution(self) -> float:
        """Inverted priority — high-priority threats reduce this score (0-25)."""
        return round(25.0 - self.priority_score, 2)


@dataclass
class ThreatFeedSnapshot:
    """Point-in-time snapshot of correlated threat intelligence."""
    snapshot_id: str
    total_iocs: int
    correlated_threats: List[CorrelatedThreat]
    phase54_score: float
    generated_at: datetime = field(default_factory=datetime.utcnow)

    @property
    def confirmed_count(self) -> int:
        return sum(1 for t in self.correlated_threats
                   if t.strength == CorrelationStrength.CONFIRMED)

    @property
    def high_priority_count(self) -> int:
        return sum(1 for t in self.correlated_threats if t.priority_score >= 18.0)


# ---------------------------------------------------------------------------
# Feed source definition
# ---------------------------------------------------------------------------


@dataclass
class FeedSource:
    """Registered threat intelligence feed."""
    name: str
    base_confidence: float   # default confidence for this feed
    categories: List[ThreatCategory] = field(default_factory=list)
    enabled: bool = True
    loader: Optional[Callable[[], List[IOCRecord]]] = field(default=None, repr=False)


# ---------------------------------------------------------------------------
# Threat Intelligence Correlation Engine
# ---------------------------------------------------------------------------


class ThreatIntelligenceCorrelationEngine:
    """
    Phase 54 — Threat Intelligence Correlation Engine.

    Ingests IOCRecords from multiple feed sources, correlates them by
    normalized_key, scores correlated threats, and generates a snapshot
    with phase54_score() gate contribution (0-25).
    """

    def __init__(self) -> None:
        self.feeds: Dict[str, FeedSource] = {}
        self.ioc_store: List[IOCRecord] = []
        # normalized_key → list of records
        self._index: Dict[str, List[IOCRecord]] = {}

    # --- Feed management ---

    def register_feed(self, feed: FeedSource) -> None:
        self.feeds[feed.name] = feed

    def unregister_feed(self, name: str) -> None:
        self.feeds.pop(name, None)

    # --- IOC ingestion ---

    def ingest(self, record: IOCRecord) -> None:
        """Ingest a single IOCRecord into the store and update the index."""
        self.ioc_store.append(record)
        key = record.normalized_key
        self._index.setdefault(key, []).append(record)

    def ingest_batch(self, records: List[IOCRecord]) -> int:
        """Ingest multiple IOCRecords. Returns count ingested."""
        for record in records:
            self.ingest(record)
        return len(records)

    def load_feed(self, feed_name: str) -> int:
        """Invoke the loader of a registered feed and ingest results."""
        feed = self.feeds.get(feed_name)
        if feed is None or feed.loader is None:
            return 0
        records = feed.loader()
        return self.ingest_batch(records)

    # --- Correlation ---

    def correlate(self) -> List[CorrelatedThreat]:
        """
        Correlate all ingested IOCs by normalized_key.
        Returns a list of CorrelatedThreat objects sorted by priority (desc).
        """
        threats: List[CorrelatedThreat] = []
        for key, records in self._index.items():
            sources = list({r.source_feed for r in records})
            max_conf = max(r.confidence for r in records)
            # pick most frequent category
            cat_votes: Dict[ThreatCategory, int] = {}
            for r in records:
                cat_votes[r.category] = cat_votes.get(r.category, 0) + 1
            category = max(cat_votes, key=cat_votes.__getitem__)
            # strength
            n = len(sources)
            if n >= 3:
                strength = CorrelationStrength.CONFIRMED
            elif n == 2:
                strength = CorrelationStrength.PROBABLE
            else:
                strength = CorrelationStrength.CANDIDATE
            # aggregate tags
            all_tags: List[str] = []
            seen: Set[str] = set()
            for r in records:
                for t in r.tags:
                    if t not in seen:
                        seen.add(t)
                        all_tags.append(t)
            first_record = records[0]
            threat = CorrelatedThreat(
                threat_id=f"thr-{uuid.uuid4().hex[:8]}",
                normalized_key=key,
                ioc_type=first_record.ioc_type,
                value=first_record.value.strip().lower(),
                sources=sources,
                records=records,
                category=category,
                strength=strength,
                max_confidence=round(max_conf, 4),
                tags=all_tags,
            )
            threats.append(threat)
        threats.sort(key=lambda t: t.priority_score, reverse=True)
        return threats

    # --- Snapshot generation ---

    def snapshot(self) -> ThreatFeedSnapshot:
        """Correlate and produce a snapshot with phase54_score."""
        threats = self.correlate()
        score = self.phase54_score(threats)
        return ThreatFeedSnapshot(
            snapshot_id=f"snap-{uuid.uuid4().hex[:8]}",
            total_iocs=len(self.ioc_store),
            correlated_threats=threats,
            phase54_score=score,
        )

    # --- Scoring ---

    def phase54_score(self, threats: Optional[List[CorrelatedThreat]] = None) -> float:
        """
        Gate score (0-25).
        = 25 × (1 − high_priority_ratio), where high_priority_ratio
          is the fraction of correlated threats with priority_score ≥ 18.
        With no threats → 25.0 (clean state).
        """
        if threats is None:
            threats = self.correlate()
        if not threats:
            return 25.0
        high = sum(1 for t in threats if t.priority_score >= 18.0)
        ratio = high / len(threats)
        return round((1.0 - ratio) * 25.0, 2)

    # --- Lookup ---

    def lookup(self, ioc_type: IOCType, value: str) -> Optional[CorrelatedThreat]:
        """Look up a correlated threat for a specific IOC value."""
        key = f"{ioc_type.value}:{value.strip().lower()}"
        records = self._index.get(key)
        if not records:
            return None
        # Build on-demand
        sources = list({r.source_feed for r in records})
        max_conf = max(r.confidence for r in records)
        n = len(sources)
        strength = (CorrelationStrength.CONFIRMED if n >= 3
                    else CorrelationStrength.PROBABLE if n == 2
                    else CorrelationStrength.CANDIDATE)
        return CorrelatedThreat(
            threat_id=f"thr-{uuid.uuid4().hex[:8]}",
            normalized_key=key,
            ioc_type=records[0].ioc_type,
            value=value.strip().lower(),
            sources=sources,
            records=records,
            category=records[0].category,
            strength=strength,
            max_confidence=round(max_conf, 4),
        )

    # --- Summary ---

    def summary(self) -> Dict:
        threats = self.correlate()
        confirmed = sum(1 for t in threats if t.strength == CorrelationStrength.CONFIRMED)
        probable  = sum(1 for t in threats if t.strength == CorrelationStrength.PROBABLE)
        candidate = sum(1 for t in threats if t.strength == CorrelationStrength.CANDIDATE)
        return {
            "total_iocs": len(self.ioc_store),
            "registered_feeds": len(self.feeds),
            "unique_threats": len(threats),
            "confirmed": confirmed,
            "probable":  probable,
            "candidate": candidate,
            "high_priority": sum(1 for t in threats if t.priority_score >= 18.0),
            "phase54_score": self.phase54_score(threats),
        }


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def make_ioc(
    ioc_type: IOCType,
    value: str,
    source_feed: str,
    confidence: float = 0.80,
    category: ThreatCategory = ThreatCategory.UNKNOWN,
    tags: Optional[List[str]] = None,
) -> IOCRecord:
    return IOCRecord(
        ioc_id=f"ioc-{uuid.uuid4().hex[:8]}",
        ioc_type=ioc_type,
        value=value,
        source_feed=source_feed,
        confidence=confidence,
        category=category,
        tags=tags or [],
    )


def intel_score(engine: ThreatIntelligenceCorrelationEngine) -> float:
    """Return phase54_score (0-25)."""
    return engine.phase54_score()
