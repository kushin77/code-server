# 📧 Gmail Agent - AI-Powered Email Management

A CLI tool that uses Gmail API and Claude AI to help you search, analyze, and manage your emails intelligently.

## Features

- 🔍 **Smart Search**: Search emails with Gmail query syntax
- 🤖 **AI Analysis**: Summarize emails and extract action items with Claude
- 💬 **Interactive Chat**: Ask questions about your emails
- 🏷️ **Label Suggestions**: Get AI-powered label recommendations
- ⚡ **Fast & Efficient**: Batch process multiple emails at once

## Quick Start

### 1. Install Dependencies

```bash
pip install -r requirements.txt
```

### 2. Set Up Gmail OAuth

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project
3. Enable the Gmail API
4. Create OAuth 2.0 Desktop credentials
5. Download as `credentials.json` and place in this directory

### 3. Configure Anthropic API

```bash
python -m src.main config-api
```

Or manually set in `.env`:
```
ANTHROPIC_API_KEY=sk-ant-your-key-here
```

### 4. Run the Agent

```bash
python -m src.main search "your search query"
```

## Usage Examples

### Search Emails
```bash
# Basic search
python -m src.main search "from:boss@company.com"

# Search and summarize with AI
python -m src.main search "subject:urgent" --summarize

# Extract action items
python -m src.main search "project" --actions

# Get more results
python -m src.main search "invoice" --max 20
```

### Interactive Chat
```bash
python -m src.main chat
```

Then ask questions like:
- "What are the most important emails I received today?"
- "Summarize emails about the Q2 planning"
- "Are there any urgent emails from my manager?"

### Check Status
```bash
python -m src.main status
```

### Setup Assistant
```bash
python -m src.main setup
```

## Gmail Search Queries

You can use any [Gmail search syntax](https://support.google.com/mail/answer/7190):

```bash
python -m src.main search "from:user@example.com"           # From specific sender
python -m src.main search "subject:meeting"                 # Subject contains
python -m src.main search "has:attachment"                  # Has attachments
python -m src.main search "is:unread"                       # Unread emails
python -m src.main search "before:2024-01-01"              # Before date
python -m src.main search "label:Work"                      # Specific label
```

## Configuration

Create `.env` file (or copy from `.env.example`):

```env
# Gmail OAuth
GMAIL_CLIENT_ID=your-client-id.apps.googleusercontent.com
GMAIL_CLIENT_SECRET=your-client-secret

# Claude API
ANTHROPIC_API_KEY=sk-ant-your-api-key

# Optional
MAX_RESULTS=10
GMAIL_CREDENTIALS_FILE=credentials.json
GMAIL_TOKEN_FILE=token.json
```

## Architecture

- `src/config.py` - Configuration management
- `src/gmail_client.py` - Gmail API wrapper
- `src/ai_analyzer.py` - Claude AI integration
- `src/main.py` - CLI interface

## Troubleshooting

### "credentials.json not found"
- Download your OAuth credentials from Google Cloud Console
- Place it in the project root directory

### "Anthropic API key not found"
- Run `python -m src.main config-api` or set `ANTHROPIC_API_KEY` in `.env`

### Gmail authentication fails
- Delete `token.json` and try again (will prompt for fresh authentication)
- Check that Gmail API is enabled in Google Cloud Console

## Next Steps

- [ ] Add email labeling/organization
- [ ] Create scheduled tasks for recurring searches
- [ ] Add email composition with AI assistance
- [ ] Implement email filtering rules
- [ ] Build web dashboard for better UX

## License

MIT
