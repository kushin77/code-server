"""
Standard Exception Hierarchy for Code Server Enterprise
"""


class CodeServerException(Exception):
    """Base exception for all Code Server Enterprise exceptions."""
    
    def __init__(self, message: str, error_code: str = None, details: dict = None):
        """
        Initialize exception.
        
        Args:
            message: Error message
            error_code: Optional error code (e.g., "AUTH_001")
            details: Optional additional details
        """
        super().__init__(message)
        self.message = message
        self.error_code = error_code or "UNKNOWN"
        self.details = details or {}
    
    def __str__(self) -> str:
        """String representation."""
        if self.error_code:
            return f"[{self.error_code}] {self.message}"
        return self.message
    
    def to_dict(self) -> dict:
        """Convert exception to dictionary for logging/API responses."""
        return {
            "error": self.__class__.__name__,
            "code": self.error_code,
            "message": self.message,
            "details": self.details,
        }


# Authentication & Authorization Exceptions

class AuthException(CodeServerException):
    """Base authentication exception."""
    pass


class AuthenticationFailure(AuthException):
    """Authentication failed."""
    
    def __init__(self, message: str = "Authentication failed", provider: str = None):
        super().__init__(message, error_code="AUTH_001")
        if provider:
            self.details["provider"] = provider


class InvalidCredentials(AuthException):
    """Invalid credentials provided."""
    
    def __init__(self, message: str = "Invalid credentials"):
        super().__init__(message, error_code="AUTH_002")


class TokenExpired(AuthException):
    """Authentication token expired."""
    
    def __init__(self, token_type: str = "unknown"):
        super().__init__(
            f"{token_type} token has expired",
            error_code="AUTH_003"
        )


class TokenRevoked(AuthException):
    """Authentication token has been revoked."""
    
    def __init__(self, reason: str = "Token revoked"):
        super().__init__(reason, error_code="AUTH_004")


class InvalidToken(AuthException):
    """Invalid or malformed token."""
    
    def __init__(self, message: str = "Invalid token format"):
        super().__init__(message, error_code="AUTH_005")


class UnauthorizedAccess(AuthException):
    """Access denied / insufficient permissions."""
    
    def __init__(self, message: str = "Insufficient permissions", required_scope: str = None):
        super().__init__(message, error_code="AUTH_006")
        if required_scope:
            self.details["required_scope"] = required_scope


class MFARequired(AuthException):
    """Multi-factor authentication required."""
    
    def __init__(self, mfa_method: str = None):
        super().__init__("Multi-factor authentication required", error_code="AUTH_007")
        if mfa_method:
            self.details["mfa_method"] = mfa_method


class MFAVerificationFailed(AuthException):
    """MFA verification failed."""
    
    def __init__(self, attempts_remaining: int = None):
        super().__init__("MFA verification failed", error_code="AUTH_008")
        if attempts_remaining is not None:
            self.details["attempts_remaining"] = attempts_remaining


# Configuration Exceptions

class ConfigException(CodeServerException):
    """Base configuration exception."""
    pass


class MissingConfig(ConfigException):
    """Required configuration value missing."""
    
    def __init__(self, config_key: str):
        super().__init__(
            f"Required configuration key '{config_key}' not found",
            error_code="CONFIG_001"
        )
        self.details["config_key"] = config_key


class InvalidConfig(ConfigException):
    """Invalid configuration value."""
    
    def __init__(self, config_key: str, reason: str):
        super().__init__(
            f"Invalid configuration for '{config_key}': {reason}",
            error_code="CONFIG_002"
        )
        self.details["config_key"] = config_key
        self.details["reason"] = reason


# Database Exceptions

class DatabaseException(CodeServerException):
    """Base database exception."""
    pass


class ConnectionError(DatabaseException):
    """Database connection failed."""
    
    def __init__(self, message: str = "Failed to connect to database"):
        super().__init__(message, error_code="DB_001")


class QueryError(DatabaseException):
    """Database query failed."""
    
    def __init__(self, message: str, query: str = None):
        super().__init__(message, error_code="DB_002")
        if query:
            self.details["query"] = query


class RecordNotFound(DatabaseException):
    """Record not found in database."""
    
    def __init__(self, resource_type: str, resource_id: str):
        super().__init__(
            f"{resource_type} with id '{resource_id}' not found",
            error_code="DB_003"
        )
        self.details["resource_type"] = resource_type
        self.details["resource_id"] = resource_id


