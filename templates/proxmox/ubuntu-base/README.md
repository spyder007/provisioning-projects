# Provisioning Scripts - Hyper-V - Ubuntu Base

This folder contains the files necessary for provisioning a base image suitable for quick provisioning additional images.

## Usage

See [the main readme]:[Home] for details on usage

## Variables

* **vm_name**: Virtual Machine name.  Can be overridden by the powershell scripts
* **cpus**: The number of virtual CPUs to assign
* **memory**: The memory to assign, in megabytes
* **disk_size**: The disk size, in megabytes
* **username**: The user name to create as part of the install process
* **password**: The password for the above user
* **output_dir**: The location on the VM Host to store the created VM Image
* **files_dirs**: The directory or directories (comma separated) to be mounted on the new image for provisioning.  The contents of this file get copied into *~/packertmp*, based on the settings in the `provisioners` section of the packer file
* **provisioning_scripts**: The scripts (comma separated) used for provisioning.  If nothing is set, uses the value in the Packer provisioning file.

## Installed Software

* ssh server (see Notes for configuration details)
* linux-cloud-tools-virtual
* apt-transport-https
* ca-certificates
* curl
* nfs-common

## Notes

This image requires the builder to use [../basic/http](../basic/http) as the `http` folder.  See the script usage section on the [the main readme][Home] for details.

## Author

Copyright (c) 2021 Matt Gerega. MIT Licensed.

[Home]: ../../README.md
