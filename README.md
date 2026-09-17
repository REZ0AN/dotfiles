# Usages Guide

Portable Linux workspace setup, development tooling, and infrastructure installation scripts for bootstrapping my environment on Ubuntu-based systems.

This repository is intended to help me, quickly recreate a consistent development environment across Linux machines and Lima VMs.

## Repository Structure

```text
.
├── agent-cli
│   ├── codex.sh
│   └── cursor.sh
├── cilium
│   └── install.sh
├── containerd
│   └── install.sh
├── gVisor
│   ├── install.sh
│   └── tests
│       ├── gvisor-pod.yaml
│       └── runtimeclass-gvisor.yaml
├── go
│   └── install.sh
├── kubernetes
│   ├── install.sh
│   └── tests
│       └── runc-test.yaml
├── lima
│   └── ubuntu22-aarch64.config.yaml
├── network-ebpf-tools
│   └── install.sh
├── node
│   └── install.sh
├── python
│   └── install.sh
└── ssh-keygen
    └── keygen.sh
```

## Components

| Directory | Purpose |
|---|---|
| `lima/` | Lima VM configuration for Ubuntu 22.04 on native ARM64 |
| `network-ebpf-tools/` | Linux networking, eBPF, compiler, kernel, DNS, and debugging tools |
| `go/` | Go installation with configurable version and architecture |
| `python/` | Python installation from source with configurable version |
| `node/` | Node.js installation using NVM |
| `ssh-keygen/` | Ed25519 SSH key generation for GitHub and other SSH-based services |
| `agent-cli/` | Agent CLI installers for Codex CLI and Cursor Agent CLI |
| `containerd/` | containerd installation and Kubernetes-compatible runtime configuration |
| `kubernetes/` | kubeadm, kubelet, kubectl, and single-node cluster initialization |
| `cilium/` | Cilium CNI installation and cluster networking validation |
| `gVisor/` | gVisor installation and containerd runtime integration |

## Target Environment

The current setup is primarily tested with:

```text
Host:         Apple Silicon Mac
VM:           Lima
Backend:      vz / Apple Virtualization.framework
Guest OS:     Ubuntu 22.04 LTS
Architecture: aarch64 / arm64
Runtime:      containerd
Kubernetes:   kubeadm
CNI:          Cilium
Sandbox:      gVisor
```

Most scripts are written for Ubuntu-based Linux systems and should also be reusable on other compatible Linux machines.

## Lima VM Setup

Validate the configuration:

```bash
limactl validate lima/ubuntu22-aarch64.config.yaml
```

Create the VM:

```bash
limactl start \
  --name=dev-workspace \
  lima/ubuntu22-aarch64.config.yaml
```

Enter the VM:

```bash
limactl shell dev-workspace
```

Later, start or stop it with:

```bash
limactl start dev-workspace
limactl stop dev-workspace
```

## Installation and Validation Order

For a fresh Linux machine or Lima VM, the recommended order is:

```text
1. network-ebpf-tools
2. Go
3. Python
4. Node.js
5. SSH keys
6. Agent CLIs
7. containerd
8. Kubernetes
9. Cilium
10. Validate runc
11. gVisor
12. RuntimeClass
13. Validate gVisor
```

## System and Networking Tools

```bash
chmod +x network-ebpf-tools/install.sh
./network-ebpf-tools/install.sh
```

This installs tools used for:

- eBPF development
- networking
- packet inspection
- DNS debugging
- kernel development
- compilation
- Linux troubleshooting

## Go

The Go installer accepts:

```text
install.sh <version> <architecture>
```

Example for ARM64:

```bash
chmod +x go/install.sh
./go/install.sh 1.26.3 arm64
```

Verify:

```bash
go version
```

## Python

The Python installer accepts a Python version:

```bash
chmod +x python/install.sh
./python/install.sh 3.12.11
```

Verify:

```bash
python3.12 --version
python3.12 -m pip --version
```

The installer uses `make altinstall` to avoid replacing Ubuntu's system Python.

## Node.js

Node.js is installed using NVM.

```bash
chmod +x node/install.sh
./node/install.sh 22
```

An exact version can also be used:

```bash
./node/install.sh 22.18.0
```

Verify:

```bash
node --version
npm --version
nvm current
```

## SSH Key Generation

Generate an Ed25519 key:

```bash
chmod +x ssh-keygen/keygen.sh

./ssh-keygen/keygen.sh \
  ~/.ssh/github_ed25519 \
  your-email@example.com
```