class DuplicateRecord(DatabaseException):
    """Duplicate record would be created."""
    
    def __init__(self, resource_type: str, unique_field: str):
        super().__init__(
            f"{resource_type} with this {unique_field} already exists",
            error_code="DB_004"
        )
        self.details["resource_type"] = resource_type
        self.details["unique_field"] = unique_field


# Service Exceptions

class ServiceException(CodeServerException):
    """Base service exception."""
    pass


class ServiceUnavailable(ServiceException):
    """Required service is unavailable."""
    
    def __init__(self, service_name: str):
        super().__init__(
            f"Service '{service_name}' is currently unavailable",
            error_code="SERVICE_001"
        )
        self.details["service_name"] = service_name


class EmailServiceError(ServiceException):
    """Email service error."""
    
    def __init__(self, message: str, recipient: str = None):
        super().__init__(f"Email service error: {message}", error_code="SERVICE_002")
        if recipient:
            self.details["recipient"] = recipient


class ExternalServiceError(ServiceException):
    """External service call failed."""
    
    def __init__(self, service_name: str, status_code: int = None, message: str = None):
        super().__init__(
            f"External service '{service_name}' error: {message or f'HTTP {status_code}'}",
            error_code="SERVICE_003"
        )
        self.details["service_name"] = service_name
        if status_code:
            self.details["status_code"] = status_code


# Validation Exceptions

class ValidationException(CodeServerException):
    """Base validation exception."""
    pass


class ValidationError(ValidationException):
    """Input validation failed."""
    
    def __init__(self, message: str, field: str = None, value: str = None):
        super().__init__(message, error_code="VALIDATION_001")
        if field:
            self.details["field"] = field
        if value:
            self.details["value"] = value


class InvalidFormat(ValidationException):
    """Invalid data format."""
    
    def __init__(self, expected_format: str, got_format: str = None):
        super().__init__(
            f"Invalid format: expected {expected_format}, got {got_format or 'unknown'}",
            error_code="VALIDATION_002"
        )
        self.details["expected_format"] = expected_format
        if got_format:
            self.details["got_format"] = got_format


class SchemaValidationError(ValidationException):
    """Pydantic/schema validation error."""
    
    def __init__(self, message: str, validation_errors: list = None):
        super().__init__(message, error_code="VALIDATION_003")
        if validation_errors:
            self.details["validation_errors"] = validation_errors


# Business Logic Exceptions

class BusinessLogicException(CodeServerException):
    """Base business logic exception."""
    pass


class OperationNotPermitted(BusinessLogicException):
    """Operation not permitted in current state."""
    
    def __init__(self, operation: str, reason: str = None):
        super().__init__(
            f"Operation '{operation}' not permitted" + (f": {reason}" if reason else ""),
            error_code="BUSINESS_001"
        )
        self.details["operation"] = operation


class InvalidStateTransition(BusinessLogicException):
    """Invalid state transition."""
    
    def __init__(self, current_state: str, requested_state: str):
        super().__init__(
            f"Cannot transition from '{current_state}' to '{requested_state}'",
            error_code="BUSINESS_002"
        )
        self.details["current_state"] = current_state
        self.details["requested_state"] = requested_state


class QuotaExceeded(BusinessLogicException):
    """Resource quota exceeded."""
    
    def __init__(self, resource_name: str, limit: int):
        super().__init__(
            f"Quota exceeded for '{resource_name}' (limit: {limit})",
            error_code="BUSINESS_003"
        )
        self.details["resource_name"] = resource_name
        self.details["limit"] = limit


# System Exceptions

class SystemException(CodeServerException):
    """Base system exception."""
    pass


class FeatureNotImplemented(SystemException):
    """Feature not yet implemented."""
    
    def __init__(self, feature_name: str):
        super().__init__(
            f"Feature '{feature_name}' is not yet implemented",
            error_code="SYSTEM_001"
        )
        self.details["feature_name"] = feature_name


class InternalServerError(SystemException):
    """Internal server error (unexpected condition)."""
    
    def __init__(self, message: str = "Internal server error"):
        super().__init__(message, error_code="SYSTEM_500")


class ResourceLimitExceeded(SystemException):
    """System resource limit exceeded."""
    
    def __init__(self, resource_type: str, message: str = None):
        super().__init__(
            f"{resource_type} resource limit exceeded" + (f": {message}" if message else ""),
            error_code="SYSTEM_002"
        )
        self.details["resource_type"] = resource_type
