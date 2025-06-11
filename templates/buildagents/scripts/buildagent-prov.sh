#/bin/bash

sudo parted -s --fix -a opt /dev/sda "resizepart 3 100%"
sudo pvresize /dev/sda3
sudo lvextend -l+100%FREE $(sudo lvdisplay -C -o "lv_path" --noheadings)
sudo resize2fs $(df / --output=source | sed -e /Filesystem/d)

#mkdir ~/.ssh
#cp /imagegeneration/authorized_keys ~/.ssh/

