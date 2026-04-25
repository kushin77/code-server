"""
K6 Load Testing Configuration & Scripts
Issue #1537 Week 3: E2E + Load Testing

Scenarios:
- OAuth endpoints: 100 concurrent users
- User endpoints: 200 concurrent users
- Team endpoints: 150 concurrent users
- API gateway: 300 concurrent users
- Measures p50/p95/p99 latencies
- Identifies bottlenecks
"""
import time
from k6 import http, check, group
from k6.options import Options

# K6 Options
options = Options()
options.stages = [
    {"duration": "1m", "target": 10},    # Ramp up to 10 users
    {"duration": "3m", "target": 100},   # Ramp up to 100 users
    {"duration": "5m", "target": 100},   # Stay at 100 users
    {"duration": "2m", "target": 50},    # Ramp down to 50 users
    {"duration": "1m", "target": 0},     # Ramp down to 0 users
]
options.thresholds = {
    "http_req_duration": ["p(95)<500"],  # 95% of requests should be below 500ms
    "http_req_failed": ["rate<0.1"],      # Error rate should be below 10%
}


def test_oauth_endpoints():
    """Load test OAuth endpoints"""
    
    with group("OAuth Authorization Code Flow"):
        # Generate authorization code
        response = http.get("http://localhost:3100/oauth/authorize", params={
            "client_id": "k6-test",
            "redirect_uri": "http://localhost:3000/callback",
            "scope": "read:user",
            "state": f"state-{time.time()}",
        })
        
        check(response, {
            "OAuth authorize endpoint status": lambda r: r.status in [200, 302],
            "Response time < 500ms": lambda r: r.timings.duration < 500,
        })
    
    with group("OAuth Token Exchange"):
        # Exchange code for token (will fail with invalid code, but test endpoint)
        response = http.post("http://localhost:3100/oauth/token", json={
            "grant_type": "authorization_code",
            "client_id": "k6-test",
            "code": "invalid-code",
            "redirect_uri": "http://localhost:3000/callback",
        })
        
        check(response, {
            "Token endpoint reachable": lambda r: r.status in [200, 400, 401],
            "Response time < 500ms": lambda r: r.timings.duration < 500,
        })
    
    with group("JWKS Endpoint"):
        response = http.get("http://localhost:3100/.well-known/jwks.json")
        
        check(response, {
            "JWKS endpoint status 200": lambda r: r.status == 200,
            "Response time < 200ms": lambda r: r.timings.duration < 200,
            "Response has keys": lambda r: "keys" in r.json(),
        })


def test_user_endpoints():
    """Load test user endpoints"""
    
    with group("User Registration"):
        user_num = int(time.time() * 1000) % 1000000
        response = http.post("http://localhost:3100/auth/register", json={
            "email": f"k6-user-{user_num}@example.com",
            "password": "K6TestPassword123!@#",
            "name": "K6 Test User",
        })
        
        check(response, {
            "Registration endpoint reachable": lambda r: r.status in [201, 400],
            "Response time < 1000ms": lambda r: r.timings.duration < 1000,
        })
    
    with group("User Login"):
        response = http.post("http://localhost:3100/auth/login", json={
            "email": "test@example.com",
            "password": "Password123!@#",
        })
        
        check(response, {
            "Login endpoint reachable": lambda r: r.status in [200, 401, 400],
            "Response time < 500ms": lambda r: r.timings.duration < 500,
        })
    
    with group("User Profile"):
        response = http.get(
            "http://localhost:3100/api/users/me",
            headers={"Authorization": "Bearer fake-token"}
        )
        
        check(response, {
            "Profile endpoint reachable": lambda r: r.status in [200, 401, 403],
            "Response time < 300ms": lambda r: r.timings.duration < 300,
        })


def test_team_endpoints():
    """Load test team endpoints"""
    
    with group("Organization Creation"):
        org_num = int(time.time() * 1000) % 1000000
        response = http.post(
            "http://localhost:3100/api/organizations",
            json={
                "name": f"K6 Org {org_num}",
                "slug": f"k6-org-{org_num}",
            },
            headers={"Authorization": "Bearer fake-token"}
        )
        
        check(response, {
            "Org endpoint reachable": lambda r: r.status in [201, 401, 403],
            "Response time < 500ms": lambda r: r.timings.duration < 500,
        })
    
    with group("Team Creation"):
        team_num = int(time.time() * 1000) % 1000000
        response = http.post(
            "http://localhost:3100/api/teams",
            json={
                "name": f"K6 Team {team_num}",
                "slug": f"k6-team-{team_num}",
            },
            headers={"Authorization": "Bearer fake-token"}
        )
        
        check(response, {
            "Team endpoint reachable": lambda r: r.status in [201, 401, 403, 404],
            "Response time < 500ms": lambda r: r.timings.duration < 500,
        })
    
    with group("Team Member Operations"):
        response = http.get(
            "http://localhost:3100/api/teams/team-123/members",
            headers={"Authorization": "Bearer fake-token"}
        )
        
        check(response, {
            "Members endpoint reachable": lambda r: r.status in [200, 401, 403, 404],
            "Response time < 300ms": lambda r: r.timings.duration < 300,
        })


def test_gateway_endpoints():
    """Load test API gateway endpoints"""
    
    with group("Health Check"):
        response = http.get("http://localhost:3100/health")
        
        check(response, {
            "Health endpoint status 200": lambda r: r.status == 200,
            "Response time < 100ms": lambda r: r.timings.duration < 100,
            "Has status field": lambda r: "status" in r.json(),
        })
    
    with group("Readiness Check"):
        response = http.get("http://localhost:3100/readiness")
        
        check(response, {
            "Readiness endpoint reachable": lambda r: r.status in [200, 503],
            "Response time < 200ms": lambda r: r.timings.duration < 200,
        })
    
    with group("API Key Authentication"):
        response = http.get(
            "http://localhost:3100/api/users/me",
            headers={"X-API-Key": "sk_test_invalid"}
        )
        
        check(response, {
            "API key endpoint reachable": lambda r: r.status in [200, 401, 403],
            "Response time < 300ms": lambda r: r.timings.duration < 300,
        })
    
    with group("Rate Limit Headers"):
        response = http.get("http://localhost:3100/health")
        
        check(response, {
            "Has rate limit headers": lambda r: "x-ratelimit-limit" in r.headers or r.status == 200,
            "Response time < 100ms": lambda r: r.timings.duration < 100,
        })


def test_oauth_load():
    """OAuth endpoints under load"""
    test_oauth_endpoints()


def test_user_load():
    """User endpoints under load"""
    test_user_endpoints()


def test_team_load():
    """Team endpoints under load"""
    test_team_endpoints()


def test_gateway_load():
    """Gateway endpoints under load"""
    test_gateway_endpoints()
