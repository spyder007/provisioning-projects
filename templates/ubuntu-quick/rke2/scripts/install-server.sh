#!/bin/sh
curl -sfL https://get.rke2.io --output install.sh
sudo chmod +x install.sh

export $(cat ~/packertmp/install_vars | xargs)
echo "Version"
echo $INSTALL_RKE2_VERSION

sudo -E ./install.sh

# Copy the server configuration file
sudo mkdir -p /etc/rancher/rke2
sudo cp ~/packertmp/server-config.yaml /etc/rancher/rke2/config.yaml
#sudo cp ~/packtertmp/manifests/* /var/lib/rancher/rke2/server/manifests/

sudo systemctl enable rke2-server.service
sudo systemctl start rke2-server.service

# For elastic.... would rather not do this here, but for now, this works
echo 'vm.max_map_count=262144' | sudo tee -a /etc/sysctl.conf

# Copy the creds file and node-token to an accessible location for future scripts
sudo cp /etc/rancher/rke2/rke2.yaml .
sudo chown $USER:$USER rke2.yaml
sudo cp /var/lib/rancher/rke2/server/node-token .
sudo chown $USER:$USER node-token