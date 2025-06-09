packer {
  required_plugins {
    hyperv = {
      version = ">= 1.1.3"
      source  = "github.com/hashicorp/hyperv"
    }
  }
}


variable "files_dirs" {
  type    = list(string)
  default = ["./templates/proxmox/rke-quick/files/"]
}

variable "provisioning_scripts" {
  type    = list(string)
}

variable "ssh_host" {
  type    = string
  default = "localhost"
}

variable "ssh_username" {
  type    = string
  default = "ubuntu"
}

variable "ssh_password" {
  type    = string
  default = "ubuntu"
}

source "null" "server" {
  ssh_host = "${var.ssh_host}"
  ssh_username = "${var.ssh_username}"
  ssh_password = "${var.ssh_password}"
  communicator = "ssh"
}

build {
  sources = ["sources.null.server"]

  # Wait for cloud-init to finish
  # This is important to ensure that the VM is fully initialized before proceeding
  provisioner "shell" {
    inline = ["cloud-init status --wait"]
  }

  # Create a temporary directory for file transfers
  provisioner "shell" {
    inline = ["mkdir -p ~/packertmp"]
  }

  # Copy files and scripts to the temporary directory
  provisioner "file" {
    destination = "~/packertmp"
    sources     = "${var.files_dirs}"
  }

  # Execute the provisioning scripts
  provisioner "shell" {
    scripts = "${var.provisioning_scripts}"
  }

  # provisioner "shell" {
  #   inline = ["shutdown now -r"]
  #   expect_disconnect = true
  #   pause_before = "3m"
  # }
}
