#/bin/bash
# change hostname

sudo sed -i "s#$BASE_NAME#$VM_NAME#g" /etc/hostname

echo "Clear DNS Cache"
sudo systemd-resolve --flush-caches

echo "Regenerating ssh keys"
sudo rm /etc/ssh/ssh_host_*
sudo dpkg-reconfigure openssh-server
sudo service ssh restart

#echo "Force DHCP Refresh"
#sudo systemctl restart systemd-networkd

mkdir -p ~/.ssh
cp ~/packertmp/authorized_keys ~/.ssh/
sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config
