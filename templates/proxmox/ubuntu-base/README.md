# Provisioning Scripts - Proxmox - Ubuntu Base Template

This folder contains the files necessary for provisioning a base template in Proxmox

## Usage

### Load Modules

Load up the modules in the root of this repository

```powershell
ls *.psm1 | % { Import-Module -Name $_ -Force }
```

### Prepare Variable file

Create a `secrets.pkrvars.hcl` file with values from the [Variables](#variables) section.  Be sure to include the ones that are required in the secrets file, but you can override any additional ones.

### Set your runner IP address

### Run Provisioner

```powershell
Build-PXUbuntuTemplate -TemplateFile .\templates\proxmox\ubuntu-base\ubuntu-2404-base.pkr.hcl -HostHttpFolder .\templates\proxmox\ubuntu-base\http\ -SecretVariableFile .\templates\proxmox\ubuntu-base\secrets.pkrvars.hcl
```

## Variables

| Variable             | Type         | Default                                            | Description                                     | Required in Secret Variable File |
| -------------------- | ------------ | -------------------------------------------------- | ----------------------------------------------- | -------------------------------- |
| `px_user`            | string       | `""`                                               | Proxmox username (required in secrets file)     | `true`                           |
| `px_password`        | string       | `""`                                               | Proxmox password (required in secrets file)     | `true`                           |
| `username`           | string       | `"ubuntu"`                                         | SSH username for initial login                  | `true`                           |
| `password`           | string       | `"ubuntu"`                                         | SSH password for initial login                  | `true`                           |
| `px_node`            | string       | `"pmxdell"`                                        | Proxmox node name where the VM will be created  |                                  |
| `px_cluster_address` | string       | `"pxhp.gerega.net"`                                | Proxmox cluster address                         |                                  |
| `cpus`               | string       | `"2"`                                              | Number of CPU cores for the VM                  |                                  |
| `disk_size`          | string       | `"48G"`                                            | Size of the VM disk                             |                                  |
| `files_dirs`         | list(string) | `["./templates/proxmox/ubuntu-base/files/"]`       | Directories containing files to copy to the VM  |                                  |
| `http`               | string       | `"http"`                                           | HTTP directory for serving cloud-init files     |                                  |
| `iso_checksum`       | string       | ``                                                 | SHA256 checksum of Ubuntu 24.04.3 ISO           |                                  |
| `iso_file`           | string       | `"local:iso/ubuntu-24.04.3-live-server-amd64.iso"` | Path to the Ubuntu ISO file in Proxmox storage  |                                  |
| `mac_address`        | string       | `""`                                               | Optional MAC address for the VM network adapter |                                  |
| `memory`             | string       | `"4096"`                                           | Amount of RAM in MB                             |                                  |

| `provisioning_scripts` | list(string) | `["./templates/proxmox/ubuntu-base/base-prov.sh"]` | Shell scripts to run during provisioning | |
| `runner_ip_address` | string | env("RUNNER_IP_ADDRESS") | IP address of the Packer runner for HTTP server | |
| `switch` | string | `"vmbr0"` | Proxmox network bridge | |

| `vlan_tag` | number | `50` | VLAN tag for network adapter | |
| `vm_id` | string | `"98999"` | Proxmox VM ID | |
| `vm_name` | string | `"ubuntu-2404-base"` | Name of the VM/template | |

## Installed Software

- ssh server (see Notes for configuration details)
- linux-cloud-tools-virtual
- apt-transport-https
- ca-certificates
- curl
- nfs-common

## Notes

This image requires the builder to use [../basic/http](../basic/http) as the `http` folder. See the script usage section on the [the main readme][Home] for details.

## Author

Copyright (c) 2021 Matt Gerega. MIT Licensed.

[Home]: ../../README.md
