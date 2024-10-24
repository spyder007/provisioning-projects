
variable "build_temp" {
  type    = string
  default = "c:\\buildtemp"
}

variable "cpus" {
  type    = string
  default = "2"
}

variable "disk_size" {
  type    = string
  default = "21440"
}

variable "files_dirs" {
  type    = list(string)
  default = ["./templates/buildagents/files/"]
}

variable "helper_script_folder" {
  type    = string
  default = "/imagegeneration/helpers"
}

variable "http" {
  type    = string
  default = "http"
}

variable "image_folder" {
  type    = string
  default = "/imagegeneration"
}

variable "image_os" {
  type    = string
  default = "ubuntu22"
}

variable "image_repository_path" {
  type    = string
  default = "${env("IMAGEREPOSITORYPATH")}"
}

variable "image_version" {
  type    = string
  default = "dev"
}

variable "imagedata_file" {
  type    = string
  default = "/imagegeneration/imagedata.json"
}

variable "installer_script_folder" {
  type    = string
  default = "/imagegeneration/installers"
}

variable "iso_checksum" {
  type    = string
  default = "e240e4b801f7bb68c20d1356b60968ad0c33a41d00d828e74ceb3364a0317be9"
}

variable "iso_url" {
  type    = string
  default = "https://releases.ubuntu.com/24.04.1/ubuntu-24.04.1-live-server-amd64.iso"
}

variable "mac_address" {
  type    = string
  default = "000000000000"
}

variable "memory" {
  type    = string
  default = "2048"
}

variable "ms_agent_org_url" {
  type    = string
  default = ""
}

variable "ms_agent_pool" {
  type    = string
  default = "Default"
}

variable "ms_agent_pat" {
  type    = string
  default = ""
  sensitive = true
}
variable "ms_agent_url" {
  type    = string
  default = "https://vstsagentpackage.azureedge.net/agent/3.234.0"
}

variable "ms_agent_filename" {
  type    = string
  default = "vsts-agent-linux-x64-3.234.0.tar.gz"
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
  default = ["./templates/buildagents/scripts/buildagent-prov.sh"]
}

