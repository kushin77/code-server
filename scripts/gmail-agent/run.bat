@echo off
REM Gmail Agent Runner Script - Windows
REM Automatically sets up and uses the virtual environment

setlocal enabledelayedexpansion
cd /d "%~dp0"

REM Create venv if it doesn't exist
if not exist "venv" (
    echo 📦 Creating virtual environment...
    python -m venv venv
)

REM Activate venv and run
call venv\Scripts\activate.bat
python -m src.main %*
