@echo off
echo 📧 Gmail Agent Setup
echo.

REM Check Python
python --version >nul 2>&1
if errorlevel 1 (
    echo ❌ Python is required but not installed
    exit /b 1
)

echo ✅ Python found: 
python --version
echo.

REM Install dependencies
echo 📦 Installing dependencies...
pip install -r requirements.txt

echo.
echo ✅ Installation complete!
echo.
echo 📋 Next steps:
echo 1. Get Gmail OAuth credentials:
echo    - Go to https://console.cloud.google.com/
echo    - Create a new project and enable Gmail API
echo    - Create OAuth 2.0 Desktop credentials
echo    - Download as credentials.json
echo.
echo 2. Set up your Anthropic API key:
echo    python -m src.main config-api
echo.
echo 3. Test with a search:
echo    python -m src.main search "is:unread"
echo.
echo 4. Check status anytime:
echo    python -m src.main status