Then add it to the SSH agent:

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/github_ed25519
```

Test GitHub authentication:

```bash
ssh -T git@github.com
```

## Agent CLIs

Install Codex CLI:

```bash
chmod +x agent-cli/codex.sh
./agent-cli/codex.sh
```

Optionally choose an install directory:

```bash
./agent-cli/codex.sh ~/.local/bin
```

Install Cursor Agent CLI:

```bash
chmod +x agent-cli/cursor.sh
./agent-cli/cursor.sh
```

Verify:

```bash
codex --version
agent --version
```

## containerd

Install and configure containerd:

```bash
chmod +x containerd/install.sh
./containerd/install.sh
```

The script configures:

- required kernel modules
- `overlay`
- `br_netfilter`
- IP forwarding
- swap disabling
- containerd
- `SystemdCgroup = true`
- `runc` as the default runtime

Verify:

```bash
containerd --version
sudo systemctl is-active containerd
sudo ctr version
```

## Kubernetes

Install kubeadm, kubelet, and kubectl:

```bash
chmod +x kubernetes/install.sh
./kubernetes/install.sh 1.33
```

The script initializes the control plane using containerd and configures kubectl for the current user.

The generated worker join command is stored in:

```text
kubernetes/k8s_join.txt
```

Check the cluster:

```bash
kubectl get nodes
kubectl get pods -n kube-system
```

Before installing the CNI, the node being `NotReady` is expected.

## Cilium

Install the Cilium CNI:

```bash
chmod +x cilium/install.sh
./cilium/install.sh
```

Verify:

```bash
cilium status
kubectl get nodes
kubectl get pods -n kube-system
```

After Cilium becomes healthy, the Kubernetes node should become:

```text
Ready
```

Optional connectivity test:

```bash
cilium connectivity test
```

## Validate runc

Apply the test Pod:

```bash
kubectl apply -f kubernetes/tests/runc-test.yaml
```

Wait until it becomes ready:

```bash
kubectl wait \
  --for=condition=Ready \
  pod/runc-test \
  --timeout=120s
```

Validate the default runtime:

```bash
kubectl get pod runc-test
kubectl exec runc-test -- echo "runc works"
```

Validate Kubernetes DNS:

```bash
kubectl exec runc-test -- \
  nslookup kubernetes.default.svc.cluster.local
```

The fully qualified service name is used here to avoid resolver search-domain differences between environments.

## gVisor

Install gVisor and register it as an additional containerd runtime:

```bash
chmod +x gVisor/install.sh
./gVisor/install.sh
```

The configuration keeps:

```text
runc   -> default runtime
gvisor -> additional sandboxed runtime
```

The containerd runtime type is:

```text
io.containerd.runsc.v1
```

### Direct gVisor Test

The installer prints a command for manual validation.

It will look similar to:

```bash
sudo timeout 20s ctr run \
  --runtime io.containerd.runsc.v1 \
  --rm \
  -t \
  docker.io/library/busybox:1.36 \
  "gvisor-test-<timestamp>" \
  echo "hello from containerd + gVisor"
```

Expected output:

```text
hello from containerd + gVisor
```

## Kubernetes RuntimeClass

Create the gVisor RuntimeClass:

```bash
kubectl apply \
  -f gVisor/tests/runtimeclass-gvisor.yaml
```

Verify:

```bash
kubectl get runtimeclass
```

Expected:

```text
NAME     HANDLER
gvisor   gvisor
```

## Validate gVisor Pod

Apply the test Pod:

```bash
kubectl apply \
  -f gVisor/tests/gvisor-pod.yaml
```

Wait for it:

```bash
kubectl wait \
  --for=condition=Ready \
  pod/gvisor-test \
  --timeout=120s
```

Check:

```bash
kubectl get pod gvisor-test
kubectl logs gvisor-test
```

Expected log:

```text
gvisor pod started
```

A stronger runtime validation:

```bash
kubectl exec gvisor-test -- dmesg | head
```

The output should show gVisor's virtualized kernel environment rather than the host kernel.

## Interactive Scripts

Infrastructure setup scripts support interactive pauses between major stages.

Example:

```bash
./containerd/install.sh
```

For unattended execution:

```bash
PAUSE_BETWEEN_STEPS=false ./containerd/install.sh
```

The same pattern is used where applicable for:

```text
containerd
kubernetes
cilium
gVisor
```

## Notes

These scripts intentionally keep the environment explicit rather than relying heavily on distribution defaults.

In particular:

- containerd is configured manually for Kubernetes.
- `runc` remains the default runtime.
- gVisor (runsc) is added as a secondary runtime.
- Cilium handles Kubernetes networking.
- swap is disabled for kubelet.
- systemd cgroups are used by containerd and kubelet.
- the Lima environment runs native ARM64 with the `vz` backend.

## Disclaimer

These are personal workspace/bootstrap scripts built around my development environment.

Review scripts before running them on production machines or environments with existing Kubernetes/container runtime configurations.
