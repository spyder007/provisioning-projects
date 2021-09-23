# Provisioning Scripts - Hyper-V - Ubuntu Kubernetes Node

This folder contains the files necessary for provisioning an Ubuntu headless server with kubernetes support (using containerd)


## Usage

See [the main readme][Home] for details on usage

## Variables

* **vm_name**: Virtual Machine name.  Can be overridden by the powershell scripts
* **cpus**: The number of virtual CPUs to assign
* **memory**: The memory to assign, in megabytes
* **disk_size**: The disk size, in megabytes
* **username**: The user name to create as part of the install process
* **password**: The password for the above user
* **output_dir**: The location on the VM Host to store the created VM Image
* **files_dirs**: The directory to be mounted on the new image for provisioning.  The contents of this file get copied into *~/packertmp*, based on the settings in the `provisioners` section of the packer file
* **provisioning_scripts**: The scripts (comma separated) used for provisioning.  If nothing is set, uses the value in the Packer provisioning file.

## Installed Software

* Everything in [Containerd][Containerd]
* kubelet
* kubectl
* kubeadm

## Notes
This template builds off of the [Containerd][Containerd] image.  When copying `k8node.pkrvars.template` to your .pkvars file, the `files_dirs` and `provisioning_scripts` settings in the template should be kept and added on to as needed.

This image requires the builder to use [../basic/http](../basic/http) as the `http` folder.  See the script usage section on the [the main readme][Home] for details.

## Author

Copyright (c) 2021 Matt Gerega. MIT Licensed.

[Home]: ../../README.md
[Containerd]: ../containerd/README.md
