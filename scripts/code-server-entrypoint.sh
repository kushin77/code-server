#!/bin/sh
set -eu

EXT_DIR="/home/coder/.local/share/code-server/extensions"
mkdir -p "$EXT_DIR"

if ! /usr/bin/code-server --list-extensions --extensions-dir "$EXT_DIR" | grep -qi '^github.copilot$'; then
	/usr/bin/code-server --install-extension /opt/vsix/github-copilot.vsix --extensions-dir "$EXT_DIR" --force >/tmp/copilot-install.log 2>&1 || true
fi

if ! /usr/bin/code-server --list-extensions --extensions-dir "$EXT_DIR" | grep -qi '^github.copilot-chat$'; then
	/usr/bin/code-server --install-extension /opt/vsix/github-copilot-chat.vsix --extensions-dir "$EXT_DIR" --force >/tmp/copilot-chat-install.log 2>&1 || true
fi

exec /usr/bin/code-server "$@"
