#/bin/bash

curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add
sudo apt-add-repository "deb http://apt.kubernetes.io/kubernetes-xenial main"

sudo apt update
sudo apt install kubeadmin kubelet kubectl
sudo swapoff -a

      