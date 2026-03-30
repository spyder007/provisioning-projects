#!/bin/sh
set -ex  # Exit on error and print commands

echo "=== Starting RKE2 Server Installation ==="

# Display version configuration
echo "=== RKE2 Version Configuration ==="
if [ -n "$INSTALL_RKE2_VERSION" ]; then
    echo "Installing specific version: $INSTALL_RKE2_VERSION"
else
    echo "Using channel: ${INSTALL_RKE2_CHANNEL:-stable}"
fi

echo "=== Downloading RKE2 installer ==="
curl -sfL https://get.rke2.io --output install.sh
sudo chmod +x install.sh

echo "=== Running RKE2 server installer ==="
sudo ./install.sh

echo "=== Configuring RKE2 server ==="
sudo mkdir -p /etc/rancher/rke2
sudo cp ~/packertmp/server-config.yaml /etc/rancher/rke2/config.yaml
echo "=== Configuration file copied ==="
cat /etc/rancher/rke2/config.yaml

echo "=== Enabling RKE2 server service ==="
sudo systemctl enable rke2-server.service

echo "=== Starting RKE2 server service ==="
# Don't exit on failure - service might take time to start, especially when joining a cluster
sudo systemctl start rke2-server.service || echo "Initial start command returned non-zero, but will wait for service to become active..."

echo "=== Waiting for RKE2 server to be ready ==="
timeout 600 sh -c 'until sudo systemctl is-active --quiet rke2-server.service; do echo "Waiting for rke2-server..."; sleep 5; done' || (echo "=== RKE2 server failed to start! Checking logs ===" && sudo journalctl -u rke2-server --no-pager -n 100 && exit 1)

# Check if this is joining an existing cluster or creating a new one
if grep -q "^server:" /etc/rancher/rke2/config.yaml; then
    echo "=== Joining existing cluster - verifying service stability ==="
    # For joining servers, just ensure the service stays active for a bit
    sleep 30
    if ! sudo systemctl is-active --quiet rke2-server.service; then
        echo "=== RKE2 server stopped after joining! Checking logs ==="
        sudo journalctl -u rke2-server --no-pager -n 100
        exit 1
    fi
    echo "=== Successfully joined cluster ==="
else
    echo "=== First server - waiting for node-token file ==="
    timeout 300 sh -c 'until [ -f /var/lib/rancher/rke2/server/node-token ]; do echo "Waiting for node-token..."; sleep 5; done' || (echo "=== node-token file not created! Checking logs ===" && sudo journalctl -u rke2-server --no-pager -n 50 && exit 1)

    echo "=== Copying credentials and token ==="
    sudo cp /etc/rancher/rke2/rke2.yaml .
    sudo chown $USER:$USER rke2.yaml
    sudo cp /var/lib/rancher/rke2/server/node-token .
    sudo chown $USER:$USER node-token
fi

echo "=== Setting vm.max_map_count for Elastic ==="
echo 'vm.max_map_count=262144' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

echo "=== RKE2 Server Installation Complete ==="