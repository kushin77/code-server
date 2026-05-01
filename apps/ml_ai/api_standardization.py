"""
Phase 28 API Standardization Module

Standardized interfaces for all Phase 27 ML/AI modules:
- Unified response/request structures
- Error handling and validation
- Rate limiting and caching hooks
- Request tracing and monitoring
"""

from abc import ABC, abstractmethod
from dataclasses import dataclass, field, asdict
from datetime import datetime
from enum import Enum
from typing import Any, Dict, Generic, List, Optional, TypeVar, Union
from uuid import uuid4


T = TypeVar('T')


class StatusCode(Enum):
    """API status codes."""
    SUCCESS = "success"
    CREATED = "created"
    ACCEPTED = "accepted"
    BAD_REQUEST = "bad_request"
    UNAUTHORIZED = "unauthorized"
    FORBIDDEN = "forbidden"
    NOT_FOUND = "not_found"
    CONFLICT = "conflict"
    RATE_LIMITED = "rate_limited"
    INTERNAL_ERROR = "internal_error"
    SERVICE_UNAVAILABLE = "service_unavailable"


@dataclass
class RequestContext:
    """Request metadata and context."""
    request_id: str = field(default_factory=lambda: str(uuid4()))
    user_id: Optional[str] = None
    api_version: str = "v1"
    timestamp: datetime = field(default_factory=datetime.utcnow)
    source: Optional[str] = None
    tags: Dict[str, str] = field(default_factory=dict)


@dataclass
class APIResponse(Generic[T]):
    """Standardized API response."""
    status: StatusCode
    data: Optional[T] = None
    message: Optional[str] = None
    error: Optional[str] = None
    error_code: Optional[str] = None
    context: RequestContext = field(default_factory=RequestContext)
    metadata: Dict[str, Any] = field(default_factory=dict)
    links: Dict[str, str] = field(default_factory=dict)
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "status": self.status.value,
            "data": self.data,
            "message": self.message,
            "error": self.error,
            "error_code": self.error_code,
            "context": asdict(self.context),
            "metadata": self.metadata,
            "links": self.links
        }
    
    def is_success(self) -> bool:
        """Check if response is successful."""
        return self.status == StatusCode.SUCCESS
    
    def is_error(self) -> bool:
        """Check if response is an error."""
        return self.status in [
            StatusCode.BAD_REQUEST,
            StatusCode.UNAUTHORIZED,
            StatusCode.FORBIDDEN,
            StatusCode.NOT_FOUND,
            StatusCode.CONFLICT,
            StatusCode.RATE_LIMITED,
            StatusCode.INTERNAL_ERROR,
            StatusCode.SERVICE_UNAVAILABLE
        ]


@dataclass
class APIRequest:
    """Standardized API request."""
    query: Dict[str, Any]
    context: RequestContext = field(default_factory=RequestContext)
    pagination: Optional['PaginationRequest'] = None
    filters: Optional[Dict[str, Any]] = None
    sort: Optional[List[tuple]] = None
    
    def validate(self) -> bool:
        """Validate request."""
        return bool(self.query)


@dataclass
class PaginationRequest:
    """Pagination parameters."""
    limit: int = 100
    offset: int = 0
    max_limit: int = 1000
    
    def validate(self) -> bool:
        """Validate pagination."""
        return 1 <= self.limit <= self.max_limit and self.offset >= 0


@dataclass
class PaginationResponse:
    """Pagination response."""
    limit: int
    offset: int
    total: int
    has_next: bool
    has_previous: bool
    
    @property
    def next_offset(self) -> Optional[int]:
        """Get next offset."""
        if self.has_next:
            return self.offset + self.limit
        return None
    
    @property
    def prev_offset(self) -> Optional[int]:
        """Get previous offset."""
        if self.has_previous:
            return max(0, self.offset - self.limit)
        return None


@dataclass
class BulkOperationRequest:
    """Bulk operation request."""
    operations: List[Dict[str, Any]]
    context: RequestContext = field(default_factory=RequestContext)
    continue_on_error: bool = False


@dataclass
class BulkOperationResponse:
    """Bulk operation response."""
    total_operations: int
    successful: int
    failed: int
    results: List[Dict[str, Any]]
    errors: List[Dict[str, Any]] = field(default_factory=list)


class APIServer(ABC):
    """Base API server class."""
    
    @abstractmethod
    def handle_request(self, request: APIRequest) -> APIResponse:
        """Handle API request."""
        pass
    
    @abstractmethod
    def validate_request(self, request: APIRequest) -> tuple[bool, Optional[str]]:
        """Validate request."""
        pass
    
    @abstractmethod
    def handle_error(self, error: Exception, context: RequestContext) -> APIResponse:
        """Handle error."""
        pass


