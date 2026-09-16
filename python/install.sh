#!/usr/bin/env bash
set -euo pipefail

PYTHON_VERSION="${1:-}"

if [[ -z "$PYTHON_VERSION" ]]; then
  echo "Usage: $0 <python-version>"
  echo "Example: $0 3.12.11"
  exit 1
fi

TARBALL="Python-${PYTHON_VERSION}.tgz"
URL="https://www.python.org/ftp/python/${PYTHON_VERSION}/${TARBALL}"

echo "==> Installing Python ${PYTHON_VERSION}"

sudo apt-get update
sudo apt-get install -y \
  build-essential \
  wget \
  curl \
  libssl-dev \
  zlib1g-dev \
  libbz2-dev \
  libreadline-dev \
  libsqlite3-dev \
  libffi-dev \
  liblzma-dev \
  tk-dev \
  uuid-dev \
  libncursesw5-dev \
  xz-utils

curl -fLO "$URL"

tar -xzf "$TARBALL"
cd "Python-${PYTHON_VERSION}"

./configure \
  --enable-optimizations \
  --with-ensurepip=install

make -j"$(nproc)"

sudo make altinstall

cd ..
rm -rf "Python-${PYTHON_VERSION}" "$TARBALL"

PYTHON_MINOR="$(echo "$PYTHON_VERSION" | cut -d. -f1,2)"

echo
echo "==> Installation complete"
"python${PYTHON_MINOR}" --version
"python${PYTHON_MINOR}" -m pip --version