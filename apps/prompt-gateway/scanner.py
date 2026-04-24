#!/usr/bin/env python3
# @file        apps/prompt-gateway/scanner.py
# @module      ai/security
# @description PII and Secret detection scanner - regex patterns for sensitive data
# @owner       ai/security
# @status      production-ready
#
# Detects: GitHub PAT, AWS credentials, private keys, passwords, emails, credit cards, SSN, phone

import re
import logging
from typing import List, Tuple

logger = logging.getLogger(__name__)


class ContentScanner:
    """Scan prompts for PII and secrets (fail-closed: block on detection)"""
    
    def __init__(self):
        # Secret patterns (high confidence)
        self.secret_patterns = {
            "github_pat": re.compile(r"gh[opsum]_[a-zA-Z0-9]{30,255}"),
            "github_oauth": re.compile(r"ghu_[a-zA-Z0-9]{70,255}"),
            "aws_access_key": re.compile(r"AKIA[0-9A-Z]{14,20}"),
            "aws_secret_key": re.compile(r"aws_secret_access_key.*?[A-Za-z0-9/+=]{35,50}"),
            "slack_token": re.compile(r"xox[baprs]-[0-9]{10,13}-[0-9]{10,13}-[a-zA-Z0-9]{20,30}"),
            "private_key_rsa": re.compile(r"(?i)---+\s?BEGIN (RSA|EC|OPENSSH) PRIVATE KEY\s?---+"),
            "private_key_generic": re.compile(r"(?i)---+\s?BEGIN (PGP|SSH|DSA) PRIVATE KEY\s?---+"),
            "bearer_token": re.compile(r"(?i)bearer\s+[a-zA-Z0-9_\-\.]+"),
            "api_key_generic": re.compile(r"(?i)(api[_-]?key|apikey|api[_-]?token|access[_-]?token)\s*[=:]\s*['\"]?[a-zA-Z0-9_\-\.]{20,}['\"]?"),
        }
        
        # PII patterns (personally identifiable information)
        self.pii_patterns = {
            "email": re.compile(r"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}"),
            "credit_card": re.compile(r"\b\d{4}[\s\-]?\d{4}[\s\-]?\d{4}[\s\-]?\d{4}\b"),
            "credit_card_amex": re.compile(r"\b3[47][0-9]{13}\b"),
            "ssn": re.compile(r"\b\d{3}-\d{2}-\d{4}\b"),
            "us_phone": re.compile(r"\b(?:\+?1[\s.-]?)?\(?[0-9]{3}\)?[\s.-]?[0-9]{3}[\s.-]?[0-9]{4}\b"),
            "passport": re.compile(r"\b[A-Z]{1,2}\d{6,9}\b"),
            "license_plate": re.compile(r"\b[A-Z]{2,3}\d{3,4}[A-Z]{2}\b"),
        }
    
    def scan(self, content: str) -> Tuple[bool, List[str]]:
        """
        Scan content for sensitive data.
        
        Returns: (is_safe, findings)
        is_safe=False means content contains secrets or PII → block
        """
        findings = []
        
        # Check secrets (critical - always block)
        for name, pattern in self.secret_patterns.items():
            if pattern.search(content):
                findings.append(f"SECRET_DETECTED: {name}")
                logger.warning(f"Secret detected: {name}")
        
        # Check PII (also block - could contain personal information)
        for name, pattern in self.pii_patterns.items():
            if pattern.search(content):
                findings.append(f"PII_DETECTED: {name}")
                logger.warning(f"PII detected: {name}")
        
        is_safe = len(findings) == 0
        return is_safe, findings


if __name__ == "__main__":
    # Test cases
    scanner = ContentScanner()
    
    test_cases = [
        ("Write hello world in Python", True, "Safe prompt"),
        ("My email is test@example.com", False, "Email detection"),
        ("My AWS key is AKIA" + "SAMPLE" + "12345678", False, "AWS key detection"),
        ("GitHub token: ghp_" + "SAMPLE" + "12345678901234567890123456", False, "GitHub PAT detection"),
        ("My credit card is 4532-1234-5678-9010", False, "Credit card detection"),
        ("-----BEGIN RSA PRIVATE KEY-----", False, "Private key detection"),
    ]
    
    print("=" * 70)
    print("Content Scanner Test")
    print("=" * 70)
    
    for content, expected_safe, description in test_cases:
        safe, findings = scanner.scan(content)
        status = "✓" if safe == expected_safe else "✗"
        print(f"{status} {description}")
        print(f"  Content: {content[:60]}..." if len(content) > 60 else f"  Content: {content}")
        print(f"  Safe: {safe}, Findings: {findings}")
        print()
