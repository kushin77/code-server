"""
crypto_asset_inventory.py — Phase 54: Cryptographic Asset Inventory & Key Lifecycle Management
Maintains a full inventory of cryptographic assets (keys, certificates, secrets, tokens),
tracks lifecycle states, detects expiry/rotation violations, and produces a gate score.
"""
from __future__ import annotations

import json
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from enum import Enum
from typing import Dict, List, Optional


# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------


class AssetType(Enum):
    SYMMETRIC_KEY    = "symmetric_key"
    ASYMMETRIC_KEY   = "asymmetric_key"
    CERTIFICATE      = "certificate"
    SECRET           = "secret"
    API_TOKEN        = "api_token"
    SSH_KEY          = "ssh_key"
    TLS_CERT         = "tls_cert"
    SIGNING_KEY      = "signing_key"


class AssetStatus(Enum):
    ACTIVE      = "active"
    EXPIRING    = "expiring"     # within rotation_warning_days
    EXPIRED     = "expired"
    REVOKED     = "revoked"
    PENDING     = "pending"      # created, not yet activated
    ROTATED     = "rotated"      # superseded by a newer asset


class RiskLevel(Enum):
    CRITICAL = "critical"   # expired or revoked-in-use
    HIGH     = "high"       # expiring within 7 days
    MEDIUM   = "medium"     # expiring within 30 days
    LOW      = "low"        # healthy
    NONE     = "none"       # not applicable (pending/revoked)


class RotationPolicy(Enum):
    DAILY      = "daily"
    WEEKLY     = "weekly"
    MONTHLY    = "monthly"
    QUARTERLY  = "quarterly"
    ANNUAL     = "annual"
    NEVER      = "never"


# ---------------------------------------------------------------------------
# Rotation policy → days
# ---------------------------------------------------------------------------

_POLICY_DAYS: Dict[str, int] = {
    RotationPolicy.DAILY.value:     1,
    RotationPolicy.WEEKLY.value:    7,
    RotationPolicy.MONTHLY.value:   30,
    RotationPolicy.QUARTERLY.value: 90,
    RotationPolicy.ANNUAL.value:    365,
    RotationPolicy.NEVER.value:     99_999,
}


# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------


