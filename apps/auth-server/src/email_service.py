"""
Email Service - SendGrid Integration
Issue #1545: Enterprise SSO Portal - Email Service Configuration
"""
import os
from typing import Optional, Dict, Any, List
from abc import ABC, abstractmethod

from log import get_logger
from apps._shared.python.exceptions import (
    EmailServiceError, ServiceException
)

logger = get_logger(__name__)


class EmailProvider(ABC):
    """Abstract base class for email providers."""
    
    @abstractmethod
    async def send_email(
        self,
        to: str,
        subject: str,
        body_html: str,
        body_text: Optional[str] = None,
        cc: Optional[List[str]] = None,
        bcc: Optional[List[str]] = None,
    ) -> Dict[str, Any]:
        """Send email via the provider."""
        pass


class SendGridProvider(EmailProvider):
    """SendGrid email provider implementation."""
    
    def __init__(self, api_key: str, from_address: str, from_name: str = ""):
        """
        Initialize SendGrid provider.
        
        Args:
            api_key: SendGrid API key
            from_address: Default from email address
            from_name: Default from name
        """
        self.api_key = api_key
        self.from_address = from_address
        self.from_name = from_name
        
        if not api_key:
            logger.warning("SendGrid API key not configured")
        else:
            logger.info(f"SendGrid provider initialized (from: {from_address})")
    
    async def send_email(
        self,
        to: str,
        subject: str,
        body_html: str,
        body_text: Optional[str] = None,
        cc: Optional[List[str]] = None,
        bcc: Optional[List[str]] = None,
    ) -> Dict[str, Any]:
        """
        Send email via SendGrid API.
        
        Args:
            to: Recipient email address
            subject: Email subject
            body_html: HTML email body
            body_text: Plain text email body (optional)
            cc: CC recipients (optional)
            bcc: BCC recipients (optional)
        
        Returns:
            Dictionary with send status
        """
        if not self.api_key:
            logger.error("SendGrid API key not configured")
            return {
                "success": False,
                "error": "SendGrid API key not configured",
                "message_id": None,
            }
        
        try:
            # Import sendgrid library (optional dependency)
            import urllib.request
            import json
            
            # Prepare SendGrid API request
            message = {
                "personalizations": [
                    {
                        "to": [{"email": to}],
                        "subject": subject,
                    }
                ],
                "from": {
                    "email": self.from_address,
                    "name": self.from_name or "Code Server",
                },
                "content": [
                    {
                        "type": "text/html",
                        "value": body_html,
                    }
                ],
            }
            
            # Add plain text version if provided
            if body_text:
                message["content"].insert(0, {
                    "type": "text/plain",
                    "value": body_text,
                })
            
            # Add CC recipients
            if cc:
                message["personalizations"][0]["cc"] = [
                    {"email": addr} for addr in cc
                ]
            
            # Add BCC recipients
            if bcc:
                message["personalizations"][0]["bcc"] = [
                    {"email": addr} for addr in bcc
                ]
            
            # Make API request to SendGrid
            req = urllib.request.Request(
                "https://api.sendgrid.com/v3/mail/send",
                data=json.dumps(message).encode("utf-8"),
                headers={
                    "Authorization": f"Bearer {self.api_key}",
                    "Content-Type": "application/json",
                },
                method="POST",
            )
            
            with urllib.request.urlopen(req, timeout=10) as response:
                # SendGrid returns 202 on success
                if response.status == 202:
                    message_id = response.headers.get("X-Message-Id", "unknown")
                    logger.info(f"Email sent via SendGrid to {to} (msg_id={message_id})")
                    return {
                        "success": True,
                        "message_id": message_id,
                        "provider": "sendgrid",
                    }
                else:
                    logger.error(f"SendGrid API returned {response.status}")
                    return {
                        "success": False,
                        "error": f"SendGrid API returned {response.status}",
                        "message_id": None,
                    }
        
        except Exception as e:
            logger.error(f"Failed to send email via SendGrid: {str(e)}")
            return {
                "success": False,
                "error": str(e),
                "message_id": None,
            }


class MockEmailProvider(EmailProvider):
    """Mock email provider for testing and development."""
    
    def __init__(self, from_address: str, from_name: str = ""):
        """Initialize mock provider."""
        self.from_address = from_address
        self.from_name = from_name
        self.sent_emails = []
        logger.info("Mock email provider initialized (testing/development)")
    
    async def send_email(
        self,
        to: str,
        subject: str,
        body_html: str,
        body_text: Optional[str] = None,
        cc: Optional[List[str]] = None,
        bcc: Optional[List[str]] = None,
    ) -> Dict[str, Any]:
        """Log email without sending (for testing)."""
        email_record = {
            "to": to,
            "subject": subject,
            "body_html": body_html,
            "body_text": body_text,
            "cc": cc,
            "bcc": bcc,
        }
        self.sent_emails.append(email_record)
        
        logger.info(f"[MOCK] Email sent to {to}: {subject}")
        
        return {
            "success": True,
            "message_id": f"mock-{len(self.sent_emails)}",
            "provider": "mock",
        }


