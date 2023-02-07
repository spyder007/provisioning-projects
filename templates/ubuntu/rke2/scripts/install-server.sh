#!/bin/sh
curl -sfL https://get.rke2.io --output install.sh
sudo chmod +x install.sh

# TODO: if ~/packertmp has a node-token file, configure this as an HA server


# ELSE - Assume one server
sudo ./install.sh

# Copy the server configuration file
sudo mkdir -p /etc/rancher/rke2
sudo cp ~/packertmp/server-config.yaml /etc/rancher/rke2/config.yaml

sudo systemctl enable rke2-server.service
sudo systemctl start rke2-server.service

# Copy the creds file and node-token to an accessible location for future scripts
sudo cp /etc/rancher/rke2/rke2.yaml .
sudo chown $USER:$USER rke2.yaml
sudo cp /var/lib/rancher/rke2/server/node-token .
sudo chown $USER:$USER node-token