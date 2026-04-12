#!/bin/bash
# Enterprise Code-Server Setup Script

set -e

echo "🚀 Setting up Enterprise Code-Server Deployment..."

# Create necessary directories
mkdir -p ~/code-server-enterprise/workspaces
mkdir -p ~/code-server-enterprise/configs

# Set permissions
chmod 755 ~/code-server-enterprise/workspaces

echo "✅ Directories created"

# Create .env file for sensitive data
cat > ~/code-server-enterprise/.env << EOF
# Update these with your actual values
CODE_SERVER_PASSWORD=changeme-enterprise-pwd
CODE_SERVER_SUDO_PASSWORD=changeme-sudo-pwd
CADDY_EMAIL=admin@example.com

# OAuth2 Settings (optional)
GITHUB_CLIENT_ID=your-github-app-id
GITHUB_CLIENT_SECRET=your-github-secret
EOF

echo "⚠️  Configuration file created: ~/.code-server-enterprise/.env"
echo "    Please update with your actual credentials!"

# Display next steps
echo ""
echo "📋 Next Steps:"
echo "  1. Edit ~/.code-server-enterprise/.env with your credentials"
echo "  2. Run: docker-compose -f ~/code-server-enterprise/docker-compose.yml up -d"
echo "  3. Access: https://localhost (accept self-signed cert)"
echo ""
echo "✨ Enterprise deployment ready!"
