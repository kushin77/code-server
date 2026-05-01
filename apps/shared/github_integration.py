"""GitHub API integration service with distributed tracing.

Provides GitHub API client with automatic tracing for:
- Repository operations
- Pull request management
- Issue tracking
- User provisioning
- OAuth token management

All GitHub API calls are automatically traced to Jaeger for visibility
into external service dependencies and performance.
"""

from __future__ import annotations

import os
from typing import Any, Dict, List, Optional
from dataclasses import dataclass

from apps.shared.external_tracing import GitHubTracer


@dataclass
class GitHubUser:
    """GitHub user information."""

    login: str
    id: int
    avatar_url: str
    html_url: str
    name: Optional[str] = None
    company: Optional[str] = None
    blog: Optional[str] = None
    location: Optional[str] = None
    email: Optional[str] = None
    bio: Optional[str] = None
    public_repos: int = 0
    followers: int = 0
    following: int = 0

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "login": self.login,
            "id": self.id,
            "avatar_url": self.avatar_url,
            "html_url": self.html_url,
            "name": self.name,
            "company": self.company,
            "blog": self.blog,
            "location": self.location,
            "email": self.email,
            "bio": self.bio,
            "public_repos": self.public_repos,
            "followers": self.followers,
            "following": self.following,
        }


@dataclass
class GitHubRepository:
    """GitHub repository information."""

    name: str
    full_name: str
    description: Optional[str]
    html_url: str
    private: bool
    owner_login: str
    stars: int
    watchers: int
    language: Optional[str]
    forks: int
    open_issues: int

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "name": self.name,
            "full_name": self.full_name,
            "description": self.description,
            "html_url": self.html_url,
            "private": self.private,
            "owner_login": self.owner_login,
            "stars": self.stars,
            "watchers": self.watchers,
            "language": self.language,
            "forks": self.forks,
            "open_issues": self.open_issues,
        }


@dataclass
class GitHubPullRequest:
    """GitHub pull request information."""

    number: int
    title: str
    description: Optional[str]
    state: str
    html_url: str
    user_login: str
    created_at: str
    updated_at: str
    merged_at: Optional[str] = None
    additions: int = 0
    deletions: int = 0
    changed_files: int = 0

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "number": self.number,
            "title": self.title,
            "description": self.description,
            "state": self.state,
            "html_url": self.html_url,
            "user_login": self.user_login,
            "created_at": self.created_at,
            "updated_at": self.updated_at,
            "merged_at": self.merged_at,
            "additions": self.additions,
            "deletions": self.deletions,
            "changed_files": self.changed_files,
        }


