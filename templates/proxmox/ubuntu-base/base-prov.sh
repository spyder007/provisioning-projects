#/bin/bash

while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo 'Waiting for cloud-init...'; sleep 1; done

sudo rm /etc/ssh/ssh_host_*
sudo truncate -s 0 /etc/machine-id
#sudo lvextend -l+100%FREE $(sudo lvdisplay -C -o "lv_path" --noheadings)
#sudo resize2fs $(df / --output=source | sed -e /Filesystem/d)
sudo apt update
sudo apt install -y nfs-common linux-cloud-tools-virtual
sudo apt upgrade -y
sudo apt autoremove -y --purge
sudo apt -y clean
sudo apt -y autoclean

sudo cloud-init clean
sudo rm -f /etc/cloud/cloud.cfg.d/subiquity-disable-cloudinit-networking.cfg
sudo rm -f /etc/netplan/00-installer-config.yaml
sudo sync