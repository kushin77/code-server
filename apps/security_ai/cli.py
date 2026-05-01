#!/usr/bin/env python3
"""
@file cli.py
@description Phase 30 security & compliance CLI

Provides a unified command-line interface for the security_ai package:
  audit      Run compliance audit against a framework
  detect     Detect threats in a JSON event file
  score      Print current compliance score from artifacts/phase30/

Usage:
  python3 -m apps.security_ai.cli audit --framework soc2
  python3 -m apps.security_ai.cli detect --events /path/to/events.json
  python3 -m apps.security_ai.cli score

@since 2026-05-01
"""

import argparse
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).parent.parent.parent


def cmd_audit(args: argparse.Namespace) -> int:
    from apps.security_ai.compliance_checker import ComplianceChecker, ComplianceFramework

    framework_map = {
        "soc2":    ComplianceFramework.SOC2_TYPE2,
        "nist":    ComplianceFramework.NIST_800_53,
        "iso":     ComplianceFramework.ISO_27001,
        "iso27001":ComplianceFramework.ISO_27001,
    }

    if args.framework not in framework_map:
        print(f"Unknown framework: {args.framework}. Use: {', '.join(framework_map)}", file=sys.stderr)
        return 1

    # Load environment config from file or use defaults
    env: dict = {}
    if args.env_file:
        with open(args.env_file) as f:
            env = json.load(f)
    else:
        # Sensible defaults for local environment
        env = {
            "rbac_enabled": True,
            "mfa_enabled": False,          # Audit will flag this
            "access_logs_enabled": True,
            "logging_enabled": True,
            "monitoring_enabled": True,
            "alerting_enabled": True,
            "uptime_percentage": 99.9,
            "tls_enabled": True,
            "encryption_enabled": True,
        }

    checker = ComplianceChecker()
    report = checker.generate_audit_report(framework_map[args.framework], env)

    if args.json:
        print(json.dumps(report, indent=2))
    else:
        fw = report["framework"].upper()
        score = report["compliance_score"]
        print(f"\n{'='*50}")
        print(f"  {fw} Compliance Audit")
        print(f"{'='*50}")
        print(f"  Score:          {score:.1f}/100")
        print(f"  Total Controls: {report['total_controls']}")
        print(f"  Compliant:      {report['compliant']}")
        print(f"  Non-Compliant:  {report['non_compliant']}")
        print(f"  Partial:        {report['partial']}")
        print(f"\n  Controls:")
        for ctrl in report["controls"]:
            status_icon = "✓" if ctrl["status"] == "compliant" else "✗" if ctrl["status"] == "non_compliant" else "~"
            print(f"    {status_icon} [{ctrl['control_id']}] {ctrl['title']}")
            if ctrl.get("remediation_steps") and ctrl["status"] != "compliant":
                for step in ctrl["remediation_steps"][:2]:
                    print(f"         → {step}")
        print(f"\n{'='*50}\n")

    # Non-zero exit if compliance below threshold
    if report["compliance_score"] < (args.threshold or 0):
        print(f"FAIL: compliance score {report['compliance_score']:.1f}% below threshold {args.threshold}%", file=sys.stderr)
        return 1
    return 0


