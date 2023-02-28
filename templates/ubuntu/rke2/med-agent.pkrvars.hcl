
vm_name = "rke2-worker"
cpus = "4"
memory = "8192"
disk_size = "51200"
files_dirs = ["./templates/ubuntu/basic/files/","./templates/ubuntu/rke2/files/"]
provisioning_scripts = ["./templates/ubuntu/basic/basic-prov.sh","./templates/ubuntu/rke2/scripts/install-agent.sh"]