class AnomalyDetectionAPI(APIServer):
    """API for anomaly detection engine."""
    
    def __init__(self, detector):
        """Initialize API."""
        self.detector = detector
    
    def handle_request(self, request: APIRequest) -> APIResponse:
        """Handle anomaly detection request."""
        is_valid, error_msg = self.validate_request(request)
        
        if not is_valid:
            return APIResponse(
                status=StatusCode.BAD_REQUEST,
                error=error_msg,
                context=request.context
            )
        
        try:
            action = request.query.get("action")
            
            if action == "detect":
                metric_name = request.query.get("metric_name")
                value = request.query.get("value")
                
                anomaly = self.detector.detect_anomaly(metric_name, value)
                
                return APIResponse(
                    status=StatusCode.SUCCESS,
                    data=asdict(anomaly) if anomaly else None,
                    message=f"Anomaly detection completed for {metric_name}",
                    context=request.context
                )
            
            elif action == "statistics":
                stats = self.detector.get_statistics()
                
                return APIResponse(
                    status=StatusCode.SUCCESS,
                    data=stats,
                    message="Statistics retrieved",
                    context=request.context
                )
            
            else:
                return APIResponse(
                    status=StatusCode.BAD_REQUEST,
                    error=f"Unknown action: {action}",
                    context=request.context
                )
        
        except Exception as e:
            return self.handle_error(e, request.context)
    
    def validate_request(self, request: APIRequest) -> tuple[bool, Optional[str]]:
        """Validate anomaly detection request."""
        action = request.query.get("action")
        
        if not action:
            return False, "Action is required"
        
        if action == "detect":
            if "metric_name" not in request.query:
                return False, "metric_name is required"
            if "value" not in request.query:
                return False, "value is required"
        
        return True, None
    
    def handle_error(self, error: Exception, context: RequestContext) -> APIResponse:
        """Handle error."""
        return APIResponse(
            status=StatusCode.INTERNAL_ERROR,
            error=str(error),
            error_code="ANOMALY_DETECTION_ERROR",
            context=context
        )


class PredictiveScalingAPI(APIServer):
    """API for predictive scaling engine."""
    
    def __init__(self, scaler):
        """Initialize API."""
        self.scaler = scaler
    
    def handle_request(self, request: APIRequest) -> APIResponse:
        """Handle scaling request."""
        is_valid, error_msg = self.validate_request(request)
        
        if not is_valid:
            return APIResponse(
                status=StatusCode.BAD_REQUEST,
                error=error_msg,
                context=request.context
            )
        
        try:
            action = request.query.get("action")
            
            if action == "recommend":
                metric_name = request.query.get("metric_name")
                value = request.query.get("value")
                
                recommendation = self.scaler.get_scaling_recommendation(metric_name, value)
                
                return APIResponse(
                    status=StatusCode.SUCCESS,
                    data=asdict(recommendation) if recommendation else None,
                    message=f"Scaling recommendation generated",
                    context=request.context
                )
            
            elif action == "statistics":
                stats = self.scaler.get_statistics()
                
                return APIResponse(
                    status=StatusCode.SUCCESS,
                    data=stats,
                    message="Statistics retrieved",
                    context=request.context
                )
            
            else:
                return APIResponse(
                    status=StatusCode.BAD_REQUEST,
                    error=f"Unknown action: {action}",
                    context=request.context
                )
        
        except Exception as e:
            return self.handle_error(e, request.context)
    
    def validate_request(self, request: APIRequest) -> tuple[bool, Optional[str]]:
        """Validate scaling request."""
        action = request.query.get("action")
        
        if not action:
            return False, "Action is required"
        
        if action == "recommend":
            if "metric_name" not in request.query:
                return False, "metric_name is required"
            if "value" not in request.query:
                return False, "value is required"
        
        return True, None
    
    def handle_error(self, error: Exception, context: RequestContext) -> APIResponse:
        """Handle error."""
        return APIResponse(
            status=StatusCode.INTERNAL_ERROR,
            error=str(error),
            error_code="SCALING_ERROR",
            context=context
        )


