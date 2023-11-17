
variable "build_temp" {
  type    = string
  default = "d:\\buildtemp"
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
  default = "a4acfda10b18da50e2ec50ccaf860d7f20b389df8765611142305c0e911d16fd"
}

variable "iso_url" {
  type    = string
  default = "https://releases.ubuntu.com/22.04/ubuntu-22.04.3-live-server-amd64.iso"
}

variable "mac_address" {
  type    = string
  default = "000000000000"
}

variable "memory" {
  type    = string
  default = "2048"
}

variable "ms_agent_filename" {
  type    = string
  default = "vsts-agent-linux-x64-3.220.5.tar.gz"
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
  default = "https://vstsagentpackage.azureedge.net/agent/3.220.5"
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
    script          = "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/apt-mock.sh"
  }

    provisioner "shell" {
    environment_vars = ["DEBIAN_FRONTEND=noninteractive"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = [
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/repos.sh",
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/apt-ubuntu-archive.sh",
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/apt.sh"]
  }
  
  provisioner "shell" {
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    script          = "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/limits.sh"
  }

  provisioner "file" {
    destination = "${var.helper_script_folder}"
    source      = "${path.root}/lib/virtual-environments/images/ubuntu/scripts/helpers"
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
    source      = "${path.root}/lib/virtual-environments/helpers/software-report-base
  }

  provisioner "file" {
    destination = "${var.installer_script_folder}/toolset.json"
    source      = "${path.root}/lib/virtual-environments/images/ubuntu/toolsets/toolset-2204.json"
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
    scripts          = ["${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/preimagedata.sh"]
  }

  provisioner "shell" {
    environment_vars = ["IMAGE_VERSION=${var.image_version}", "IMAGE_OS=${var.image_os}", "HELPER_SCRIPTS=${var.helper_script_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/scripts/configure-environment.sh"]
  }

  provisioner "shell" {
    environment_vars = ["DEBIAN_FRONTEND=noninteractive", "HELPER_SCRIPTS=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/apt-vital.sh"]
  }

  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/complete-snap-setup.sh", "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/powershellcore.sh"]
  }



  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} pwsh -f {{ .Path }}'"
    scripts          = ["${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/Install-PowerShellModules.ps1", "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/Install-AzureModules.ps1"]
  }

  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}", "DEBIAN_FRONTEND=noninteractive"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = [
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/action-archive-cache.sh",
			                  "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/runner-package.sh",
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/apt-common.sh",
			                  "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/azcopy.sh",
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/azure-cli.sh",
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/azure-devops-cli.sh",
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/bicep.sh",
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/aliyun-cli.sh",
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/apache.sh",
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/aws.sh",
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/clang.sh",
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/swift.sh",
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/cmake.sh",
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/codeql-bundle.sh",
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/containers.sh",
			"${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/dotnetcore-sdk.sh",
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/firefox.sh",
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/microsoft-edge.sh",
			"${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/gcc.sh",
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/gfortran.sh",
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/git.sh",
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/git-lfs.sh",
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/github-cli.sh",
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/google-chrome.sh",
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/google-cloud-cli.sh",
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/haskell.sh",
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/heroku.sh",
			"${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/java-tools.sh",
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/kubernetes-tools.sh",
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/oc.sh",
			"${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/leiningen.sh",
			"${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/miniconda.sh",
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/mono.sh",
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/kotlin.sh",
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/mysql.sh",
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/mssql-cmd-tools.sh",
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/sqlpackage.sh",
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/nginx.sh",
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/nvm.sh",
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/nodejs.sh",
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/bazel.sh",
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/oras-cli.sh",
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/php.sh",
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/postgresql.sh",
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/pulumi.sh",
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/ruby.sh",
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/r.sh",
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/rust.sh",
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/julia.sh",
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/sbt.sh",
			"${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/selenium.sh",
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/terraform.sh",
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/packer.sh",
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/vcpkg.sh",
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/dpkg-config.sh",
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/yq.sh",
			"${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/android.sh",
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/pypy.sh",
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/python.sh",
                        "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/zstd.sh"
                        ]
  }

  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}", "DOCKERHUB_LOGIN=${var.dockerhub_login}", "DOCKERHUB_PASSWORD=${var.dockerhub_password}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/docker-compose.sh", "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/docker.sh"]
  }

  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} pwsh -f {{ .Path }}'"
    scripts          = ["${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/Install-Toolset.ps1", "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/Configure-Toolset.ps1"]
  }

  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/pipx-packages.sh"]
  }

  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "DEBIAN_FRONTEND=noninteractive", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}"]
    execute_command  = "/bin/sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/homebrew.sh"]
  }

  provisioner "shell" {
    execute_command   = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts           = ["${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/snap.sh"]
  }

  provisioner "shell" {
    execute_command   = "/bin/sh -c '{{ .Vars }} {{ .Path }}'"
    expect_disconnect = true
    scripts           = ["${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/reboot.sh"]
  }

  provisioner "shell" {
    execute_command     = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    pause_before        = "1m0s"
    scripts             = ["${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/cleanup.sh"]
    start_retry_timeout = "10m"
  }

  provisioner "shell" {
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    script          = "${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/apt-mock-remove.sh"
  }

  provisioner "shell" {
    environment_vars = ["IMAGE_VERSION=${var.image_version}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}"]
    inline           = ["pwsh -File ${var.image_folder}/SoftwareReport/SoftwareReport.Generator.ps1 -OutputDirectory ${var.image_folder}", "pwsh -File ${var.image_folder}/tests/RunAll-Tests.ps1 -OutputDirectory ${var.image_folder}"]
  }

  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPT_FOLDER=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}", "IMAGE_FOLDER=${var.image_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/lib/virtual-environments/images/ubuntu/scripts/build/post-deployment.sh"]
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
