
cpus = "2"
memory = "4096"
files_dirs = ["./templates/ubuntu-quick/basic/files/","./templates/ubuntu-quick/rke2/files/"]
provisioning_scripts = ["./templates/ubuntu-quick/basic/basic-prov.sh","./templates/ubuntu-quick/rke2/scripts/install-agent.sh"]
vmcx_path = "\\\\cloud.gerega.net\\Images\\bases\\ubuntu-20230228.11\\ubuntu-2204-base"
baseVmName = "ubuntu-2204-base"