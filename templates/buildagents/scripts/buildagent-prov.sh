#/bin/bash
  
sudo lvextend -l+100%FREE $(sudo lvdisplay -C -o "lv_path" --noheadings)
sudo resize2fs $(df / --output=source | sed -e /Filesystem/d)
sudo apt update
sudo apt upgrade -y
mkdir ~/.ssh
cp /imagegeneration/authorized_keys ~/.ssh/
chmod go-w ~/
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys

