#!/usr/bin/env bash
set -euo pipefail

PAUSE_BETWEEN_STEPS="${PAUSE_BETWEEN_STEPS:-true}"

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
# 1. Packages
# ---------------------------------------------------------------------

step "Installing Kubernetes/containerd prerequisites"

sudo apt-get update

sudo apt-get install -y \
  ca-certificates \
  curl \
  gnupg \
  apt-transport-https \
  socat \
  conntrack \
  iptables \
  jq

success "Required packages installed"

pause

# ---------------------------------------------------------------------
# 2. Kernel modules
# ---------------------------------------------------------------------

step "Configuring required kernel modules"

cat <<'EOF' | sudo tee /etc/modules-load.d/k8s.conf >/dev/null
overlay
br_netfilter
EOF

info "Loading overlay module"
sudo modprobe overlay

info "Loading br_netfilter module"
sudo modprobe br_netfilter

success "Kernel modules configured"

pause

# ---------------------------------------------------------------------
# 3. Sysctl
# ---------------------------------------------------------------------

step "Configuring Kubernetes networking sysctl values"

cat <<'EOF' | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf >/dev/null
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system >/dev/null

success "Kernel networking parameters configured"

pause

# ---------------------------------------------------------------------
# 4. Swap
# ---------------------------------------------------------------------

step "Disabling swap"

sudo swapoff -a

if grep -Eq '^[^#].*\sswap\s' /etc/fstab; then
  sudo sed -i '/ swap / s/^/#/' /etc/fstab
  info "Swap entries in /etc/fstab were disabled"
else
  info "No active swap entry found in /etc/fstab"
fi

success "Swap disabled"

pause

# ---------------------------------------------------------------------
# Checkpoint
# ---------------------------------------------------------------------

step "Checkpoint: validating host prerequisites"

info "Kernel modules:"
lsmod | grep -E 'overlay|br_netfilter' || {
  warn "Required kernel modules were not detected"
  exit 1
}

echo
info "IPv4 forwarding:"
sysctl net.ipv4.ip_forward

echo
info "Bridge iptables:"
sysctl net.bridge.bridge-nf-call-iptables

echo
info "Swap:"
free -h | grep -i swap

[[ "$(sysctl -n net.ipv4.ip_forward)" == "1" ]] || {
  echo "ERROR: net.ipv4.ip_forward must be 1"
  exit 1
}

[[ "$(sysctl -n net.bridge.bridge-nf-call-iptables)" == "1" ]] || {
  echo "ERROR: net.bridge.bridge-nf-call-iptables must be 1"
  exit 1
}

if [[ "$(swapon --show --noheadings | wc -l)" -ne 0 ]]; then
  echo "ERROR: swap is still enabled"
  exit 1
fi

success "Host prerequisites validated"

pause

# ---------------------------------------------------------------------
# 5. containerd
# ---------------------------------------------------------------------

step "Installing containerd"

sudo apt-get install -y containerd

sudo systemctl enable --now containerd

success "containerd installed and started"

echo
info "containerd version:"
containerd --version

pause

# ---------------------------------------------------------------------
# 6. Validate containerd installation
# ---------------------------------------------------------------------

step "Checkpoint: validating containerd"

if ! sudo systemctl is-active --quiet containerd; then
  echo "ERROR: containerd service is not active"
  exit 1
fi

success "containerd service is active"

echo
info "Client/server version:"
sudo ctr version

echo
info "Required plugins:"
sudo ctr plugins ls | grep -E 'cri|snapshotter.v1 +overlayfs' || {
  warn "Expected CRI/overlayfs plugins were not found"
  exit 1
}

pause

# ---------------------------------------------------------------------
# 7. Generate configuration
# ---------------------------------------------------------------------

step "Generating containerd configuration"

sudo mkdir -p /etc/containerd

sudo containerd config default \
  | sudo tee /etc/containerd/config.toml >/dev/null

CONFIG_VERSION="$(head -n 1 /etc/containerd/config.toml)"

info "Generated config:"
echo "    $CONFIG_VERSION"

if ! grep -q '^version = 3' /etc/containerd/config.toml; then
  warn "Expected containerd v2 config schema: version = 3"
fi

success "containerd config generated"

pause

# ---------------------------------------------------------------------
# 8. systemd cgroup
# ---------------------------------------------------------------------

step "Enabling systemd cgroup driver"

if grep -q 'SystemdCgroup = false' /etc/containerd/config.toml; then
  sudo sed -i \
    's/SystemdCgroup = false/SystemdCgroup = true/' \
    /etc/containerd/config.toml

  success "SystemdCgroup changed to true"
else
  warn "Could not find 'SystemdCgroup = false'"
  warn "Checking whether it is already enabled..."
fi

echo
grep -n "SystemdCgroup" /etc/containerd/config.toml || {
  echo "ERROR: SystemdCgroup option not found"
  exit 1
}

pause

# ---------------------------------------------------------------------
# 9. Restart
# ---------------------------------------------------------------------

step "Restarting containerd"

sudo systemctl restart containerd

if ! sudo systemctl is-active --quiet containerd; then
  echo "ERROR: containerd failed to restart"
  sudo systemctl status containerd --no-pager
  exit 1
fi

success "containerd restarted successfully"

pause

# ---------------------------------------------------------------------
# 10. Effective config validation
# ---------------------------------------------------------------------

step "Validating effective containerd configuration"

sudo containerd config dump > /tmp/containerd-effective.toml

info "SystemdCgroup:"
grep -n "SystemdCgroup" /tmp/containerd-effective.toml

echo
info "Default runtime:"
grep -n "default_runtime_name" /tmp/containerd-effective.toml

echo
info "CRI runtime:"
grep -n "io.containerd.cri.v1.runtime" /tmp/containerd-effective.toml

echo

if ! grep -q "SystemdCgroup = true" /tmp/containerd-effective.toml; then
  echo "ERROR: effective configuration does not use SystemdCgroup=true"
  exit 1
fi

if ! grep -q "default_runtime_name = 'runc'" /tmp/containerd-effective.toml; then
  echo "ERROR: default runtime is not runc"
  exit 1
fi

success "containerd effective configuration looks correct"

# ---------------------------------------------------------------------
# Complete
# ---------------------------------------------------------------------

step "Setup complete"

echo "containerd is ready for kubeadm."
echo
echo "Summary:"
echo "  Kernel modules : overlay, br_netfilter"
echo "  IPv4 forwarding: enabled"
echo "  Swap            : disabled"
echo "  containerd      : active"
echo "  Cgroup driver   : systemd"
echo "  Runtime         : runc"
echo
echo "Next step: install kubeadm, kubelet and kubectl."
