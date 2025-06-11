sudo parted -s -a opt /dev/sda "resizepart 3 100%"
sudo shutdown -r now