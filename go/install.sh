# Architecture is arm64 since you're on M2 with vz native
GO_VERSION=1.26.3
ARCH=arm64

# Download
curl -LO https://go.dev/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz

# Remove any existing Go install and extract fresh
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf go${GO_VERSION}.linux-${ARCH}.tar.gz

# Clean up the tarball
rm go${GO_VERSION}.linux-${ARCH}.tar.gz

# Add to PATH (for bash)
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
echo 'export PATH=$PATH:$(go env GOPATH)/bin' >> ~/.bashrc
source ~/.bashrc
exec bash

# Verify
go version