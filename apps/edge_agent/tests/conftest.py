"""Edge agent test configuration."""


def pytest_configure(config):
    """Scope pytest-cov to the edge-agent package for this test subtree."""
    if hasattr(config.option, "cov_source"):
        config.option.cov_source = ["apps/edge_agent"]