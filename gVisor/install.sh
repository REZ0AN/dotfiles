#!/usr/bin/env bash
set -euo pipefail

PAUSE_BETWEEN_STEPS="${PAUSE_BETWEEN_STEPS:-true}"

CONTAINERD_CONFIG="/etc/containerd/config.toml"
EFFECTIVE_CONFIG="/tmp/containerd-effective.toml"

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

fail() {
  echo " [ERROR] $1" >&2
  exit 1
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

command -v containerd >/dev/null 2>&1 \
  || fail "containerd is not installed"

command -v ctr >/dev/null 2>&1 \
  || fail "ctr is not installed"

[[ -f "$CONTAINERD_CONFIG" ]] \
  || fail "$CONTAINERD_CONFIG does not exist"

sudo systemctl is-active --quiet containerd \
  || fail "containerd is not running"

success "containerd is installed and running"

pause

# ---------------------------------------------------------------------
# 2. Architecture
# ---------------------------------------------------------------------

step "Checking architecture"

ARCH="$(dpkg --print-architecture)"

case "$ARCH" in
  arm64|amd64)
    ;;
  *)
    fail "Unsupported architecture: $ARCH"
    ;;
esac

info "Architecture: $ARCH"
success "Architecture supported"

pause

# ---------------------------------------------------------------------
# 3. Configure gVisor repository
# ---------------------------------------------------------------------

step "Configuring gVisor repository"

sudo mkdir -p /usr/share/keyrings

curl -fsSL https://gvisor.dev/archive.key \
  | sudo gpg --dearmor \
      --yes \
      -o /usr/share/keyrings/gvisor-archive-keyring.gpg

echo \
  "deb [arch=${ARCH} signed-by=/usr/share/keyrings/gvisor-archive-keyring.gpg] https://storage.googleapis.com/gvisor/releases release main" \
  | sudo tee /etc/apt/sources.list.d/gvisor.list >/dev/null

success "gVisor repository configured"

pause

# ---------------------------------------------------------------------
# 4. Install gVisor
# ---------------------------------------------------------------------

step "Installing gVisor"

sudo apt-get update
sudo apt-get install -y runsc

success "gVisor installed"

pause

# ---------------------------------------------------------------------
# 5. Validate binaries
# ---------------------------------------------------------------------

step "Validating gVisor binaries"

RUNSC_BIN="$(command -v runsc || true)"
SHIM_BIN="$(command -v containerd-shim-runsc-v1 || true)"

[[ -n "$RUNSC_BIN" ]] \
  || fail "runsc not found"

[[ -n "$SHIM_BIN" ]] \
  || fail "containerd-shim-runsc-v1 not found"

info "runsc:"
echo "    $RUNSC_BIN"

info "shim:"
echo "    $SHIM_BIN"

echo
runsc --version

runsc flags >/dev/null

success "gVisor binaries are functional"

pause

# ---------------------------------------------------------------------
# 6. Test runsc directly
# ---------------------------------------------------------------------

step "Testing runsc directly"

DIRECT_RUNSC_OUTPUT="$(
  sudo timeout 20s \
    runsc do echo "hello from gVisor" 2>&1
)"

echo "$DIRECT_RUNSC_OUTPUT"

echo "$DIRECT_RUNSC_OUTPUT" \
  | grep -q "hello from gVisor" \
  || fail "Direct runsc test failed"

success "runsc works independently"

pause

# ---------------------------------------------------------------------
# 7. Backup containerd config
# ---------------------------------------------------------------------

step "Backing up containerd config"

BACKUP="${CONTAINERD_CONFIG}.bak.$(date +%Y%m%d-%H%M%S)"

sudo cp \
  "$CONTAINERD_CONFIG" \
  "$BACKUP"

success "Backup created:"
echo "    $BACKUP"

pause

# ---------------------------------------------------------------------
# 8. Register gVisor runtime
# ---------------------------------------------------------------------

