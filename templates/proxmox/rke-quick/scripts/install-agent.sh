#!/bin/sh
set -ex  # Exit on error and print commands

echo "=== Starting RKE2 Agent Installation ==="

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

echo "=== Running RKE2 agent installer ==="
sudo INSTALL_RKE2_TYPE="agent" ./install.sh

echo "=== Configuring RKE2 agent ==="
sudo mkdir -p /etc/rancher/rke2
sudo cp ~/packertmp/agent-config.yaml /etc/rancher/rke2/config.yaml
echo "=== Configuration file copied ==="
cat /etc/rancher/rke2/config.yaml

echo "=== Enabling RKE2 agent service ==="
sudo systemctl enable rke2-agent.service

echo "=== Starting RKE2 agent service ==="
sudo systemctl start rke2-agent.service

echo "=== Waiting for RKE2 agent to be ready ==="
timeout 300 sh -c 'until sudo systemctl is-active --quiet rke2-agent.service; do echo "Waiting for rke2-agent..."; sleep 5; done' || (echo "=== RKE2 agent failed to start! Checking logs ===" && sudo journalctl -u rke2-agent --no-pager -n 50 && exit 1)

echo "=== Setting vm.max_map_count for Elastic ==="
echo 'vm.max_map_count=262144' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

echo "=== RKE2 Agent Installation Complete ==="