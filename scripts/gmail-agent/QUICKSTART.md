# 🚀 Gmail Agent - Quick Start Guide

## Step 1️⃣: Install Dependencies (2 min)

### Recommended: Use Helper Scripts

#### Windows
```cmd
run.bat status
```
*First run will auto-create virtual environment*

#### Mac/Linux / Deployment Host
```bash
bash run.sh status
```
*First run will auto-create virtual environment*

### Manual Setup

#### Windows
```cmd
python -m venv venv
venv\Scripts\activate.bat
pip install -r requirements.txt
```

#### Mac/Linux
```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

---

## Step 2️⃣: Get Gmail Credentials (10 min)

1. **Open Google Cloud Console**: https://console.cloud.google.com/

2. **Create Project**:
   - Click "Create Project" at the top
   - Name it "Gmail Agent"
   - Click "Create"

3. **Enable Gmail API**:
   - Search for "Gmail API" in the search bar
   - Click "Gmail API"
   - Click "Enable"

4. **Create OAuth Credentials**:
   - Go to "Credentials" (left menu)
   - Click "Create Credentials" → "OAuth 2.0 Client ID"
   - Choose "Desktop application"
   - Click "Create"
   - Download the JSON file
   - Save as `credentials.json` in this directory

---

## Step 3️⃣: Set Your Anthropic API Key (2 min)

Get your API key from: https://console.anthropic.com/

```bash
python -m src.main config-api
# Enter your API key when prompted
```

Or manually create `.env`:
```
ANTHROPIC_API_KEY=sk-ant-your-actual-key
```

---

## Step 4️⃣: Test It Out! 🎉

Check that everything is configured:
```bash
# Windows
run.bat status

# Mac/Linux or Deployment Host
bash run.sh status
```

Try a simple search (you need Gmail credentials first):
```bash
# Windows
run.bat search "is:unread"

# Mac/Linux or Deployment Host
bash run.sh search "is:unread"
```

---

## 🚀 Deployment Host Setup

If running on your production host (192.168.168.31):

```bash
ssh akushnir@192.168.168.31
cd /home/akushnir/code-server-enterprise/scripts/gmail-agent
bash run.sh status
```

---

## 📚 Common Commands

```bash
# Search emails
python -m src.main search "from:boss@company.com"

# Search and summarize with AI
python -m src.main search "subject:meeting" --summarize

# Extract action items
python -m src.main search "project deadline" --actions

# Get more results
python -m src.main search "invoice" --max 25

# Chat interactively
python -m src.main chat

# Check setup status
python -m src.main status

# Redo setup
python -m src.main setup
```

---

## 💡 Advanced Gmail Queries

```bash
# From specific sender
python -m src.main search "from:john@example.com"

# Has attachments
python -m src.main search "has:attachment"

# Specific label
python -m src.main search "label:Work"

# Before/after dates
python -m src.main search "before:2024-01-01"
python -m src.main search "after:2024-01-01"

# Unread emails
python -m src.main search "is:unread"

# Starred emails
python -m src.main search "is:starred"

# Subject contains
python -m src.main search "subject:important"

# Body contains
python -m src.main search "urgent help needed"
```

---

## 🆘 Troubleshooting

### "credentials.json not found"
→ Download it from Google Cloud Console (see Step 2)

### "Anthropic API key not configured"
→ Run `python -m src.main config-api` or set `.env`

### Gmail auth fails
→ Delete `token.json` and try again (will re-authenticate)

### Import errors
→ Make sure dependencies are installed: `pip install -r requirements.txt`

---

## 🎯 What's Next?

Your Gmail agent can now:
- ✅ Search your emails
- ✅ Summarize multiple emails
- ✅ Extract action items
- ✅ Chat about your emails

Future features:
- 🔄 Email labeling automation
- 📅 Scheduled searches
- 🤖 Smart inbox management
- 🔔 Alert on important emails

---

**Questions?** Check the README.md for full documentation!
