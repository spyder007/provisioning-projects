#/bin/bash

sudo apt install docker.io -y
sudo cp ~/packertmp/daemon.json /etc/docker/
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker $USER
sudo swapoff -a