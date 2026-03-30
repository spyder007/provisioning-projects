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

variable "rke2_version" {
  type    = string
  default = ""
  description = "RKE2 version to install (e.g., 'v1.28.5+rke2r1'). Leave empty to use channel."
}

variable "rke2_channel" {
  type    = string
  default = "stable"
  description = "RKE2 channel to use (stable, latest, testing, or specific minor like v1.28). Ignored if rke2_version is set."
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
  ssh_timeout = "15m"
  ssh_handshake_attempts = 30
}

build {
  sources = ["sources.null.server"]

  # Wait for cloud-init to finish
  # This is important to ensure that the VM is fully initialized before proceeding
  provisioner "shell" {
    inline = [
      "echo '=== Checking cloud-init status ==='",
      "cloud-init status --wait || (echo '=== Cloud-init failed! Dumping logs ===' && sudo cloud-init status --long && sudo journalctl -u cloud-init --no-pager && exit 1)"
    ]
  }

  # Create a temporary directory for file transfers
  provisioner "shell" {
    inline = [
      "echo '=== Creating temporary directory ==='",
      "mkdir -p ~/packertmp",
      "echo '=== Directory created successfully ==='"
    ]
  }

  # Copy files and scripts to the temporary directory
  provisioner "file" {
    destination = "~/packertmp"
    sources     = "${var.files_dirs}"
  }

  # Verify files were copied
  provisioner "shell" {
    inline = [
      "echo '=== Verifying copied files ==='",
      "ls -la ~/packertmp/",
      "echo '=== File verification complete ==='"
    ]
  }

  # Execute the provisioning scripts
  provisioner "shell" {
    scripts           = "${var.provisioning_scripts}"
    expect_disconnect = false
    environment_vars = [
      "INSTALL_RKE2_VERSION=${var.rke2_version}",
      "INSTALL_RKE2_CHANNEL=${var.rke2_channel}"
    ]
  }

  # provisioner "shell" {
  #   inline = ["shutdown now -r"]
  #   expect_disconnect = true
  #   pause_before = "3m"
  # }
}
