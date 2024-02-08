#!/bin/sh
curl -sfL https://get.rke2.io --output install.sh
sudo chmod +x install.sh

export $(cat ~/packertmp/install_vars | xargs)
export INSTALL_RKE2_TYPE="agent"
echo "Version $INSTALL_RKE2_VERSION"

sudo INSTALL_RKE2_VERSION="v1.26.12+rke2r1" INSTALL_RKE2_TYPE="agent" ./install.sh

sudo systemctl enable rke2-agent.service
sudo mkdir -p /etc/rancher/rke2
sudo cp ~/packertmp/agent-config.yaml /etc/rancher/rke2/config.yaml
#sudo cp ~/packtertmp/manifests/* /var/lib/rancher/rke2/server/manifests/

sudo systemctl start rke2-agent.service

# For elastic.... would rather not do this here, but for now, this works
echo 'vm.max_map_count=262144' | sudo tee -a /etc/sysctl.conf