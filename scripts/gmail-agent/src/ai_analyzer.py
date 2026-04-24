"""Claude AI integration for email analysis."""

from typing import Optional, List, Dict, Any
from anthropic import Anthropic

from .config import Config


class EmailAnalyzer:
    """AI-powered email analyzer using Claude."""

    def __init__(self):
        """Initialize AI analyzer."""
        self.client = Anthropic()
        self.conversation_history: List[Dict[str, str]] = []

    def analyze_emails(self, emails: List[str], task: str) -> str:
        """
        Analyze multiple emails with AI.
        
        Args:
            emails: List of email texts to analyze
            task: What to do with the emails (e.g., "summarize", "extract action items")
            
        Returns:
            AI-generated analysis
        """
        email_text = "\n\n---\n\n".join(emails)
        
        prompt = f"""I have the following emails:

{email_text}

Please {task}."""

        return self.chat(prompt)

    def chat(self, user_message: str) -> str:
        """
        Send a message to Claude and maintain conversation history.
        
        Args:
            user_message: User's message
            
        Returns:
            Claude's response
        """
        # Add user message to history
        self.conversation_history.append({
            "role": "user",
            "content": user_message
        })

        try:
            response = self.client.messages.create(
                model="claude-3-5-sonnet-20241022",
                max_tokens=2048,
                system="You are an intelligent email management assistant. Help the user analyze, organize, and understand their emails efficiently.",
                messages=self.conversation_history
            )

            assistant_message = response.content[0].text
            
            # Add assistant response to history
            self.conversation_history.append({
                "role": "assistant",
                "content": assistant_message
            })

            return assistant_message
        except Exception as e:
            error_msg = f"❌ AI analysis failed: {e}"
            print(error_msg)
            return error_msg

    def summarize_emails(self, emails: List[str]) -> str:
        """Summarize a list of emails."""
        return self.analyze_emails(emails, "summarize these emails concisely")

    def extract_action_items(self, emails: List[str]) -> str:
        """Extract action items from emails."""
        return self.analyze_emails(emails, "extract all action items with deadlines")

    def suggest_labels(self, email: str) -> str:
        """Suggest Gmail labels for an email."""
        prompt = f"""Based on this email, suggest appropriate Gmail labels:

{email}

Format: comma-separated labels (e.g., Important, Work, Follow-up)"""
        return self.chat(prompt)
