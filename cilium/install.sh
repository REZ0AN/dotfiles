#!/usr/bin/env bash
set -euo pipefail

PAUSE_BETWEEN_STEPS="${PAUSE_BETWEEN_STEPS:-true}"
RUN_CONNECTIVITY_TEST="${RUN_CONNECTIVITY_TEST:-false}"

step() {
  echo
  echo "============================================================"
  echo "==> $1"
  echo "============================================================"
}

info() {
  echo " -> $1"
}

success() {
  echo " [OK] $1"
}

warn() {
  echo " [WARN] $1"
}

pause() {
  if [[ "$PAUSE_BETWEEN_STEPS" == "true" ]]; then
    echo
    read -r -p "Press Enter to continue..."
  fi
}

# ---------------------------------------------------------------------
# 1. Preflight
# ---------------------------------------------------------------------

step "Checking Kubernetes cluster"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "ERROR: kubectl is not installed."
  exit 1
fi

if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "ERROR: Kubernetes cluster is not reachable."
  exit 1
fi

success "Kubernetes API server is reachable"

echo
info "Current nodes:"
kubectl get nodes -o wide

echo
warn "NotReady is expected before installing the CNI."

pause

# ---------------------------------------------------------------------
# 2. Detect architecture
# ---------------------------------------------------------------------

step "Detecting system architecture"

MACHINE_ARCH="$(uname -m)"

case "$MACHINE_ARCH" in
  aarch64|arm64)
    CLI_ARCH="arm64"
    ;;
  x86_64|amd64)
    CLI_ARCH="amd64"
    ;;
  *)
    echo "ERROR: unsupported architecture: $MACHINE_ARCH"
    exit 1
    ;;
esac

success "Detected architecture: ${MACHINE_ARCH} -> ${CLI_ARCH}"

pause

# ---------------------------------------------------------------------
# 3. Install Cilium CLI
# ---------------------------------------------------------------------

step "Installing Cilium CLI"

CILIUM_CLI_VERSION="$(
  curl -fsSL \
    https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt
)"

info "Latest stable Cilium CLI: ${CILIUM_CLI_VERSION}"

TARBALL="cilium-linux-${CLI_ARCH}.tar.gz"
CHECKSUM="${TARBALL}.sha256sum"

BASE_URL="https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}"

info "Downloading ${TARBALL}"

curl -L --fail --remote-name-all \
  "${BASE_URL}/${TARBALL}" \
  "${BASE_URL}/${CHECKSUM}"

info "Verifying checksum"

sha256sum --check "$CHECKSUM"

info "Installing cilium binary"

sudo tar xzf "$TARBALL" -C /usr/local/bin

rm -f \
  "$TARBALL" \
  "$CHECKSUM"

success "Cilium CLI installed"

echo
cilium version --client

pause

# ---------------------------------------------------------------------
# 4. Verify Pod CIDR allocation
# ---------------------------------------------------------------------

step "Checking Kubernetes Pod CIDR"

POD_CIDR="$(
  kubectl get nodes \
    -o jsonpath='{.items[0].spec.podCIDR}'
)"

if [[ -z "$POD_CIDR" ]]; then
  echo "ERROR: Kubernetes has not assigned a PodCIDR to the node."
  echo
  echo "Kubernetes host-scope IPAM requires a PodCIDR."
  exit 1
fi

success "Node Pod CIDR: ${POD_CIDR}"

pause

# ---------------------------------------------------------------------
# 5. Install Cilium
# ---------------------------------------------------------------------

step "Installing Cilium CNI"

cilium install \
  --set ipam.mode=kubernetes

success "Cilium installation submitted"

pause

# ---------------------------------------------------------------------
# 6. Wait for Cilium
# ---------------------------------------------------------------------

step "Waiting for Cilium to become ready"

cilium status --wait

success "Cilium reports healthy"

pause

# ---------------------------------------------------------------------
# 7. Validate node
# ---------------------------------------------------------------------

step "Checkpoint: Kubernetes node status"

kubectl get nodes -o wide

NODE_READY="$(
  kubectl get nodes \
    -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}'
)"

if [[ "$NODE_READY" != "True" ]]; then
  echo
  echo "ERROR: Kubernetes node is not Ready."
  exit 1
fi

success "Kubernetes node is Ready"

pause

# ---------------------------------------------------------------------
# 8. Validate kube-system Pods
# ---------------------------------------------------------------------

step "Checkpoint: kube-system Pods"

kubectl get pods -n kube-system -o wide

echo
info "Checking CoreDNS"

COREDNS_NOT_RUNNING="$(
  kubectl get pods \
    -n kube-system \
    -l k8s-app=kube-dns \
    --field-selector=status.phase!=Running \
    --no-headers 2>/dev/null \
    | wc -l
)"

if [[ "$COREDNS_NOT_RUNNING" -ne 0 ]]; then
  warn "One or more CoreDNS Pods are not Running."
  kubectl get pods -n kube-system -l k8s-app=kube-dns
  exit 1
fi

success "CoreDNS is Running"

pause

# ---------------------------------------------------------------------
# 9. Cilium status
# ---------------------------------------------------------------------

step "Checkpoint: Cilium status"

cilium status

success "Cilium is operational"

# ---------------------------------------------------------------------
# 10. Optional connectivity test
# ---------------------------------------------------------------------

if [[ "$RUN_CONNECTIVITY_TEST" == "true" ]]; then
  pause

  step "Running Cilium connectivity test"

  cilium connectivity test

  success "Cilium connectivity test completed"
else
  echo
  info "Connectivity test skipped."
  info "Run manually with:"
  echo
  echo "    cilium connectivity test"
fi

# ---------------------------------------------------------------------
# Complete
# ---------------------------------------------------------------------

step "Cilium CNI setup complete"

echo "Architecture : ${CLI_ARCH}"
echo "Pod CIDR     : ${POD_CIDR}"
echo "IPAM mode    : kubernetes"
echo
echo "Cluster status:"
kubectl get nodes
echo
cilium status
