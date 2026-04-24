#!/usr/bin/env python3
# @file        apps/prompt-gateway/tests/test_scanner.py
# @module      ai/security
# @description Unit tests for PII/Secret scanner
# @owner       ai/security

import pytest
from scanner import ContentScanner


@pytest.fixture
def scanner():
    return ContentScanner()


# ============================================================================
# Secret Detection Tests
# ============================================================================

def test_github_pat_detected(scanner):
    """GitHub PAT should be detected"""
    content = "My GitHub token is ghp_1234567890123456789012345678901234"
    safe, findings = scanner.scan(content)
    assert not safe
    assert any("github_pat" in f for f in findings)


def test_aws_access_key_detected(scanner):
    """AWS access key should be detected"""
    content = "AWS Key: AKIA1234567890ABCDEF"
    safe, findings = scanner.scan(content)
    assert not safe
    assert any("aws_access_key" in f for f in findings)


def test_slack_token_detected(scanner):
    """Slack token should be detected"""
    content = "Token: xox" + "b-1234567890-1234567890-EXAMPLE"
    safe, findings = scanner.scan(content)
    assert not safe
    assert any("slack_token" in f for f in findings)


def test_private_key_rsa_detected(scanner):
    """RSA private key should be detected"""
    content = "-----BEGIN RSA PRIVATE KEY-----"
    safe, findings = scanner.scan(content)
    assert not safe
    assert any("private_key_rsa" in f for f in findings)


def test_bearer_token_detected(scanner):
    """Bearer token should be detected"""
    content = "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
    safe, findings = scanner.scan(content)
    assert not safe
    assert any("bearer_token" in f for f in findings)


# ============================================================================
# PII Detection Tests
# ============================================================================

def test_email_detected(scanner):
    """Email address should be detected"""
    content = "Contact me at user@example.com for details"
    safe, findings = scanner.scan(content)
    assert not safe
    assert any("email" in f for f in findings)


def test_credit_card_detected(scanner):
    """Credit card number should be detected"""
    content = "Card: 4532-1234-5678-9010"
    safe, findings = scanner.scan(content)
    assert not safe
    assert any("credit_card" in f for f in findings)


def test_credit_card_amex_detected(scanner):
    """AMEX card should be detected"""
    content = "AMEX: 371449635398431"
    safe, findings = scanner.scan(content)
    assert not safe
    assert any("credit_card_amex" in f for f in findings)


def test_ssn_detected(scanner):
    """Social Security Number should be detected"""
    content = "SSN: 123-45-6789"
    safe, findings = scanner.scan(content)
    assert not safe
    assert any("ssn" in f for f in findings)


def test_us_phone_detected(scanner):
    """US phone number should be detected"""
    content = "Call me at (123) 456-7890"
    safe, findings = scanner.scan(content)
    assert not safe
    assert any("us_phone" in f for f in findings)


# ============================================================================
# Safe Content Tests
# ============================================================================

def test_safe_prompt_allowed(scanner):
    """Safe prompt should pass scan"""
    content = "Write a hello world program in Python"
    safe, findings = scanner.scan(content)
    assert safe
    assert len(findings) == 0


def test_safe_code_allowed(scanner):
    """Safe code examples should pass"""
    content = """
    def factorial(n):
        if n <= 1:
            return 1
        return n * factorial(n - 1)
    """
    safe, findings = scanner.scan(content)
    assert safe
    assert len(findings) == 0


def test_generic_numbers_allowed(scanner):
    """Generic numbers that don't match patterns should be safe"""
    content = "The number is 1234567890"
    safe, findings = scanner.scan(content)
    assert safe


# ============================================================================
# Edge Cases
# ============================================================================

def test_multiple_findings(scanner):
    """Multiple secrets in one content should all be detected"""
    content = """
    GitHub: ghp_1234567890123456789012345678901234
    AWS: AKIA1234567890ABCDEF
    Email: user@example.com
    """
    safe, findings = scanner.scan(content)
    assert not safe
    assert len(findings) >= 3  # Multiple findings


def test_case_insensitive_patterns(scanner):
    """Some patterns should be case-insensitive"""
    content = "BEARER eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
    safe, findings = scanner.scan(content)
    assert not safe


def test_empty_content(scanner):
    """Empty content should be safe"""
    content = ""
    safe, findings = scanner.scan(content)
    assert safe
    assert len(findings) == 0


def test_whitespace_variations(scanner):
    """Patterns should work with various whitespace"""
    # Credit card with different separators
    test_cases = [
        "4532-1234-5678-9010",
        "4532 1234 5678 9010",
        "4532123456789010",  # No separators
    ]
    
    for content in test_cases:
        safe, findings = scanner.scan(content)
        assert not safe, f"Should detect: {content}"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