def cmd_detect(args: argparse.Namespace) -> int:
    from apps.security_ai.threat_detector import ThreatDetector, SecurityEvent
    import datetime

    # Load events from file or stdin
    if args.events:
        with open(args.events) as f:
            raw_events = json.load(f)
    else:
        raw_events = json.load(sys.stdin)

    if not isinstance(raw_events, list):
        raw_events = [raw_events]

    # Convert dict events to SecurityEvent objects
    events = []
    for e in raw_events:
        events.append(SecurityEvent(
            timestamp=e.get("timestamp", datetime.datetime.now().isoformat()),
            source=e.get("source", "unknown"),
            event_type=e.get("event_type", "unknown"),
            container_id=e.get("container_id", "unknown"),
            process=e.get("process", ""),
            syscall=e.get("syscall"),
            network_flow=e.get("network_flow"),
            file_access=e.get("file_access"),
            metadata=e.get("metadata", {}),
        ))

    detector = ThreatDetector()
    threats = detector.detect_threats(events)

    if args.json:
        output = [
            {
                "threat_id": t.threat_id,
                "threat_type": t.threat_type.value,
                "severity": t.severity.name,
                "affected_service": t.affected_service,
                "description": t.description,
                "confidence": t.confidence,
                "recommended_actions": t.recommended_actions,
            }
            for t in threats
        ]
        print(json.dumps(output, indent=2))
    else:
        if not threats:
            print("✓ No threats detected")
        else:
            print(f"\n{'='*50}")
            print(f"  Threat Detection Results ({len(threats)} threats)")
            print(f"{'='*50}")
            for t in threats:
                icon = "🔴" if t.severity.value >= 4 else "🟡" if t.severity.value == 3 else "🟢"
                print(f"\n  {icon} {t.threat_id}")
                print(f"     Type:     {t.threat_type.value}")
                print(f"     Severity: {t.severity.name}")
                print(f"     Service:  {t.affected_service}")
                print(f"     Detail:   {t.description}")
                print(f"     Actions:  {t.recommended_actions[0] if t.recommended_actions else 'N/A'}")
            print(f"\n{'='*50}\n")

    # Non-zero exit if critical threats found
    critical = [t for t in threats if t.severity.value >= 5]
    if critical:
        print(f"ALERT: {len(critical)} CRITICAL threat(s) detected", file=sys.stderr)
        return 1
    return 0


def cmd_score(args: argparse.Namespace) -> int:
    compliance_file = REPO_ROOT / "artifacts" / "phase30" / "compliance.json"
    violations_file = REPO_ROOT / "artifacts" / "phase30" / "violations.json"

    if not compliance_file.exists():
        print("No compliance data found. Run: bash scripts/ops/phase-30-security-enforcement.sh --mode audit")
        return 1

    with open(compliance_file) as f:
        comp = json.load(f)

    score = comp.get("score", 0)
    violations = comp.get("open_violations", 0)
    critical = comp.get("critical_violations", 0)

    if args.json:
        print(json.dumps(comp, indent=2))
    else:
        status = "🟢 COMPLIANT" if score >= 95 else "🟡 PARTIAL" if score >= 80 else "🔴 NON-COMPLIANT"
        print(f"\n{'='*50}")
        print(f"  Security Compliance Score")
        print(f"{'='*50}")
        print(f"  Overall Score:      {score}/100  {status}")
        print(f"  Open Violations:    {violations}")
        print(f"  Critical Issues:    {critical}")
        print(f"  Last Audit:         {comp.get('last_audit', 'never')}")
        print(f"\n  Framework Scores:")
        for fw, details in comp.get("frameworks", {}).items():
            fw_score = details.get("score", 0)
            fw_status = details.get("status", "unknown")
            icon = "✓" if fw_status == "compliant" else "~" if fw_status == "partial" else "✗"
            print(f"    {icon} {fw.upper():<20} {fw_score}/100")
        print(f"{'='*50}\n")

    return 0 if score >= 95 else 1


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="security_ai",
        description="Phase 30 AI-driven security & compliance CLI",
    )
    parser.add_argument("--json", action="store_true", help="Output in JSON format")
    sub = parser.add_subparsers(dest="command", required=True)

    # audit subcommand
    p_audit = sub.add_parser("audit", help="Run compliance audit")
    p_audit.add_argument("--framework", default="soc2", choices=["soc2","nist","iso","iso27001"],
                         help="Compliance framework to audit against")
    p_audit.add_argument("--env-file", metavar="FILE", help="JSON file with environment config")
    p_audit.add_argument("--threshold", type=float, default=None,
                         help="Exit non-zero if score below this value")

    # detect subcommand
    p_detect = sub.add_parser("detect", help="Detect threats in event stream")
    p_detect.add_argument("--events", metavar="FILE", help="JSON file of security events (stdin if omitted)")

    # score subcommand
    sub.add_parser("score", help="Print current compliance score from artifacts/phase30/")

    args = parser.parse_args()
    # Propagate --json to subcommand namespace
    args.json = args.json

    if args.command == "audit":
        return cmd_audit(args)
    elif args.command == "detect":
        return cmd_detect(args)
    elif args.command == "score":
        return cmd_score(args)
    return 0


if __name__ == "__main__":
    sys.exit(main())
