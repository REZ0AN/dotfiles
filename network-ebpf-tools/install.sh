#!/usr/bin/env bash
set -euo pipefail

echo "==> Updating package index..."
sudo apt-get update

echo "==> Installing core development, eBPF, networking, and debugging packages..."
sudo apt-get install -y \
  clang \
  llvm \
  libelf-dev \
  libbpf-dev \
  libpcap-dev \
  build-essential \
  linux-tools-common \
  linux-headers-generic \
  linux-tools-generic \
  iproute2 \
  iputils-ping \
  dwarves \
  tcpdump \
  bind9-dnsutils

KERNEL_VERSION="$(uname -r)"

echo "==> Current kernel: ${KERNEL_VERSION}"

echo "==> Attempting to install kernel-specific headers..."
if apt-cache show "linux-headers-${KERNEL_VERSION}" >/dev/null 2>&1; then
  sudo apt-get install -y "linux-headers-${KERNEL_VERSION}"
else
  echo "WARN: linux-headers-${KERNEL_VERSION} is not available in the configured repositories."
fi

echo "==> Attempting to install kernel-specific tools..."
if apt-cache show "linux-tools-${KERNEL_VERSION}" >/dev/null 2>&1; then
  sudo apt-get install -y "linux-tools-${KERNEL_VERSION}"
else
  echo "WARN: linux-tools-${KERNEL_VERSION} is not available in the configured repositories."
fi

echo
echo "==> Installation complete."
echo
echo "Installed versions:"
clang --version | head -n 1 || true
llvm-config --version || true
gcc --version | head -n 1 || true
pahole --version || true
tcpdump --version | head -n 1 || true
ip -V || true