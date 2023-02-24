variable "memory" {
  type    = string
  default = "1024"
}

variable "cpus" {
  type    = string
  default = "1"
}

variable "vmcx_path" {
  type = string
}

variable "baseVmName" {
  type = string
}

variable "output_dir" {
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

variable "domainUser" {
  type    = string
  default = ""
}

variable "domainPassword" {
  type    = string
  default = ""
}

variable "username" {
  type    = string
  default = ""
}

variable "password" {
  type    = string
  default = ""
}

variable "mac_address" {
  type = string
  default = ""
}

variable "domainName" {
  type = string
  default = ""
}

source "hyperv-vmcx" "vm" {
  cpus                  = "${var.cpus}"
  clone_from_vmcx_path  = "${var.vmcx_path}"
  communicator          = "winrm"
  enable_mac_spoofing   = true
  enable_secure_boot    = true
  generation            = 2
  mac_address           = var.mac_address == "" ? null : var.mac_address
  memory                = "${var.memory}"
  output_directory      = "${var.output_dir}${var.vm_name}\\"
  shutdown_command      = "shutdown /s"
  switch_name           = "${var.switch}"
  vm_name               = "${var.vm_name}"
  boot_wait             = "2m"
  winrm_password        = "${var.password}"
  winrm_timeout         = "8h"
  winrm_username        = "${var.username}"
  guest_additions_mode  = "disable"
  shutdown_timeout      = "30m"
  winrm_use_ssl         = false
}

build {
  sources = ["source.hyperv-vmcx.vm"]

  provisioner "powershell" {
    environment_vars  = ["DOMAIN_USER=${var.domainUser}", "DOMAIN_PASS=${var.domainPassword}", "DOMAIN_NAME=${var.domainName}", "VM_MACHINE_NAME=${var.vm_name}"]
    elevated_password = "${var.password}"
    elevated_user     = "${var.username}"
    script            = "./templates/windows-quick/scripts/basic.ps1"
  }

  provisioner "windows-restart" {
    restart_timeout = "1h"
  }
}