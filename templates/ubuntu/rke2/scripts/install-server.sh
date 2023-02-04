#!/bin/sh
curl -sfL https://get.rke2.io --output install.sh
sudo chmod +x install.sh

sudo ./install.sh
sudo systemctl enable rke2-server.service
sudo systemctl start rke2-server.service