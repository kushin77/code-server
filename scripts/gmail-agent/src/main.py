"""CLI interface for Gmail Agent."""

import click
from .config import Config
from .gmail_client import GmailClient
from .ai_analyzer import EmailAnalyzer


@click.group()
def cli():
    """📧 Gmail Agent - AI-powered email management."""
    pass


@cli.command()
@click.argument("query")
@click.option("--max", default=None, type=int, help="Maximum emails to fetch")
@click.option("--summarize", is_flag=True, help="Summarize found emails with AI")
@click.option("--actions", is_flag=True, help="Extract action items")
def search(query: str, max: int, summarize: bool, actions: bool):
    """Search for emails matching a query."""
    if not Config.validate():
        return

    gmail = GmailClient()
    if not gmail.authenticate():
        return

    # Search for emails
    messages = gmail.search_emails(query, max)
    if not messages:
        click.echo("No emails found.")
        return

    # Get full email details
    emails_text = []
    for msg in messages[:5]:  # Limit to 5 for AI analysis
        email = gmail.get_email(msg["id"])
        if email:
            text = gmail.get_email_text(email)
            emails_text.append(text)
            click.echo(f"\n📨 Found: {email['payload']['headers'][0]['value']}")

    # AI analysis if requested
    if summarize or actions:
        analyzer = EmailAnalyzer()
        click.echo("\n🤖 Analyzing with AI...")
        
        if summarize:
            summary = analyzer.summarize_emails(emails_text)
            click.echo(f"\n📝 Summary:\n{summary}")
        
        if actions:
            items = analyzer.extract_action_items(emails_text)
            click.echo(f"\n✅ Action Items:\n{items}")


@cli.command()
def chat():
    """Interactive chat with AI about your emails."""
    if not Config.validate():
        return

    analyzer = EmailAnalyzer()
    click.echo("💬 Chat mode (type 'exit' to quit)")
    click.echo("Ask questions about your emails or get help organizing them.\n")

    while True:
        try:
            user_input = click.prompt("You")
            if user_input.lower() == "exit":
                break
            
            response = analyzer.chat(user_input)
            click.echo(f"\nAssistant: {response}\n")
        except KeyboardInterrupt:
            break
        except Exception as e:
            click.echo(f"❌ Error: {e}")


@cli.command()
def setup():
    """Setup Gmail OAuth credentials."""
    click.echo("📋 Gmail Agent Setup\n")
    
    creds_file = click.prompt(
        "Path to credentials.json",
        default="credentials.json"
    )
    
    import os
    import json
    
    if not os.path.exists(creds_file):
        click.echo(f"❌ {creds_file} not found")
        click.echo("\n📖 To set up OAuth credentials:")
        click.echo("1. Go to https://console.cloud.google.com/")
        click.echo("2. Create a new project")
        click.echo("3. Enable Gmail API")
        click.echo("4. Create OAuth 2.0 Desktop Application credentials")
        click.echo("5. Download as credentials.json")
        return
    
    gmail = GmailClient()
    if gmail.authenticate():
        click.echo("✅ Setup complete! You can now use the agent.")
    else:
        click.echo("❌ Setup failed")


@cli.command()
@click.option("--anthropic-key", prompt=False, hide_input=True, help="Your Anthropic API key")
def config_api(anthropic_key: str):
    """Configure API keys."""
    click.echo("🔑 Configuring API keys...\n")
    
    if anthropic_key:
        # Create .env file with API key
        with open(".env", "w") as f:
            f.write(f"ANTHROPIC_API_KEY={anthropic_key}\n")
        click.echo("✅ API key saved to .env")
    else:
        click.echo("ℹ️  Set ANTHROPIC_API_KEY in your .env file")
        click.echo("📝 See .env.example for the format")


@cli.command()
def status():
    """Check agent status and configuration."""
    click.echo("📊 Gmail Agent Status\n")
    
    # Check API key
    if Config.ANTHROPIC_API_KEY:
        click.echo("✅ Anthropic API key: Configured")
    else:
        click.echo("❌ Anthropic API key: Not configured")
    
    # Check Gmail credentials
    import os
    if os.path.exists(Config.GMAIL_CREDENTIALS_FILE):
        click.echo(f"✅ Gmail credentials: Found ({Config.GMAIL_CREDENTIALS_FILE})")
    else:
        click.echo(f"❌ Gmail credentials: Not found")
    
    if os.path.exists(Config.GMAIL_TOKEN_FILE):
        click.echo(f"✅ Gmail token: Cached ({Config.GMAIL_TOKEN_FILE})")
    else:
        click.echo(f"⚪ Gmail token: Not cached (will generate on first use)")


if __name__ == "__main__":
    cli()
