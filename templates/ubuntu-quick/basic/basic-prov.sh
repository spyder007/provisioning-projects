#/bin/bash
# change hostname

RELEASE_VER=$(lsb_release -r)
NUM_VER=$(cut -f2 <<< "$RELEASE_VER")

if [ $NUM_VER -eq "24.04"]
then
    sudo hostnamectl set-hostname "$VM_NAME"
    sudo sed -i "s#$BASE_NAME#$VM_NAME#g" /etc/hostname
else
    sudo sed -i "s#$BASE_NAME#$VM_NAME#g" /etc/hostname
fi
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
