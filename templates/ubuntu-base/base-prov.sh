#/bin/bash
  
sudo lvextend -l+100%FREE $(sudo lvdisplay -C -o "lv_path" --noheadings)
sudo resize2fs $(df / --output=source | sed -e /Filesystem/d)
sudo apt update
sudo apt install -y nfs-common linux-cloud-tools-virtual
sudo apt upgrade -y
sudo apt autoremove -y
