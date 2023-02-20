variable "memory" {
  type    = string
  default = "1024"
}

variable "cpus" {
  type    = string
  default = "1"
}

variable "baseImageLocation" {
  type = string
}

variable "baseImageName" {
  type = string
}

variable "output_directory" {
  type    = string
  default = ""
}

variable "switch" {
  type    = string
  default = ""
}

variable "vm_name" {
  type    = string
  default = ""
}

source "hyperv-vmcx" "vm" {
  cpus                  = "${var.cpus}"
  clone_from_vmcx_path  = "${var.vmcx_path}"
  communicator          = "winrm"
  enable_mac_spoofing   = true
  enable_secure_boot    = false
  generation            = 2
  mac_address           = var.mac_address == "" ? null : var.mac_address
  memory                = "${var.memory}"
  output_directory      = "${var.output_dir}${var.vm_name}\\"
  shutdown_command      = "shutdown /s"
  ssh_password          = "${var.password}"
  ssh_timeout           = "1h"
  ssh_username          = "${var.username}"
  switch_name           = "${var.switch}"
  vm_name               = "${var.vm_name}"
  boot_wait             = "1m"
  winrm_password        = "password"
  winrm_timeout         = "8h"
  winrm_username        = "Administrator"
  guest_additions_mode  = "disable"
  shutdown_timeout      = "30m"

}

build {
  sources = ["source.hyperv-vmcx.vm"]

  provisioner "powershell" {
    elevated_password = "${var.password}"
    elevated_user     = "${var.username}"
    script            = "./scripts/basic.ps1"
  }

  provisioner "windows-restart" {
    restart_timeout = "1h"
  }
}