#/bin/bash
  
sudo lvextend -l+100%FREE $(sudo lvdisplay -C -o "lv_path" --noheadings)
sudo resize2fs $(df / --output=source | sed -e /Filesystem/d)
sudo apt update
sudo apt upgrade -y
sudo apt install -y linux-cloud-tools-virtual
mkdir ~/.ssh
cp /imagegeneration/authorized_keys ~/.ssh/