class EmailService:
    """
    Unified email service with provider abstraction.
    
    Supports:
    - SendGrid provider (production)
    - Mock provider (testing)
    - Configurable sender
    """
    
    def __init__(self, provider: EmailProvider):
        """
        Initialize email service.
        
        Args:
            provider: Email provider instance
        """
        self.provider = provider
    
    async def send_password_reset_email(
        self,
        to: str,
        reset_token: str,
        reset_url: str,
    ) -> Dict[str, Any]:
        """
        Send password reset email.
        
        Args:
            to: Recipient email
            reset_token: Password reset token
            reset_url: Link to reset password page
        
        Returns:
            Send status dictionary
        """
        subject = "Password Reset - Code Server"
        
        body_html = f"""
        <html>
            <body>
                <h2>Password Reset Request</h2>
                <p>You requested to reset your password. Click the link below to proceed:</p>
                <p><a href="{reset_url}?token={reset_token}">Reset Your Password</a></p>
                <p>Or copy this link: {reset_url}?token={reset_token}</p>
                <p>This link expires in 1 hour.</p>
                <p>If you didn't request this, please ignore this email.</p>
            </body>
        </html>
        """
        
        body_text = f"""
        Password Reset Request
        
        You requested to reset your password. Click or copy this link:
        {reset_url}?token={reset_token}
        
        This link expires in 1 hour.
        If you didn't request this, please ignore this email.
        """
        
        return await self.provider.send_email(
            to=to,
            subject=subject,
            body_html=body_html,
            body_text=body_text,
        )
    
    async def send_email_verification(
        self,
        to: str,
        verification_url: str,
        verification_code: Optional[str] = None,
    ) -> Dict[str, Any]:
        """
        Send email verification link.
        
        Args:
            to: Recipient email
            verification_url: Link to verify email
            verification_code: Optional verification code
        
        Returns:
            Send status dictionary
        """
        subject = "Verify Your Email - Code Server"
        
        body_html = f"""
        <html>
            <body>
                <h2>Verify Your Email</h2>
                <p>Click the link below to verify your email address:</p>
                <p><a href="{verification_url}">Verify Email</a></p>
                <p>Or copy this link: {verification_url}</p>
                {f"<p>Verification code: {verification_code}</p>" if verification_code else ""}
                <p>This link expires in 24 hours.</p>
            </body>
        </html>
        """
        
        body_text = f"""
        Verify Your Email
        
        Click or copy this link to verify your email:
        {verification_url}
        
        {f"Verification code: {verification_code}" if verification_code else ""}
        This link expires in 24 hours.
        """
        
        return await self.provider.send_email(
            to=to,
            subject=subject,
            body_html=body_html,
            body_text=body_text,
        )
    
    async def send_mfa_setup_email(
        self,
        to: str,
        mfa_method: str,
    ) -> Dict[str, Any]:
        """
        Send multi-factor authentication setup notification.
        
        Args:
            to: Recipient email
            mfa_method: MFA method set up (TOTP, SMS, etc.)
        
        Returns:
            Send status dictionary
        """
        subject = "Multi-Factor Authentication Enabled - Code Server"
        
        body_html = f"""
        <html>
            <body>
                <h2>Multi-Factor Authentication Enabled</h2>
                <p>Your account now has multi-factor authentication enabled via {mfa_method}.</p>
                <p>If you didn't make this change, please contact support immediately.</p>
            </body>
        </html>
        """
        
        return await self.provider.send_email(
            to=to,
            subject=subject,
            body_html=body_html,
        )


def setup_email_service(config) -> EmailService:
    """
    Setup email service based on configuration.
    
    Args:
        config: Configuration object
    
    Returns:
        Configured EmailService instance
    """
    # Get email settings from config
    email_provider_name = getattr(config, "EMAIL_PROVIDER", "mock")
    sendgrid_api_key = getattr(config, "SENDGRID_API_KEY", "")
    email_from_address = getattr(config, "EMAIL_FROM_ADDRESS", "noreply@kushnir.cloud")
    email_from_name = getattr(config, "EMAIL_FROM_NAME", "Code Server")
    
    # Create appropriate provider
    if email_provider_name == "sendgrid" and sendgrid_api_key:
        provider = SendGridProvider(
            api_key=sendgrid_api_key,
            from_address=email_from_address,
            from_name=email_from_name,
        )
    else:
        provider = MockEmailProvider(
            from_address=email_from_address,
            from_name=email_from_name,
        )
    
    # Create email service
    email_service = EmailService(provider=provider)
    
    logger.info(f"Email service initialized with {email_provider_name} provider")
    
    return email_service
