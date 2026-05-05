packer {
  required_plugins {
    proxmox = {
      version = "~> 1"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

variable "cpus" {
  type    = string
  default = "2"
}

variable "disk_size" {
  type    = string
  default = "48G"
}

variable "files_dirs" {
  type    = list(string)
  default = ["./templates/proxmox/ubuntu-base/files/"]
}

variable "http" {
  type    = string
  default = "http"
}

variable "iso_checksum" {
  type    = string
  default = "" # TODO: fill in SHA256 from https://releases.ubuntu.com/26.04/SHA256SUMS
}

variable "iso_file" {
  type    = string
  default = "local:iso/ubuntu-26.04-live-server-amd64.iso" # TODO: confirm exact filename
}

variable "mac_address" {
  type    = string
  default = ""
}

variable "memory" {
  type    = string
  default = "4096"
}

variable "password" {
  type    = string
  default = "ubuntu"
}

variable "provisioning_scripts" {
  type    = list(string)
  default = ["./templates/proxmox/ubuntu-base/base-prov.sh"]
}

variable "px_node" {
  type    = string
  default = "pmxdell"
}

variable "px_cluster_address" {
  type    = string
  default = "pxhp.gerega.net"
}

variable "switch" {
  type    = string
  default = "vmbr0"
}

variable "username" {
  type    = string
  default = "ubuntu"
}

variable "vm_name" {
  type    = string
  default = "ubuntu-2604-base"
}

variable "px_user" {
  type    = string
  default = ""
}

variable "px_password" {
  type    = string
  default = ""
}

variable "runner_ip_address" {
  type    = string
  default = env("RUNNER_IP_ADDRESS")
}

variable "vlan_tag" {
  type    = number
  default = 50
}

variable "vm_id" {
  type    = string
  default = "98998"
}

source "proxmox-iso" "ubuntu_vm" {
  boot_command        = [ "<esc><wait>",
                          "c",
                          "linux /casper/vmlinuz quiet autoinstall ip=dhcp multipath=off ds=nocloud-net\\;s=http://${var.runner_ip_address}:{{ .HTTPPort }}/", "<enter><wait3s>",
                          "initrd /casper/initrd", "<enter><wait3s>","boot", "<enter>"]
  boot_wait           = "10s"
  disks {
    disk_size         = "${var.disk_size}"
    storage_pool      = "local-lvm"
    type              = "scsi"
  }

  cloud_init               = true
  cloud_init_storage_pool  = "local-lvm"
  machine                  = "q35"
  http_directory           = "${var.http}"
  insecure_skip_tls_verify = true

  boot_iso {
    iso_checksum        = "${var.iso_checksum}"
    iso_file            = "${var.iso_file}"
    iso_storage_pool    = "local"
  }

  network_adapters {
    bridge = "${var.switch}"
    model  = "virtio"
    vlan_tag = var.vlan_tag
    #mac_address = var.mac_address == "" ? null : var.mac_address
  }

  node                 = "${var.px_node}"
  proxmox_url          = "https://${var.px_cluster_address}:8006/api2/json"
  ssh_password         = "${var.password}"
  ssh_timeout          = "1h"
  ssh_username         = "${var.username}"
  template_description = "Ubuntu 26.04 Base Image, generated on ${timestamp()}"
  template_name        = "ubuntu-2604-base"
  username             = "${var.px_user}"
  password             = "${var.px_password}"

  cpu_type            = "host"
  cores               = "${var.cpus}"
  memory              = "${var.memory}"
  vm_name             = "${var.vm_name}"
  vm_id               = "${var.vm_id}"
}

build {
  sources = ["source.proxmox-iso.ubuntu_vm"]

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

  # Provisioning the VM Template for Cloud-Init Integration in Proxmox #3
  provisioner "shell" {
      inline = [
          "sudo cp ~/packertmp/99-pve.cfg /etc/cloud/cloud.cfg.d/99-pve.cfg"
          ]
  }

}