step "Registering gVisor runtime"

GVISOR_HEADER="[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.gvisor]"

if sudo grep -Fq "$GVISOR_HEADER" "$CONTAINERD_CONFIG"; then
  info "gVisor runtime already exists"
else
  cat <<'EOF' | sudo tee -a "$CONTAINERD_CONFIG" >/dev/null

[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.gvisor]
  runtime_type = 'io.containerd.runsc.v1'
EOF

  success "gVisor runtime added"
fi

pause

# ---------------------------------------------------------------------
# 9. Restart containerd
# ---------------------------------------------------------------------

step "Restarting containerd"

sudo systemctl restart containerd

sleep 2

sudo systemctl is-active --quiet containerd \
  || fail "containerd failed to restart"

success "containerd restarted"

pause

# ---------------------------------------------------------------------
# 10. Validate effective config
# ---------------------------------------------------------------------

step "Validating effective containerd config"

sudo containerd config dump > "$EFFECTIVE_CONFIG"

info "Default runtime:"
grep "default_runtime_name" "$EFFECTIVE_CONFIG"

echo
info "gVisor runtime:"
grep -A5 "runtimes.gvisor" "$EFFECTIVE_CONFIG"

grep -q \
  "default_runtime_name = 'runc'" \
  "$EFFECTIVE_CONFIG" \
  || fail "runc is not the default runtime"

grep -A5 \
  "runtimes.gvisor" \
  "$EFFECTIVE_CONFIG" \
  | grep -q "runtime_type = 'io.containerd.runsc.v1'" \
  || fail "gVisor runtime is not configured correctly"

success "containerd runtime configuration is correct"

pause

# ---------------------------------------------------------------------
# 11. Pull BusyBox
# ---------------------------------------------------------------------

step "Pulling BusyBox"

sudo ctr images pull \
  docker.io/library/busybox:1.36

success "BusyBox image available"

pause


# ---------------------------------------------------------------------
# Manual containerd -> gVisor validation
# ---------------------------------------------------------------------

step "Manual gVisor validation"

TEST_ID="gvisor-test-$(date +%s)"
EXPECTED_OUTPUT="hello from containerd + gVisor"

echo "Run the following command in another terminal:"
echo
cat <<EOF
sudo timeout 20s ctr run \\
  --runtime io.containerd.runsc.v1 \\
  --rm \\
  -t \\
  docker.io/library/busybox:1.36 \\
  "$TEST_ID" \\
  echo "$EXPECTED_OUTPUT"
EOF

echo
echo "Expected output:"
echo
echo "$EXPECTED_OUTPUT"
echo
echo "If the command prints the expected output and exits successfully,"
echo "the containerd -> gVisor runtime path is working."

pause


# ---------------------------------------------------------------------
# 13. Optional runc workload check
# ---------------------------------------------------------------------

step "Checking existing runc workload"

if command -v kubectl >/dev/null 2>&1 \
  && kubectl get pod runc-test >/dev/null 2>&1; then

  kubectl get pod runc-test

  POD_STATUS="$(
    kubectl get pod runc-test \
      -o jsonpath='{.status.phase}'
  )"

  [[ "$POD_STATUS" == "Running" ]] \
    || fail "runc-test is not Running"

  success "Existing runc workload is still healthy"
else
  info "runc-test Pod not found; skipping this check"
fi

# ---------------------------------------------------------------------
# Complete
# ---------------------------------------------------------------------

step "gVisor setup complete"

echo "Architecture       : $ARCH"
echo "runsc              : $RUNSC_BIN"
echo "containerd shim    : $SHIM_BIN"
echo "Default runtime    : runc"
echo "gVisor runtime     : io.containerd.runsc.v1"
echo "containerd config  : $CONTAINERD_CONFIG"
echo "Backup             : $BACKUP"
echo
echo "Next step:"
echo "  Create a Kubernetes RuntimeClass with handler: gvisor"