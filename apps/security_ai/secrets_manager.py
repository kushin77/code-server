"""
secrets_manager.py — Phase 58: Secrets Management & Credential Rotation Engine
Tracks secrets (API keys, certificates, DB passwords, tokens) with rotation
policies, expiry enforcement, access auditing, and a gate scoring function.
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


class SecretType(Enum):
    API_KEY          = "api_key"
    DATABASE_PASSWORD = "database_password"
    TLS_CERTIFICATE  = "tls_certificate"
    SSH_KEY          = "ssh_key"
    SERVICE_TOKEN    = "service_token"
    ENCRYPTION_KEY   = "encryption_key"
    OAUTH_SECRET     = "oauth_secret"


class SecretStatus(Enum):
    ACTIVE    = "active"
    EXPIRING  = "expiring"    # within rotation_warning_days of expiry
    EXPIRED   = "expired"
    ROTATED   = "rotated"
    REVOKED   = "revoked"


class RotationPolicy(Enum):
    DAILY      = "daily"
    WEEKLY     = "weekly"
    MONTHLY    = "monthly"
    QUARTERLY  = "quarterly"
    ANNUALLY   = "annually"
    MANUAL     = "manual"


class AccessOutcome(Enum):
    GRANTED  = "granted"
    DENIED   = "denied"
    ROTATED  = "rotated"


class RiskLevel(Enum):
    CRITICAL = "critical"
    HIGH     = "high"
    MEDIUM   = "medium"
    LOW      = "low"
    NONE     = "none"


# ---------------------------------------------------------------------------
# Rotation policy → TTL in days
# ---------------------------------------------------------------------------

_POLICY_DAYS: Dict[str, int] = {
    RotationPolicy.DAILY.value:     1,
    RotationPolicy.WEEKLY.value:    7,
    RotationPolicy.MONTHLY.value:   30,
    RotationPolicy.QUARTERLY.value: 90,
    RotationPolicy.ANNUALLY.value:  365,
    RotationPolicy.MANUAL.value:    -1,   # never auto-expiry
}

_WARNING_DAYS = 7   # warn when within 7 days of expiry


# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------


@dataclass
class Secret:
    """A tracked secret/credential."""
    secret_id: str = field(default_factory=lambda: str(uuid.uuid4())[:12])
    name: str = ""
    secret_type: SecretType = SecretType.SERVICE_TOKEN
    rotation_policy: RotationPolicy = RotationPolicy.MONTHLY
    owner_service: str = ""
    environment: str = "production"
    is_encrypted_at_rest: bool = True
    created_at: datetime = field(default_factory=datetime.utcnow)
    last_rotated_at: datetime = field(default_factory=datetime.utcnow)
    rotated_count: int = 0
    tags: List[str] = field(default_factory=list)
    _revoked: bool = False

    @property
    def ttl_days(self) -> int:
        return _POLICY_DAYS.get(self.rotation_policy.value, -1)

    @property
    def expires_at(self) -> Optional[datetime]:
        ttl = self.ttl_days
        if ttl < 0:
            return None
        return self.last_rotated_at + timedelta(days=ttl)

    @property
    def days_until_expiry(self) -> Optional[float]:
        exp = self.expires_at
        if exp is None:
            return None
        return (exp - datetime.utcnow()).total_seconds() / 86400

    @property
    def status(self) -> SecretStatus:
        if self._revoked:
            return SecretStatus.REVOKED
        exp = self.expires_at
        if exp is None:
            return SecretStatus.ACTIVE
        now = datetime.utcnow()
        if now >= exp:
            return SecretStatus.EXPIRED
        if (exp - now).total_seconds() / 86400 <= _WARNING_DAYS:
            return SecretStatus.EXPIRING
        return SecretStatus.ACTIVE

    @property
    def risk_level(self) -> RiskLevel:
        s = self.status
        if s == SecretStatus.EXPIRED:
            return RiskLevel.CRITICAL
        if s == SecretStatus.REVOKED:
            return RiskLevel.HIGH
        if not self.is_encrypted_at_rest:
            return RiskLevel.HIGH
        if s == SecretStatus.EXPIRING:
            return RiskLevel.MEDIUM
        return RiskLevel.LOW

    def rotate(self) -> None:
        self.last_rotated_at = datetime.utcnow()
        self.rotated_count += 1

    def revoke(self) -> None:
        self._revoked = True

    def to_dict(self) -> dict:
        return {
            "secret_id": self.secret_id,
            "name": self.name,
            "secret_type": self.secret_type.value,
            "rotation_policy": self.rotation_policy.value,
            "owner_service": self.owner_service,
            "environment": self.environment,
            "is_encrypted_at_rest": self.is_encrypted_at_rest,
            "status": self.status.value,
            "risk_level": self.risk_level.value,
            "rotated_count": self.rotated_count,
            "created_at": self.created_at.isoformat(),
            "last_rotated_at": self.last_rotated_at.isoformat(),
            "expires_at": self.expires_at.isoformat() if self.expires_at else None,
            "days_until_expiry": round(self.days_until_expiry, 2) if self.days_until_expiry is not None else None,
            "tags": self.tags,
        }


@dataclass
class AccessEvent:
    """Record of a secret access attempt."""
    event_id: str = field(default_factory=lambda: str(uuid.uuid4())[:10])
    secret_id: str = ""
    accessor: str = ""
    outcome: AccessOutcome = AccessOutcome.GRANTED
    reason: str = ""
    accessed_at: datetime = field(default_factory=datetime.utcnow)

    def to_dict(self) -> dict:
        return {
            "event_id": self.event_id,
            "secret_id": self.secret_id,
            "accessor": self.accessor,
            "outcome": self.outcome.value,
            "reason": self.reason,
            "accessed_at": self.accessed_at.isoformat(),
        }


@dataclass
class RotationRecord:
    """History entry for a rotation event."""
    record_id: str = field(default_factory=lambda: str(uuid.uuid4())[:10])
    secret_id: str = ""
    triggered_by: str = "policy"     # 'policy' | 'manual' | 'breach'
    rotated_at: datetime = field(default_factory=datetime.utcnow)
    success: bool = True
    notes: str = ""

    def to_dict(self) -> dict:
        return {
            "record_id": self.record_id,
            "secret_id": self.secret_id,
            "triggered_by": self.triggered_by,
            "rotated_at": self.rotated_at.isoformat(),
            "success": self.success,
            "notes": self.notes,
        }


@dataclass
class SecretsReport:
    """Snapshot report produced by SecretsManager."""
    report_id: str = field(default_factory=lambda: str(uuid.uuid4())[:10])
    generated_at: datetime = field(default_factory=datetime.utcnow)
    total_secrets: int = 0
    active_count: int = 0
    expiring_count: int = 0
    expired_count: int = 0
    revoked_count: int = 0
    unencrypted_count: int = 0
    rotation_rate: float = 0.0   # rotations per secret (avg)
    risk_breakdown: Dict[str, int] = field(default_factory=dict)

    def phase58_score(self) -> float:
        """
        Gate contribution 0-25.
        Starts at 25; deducts:
          5 per expired secret (max -15)
          3 per expiring secret (max -9)
          4 per unencrypted secret (max -12)
        Floor at 0.
        """
        deductions = (
            min(self.expired_count * 5, 15) +
            min(self.expiring_count * 3, 9) +
            min(self.unencrypted_count * 4, 12)
        )
        return max(0.0, round(25.0 - deductions, 2))

    def to_dict(self) -> dict:
        return {
            "report_id": self.report_id,
            "generated_at": self.generated_at.isoformat(),
            "total_secrets": self.total_secrets,
            "active_count": self.active_count,
            "expiring_count": self.expiring_count,
            "expired_count": self.expired_count,
            "revoked_count": self.revoked_count,
            "unencrypted_count": self.unencrypted_count,
            "rotation_rate": round(self.rotation_rate, 2),
            "risk_breakdown": self.risk_breakdown,
            "phase58_score": self.phase58_score(),
        }


# ---------------------------------------------------------------------------
# Core engine
# ---------------------------------------------------------------------------


class SecretsManager:
    """
    Phase 58 — Secrets Management & Credential Rotation Engine.

    Workflow:
      1. register_secret()      — add a secret to the vault
      2. rotate_secret()        — trigger rotation; logs RotationRecord
      3. revoke_secret()        — permanently revoke a secret
      4. record_access()        — log an access event
      5. scan_secrets()         — returns list of (secret, RiskLevel)
      6. secrets_by_status()    — group secrets by SecretStatus
      7. secrets_by_risk()      — group secrets by RiskLevel
      8. expired_secrets()      — all EXPIRED secrets
      9. expiring_secrets()     — all EXPIRING secrets
      10. unencrypted_secrets() — secrets not encrypted at rest
      11. generate_report()     — produce SecretsReport snapshot
      12. phase58_score()       — gate contribution 0-25
      13. summary() / persist_state()
    """

    def __init__(self) -> None:
        self._secrets: Dict[str, Secret] = {}
        self._access_log: List[AccessEvent] = []
        self._rotation_history: List[RotationRecord] = []

    # ---- Registration ----------------------------------------------------

    def register_secret(self, secret: Secret) -> Secret:
        self._secrets[secret.secret_id] = secret
        return secret

    def get_secret(self, secret_id: str) -> Optional[Secret]:
        return self._secrets.get(secret_id)

    def secrets(self) -> List[Secret]:
        return list(self._secrets.values())

    # ---- Rotation --------------------------------------------------------

    def rotate_secret(
        self,
        secret_id: str,
        triggered_by: str = "policy",
        notes: str = "",
    ) -> Optional[RotationRecord]:
        secret = self._secrets.get(secret_id)
        if not secret or secret.status == SecretStatus.REVOKED:
            return None
        secret.rotate()
        record = RotationRecord(
            secret_id=secret_id,
            triggered_by=triggered_by,
            notes=notes,
        )
        self._rotation_history.append(record)
        return record

    def rotate_all_expired(self, triggered_by: str = "policy") -> List[RotationRecord]:
        records: List[RotationRecord] = []
        for secret in self._secrets.values():
            if secret.status == SecretStatus.EXPIRED:
                rec = self.rotate_secret(secret.secret_id, triggered_by=triggered_by,
                                         notes="Auto-rotated: was expired")
                if rec:
                    records.append(rec)
        return records

    def rotation_history(self) -> List[RotationRecord]:
        return list(self._rotation_history)

    # ---- Revocation ------------------------------------------------------

    def revoke_secret(self, secret_id: str) -> bool:
        secret = self._secrets.get(secret_id)
        if not secret:
            return False
        secret.revoke()
        return True

    # ---- Access logging --------------------------------------------------

    def record_access(self, event: AccessEvent) -> AccessEvent:
        self._access_log.append(event)
        return event

    def access_log(self) -> List[AccessEvent]:
        return list(self._access_log)

    def access_denied_events(self) -> List[AccessEvent]:
        return [e for e in self._access_log if e.outcome == AccessOutcome.DENIED]

    # ---- Queries ---------------------------------------------------------

    def expired_secrets(self) -> List[Secret]:
        return [s for s in self._secrets.values() if s.status == SecretStatus.EXPIRED]

    def expiring_secrets(self) -> List[Secret]:
        return [s for s in self._secrets.values() if s.status == SecretStatus.EXPIRING]

    def unencrypted_secrets(self) -> List[Secret]:
        return [s for s in self._secrets.values() if not s.is_encrypted_at_rest]

    def revoked_secrets(self) -> List[Secret]:
        return [s for s in self._secrets.values() if s.status == SecretStatus.REVOKED]

    def secrets_by_status(self) -> Dict[str, List[Secret]]:
        result: Dict[str, List[Secret]] = {s.value: [] for s in SecretStatus}
        for sec in self._secrets.values():
            result[sec.status.value].append(sec)
        return result

    def secrets_by_risk(self) -> Dict[str, List[Secret]]:
        result: Dict[str, List[Secret]] = {r.value: [] for r in RiskLevel}
        for sec in self._secrets.values():
            result[sec.risk_level.value].append(sec)
        return result

    def scan_secrets(self) -> List[tuple]:
        """Return list of (secret, risk_level) for all secrets."""
        return [(s, s.risk_level) for s in self._secrets.values()]

    def secrets_for_service(self, service: str) -> List[Secret]:
        return [s for s in self._secrets.values() if s.owner_service == service]

    # ---- Reporting -------------------------------------------------------

    def generate_report(self) -> SecretsReport:
        all_secrets = self.secrets()
        by_status = self.secrets_by_status()
        by_risk: Dict[str, int] = {r.value: 0 for r in RiskLevel}
        for sec in all_secrets:
            by_risk[sec.risk_level.value] += 1
        total_rotations = sum(s.rotated_count for s in all_secrets)
        return SecretsReport(
            total_secrets=len(all_secrets),
            active_count=len(by_status.get(SecretStatus.ACTIVE.value, [])),
            expiring_count=len(by_status.get(SecretStatus.EXPIRING.value, [])),
            expired_count=len(by_status.get(SecretStatus.EXPIRED.value, [])),
            revoked_count=len(by_status.get(SecretStatus.REVOKED.value, [])),
            unencrypted_count=len(self.unencrypted_secrets()),
            rotation_rate=total_rotations / max(len(all_secrets), 1),
            risk_breakdown=by_risk,
        )

    def phase58_score(self) -> float:
        return self.generate_report().phase58_score()

    def summary(self) -> dict:
        report = self.generate_report()
        return {
            "status": "ok" if report.expired_count == 0 and report.unencrypted_count == 0 else "attention_required",
            "total_secrets": report.total_secrets,
            "active": report.active_count,
            "expiring": report.expiring_count,
            "expired": report.expired_count,
            "revoked": report.revoked_count,
            "unencrypted": report.unencrypted_count,
            "rotation_rate": report.rotation_rate,
            "access_events": len(self._access_log),
            "denied_events": len(self.access_denied_events()),
            "rotation_records": len(self._rotation_history),
            "phase58_score": report.phase58_score(),
        }

    def persist_state(
        self, output_path: str = "artifacts/phase58/secrets-state.json"
    ) -> str:
        import os
        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        state = {
            "phase": 58,
            "engine": "SecretsManager",
            "exported_at": datetime.utcnow().isoformat(),
            "summary": self.summary(),
            "secrets": [s.to_dict() for s in self._secrets.values()],
            "rotation_history": [r.to_dict() for r in self._rotation_history],
        }
        with open(output_path, "w") as f:
            json.dump(state, f, indent=2)
        return output_path


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def make_secret(
    name: str,
    secret_type: SecretType = SecretType.SERVICE_TOKEN,
    rotation_policy: RotationPolicy = RotationPolicy.MONTHLY,
    owner_service: str = "platform",
    environment: str = "production",
    is_encrypted_at_rest: bool = True,
    days_since_rotation: int = 0,
    tags: Optional[List[str]] = None,
) -> Secret:
    s = Secret(
        name=name,
        secret_type=secret_type,
        rotation_policy=rotation_policy,
        owner_service=owner_service,
        environment=environment,
        is_encrypted_at_rest=is_encrypted_at_rest,
        tags=tags or [],
    )
    if days_since_rotation:
        s.last_rotated_at = datetime.utcnow() - timedelta(days=days_since_rotation)
    return s


def make_access_event(
    secret_id: str,
    accessor: str,
    outcome: AccessOutcome = AccessOutcome.GRANTED,
    reason: str = "",
) -> AccessEvent:
    return AccessEvent(
        secret_id=secret_id,
        accessor=accessor,
        outcome=outcome,
        reason=reason,
    )
