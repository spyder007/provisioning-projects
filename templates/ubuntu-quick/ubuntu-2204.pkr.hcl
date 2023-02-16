
variable "cpus" {
  type    = string
  default = "2"
}

variable "disk_size" {
  type    = string
  default = "21440"
}

variable "vmcx_path" {
  type = string
}

variable "files_dirs" {
  type    = list(string)
  default = ["./templates/ubuntu-quick/basic/files/"]
}

variable "mac_address" {
  type    = string
  default = ""
}

variable "memory" {
  type    = string
  default = "2048"
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
  default = ["./templates/ubuntu-quick/basic/basic-prov.sh"]
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

source "hyperv-vmcx" "ubuntu_vm" {
  cpus                  = "${var.cpus}"
  disk_size             = "${var.disk_size}"
  clone_from_vmcx_path  = "${var.vmcx_path}"
  enable_mac_spoofing   = true
  enable_secure_boot    = false
  generation            = 2
  mac_address           = var.mac_address == "" ? null : var.mac_address
  memory                = "${var.memory}"
  output_directory      = "${var.output_dir}${var.vm_name}\\"
  shutdown_command      = "sudo -S -E shutdown -P now"
  ssh_password          = "${var.password}"
  ssh_timeout           = "1h"
  ssh_username          = "${var.username}"
  switch_name           = "${var.switch}"
  vm_name               = "${var.vm_name}"
}

build {
  sources = ["source.hyperv-vmcx.ubuntu_vm"]

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

}
