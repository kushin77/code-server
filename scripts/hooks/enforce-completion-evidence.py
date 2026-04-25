#!/usr/bin/env python3
"""Hook validator: block completion without mandatory workflow evidence."""

import json
import re
import sys
from typing import Any, List


def _flatten_strings(value: Any, sink: List[str]) -> None:
    if isinstance(value, str):
        sink.append(value)
        return
    if isinstance(value, dict):
        for item in value.values():
            _flatten_strings(item, sink)
        return
    if isinstance(value, list):
        for item in value:
            _flatten_strings(item, sink)


def _emit(payload: dict, exit_code: int) -> None:
    print(json.dumps(payload))
    sys.exit(exit_code)


def main() -> None:
    raw = sys.stdin.read().strip()
    if not raw:
        _emit({"continue": True}, 0)

    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        _emit(
            {
                "continue": False,
                "stopReason": "Invalid hook payload JSON",
                "systemMessage": "Cannot evaluate completion evidence because hook payload is invalid JSON."
            },
            2,
        )

    strings: List[str] = []
    _flatten_strings(data, strings)
    haystack = "\n".join(strings)

    completion_trigger = re.search(
        r"\b(task complete|task completed|issue complete|issue completed|work complete|work completed|final status|completion status|completed)\b",
        haystack,
        flags=re.IGNORECASE,
    )

    # Only enforce when a completion-like message exists in the event payload.
    if not completion_trigger:
        _emit({"continue": True}, 0)

    checks = {
        "Commit SHA": re.search(r"commit(?:\s+sha)?[^\n\r]{0,40}\b[0-9a-f]{7,40}\b", haystack, flags=re.IGNORECASE),
        "Push confirmation": re.search(r"(remote\s+push\s+confirmation|push\s+confirmation|pushed\s+to\s+remote|git\s+push)", haystack, flags=re.IGNORECASE),
        "Main merge confirmation": re.search(r"(main\s+merge\s+confirmation|merged\s+to\s+main|merge\s+to\s+main)", haystack, flags=re.IGNORECASE),
        "Redeploy confirmation": re.search(r"(redeploy\s+confirmation|redeployed\s+from\s+main|redeployed)", haystack, flags=re.IGNORECASE),
        "Local branch cleanup confirmation": re.search(r"(local\s+branch\s+(cleanup|deletion|deleted)\s+confirmation|deleted\s+local\s+branch)", haystack, flags=re.IGNORECASE),
        "Remote branch cleanup confirmation": re.search(r"(remote\s+branch\s+(cleanup|deletion|deleted)\s+confirmation|deleted\s+remote\s+branch)", haystack, flags=re.IGNORECASE),
    }

    missing = [name for name, passed in checks.items() if not passed]
    if not missing:
        _emit({"continue": True}, 0)

    required = "\\n".join(f"- {item}" for item in missing)
    _emit(
        {
            "continue": False,
            "stopReason": "Missing mandatory completion evidence",
            "systemMessage": (
                "Completion output is blocked by policy. Add the missing evidence fields before ending the session:\n"
                f"{required}"
            ),
        },
        2,
    )


if __name__ == "__main__":
    main()
