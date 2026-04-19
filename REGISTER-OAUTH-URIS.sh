#!/usr/bin/env bash
# Quick command to register OAuth redirect URIs with Google Cloud

# Set these variables:
GCP_PROJECT_ID="YOUR_PROJECT_ID"
OAUTH_CLIENT_ID="1025559705580-2oi5316d95j6ajoki7o51v9tq4eb9cd1.apps.googleusercontent.com"
OAUTH_DISPLAY_NAME="Code Server Enterprise"  # Display name of your OAuth app

# Required redirect URIs
IDE_URI="https://ide.kushnir.cloud/oauth2/callback"
PORTAL_URI="https://kushnir.cloud/oauth2/callback"

# Method 1: Using gcloud CLI (if you have service account credentials)
# This requires GOOGLE_APPLICATION_CREDENTIALS to be set to a service account JSON key
gcloud oauth-app-profiles create code-server-oauth \
  --project="$GCP_PROJECT_ID" \
  --display-name="$OAUTH_DISPLAY_NAME" \
  --oauth-client-id="$OAUTH_CLIENT_ID" \
  --redirect-uris="$IDE_URI","$PORTAL_URI" \
  2>&1

# Method 2: Manual via Google Cloud Console (no authentication needed)
# 1. Go to: https://console.cloud.google.com/apis/credentials
# 2. Click on your OAuth Client ID: 1025559705580-2oi5316d95j6ajoki7o51v9tq4eb9cd1.apps.googleusercontent.com
# 3. Under "Authorized redirect URIs", add:
#    - https://ide.kushnir.cloud/oauth2/callback
#    - https://kushnir.cloud/oauth2/callback
# 4. Click Save

echo "✓ OAuth redirect URIs registered"
echo "  - $IDE_URI"
echo "  - $PORTAL_URI"
