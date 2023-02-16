
variable "cpus" {
  type    = string
  default = "2"
}

variable "disk_size" {
  type    = string
  default = "42880"
}

variable "files_dirs" {
  type    = list(string)
  default = ["./templates/ubuntu-base/files/"]
}

variable "http" {
  type    = string
  default = "http"
}

variable "iso_checksum" {
  type    = string
  default = "10f19c5b2b8d6db711582e0e27f5116296c34fe4b313ba45f9b201a5007056cb"
}

variable "iso_url" {
  type    = string
  default = "https://releases.ubuntu.com/22.04/ubuntu-22.04.1-live-server-amd64.iso"
}

variable "mac_address" {
  type    = string
  default = ""
}

variable "memory" {
  type    = string
  default = "4096"
}

variable "output_dir" {
  type    = string
  default = "d:\\packertest\\"
}

variable "password" {
  type    = string
  default = "ubuntu"
}

variable "provisioning_scripts" {
  type    = list(string)
  default = ["./templates/ubuntu-base/base-prov.sh"]
}

variable "switch" {
  type    = string
  default = "vSwitch"
}

variable "username" {
  type    = string
  default = "ubuntu"
}

variable "vm_name" {
  type    = string
  default = "ubuntu-xenial"
}

source "hyperv-iso" "ubuntu_vm" {
  boot_command        = ["<esc><wait>", "c", "linux /casper/vmlinuz quiet autoinstall net.ifnames=0 biosdevname=0 ip=dhcp ipv6.disable=1 ds=nocloud-net\\;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ <enter>", "initrd /casper/initrd <enter>", "boot <enter>"]
  boot_wait           = "10s"
  cpus                = "${var.cpus}"
  disk_size           = "${var.disk_size}"
  enable_mac_spoofing = true
  enable_secure_boot  = false
  generation          = 2
  http_directory      = "${var.http}"
  iso_checksum        = "${var.iso_checksum}"
  iso_url             = "${var.iso_url}"
  mac_address         = var.mac_address == "" ? null : var.mac_address
  memory              = "${var.memory}"
  output_directory    = "${var.output_dir}${var.vm_name}\\"
  shutdown_command    = "sudo -S -E shutdown -P now"
  ssh_password        = "${var.password}"
  ssh_timeout         = "1h"
  ssh_username        = "${var.username}"
  switch_name         = "${var.switch}"
  vm_name             = "${var.vm_name}"
}

build {
  sources = ["source.hyperv-iso.ubuntu_vm"]

  provisioner "shell" {
    inline = ["mkdir ~/packertmp"]
  }

  provisioner "file" {
    destination = "~/packertmp"
    sources     = "${var.files_dirs}"
  }

  provisioner "shell" {
    scripts = "${var.provisioning_scripts}"
  }

  provisioner "shell" {
    inline = ["sudo dhclient -r"]
  }
}
