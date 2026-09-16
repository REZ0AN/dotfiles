#!/usr/bin/env bash
set -euo pipefail

KEY_PATH="${1:-}"
EMAIL="${2:-}"

if [[ -z "$KEY_PATH" || -z "$EMAIL" ]]; then
  echo "Usage: $0 <key-path> <github-email>"
  echo "Example: $0 ~/.ssh/github_ed25519 you@example.com"
  exit 1
fi

mkdir -p "$(dirname "$KEY_PATH")"

ssh-keygen \
  -t ed25519 \
  -C "$EMAIL" \
  -f "$KEY_PATH"

echo
echo "Public key:"
cat "${KEY_PATH}.pub"