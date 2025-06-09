packer {
  required_plugins {
    hyperv = {
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
  default = "d6dab0c3a657988501b4bd76f1297c053df710e06e0c3aece60dead24f270b4d"
}

variable "iso_url" {
  type    = string
  default = "https://releases.ubuntu.com/24.04.2/ubuntu-24.04.2-live-server-amd64.iso"
}

variable "iso_file" {
  type    = string
  default = "local:iso/ed98c57061f75178af0d15d9a5f83487504f970b.iso"
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
  default = "ubuntu-xenial"
}

variable "pmx_user" {
  type    = string
  default = ""
}

variable "pmx_password" {
  type    = string
  default = ""
}

variable "runner_ip_address" {
    type = string
    default = env("RUNNER_IP_ADDRESS")
}

source "proxmox-iso" "ubuntu_vm" {
  boot_command        = [ "<esc><wait>", 
                          "c", 
                          "linux /casper/vmlinuz quiet autoinstall net.ifnames=0 biosdevname=0 ip=dhcp ds=nocloud-net\\;s=http://${var.runner_ip_address}:{{ .HTTPPort }}/", "<enter><wait3s>",
                          "initrd /casper/initrd", "<enter><wait3s>","boot", "<enter>"]
  boot_wait           = "10s"
  disks {
    disk_size         = "${var.disk_size}"
    storage_pool      = "local-lvm"
    type              = "scsi"
  }

  cloud_init = true
  cloud_init_storage_pool = "local-lvm"

  http_directory           = "${var.http}"
  insecure_skip_tls_verify = true
  boot_iso {
    iso_checksum        = "${var.iso_checksum}"
    #iso_url             = "${var.iso_url}"
    iso_file            = "${var.iso_file}"
    iso_storage_pool    = "local"
  }
  network_adapters {
    bridge = "${var.switch}"
    model  = "virtio"
    #mac_address = var.mac_address == "" ? null : var.mac_address
  }
  node                 = "pxhp"
  #node                = "pmxdell" 
  
  proxmox_url          = "https://192.168.1.25:8006/api2/json"
  ssh_password         = "${var.password}"
  ssh_timeout          = "1h"
  ssh_username         = "${var.username}"
  template_description = "Ubuntu 24.04 Base Image, generated on ${timestamp()}"
  template_name        = "ubuntu-2404-base"
  username             = "${var.pmx_user}"
  password             = "${var.pmx_password}"

  cores               = "${var.cpus}"
  memory              = "${var.memory}"
  vm_name             = "${var.vm_name}"
  vm_id               = "9999"
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
