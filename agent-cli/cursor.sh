#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="$HOME/.local/bin"

echo "==> Installing Cursor Agent CLI"

curl https://cursor.com/install -fsS | bash

if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
  echo "==> Adding $INSTALL_DIR to ~/.bashrc"

  if ! grep -qxF 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.bashrc" 2>/dev/null; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
  fi

  export PATH="$HOME/.local/bin:$PATH"
fi

echo
echo "==> Installation complete"

agent --version