@dataclass
class CryptoAsset:
    """
    A single cryptographic asset tracked in the inventory.
    created_at / expires_at / last_rotated: naive UTC datetimes.
    """
    asset_id: str = field(default_factory=lambda: str(uuid.uuid4())[:12])
    name: str = ""
    asset_type: AssetType = AssetType.SECRET
    owner: str = ""                      # service / team owning the asset
    rotation_policy: RotationPolicy = RotationPolicy.MONTHLY
    created_at: datetime = field(default_factory=datetime.utcnow)
    expires_at: Optional[datetime] = None
    last_rotated: Optional[datetime] = None
    status: AssetStatus = AssetStatus.ACTIVE
    tags: List[str] = field(default_factory=list)
    metadata: Dict = field(default_factory=dict)
    # rotation_warning_days: how many days before expiry we flag EXPIRING
    rotation_warning_days: int = 30

    # ------------------------------------------------------------------ #

    def days_until_expiry(self, now: Optional[datetime] = None) -> Optional[int]:
        if self.expires_at is None:
            return None
        ref = now or datetime.utcnow()
        return (self.expires_at - ref).days

    def days_since_last_rotation(self, now: Optional[datetime] = None) -> Optional[int]:
        if self.last_rotated is None:
            return None
        ref = now or datetime.utcnow()
        return (ref - self.last_rotated).days

    def is_overdue_for_rotation(self, now: Optional[datetime] = None) -> bool:
        if self.rotation_policy == RotationPolicy.NEVER:
            return False
        policy_days = _POLICY_DAYS[self.rotation_policy.value]
        days_since = self.days_since_last_rotation(now)
        if days_since is None:
            # Never rotated — use created_at as baseline
            ref = now or datetime.utcnow()
            days_since = (ref - self.created_at).days
        return days_since > policy_days

    def compute_status(self, now: Optional[datetime] = None) -> AssetStatus:
        """Derive live status from current datetime."""
        if self.status == AssetStatus.REVOKED:
            return AssetStatus.REVOKED
        if self.status == AssetStatus.ROTATED:
            return AssetStatus.ROTATED
        ref = now or datetime.utcnow()
        due = self.days_until_expiry(ref)
        if due is not None:
            if due <= 0:
                return AssetStatus.EXPIRED
            if due <= self.rotation_warning_days:
                return AssetStatus.EXPIRING
        return AssetStatus.ACTIVE

    def risk_level(self, now: Optional[datetime] = None) -> RiskLevel:
        status = self.compute_status(now)
        if status in (AssetStatus.EXPIRED, AssetStatus.REVOKED):
            return RiskLevel.CRITICAL
        due = self.days_until_expiry(now)
        if status == AssetStatus.EXPIRING:
            if due is not None and due <= 7:
                return RiskLevel.HIGH
            return RiskLevel.MEDIUM
        if status in (AssetStatus.ROTATED, AssetStatus.PENDING):
            return RiskLevel.NONE
        return RiskLevel.LOW

    def rotate(self, now: Optional[datetime] = None) -> None:
        """Record a rotation event: update last_rotated, push expiry forward."""
        ref = now or datetime.utcnow()
        self.last_rotated = ref
        if self.rotation_policy != RotationPolicy.NEVER:
            policy_days = _POLICY_DAYS[self.rotation_policy.value]
            self.expires_at = ref + timedelta(days=policy_days)
        self.status = AssetStatus.ACTIVE

    def revoke(self) -> None:
        self.status = AssetStatus.REVOKED

    def to_dict(self) -> dict:
        return {
            "asset_id": self.asset_id,
            "name": self.name,
            "asset_type": self.asset_type.value,
            "owner": self.owner,
            "rotation_policy": self.rotation_policy.value,
            "status": self.status.value,
            "live_status": self.compute_status().value,
            "risk_level": self.risk_level().value,
            "days_until_expiry": self.days_until_expiry(),
            "is_overdue_for_rotation": self.is_overdue_for_rotation(),
            "created_at": self.created_at.isoformat(),
            "expires_at": self.expires_at.isoformat() if self.expires_at else None,
            "last_rotated": self.last_rotated.isoformat() if self.last_rotated else None,
            "tags": self.tags,
        }


@dataclass
class RotationEvent:
    """Audit log entry for a rotation or revocation."""
    event_id: str = field(default_factory=lambda: str(uuid.uuid4())[:10])
    asset_id: str = ""
    asset_name: str = ""
    event_type: str = "rotation"    # "rotation" | "revocation" | "creation" | "expiry"
    triggered_by: str = "system"
    occurred_at: datetime = field(default_factory=datetime.utcnow)
    notes: str = ""

    def to_dict(self) -> dict:
        return {
            "event_id": self.event_id,
            "asset_id": self.asset_id,
            "asset_name": self.asset_name,
            "event_type": self.event_type,
            "triggered_by": self.triggered_by,
            "occurred_at": self.occurred_at.isoformat(),
            "notes": self.notes,
        }


@dataclass
class InventoryReport:
    """Snapshot of the full asset inventory with risk summary."""
    report_id: str = field(default_factory=lambda: str(uuid.uuid4())[:10])
    generated_at: datetime = field(default_factory=datetime.utcnow)
    total_assets: int = 0
    active: int = 0
    expiring: int = 0
    expired: int = 0
    revoked: int = 0
    overdue_for_rotation: int = 0
    risk_breakdown: Dict[str, int] = field(default_factory=dict)
    assets: List[dict] = field(default_factory=list)
    events: List[dict] = field(default_factory=list)

    def phase54_score(self) -> float:
        """
        Gate contribution 0-25.
        Starts at 25; deducts:
          - CRITICAL risk: 4 pts each (expired/revoked-in-use)
          - HIGH risk:     2 pts each (expiring ≤ 7d)
          - MEDIUM risk:   1 pt  each (expiring ≤ 30d)
          - overdue rotation: 1 pt each (capped at 5)
        Floor at 0.
        """
        if self.total_assets == 0:
            return 25.0
        deductions = (
            self.risk_breakdown.get("critical", 0) * 4
            + self.risk_breakdown.get("high", 0) * 2
            + self.risk_breakdown.get("medium", 0) * 1
            + min(self.overdue_for_rotation, 5)
        )
        return max(0.0, round(25.0 - deductions, 2))

    def to_dict(self) -> dict:
        return {
            "report_id": self.report_id,
            "generated_at": self.generated_at.isoformat(),
            "total_assets": self.total_assets,
            "active": self.active,
            "expiring": self.expiring,
            "expired": self.expired,
            "revoked": self.revoked,
            "overdue_for_rotation": self.overdue_for_rotation,
            "risk_breakdown": self.risk_breakdown,
            "phase54_score": self.phase54_score(),
            "assets": self.assets,
            "events": self.events,
        }


