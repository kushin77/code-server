"""Gmail API client wrapper."""

import os
import pickle
from typing import Optional, List, Dict, Any
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build

from .config import Config


class GmailClient:
    """Wrapper around Gmail API."""

    def __init__(self):
        """Initialize Gmail client."""
        self.service = None
        self.creds = None

    def authenticate(self) -> bool:
        """Authenticate with Gmail API using OAuth."""
        token_file = Config.GMAIL_TOKEN_FILE

        # Load existing token if available
        if os.path.exists(token_file):
            with open(token_file, "rb") as token:
                self.creds = pickle.load(token)

        # If no valid credentials, get new ones
        if not self.creds or not self.creds.valid:
            if self.creds and self.creds.expired and self.creds.refresh_token:
                self.creds.refresh(Request())
            else:
                if not os.path.exists(Config.GMAIL_CREDENTIALS_FILE):
                    print("❌ credentials.json not found. Please set up OAuth credentials.")
                    print("   See README.md for instructions.")
                    return False

                flow = InstalledAppFlow.from_client_secrets_file(
                    Config.GMAIL_CREDENTIALS_FILE,
                    Config.GMAIL_SCOPES
                )
                self.creds = flow.run_local_server(port=0)

            # Save token for next run
            with open(token_file, "wb") as token:
                pickle.dump(self.creds, token)

        # Build Gmail service
        self.service = build("gmail", "v1", credentials=self.creds)
        print("✅ Gmail authenticated successfully")
        return True

    def search_emails(self, query: str, max_results: Optional[int] = None) -> List[Dict[str, Any]]:
        """
        Search for emails matching a query.
        
        Args:
            query: Gmail search query (e.g., "from:user@example.com", "subject:test")
            max_results: Maximum number of results to return (default from Config)
            
        Returns:
            List of email metadata
        """
        if not self.service:
            raise RuntimeError("Not authenticated. Call authenticate() first.")

        max_results = max_results or Config.MAX_RESULTS
        
        try:
            results = self.service.users().messages().list(
                userId="me",
                q=query,
                maxResults=max_results
            ).execute()
            
            messages = results.get("messages", [])
            print(f"📧 Found {len(messages)} emails")
            return messages
        except Exception as e:
            print(f"❌ Search failed: {e}")
            return []

    def get_email(self, message_id: str) -> Optional[Dict[str, Any]]:
        """
        Get full email details.
        
        Args:
            message_id: Gmail message ID
            
        Returns:
            Full email data or None if error
        """
        if not self.service:
            raise RuntimeError("Not authenticated. Call authenticate() first.")

        try:
            message = self.service.users().messages().get(
                userId="me",
                id=message_id,
                format="full"
            ).execute()
            return message
        except Exception as e:
            print(f"❌ Failed to get email: {e}")
            return None

    def get_email_text(self, message: Dict[str, Any]) -> str:
        """Extract email text from message object."""
        try:
            headers = message["payload"]["headers"]
            subject = next((h["value"] for h in headers if h["name"] == "Subject"), "No Subject")
            sender = next((h["value"] for h in headers if h["name"] == "From"), "Unknown")
            
            body = ""
            if "parts" in message["payload"]:
                for part in message["payload"]["parts"]:
                    if part["mimeType"] == "text/plain":
                        data = part["body"].get("data", "")
                        if data:
                            import base64
                            body = base64.urlsafe_b64decode(data).decode("utf-8")
                            break
            else:
                data = message["payload"]["body"].get("data", "")
                if data:
                    import base64
                    body = base64.urlsafe_b64decode(data).decode("utf-8")
            
            return f"From: {sender}\nSubject: {subject}\n\n{body}"
        except Exception as e:
            print(f"❌ Failed to extract email text: {e}")
            return ""
