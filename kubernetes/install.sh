#!/usr/bin/env bash
set -euo pipefail

K8S_VERSION="${1:-1.33}"
POD_NETWORK_CIDR="${POD_NETWORK_CIDR:-10.244.0.0/16}"
CRI_SOCKET="${CRI_SOCKET:-unix:///run/containerd/containerd.sock}"
JOIN_FILE="${JOIN_FILE:-$PWD/k8s_joing.txt}"
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
# 1. Preflight
# ---------------------------------------------------------------------

step "Checking prerequisites"

if ! command -v containerd >/dev/null 2>&1; then
  echo "ERROR: containerd is not installed."
  exit 1
fi

if ! sudo systemctl is-active --quiet containerd; then
  echo "ERROR: containerd is not running."
  exit 1
fi

success "containerd is installed and active"

if [[ "$(sysctl -n net.ipv4.ip_forward)" != "1" ]]; then
  echo "ERROR: net.ipv4.ip_forward must be 1."
  exit 1
fi

success "IPv4 forwarding is enabled"

if [[ "$(swapon --show --noheadings | wc -l)" -ne 0 ]]; then
  echo "ERROR: swap is enabled."
  exit 1
fi

success "Swap is disabled"

pause

# ---------------------------------------------------------------------
# 2. Kubernetes repository
# ---------------------------------------------------------------------

step "Configuring Kubernetes v${K8S_VERSION} repository"

sudo mkdir -p /etc/apt/keyrings

# Remove old key before recreating it so reruns do not cause gpg prompts.
sudo rm -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg

curl -fsSL \
  "https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/Release.key" \
  | sudo gpg --dearmor \
      -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo \
  "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/ /" \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null

success "Kubernetes apt repository configured"

pause

# ---------------------------------------------------------------------
# 3. Install kubeadm, kubelet, kubectl
# ---------------------------------------------------------------------

step "Installing kubeadm, kubelet and kubectl"

sudo apt-get update

sudo apt-get install -y \
  kubelet \
  kubeadm \
  kubectl

sudo apt-mark hold \
  kubelet \
  kubeadm \
  kubectl

sudo systemctl enable kubelet

success "Kubernetes tools installed"

pause

# ---------------------------------------------------------------------
# 4. Checkpoint
# ---------------------------------------------------------------------

step "Checkpoint: Kubernetes tools"

info "kubeadm:"
kubeadm version -o short

echo
info "kubelet:"
kubelet --version

echo
info "kubectl:"
kubectl version --client

echo
info "Package holds:"
apt-mark showhold | grep -E '^(kubeadm|kubelet|kubectl)$'

echo
warn "kubelet may be restarting until kubeadm init creates its configuration."
warn "That is expected at this stage."

pause

# ---------------------------------------------------------------------
# 5. kubeadm init
# ---------------------------------------------------------------------

step "Initializing Kubernetes control plane"

info "Pod network CIDR : ${POD_NETWORK_CIDR}"
info "CRI socket       : ${CRI_SOCKET}"

sudo kubeadm init \
  --pod-network-cidr="${POD_NETWORK_CIDR}" \
  --cri-socket="${CRI_SOCKET}"

success "kubeadm init completed"

pause

# ---------------------------------------------------------------------
# 6. Configure kubectl
# ---------------------------------------------------------------------

step "Configuring kubectl for $(whoami)"

mkdir -p "$HOME/.kube"

sudo cp /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
chmod 600 "$HOME/.kube/config"

success "kubectl configuration installed"

pause

# ---------------------------------------------------------------------
# 7. Save worker join command
# ---------------------------------------------------------------------

step "Generating worker join command"

kubeadm token create \
  --print-join-command \
  | tee "$JOIN_FILE" >/dev/null

chmod 600 "$JOIN_FILE"

success "Join command saved to:"
echo "    $JOIN_FILE"

echo
cat "$JOIN_FILE"

pause

# ---------------------------------------------------------------------
# 8. kubeadm checkpoint
# ---------------------------------------------------------------------

step "Checkpoint: control plane"

info "Nodes:"
kubectl get nodes -o wide

echo
info "kube-system Pods:"
kubectl get pods -n kube-system

echo
info "kubelet cgroup driver:"

if grep -q 'cgroupDriver: systemd' /var/lib/kubelet/config.yaml; then
  grep 'cgroupDriver:' /var/lib/kubelet/config.yaml
  success "kubelet uses systemd cgroups"
else
  echo "ERROR: kubelet is not configured with cgroupDriver: systemd"
  exit 1
fi

echo
warn "The node is expected to be NotReady until a CNI is installed."
warn "CoreDNS may remain Pending until the CNI is configured."

pause

# ---------------------------------------------------------------------
# 9. Untaint control-plane
# ---------------------------------------------------------------------

step "Removing control-plane scheduling taint"

kubectl taint nodes \
  --all \
  node-role.kubernetes.io/control-plane- \
  2>/dev/null || true

success "Control-plane taint removal attempted"

pause

# ---------------------------------------------------------------------
# 10. Final checkpoint
# ---------------------------------------------------------------------

step "Final checkpoint"

info "Node taints:"
kubectl describe node | grep -i 'Taints:' || true

echo
info "Cluster nodes:"
kubectl get nodes

echo
info "Control-plane components:"
kubectl get pods -n kube-system

echo
info "Join command file:"
echo "    $JOIN_FILE"

echo
echo "Worker join command:"
cat "$JOIN_FILE"

# ---------------------------------------------------------------------
# Complete
# ---------------------------------------------------------------------

step "Kubernetes control-plane setup complete"

echo "Kubernetes version : v${K8S_VERSION}"
echo "Pod CIDR           : ${POD_NETWORK_CIDR}"
echo "CRI                : ${CRI_SOCKET}"
echo "Join command       : ${JOIN_FILE}"
echo
echo "Next step: install a CNI plugin."