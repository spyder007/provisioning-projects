sudo apt update
sudo apt upgrade -y
mkdir ~/.ssh
cp ~/packertmp/authorized_keys ~/.ssh/
sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config
sudo service ssh restart
sudo apt install docker.io -y
sudo cp ~/packertmp/daemon.json /etc/docker/
sudo systemctl enable docker
sudo systemctl reload docker
sudo systemctl start docker
      