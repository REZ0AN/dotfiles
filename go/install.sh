#!/usr/bin/env bash
set -euo pipefail

GO_VERSION="${1:-}"
ARCH="${2:-}"

if [[ -z "$GO_VERSION" || -z "$ARCH" ]]; then
  echo "Usage: $0 <go-version> <arch>"
  echo "Example: $0 1.26.3 arm64"
  exit 1
fi

TARBALL="go${GO_VERSION}.linux-${ARCH}.tar.gz"
URL="https://go.dev/dl/${TARBALL}"

echo "==> Installing Go ${GO_VERSION} for ${ARCH}"

curl -fLO "$URL"

sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf "$TARBALL"

rm -f "$TARBALL"

if ! grep -qxF 'export PATH=$PATH:/usr/local/go/bin' ~/.bashrc; then
  echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
fi

if ! grep -qxF 'export PATH=$PATH:$(go env GOPATH)/bin' ~/.bashrc; then
  echo 'export PATH=$PATH:$(go env GOPATH)/bin' >> ~/.bashrc
fi

export PATH="$PATH:/usr/local/go/bin"
export PATH="$PATH:$(go env GOPATH)/bin"

echo
echo "==> Installation complete"
go version