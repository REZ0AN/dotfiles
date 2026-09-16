#!/usr/bin/env bash
set -euo pipefail

NODE_VERSION="${1:-}"

if [[ -z "$NODE_VERSION" ]]; then
  echo "Usage: $0 <node-version>"
  echo "Example: $0 22"
  echo "Example: $0 22.18.0"
  exit 1
fi

export NVM_DIR="$HOME/.nvm"

if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
  echo "==> Installing nvm"

  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
fi

# Load nvm into this shell
# shellcheck disable=SC1090
source "$NVM_DIR/nvm.sh"

echo "==> Installing Node.js ${NODE_VERSION}"

nvm install "$NODE_VERSION"
nvm alias default "$NODE_VERSION"
nvm use "$NODE_VERSION"

echo
echo "==> Installation complete"
node --version
npm --version
nvm current