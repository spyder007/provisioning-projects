#!/bin/sh
curl -sfL https://get.rke2.io --output install.sh
sudo chmod +x install.sh

sudo INSTALL_RKE2_TYPE="agent" ./install.sh

sudo systemctl enable rke2-agent.service
mkdir -p /etc/rancher/rke2
cp ~/packertmp/agent-config.yaml /etc/rancher/rke2/config.yaml

sudo systemctl start rke2-agent.service