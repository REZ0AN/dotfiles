#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${1:-$HOME/.local/bin}"

echo "==> Installing Codex CLI"
echo "==> Install directory: $INSTALL_DIR"

mkdir -p "$INSTALL_DIR"

CODEX_INSTALL_DIR="$INSTALL_DIR" \
  curl -fsSL https://chatgpt.com/codex/install.sh | sh

echo

if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
  echo "==> Adding $INSTALL_DIR to ~/.bashrc"

  if ! grep -qxF "export PATH=\"\$PATH:$INSTALL_DIR\"" "$HOME/.bashrc" 2>/dev/null; then
    echo "export PATH=\"\$PATH:$INSTALL_DIR\"" >> "$HOME/.bashrc"
  fi

  export PATH="$PATH:$INSTALL_DIR"
fi

echo
echo "==> Installation complete"

"$INSTALL_DIR/codex" --version