# ---------------------------------------------------------------------------
# Core engine
# ---------------------------------------------------------------------------


class CryptoAssetInventoryEngine:
    """
    Phase 54 — Cryptographic Asset Inventory & Key Lifecycle Management.

    Workflow:
      1. register_asset()        — add an asset to inventory
      2. rotate_asset()          — record a rotation, push expiry
      3. revoke_asset()          — mark asset revoked
      4. scan()                  — update live statuses, detect violations
      5. generate_report()       — full InventoryReport with score
      6. phase54_score()         — gate contribution (0-25)
      7. summary() / persist_state()
    """

    def __init__(self) -> None:
        self._assets: Dict[str, CryptoAsset] = {}
        self._events: List[RotationEvent] = []

    # ---- Asset registration -----------------------------------------------

    def register_asset(self, asset: CryptoAsset) -> CryptoAsset:
        self._assets[asset.asset_id] = asset
        self._log_event(asset, "creation", notes="Asset registered in inventory")
        return asset

    def get_asset(self, asset_id: str) -> Optional[CryptoAsset]:
        return self._assets.get(asset_id)

    def assets(self) -> List[CryptoAsset]:
        return list(self._assets.values())

    def asset_count(self) -> int:
        return len(self._assets)

    # ---- Lifecycle actions ------------------------------------------------

    def rotate_asset(
        self,
        asset_id: str,
        triggered_by: str = "system",
        now: Optional[datetime] = None,
    ) -> bool:
        asset = self._assets.get(asset_id)
        if not asset or asset.status == AssetStatus.REVOKED:
            return False
        asset.rotate(now)
        self._log_event(asset, "rotation", triggered_by=triggered_by,
                        notes=f"Rotated; next expiry: {asset.expires_at}")
        return True

    def revoke_asset(self, asset_id: str, triggered_by: str = "system") -> bool:
        asset = self._assets.get(asset_id)
        if not asset:
            return False
        asset.revoke()
        self._log_event(asset, "revocation", triggered_by=triggered_by,
                        notes="Asset revoked")
        return True

    def rotate_overdue_assets(
        self,
        triggered_by: str = "auto-rotation",
        now: Optional[datetime] = None,
    ) -> int:
        """Rotate all assets that are overdue per their rotation policy."""
        count = 0
        for asset in self._assets.values():
            if asset.status != AssetStatus.REVOKED and asset.is_overdue_for_rotation(now):
                asset.rotate(now)
                self._log_event(asset, "rotation", triggered_by=triggered_by,
                                notes="Auto-rotation triggered by policy enforcement")
                count += 1
        return count

    # ---- Scan & analysis --------------------------------------------------

    def scan(self, now: Optional[datetime] = None) -> Dict[str, int]:
        """
        Evaluate live status of all assets.
        Returns summary counts.
        """
        counts: Dict[str, int] = {
            "active": 0, "expiring": 0, "expired": 0,
            "revoked": 0, "pending": 0, "rotated": 0, "overdue": 0,
        }
        for asset in self._assets.values():
            live = asset.compute_status(now)
            status_key = live.value
            if status_key in counts:
                counts[status_key] += 1
            if asset.is_overdue_for_rotation(now):
                counts["overdue"] += 1
            if live == AssetStatus.EXPIRED:
                self._log_event(asset, "expiry", notes="Asset detected as expired during scan")
        return counts

    def assets_by_risk(self, now: Optional[datetime] = None) -> Dict[str, List[CryptoAsset]]:
        result: Dict[str, List[CryptoAsset]] = {lvl.value: [] for lvl in RiskLevel}
        for asset in self._assets.values():
            result[asset.risk_level(now).value].append(asset)
        return result

    def expiring_soon(self, days: int = 30, now: Optional[datetime] = None) -> List[CryptoAsset]:
        """Return assets expiring within `days` days."""
        ref = now or datetime.utcnow()
        result = []
        for asset in self._assets.values():
            due = asset.days_until_expiry(ref)
            if due is not None and 0 < due <= days:
                result.append(asset)
        return sorted(result, key=lambda a: a.days_until_expiry(ref) or 0)

    def expired_assets(self, now: Optional[datetime] = None) -> List[CryptoAsset]:
        return [a for a in self._assets.values() if a.compute_status(now) == AssetStatus.EXPIRED]

    def overdue_assets(self, now: Optional[datetime] = None) -> List[CryptoAsset]:
        return [a for a in self._assets.values() if a.is_overdue_for_rotation(now)]

    # ---- Scoring ----------------------------------------------------------

    def phase54_score(self, now: Optional[datetime] = None) -> float:
        """Gate contribution 0-25 derived from risk breakdown."""
        report = self.generate_report(now)
        return report.phase54_score()

    # ---- Reporting --------------------------------------------------------

    def generate_report(self, now: Optional[datetime] = None) -> InventoryReport:
        by_risk = self.assets_by_risk(now)
        scan_counts = self.scan(now)
        report = InventoryReport(
            total_assets=len(self._assets),
            active=scan_counts["active"],
            expiring=scan_counts["expiring"],
            expired=scan_counts["expired"],
            revoked=scan_counts["revoked"],
            overdue_for_rotation=scan_counts["overdue"],
            risk_breakdown={k: len(v) for k, v in by_risk.items() if v},
            assets=[a.to_dict() for a in self._assets.values()],
            events=[e.to_dict() for e in self._events[-50:]],
        )
        return report

    def summary(self) -> dict:
        report = self.generate_report()
        return {
            "status": "ok" if self._assets else "no_assets",
            "total_assets": report.total_assets,
            "active": report.active,
            "expiring": report.expiring,
            "expired": report.expired,
            "revoked": report.revoked,
            "overdue_for_rotation": report.overdue_for_rotation,
            "risk_breakdown": report.risk_breakdown,
            "total_events": len(self._events),
            "phase54_score": report.phase54_score(),
        }

    def persist_state(
        self, output_path: str = "artifacts/phase54/crypto-inventory.json"
    ) -> str:
        import os
        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        state = {
            "phase": 54,
            "engine": "CryptoAssetInventoryEngine",
            "exported_at": datetime.utcnow().isoformat(),
            "summary": self.summary(),
            "assets": [a.to_dict() for a in self._assets.values()],
            "events": [e.to_dict() for e in self._events],
        }
        with open(output_path, "w") as f:
            json.dump(state, f, indent=2)
        return output_path

    # ---- Internal ---------------------------------------------------------

    def _log_event(
        self,
        asset: CryptoAsset,
        event_type: str,
        triggered_by: str = "system",
        notes: str = "",
    ) -> RotationEvent:
        ev = RotationEvent(
            asset_id=asset.asset_id,
            asset_name=asset.name,
            event_type=event_type,
            triggered_by=triggered_by,
            notes=notes,
        )
        self._events.append(ev)
        return ev

    def events(self) -> List[RotationEvent]:
        return list(self._events)


# ---------------------------------------------------------------------------
# Helper factory
# ---------------------------------------------------------------------------


def make_asset(
    name: str,
    asset_type: AssetType = AssetType.SECRET,
    owner: str = "platform",
    rotation_policy: RotationPolicy = RotationPolicy.MONTHLY,
    expires_in_days: Optional[int] = 30,
    last_rotated_days_ago: Optional[int] = None,
    rotation_warning_days: int = 7,
) -> CryptoAsset:
    now = datetime.utcnow()
    expires_at = now + timedelta(days=expires_in_days) if expires_in_days is not None else None
    last_rotated = now - timedelta(days=last_rotated_days_ago) if last_rotated_days_ago is not None else None
    return CryptoAsset(
        name=name,
        asset_type=asset_type,
        owner=owner,
        rotation_policy=rotation_policy,
        expires_at=expires_at,
        last_rotated=last_rotated,
        rotation_warning_days=rotation_warning_days,
    )