variable "run_validation_diskspace" {
  type    = string
  default = "false"
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

variable "dockerhub_login" {
  type = string
  default = ""
}

variable "dockerhub_password" {
  type = string
  default = ""
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
  mac_address         = "${var.mac_address}"
  memory              = "${var.memory}"
  output_directory    = "${var.output_dir}${var.vm_name}\\"
  shutdown_command    = "sudo -S -E shutdown -P now"
  shutdown_timeout    = "15m"
  ssh_password        = "${var.password}"
  ssh_timeout         = "1h"
  ssh_username        = "${var.username}"
  switch_name         = "${var.switch}"
  temp_path           = "${var.build_temp}"
  vm_name             = "${var.vm_name}"
}

build {
  sources = ["source.hyperv-iso.ubuntu_vm"]

  provisioner "shell" {
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    inline          = ["mkdir ${var.image_folder}", "chmod 777 ${var.image_folder}"]
  }

  provisioner "file" {
    destination = "${var.image_folder}"
    sources     = "${var.files_dirs}"
  }

  provisioner "shell" {
    scripts = "${var.provisioning_scripts}"
  }

  provisioner "shell" {
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    script          = "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/configure-apt-mock.sh"
  }

  provisioner "file" {
    destination = "${var.helper_script_folder}"
    source      = "${path.root}/lib/virtual-environments/images/ubuntu/scripts/helpers"
  }

  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}","DEBIAN_FRONTEND=noninteractive"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = [
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/install-ms-repos.sh",
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/configure-apt-sources.sh",
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/configure-apt.sh"]
  }
  
  provisioner "shell" {
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    script          = "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/configure-limits.sh"
  }

  provisioner "file" {
    destination = "${var.installer_script_folder}"
    source      = "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build"
  }

  provisioner "file" {
    destination = "${var.image_folder}"
    sources     = [
      "${path.root}/lib/virtual-environments/images/ubuntu/assets/post-gen",
      "${path.root}/lib/virtual-environments/images/ubuntu/scripts/tests",
      "${path.root}/lib/virtual-environments/images/ubuntu/scripts/docs-gen"
    ]
  }

  provisioner "file" {
    destination = "${var.image_folder}/docs-gen/"
    source      = "${path.root}/lib/virtual-environments/helpers/software-report-base"
  }

  provisioner "file" {
    destination = "${var.installer_script_folder}/toolset.json"
    source      = "${path.root}/lib/virtual-environments/images/ubuntu/toolsets/toolset-2404.json"
  }

  provisioner "shell" {
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    inline          = [
      "mv ${var.image_folder}/docs-gen ${var.image_folder}/SoftwareReport",
      "mv ${var.image_folder}/post-gen ${var.image_folder}/post-generation"
    ]
  }

  provisioner "shell" {
    environment_vars = ["IMAGE_VERSION=${var.image_version}", "IMAGEDATA_FILE=${var.imagedata_file}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/configure-image-data.sh"]
  }

  provisioner "shell" {
    environment_vars = ["IMAGE_VERSION=${var.image_version}", "IMAGE_OS=${var.image_os}", "HELPER_SCRIPTS=${var.helper_script_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/scripts/configure-environment.sh"]
  }

  provisioner "shell" {
    environment_vars = ["DEBIAN_FRONTEND=noninteractive", "HELPER_SCRIPTS=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/install-apt-vital.sh"]
  }

  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/install-powershell.sh"]
  }



  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} pwsh -f {{ .Path }}'"
    scripts          = ["${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/Install-PowerShellModules.ps1", "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/Install-PowerShellAzModules.ps1"]
  }


  provisioner "shell" {
  environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}", "DEBIAN_FRONTEND=noninteractive"]
  execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
  scripts          = [
                      "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/install-actions-cache.sh",
                      "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/install-runner-package.sh",
                      "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/install-apt-common.sh",
                      "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/install-azcopy.sh",
                      "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/install-azure-cli.sh",
                      "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/install-azure-devops-cli.sh",
                      "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/install-bicep.sh",
                      "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/install-apache.sh",
                      "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/install-aws-tools.sh",
                      "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/install-clang.sh",
                      "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/install-swift.sh",
                      "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/install-cmake.sh",
                      "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/install-codeql-bundle.sh",
                      ]
  }

  provisioner "shell" {
  environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}", "DEBIAN_FRONTEND=noninteractive"]
  execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
  scripts          = [
                      "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/install-container-tools.sh",
                      "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/install-dotnetcore-sdk.sh",
                      "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/install-microsoft-edge.sh",
                      "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/install-gcc-compilers.sh",
                      "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/install-firefox.sh",
                      "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/install-gfortran.sh",
                      ]
  }

  provisioner "shell" {
  environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}", "DEBIAN_FRONTEND=noninteractive"]
  execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
  scripts          = [
                      "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/install-git.sh",
                      "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/install-git-lfs.sh",
                      "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/install-github-cli.sh",
                      "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/install-google-chrome.sh",
                      "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/install-haskell.sh",
                      "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/install-java-tools.sh",
                      ]
  }

  provisioner "shell" {
  environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}", "DEBIAN_FRONTEND=noninteractive"]
  execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
  scripts          = [
                      "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/install-kubernetes-tools.sh",
                      "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/install-miniconda.sh",
                      "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/install-kotlin.sh",
                      "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/install-mysql.sh",
                      "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/install-nginx.sh",
                      ]
  }

  provisioner "shell" {
  environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}", "DEBIAN_FRONTEND=noninteractive"]
  execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
  scripts          = [
                      "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/install-nodejs.sh",
                      "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/install-bazel.sh",
                      "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/install-php.sh",
                      "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/install-postgresql.sh",
                      "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/install-pulumi.sh",
                      "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/install-ruby.sh",
                      ]
  }

  provisioner "shell" {
  environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}", "DEBIAN_FRONTEND=noninteractive"]
  execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
  scripts          = [
                      "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/install-rust.sh",
                      "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/install-julia.sh",
                      "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/install-selenium.sh",
                      "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/install-packer.sh",
                      "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/install-vcpkg.sh",
                      "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/configure-dpkg.sh",
                      "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/install-yq.sh",
                      "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/install-android-sdk.sh",
                      "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/install-pypy.sh",
                      "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/install-python.sh",
                      "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/install-zstd.sh"
                      ]
  }

  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}", "DOCKERHUB_LOGIN=${var.dockerhub_login}", "DOCKERHUB_PASSWORD=${var.dockerhub_password}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/install-docker.sh"]
  }

  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} pwsh -f {{ .Path }}'"
    scripts          = ["${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/Install-Toolset.ps1", "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/Configure-Toolset.ps1"]
  }

  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/install-pipx-packages.sh"]
  }

  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "DEBIAN_FRONTEND=noninteractive", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}"]
    execute_command  = "/bin/sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/install-homebrew.sh"]
  }

  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}"]
    execute_command   = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts           = ["${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/configure-snap.sh"]
  }

  provisioner "shell" {
    execute_command   = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    expect_disconnect = true
    inline            = ["echo 'Reboot VM'", "sudo reboot"]
  }

  provisioner "shell" {
    execute_command     = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    pause_before        = "1m0s"
    scripts             = ["${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/cleanup.sh"]
    start_retry_timeout = "10m"
  }


  provisioner "shell" {
    environment_vars = ["IMAGE_VERSION=${var.image_version}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}"]
    inline           = ["pwsh -File ${var.image_folder}/SoftwareReport/Generate-SoftwareReport.ps1 -OutputDirectory ${var.image_folder}", "pwsh -File ${var.image_folder}/tests/RunAll-Tests.ps1 -OutputDirectory ${var.image_folder}"]
  }

  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPT_FOLDER=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}", "IMAGE_FOLDER=${var.image_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/configure-system.sh"]
  }

  provisioner "shell" {
    environment_vars = ["MS_AGENT_URL=${var.ms_agent_url}", "MS_AGENT_FILENAME=${var.ms_agent_filename}", "MS_AGENT_PAT=${var.ms_agent_pat}", "MS_AGENT_ORG_URL=${var.ms_agent_org_url}", "MS_AGENT_POOL_NAME=${var.ms_agent_pool}"]
    scripts          = ["${path.root}/scripts/configure-buildagent.sh"]
  }
  provisioner "shell" {
    scripts          = ["${path.root}/scripts/configure-grafana-agent.sh"]
  }

  provisioner "shell" {
    inline = ["sudo usermod -aG docker $USER", "sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config"]
  }

}