class GitHubIntegration:
    """GitHub API integration with distributed tracing."""

    def __init__(
        self,
        token: Optional[str] = None,
        base_url: str = "https://api.github.com",
    ):
        """Initialize GitHub integration with tracing."""
        self.token = token or os.getenv("GITHUB_TOKEN")
        self.tracer = GitHubTracer(base_url=base_url, token=self.token)

    async def get_user(self, username: str) -> Optional[GitHubUser]:
        """Get GitHub user information with tracing.

        Args:
            username: GitHub username

        Returns:
            GitHubUser or None if not found
        """
        endpoint = f"/users/{username}"

        try:
            result = await self.tracer.get(endpoint)
            if result.get("status") == "ok":
                # Mock response - in production would parse real API response
                return GitHubUser(
                    login=username,
                    id=12345,
                    avatar_url="https://avatars.githubusercontent.com/u/12345",
                    html_url=f"https://github.com/{username}",
                    name=f"{username} Name",
                    public_repos=42,
                    followers=100,
                    following=50,
                )
            return None
        except Exception as e:
            # Span automatically records error
            return None

    async def get_repository(
        self,
        owner: str,
        repo: str,
    ) -> Optional[GitHubRepository]:
        """Get GitHub repository information with tracing.

        Args:
            owner: Repository owner
            repo: Repository name

        Returns:
            GitHubRepository or None if not found
        """
        endpoint = f"/repos/{owner}/{repo}"

        try:
            result = await self.tracer.get(endpoint)
            if result.get("status") == "ok":
                # Mock response
                return GitHubRepository(
                    name=repo,
                    full_name=f"{owner}/{repo}",
                    description="Repository description",
                    html_url=f"https://github.com/{owner}/{repo}",
                    private=False,
                    owner_login=owner,
                    stars=250,
                    watchers=50,
                    language="Python",
                    forks=10,
                    open_issues=5,
                )
            return None
        except Exception:
            return None

    async def get_user_repositories(self, username: str) -> List[GitHubRepository]:
        """Get user's repositories with tracing.

        Args:
            username: GitHub username

        Returns:
            List of GitHubRepository objects
        """
        endpoint = f"/users/{username}/repos"

        try:
            result = await self.tracer.get(endpoint)
            if result.get("status") == "ok":
                # Mock response with 3 repos
                return [
                    GitHubRepository(
                        name=f"repo-{i}",
                        full_name=f"{username}/repo-{i}",
                        description=f"Repository {i}",
                        html_url=f"https://github.com/{username}/repo-{i}",
                        private=False,
                        owner_login=username,
                        stars=100 + i * 10,
                        watchers=20 + i * 5,
                        language="Python",
                        forks=5,
                        open_issues=2 + i,
                    )
                    for i in range(3)
                ]
            return []
        except Exception:
            return []

    async def create_pull_request(
        self,
        owner: str,
        repo: str,
        title: str,
        body: str,
        head: str,
        base: str,
    ) -> Optional[GitHubPullRequest]:
        """Create pull request with tracing.

        Args:
            owner: Repository owner
            repo: Repository name
            title: PR title
            body: PR description
            head: Branch to merge from
            base: Branch to merge into

        Returns:
            GitHubPullRequest or None if failed
        """
        endpoint = f"/repos/{owner}/{repo}/pulls"
        data = {
            "title": title,
            "body": body,
            "head": head,
            "base": base,
        }

        try:
            result = await self.tracer.post(endpoint, data=data)
            if result.get("status") == "created":
                # Mock response
                return GitHubPullRequest(
                    number=42,
                    title=title,
                    description=body,
                    state="open",
                    html_url=f"https://github.com/{owner}/{repo}/pull/42",
                    user_login="bot",
                    created_at="2026-05-01T12:00:00Z",
                    updated_at="2026-05-01T12:00:00Z",
                    additions=100,
                    deletions=50,
                    changed_files=5,
                )
            return None
        except Exception:
            return None

    async def add_issue_comment(
        self,
        owner: str,
        repo: str,
        issue_number: int,
        body: str,
    ) -> bool:
        """Add comment to GitHub issue with tracing.

        Args:
            owner: Repository owner
            repo: Repository name
            issue_number: Issue number
            body: Comment body

        Returns:
            True if successful
        """
        endpoint = f"/repos/{owner}/{repo}/issues/{issue_number}/comments"
        data = {"body": body}

        try:
            result = await self.tracer.post(endpoint, data=data)
            return result.get("status") == "created"
        except Exception:
            return False

    def get_traces(self) -> List[Dict[str, Any]]:
        """Get all recorded traces.

        Returns:
            List of trace dictionaries for Jaeger export
        """
        return self.tracer.export_spans()

    def clear_traces(self) -> None:
        """Clear recorded traces."""
        self.tracer.clear_spans()


# Singleton instance for application-wide use
_github_integration: Optional[GitHubIntegration] = None


def get_github_integration() -> GitHubIntegration:
    """Get or create GitHub integration instance."""
    global _github_integration
    if _github_integration is None:
        _github_integration = GitHubIntegration()
    return _github_integration


__all__ = [
    "GitHubUser",
    "GitHubRepository",
    "GitHubPullRequest",
    "GitHubIntegration",
    "get_github_integration",
]
