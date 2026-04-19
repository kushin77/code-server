"""Configuration management for Gmail Agent."""

import os
from pathlib import Path
from dotenv import load_dotenv

# Load environment variables
env_path = Path(__file__).parent.parent / ".env"
load_dotenv(env_path)


class Config:
    """Gmail Agent configuration."""

    # Gmail API
    GMAIL_CLIENT_ID = os.getenv("GMAIL_CLIENT_ID", "")
    GMAIL_CLIENT_SECRET = os.getenv("GMAIL_CLIENT_SECRET", "")
    GMAIL_CREDENTIALS_FILE = os.getenv("GMAIL_CREDENTIALS_FILE", "credentials.json")
    GMAIL_TOKEN_FILE = os.getenv("GMAIL_TOKEN_FILE", "token.json")

    # Claude API
    ANTHROPIC_API_KEY = os.getenv("ANTHROPIC_API_KEY", "")

    # Settings
    MAX_RESULTS = int(os.getenv("MAX_RESULTS", "10"))
    GMAIL_SCOPES = ["https://www.googleapis.com/auth/gmail.readonly"]

    @classmethod
    def validate(cls) -> bool:
        """Validate that all required environment variables are set."""
        required = ["ANTHROPIC_API_KEY"]
        missing = [var for var in required if not getattr(cls, var)]
        
        if missing:
            print(f"❌ Missing required environment variables: {', '.join(missing)}")
            return False
        return True