class RootCauseAnalysisAPI(APIServer):
    """API for root cause analysis engine."""
    
    def __init__(self, analyzer):
        """Initialize API."""
        self.analyzer = analyzer
    
    def handle_request(self, request: APIRequest) -> APIResponse:
        """Handle RCA request."""
        is_valid, error_msg = self.validate_request(request)
        
        if not is_valid:
            return APIResponse(
                status=StatusCode.BAD_REQUEST,
                error=error_msg,
                context=request.context
            )
        
        try:
            action = request.query.get("action")
            
            if action == "analyze":
                incident_id = request.query.get("incident_id")
                primary_issue = request.query.get("primary_issue")
                affected_services = request.query.get("affected_services", [])
                
                report = self.analyzer.analyze_incident(
                    incident_id=incident_id,
                    primary_issue=primary_issue,
                    affected_services=affected_services
                )
                
                return APIResponse(
                    status=StatusCode.SUCCESS,
                    data=asdict(report) if report else None,
                    message=f"Incident analysis completed",
                    context=request.context
                )
            
            elif action == "statistics":
                stats = self.analyzer.get_statistics()
                
                return APIResponse(
                    status=StatusCode.SUCCESS,
                    data=stats,
                    message="Statistics retrieved",
                    context=request.context
                )
            
            else:
                return APIResponse(
                    status=StatusCode.BAD_REQUEST,
                    error=f"Unknown action: {action}",
                    context=request.context
                )
        
        except Exception as e:
            return self.handle_error(e, request.context)
    
    def validate_request(self, request: APIRequest) -> tuple[bool, Optional[str]]:
        """Validate RCA request."""
        action = request.query.get("action")
        
        if not action:
            return False, "Action is required"
        
        if action == "analyze":
            if "incident_id" not in request.query:
                return False, "incident_id is required"
            if "primary_issue" not in request.query:
                return False, "primary_issue is required"
        
        return True, None
    
    def handle_error(self, error: Exception, context: RequestContext) -> APIResponse:
        """Handle error."""
        return APIResponse(
            status=StatusCode.INTERNAL_ERROR,
            error=str(error),
            error_code="RCA_ERROR",
            context=context
        )


class IntelligentAlertingAPI(APIServer):
    """API for intelligent alerting engine."""
    
    def __init__(self, alerter):
        """Initialize API."""
        self.alerter = alerter
    
    def handle_request(self, request: APIRequest) -> APIResponse:
        """Handle alerting request."""
        is_valid, error_msg = self.validate_request(request)
        
        if not is_valid:
            return APIResponse(
                status=StatusCode.BAD_REQUEST,
                error=error_msg,
                context=request.context
            )
        
        try:
            action = request.query.get("action")
            
            if action == "process":
                alert_data = request.query.get("alert")
                
                enriched = self.alerter.process_alert(alert_data)
                
                return APIResponse(
                    status=StatusCode.SUCCESS,
                    data=asdict(enriched) if enriched else None,
                    message=f"Alert processed",
                    context=request.context
                )
            
            elif action == "statistics":
                stats = self.alerter.get_statistics()
                
                return APIResponse(
                    status=StatusCode.SUCCESS,
                    data=stats,
                    message="Statistics retrieved",
                    context=request.context
                )
            
            else:
                return APIResponse(
                    status=StatusCode.BAD_REQUEST,
                    error=f"Unknown action: {action}",
                    context=request.context
                )
        
        except Exception as e:
            return self.handle_error(e, request.context)
    
    def validate_request(self, request: APIRequest) -> tuple[bool, Optional[str]]:
        """Validate alerting request."""
        action = request.query.get("action")
        
        if not action:
            return False, "Action is required"
        
        if action == "process":
            if "alert" not in request.query:
                return False, "alert is required"
        
        return True, None
    
    def handle_error(self, error: Exception, context: RequestContext) -> APIResponse:
        """Handle error."""
        return APIResponse(
            status=StatusCode.INTERNAL_ERROR,
            error=str(error),
            error_code="ALERTING_ERROR",
            context=context
        )


class APIRegistry:
    """Registry of all available APIs."""
    
    def __init__(self):
        """Initialize registry."""
        self.apis: Dict[str, APIServer] = {}
    
    def register(self, name: str, api: APIServer) -> None:
        """Register API."""
        self.apis[name] = api
    
    def get_api(self, name: str) -> Optional[APIServer]:
        """Get API by name."""
        return self.apis.get(name)
    
    def list_apis(self) -> List[str]:
        """List registered APIs."""
        return list(self.apis.keys())
    
    def handle_request(self, api_name: str, request: APIRequest) -> APIResponse:
        """Handle request through registry."""
        api = self.get_api(api_name)
        
        if not api:
            return APIResponse(
                status=StatusCode.NOT_FOUND,
                error=f"API not found: {api_name}",
                context=request.context
            )
        
        return api.handle_request(request)
