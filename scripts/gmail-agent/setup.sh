#!/bin/bash

echo "📧 Gmail Agent Setup"
echo ""

# Check Python
if ! command -v python3 &> /dev/null; then
    echo "❌ Python 3 is required but not installed"
    exit 1
fi

echo "✅ Python found: $(python3 --version)"
echo ""

# Install dependencies
echo "📦 Installing dependencies..."
pip install -r requirements.txt

echo ""
echo "✅ Installation complete!"
echo ""
echo "📋 Next steps:"
echo "1. Get Gmail OAuth credentials:"
echo "   - Go to https://console.cloud.google.com/"
echo "   - Create a new project and enable Gmail API"
echo "   - Create OAuth 2.0 Desktop credentials"
echo "   - Download as credentials.json"
echo ""
echo "2. Set up your Anthropic API key:"
echo "   python -m src.main config-api"
echo ""
echo "3. Test with a search:"
echo "   python -m src.main search 'is:unread'"
echo ""
echo "4. Check status anytime:"
echo "   python -m src.main status"
