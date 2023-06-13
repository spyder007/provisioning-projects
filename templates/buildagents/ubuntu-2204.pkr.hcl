
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
  default = "5e38b55d57d94ff029719342357325ed3bda38fa80054f9330dc789cd2d43931"
}

variable "iso_url" {
  type    = string
  default = "https://releases.ubuntu.com/22.04/ubuntu-22.04.2-live-server-amd64.iso"
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
  default = "hhttps://vstsagentpackage.azureedge.net/agent/3.220.5"
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
    script          = "${path.root}/lib/virtual-environments/images/linux/scripts/base/apt-mock.sh"
  }

  provisioner "shell" {
    environment_vars = ["DEBIAN_FRONTEND=noninteractive"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/lib/virtual-environments/images/linux/scripts/base/repos.sh"]
  }

  provisioner "shell" {
    environment_vars = ["DEBIAN_FRONTEND=noninteractive"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    script           = "${path.root}/lib/virtual-environments/images/linux/scripts/base/apt.sh"
  }

  provisioner "shell" {
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    script          = "${path.root}/lib/virtual-environments/images/linux/scripts/base/limits.sh"
  }

  provisioner "file" {
    destination = "${var.helper_script_folder}"
    source      = "${path.root}/lib/virtual-environments/images/linux/scripts/helpers"
  }

  provisioner "file" {
    destination = "${var.installer_script_folder}"
    source      = "${path.root}/lib/virtual-environments/images/linux/scripts/installers"
  }

  provisioner "file" {
    destination = "${var.image_folder}"
    source      = "${path.root}/lib/virtual-environments/images/linux/post-generation"
  }

  provisioner "file" {
    destination = "${var.image_folder}"
    source      = "${path.root}/lib/virtual-environments/images/linux/scripts/tests"
  }

  provisioner "file" {
    destination = "${var.image_folder}"
    source      = "${path.root}/lib/virtual-environments/images/linux/scripts/SoftwareReport"
  }
  
  provisioner "file" {
    destination = "${var.image_folder}/SoftwareReport/"
    source      = "${path.root}/lib/virtual-environments/helpers/software-report-base"
  }

  provisioner "file" {
    destination = "${var.installer_script_folder}/toolset.json"
    source      = "${path.root}/lib/virtual-environments/images/linux/toolsets/toolset-2204.json"
  }

  provisioner "shell" {
    environment_vars = ["IMAGE_VERSION=${var.image_version}", "IMAGEDATA_FILE=${var.imagedata_file}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/lib/virtual-environments/images/linux/scripts/installers/preimagedata.sh"]
  }

  provisioner "shell" {
    environment_vars = ["IMAGE_VERSION=${var.image_version}", "IMAGE_OS=${var.image_os}", "HELPER_SCRIPTS=${var.helper_script_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/scripts/configure-environment.sh"]
  }

  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/lib/virtual-environments/images/linux/scripts/installers/complete-snap-setup.sh", "${path.root}/lib/virtual-environments/images/linux/scripts/installers/powershellcore.sh"]
  }



  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} pwsh -f {{ .Path }}'"
    scripts          = ["${path.root}/lib/virtual-environments/images/linux/scripts/installers/Install-PowerShellModules.ps1", "${path.root}/lib/virtual-environments/images/linux/scripts/installers/Install-AzureModules.ps1"]
  }

  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}", "DOCKERHUB_LOGIN=${var.dockerhub_login}", "DOCKERHUB_PASSWORD=${var.dockerhub_password}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/lib/virtual-environments/images/linux/scripts/installers/docker-compose.sh", "${path.root}/lib/virtual-environments/images/linux/scripts/installers/docker-moby.sh"]
  }

  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}", "DEBIAN_FRONTEND=noninteractive"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = [
                        "${path.root}/lib/virtual-environments/images/linux/scripts/installers/azcopy.sh",
                        "${path.root}/lib/virtual-environments/images/linux/scripts/installers/azure-cli.sh",
                        "${path.root}/lib/virtual-environments/images/linux/scripts/installers/azure-devops-cli.sh",
                        "${path.root}/lib/virtual-environments/images/linux/scripts/installers/basic.sh",
                        "${path.root}/lib/virtual-environments/images/linux/scripts/installers/bicep.sh",
                        "${path.root}/lib/virtual-environments/images/linux/scripts/installers/aliyun-cli.sh",
                        "${path.root}/lib/virtual-environments/images/linux/scripts/installers/apache.sh",
                        "${path.root}/lib/virtual-environments/images/linux/scripts/installers/aws.sh",
                        "${path.root}/lib/virtual-environments/images/linux/scripts/installers/clang.sh",
                        "${path.root}/lib/virtual-environments/images/linux/scripts/installers/swift.sh",
                        "${path.root}/lib/virtual-environments/images/linux/scripts/installers/cmake.sh",
                        "${path.root}/lib/virtual-environments/images/linux/scripts/installers/codeql-bundle.sh",
                        "${path.root}/lib/virtual-environments/images/linux/scripts/installers/containers.sh",
			"${path.root}/lib/virtual-environments/images/linux/scripts/installers/dotnetcore-sdk.sh",
                        "${path.root}/lib/virtual-environments/images/linux/scripts/installers/firefox.sh",
                        "${path.root}/lib/virtual-environments/images/linux/scripts/installers/microsoft-edge.sh",
			"${path.root}/lib/virtual-environments/images/linux/scripts/installers/gcc.sh",
                        "${path.root}/lib/virtual-environments/images/linux/scripts/installers/gfortran.sh",
                        "${path.root}/lib/virtual-environments/images/linux/scripts/installers/git.sh",
                        "${path.root}/lib/virtual-environments/images/linux/scripts/installers/github-cli.sh",
                        "${path.root}/lib/virtual-environments/images/linux/scripts/installers/google-chrome.sh",
                        "${path.root}/lib/virtual-environments/images/linux/scripts/installers/google-cloud-sdk.sh",
                        "${path.root}/lib/virtual-environments/images/linux/scripts/installers/haskell.sh",
                        "${path.root}/lib/virtual-environments/images/linux/scripts/installers/heroku.sh",
			"${path.root}/lib/virtual-environments/images/linux/scripts/installers/java-tools.sh",
                        "${path.root}/lib/virtual-environments/images/linux/scripts/installers/kubernetes-tools.sh",
                        "${path.root}/lib/virtual-environments/images/linux/scripts/installers/oc.sh",
			"${path.root}/lib/virtual-environments/images/linux/scripts/installers/leiningen.sh",
			"${path.root}/lib/virtual-environments/images/linux/scripts/installers/miniconda.sh",
                        "${path.root}/lib/virtual-environments/images/linux/scripts/installers/mono.sh",
                        "${path.root}/lib/virtual-environments/images/linux/scripts/installers/kotlin.sh",
                        "${path.root}/lib/virtual-environments/images/linux/scripts/installers/mysql.sh",
                        "${path.root}/lib/virtual-environments/images/linux/scripts/installers/mssql-cmd-tools.sh",
                        "${path.root}/lib/virtual-environments/images/linux/scripts/installers/sqlpackage.sh",
                        "${path.root}/lib/virtual-environments/images/linux/scripts/installers/nginx.sh",
                        "${path.root}/lib/virtual-environments/images/linux/scripts/installers/nvm.sh",
                        "${path.root}/lib/virtual-environments/images/linux/scripts/installers/nodejs.sh",
                        "${path.root}/lib/virtual-environments/images/linux/scripts/installers/bazel.sh",
                        "${path.root}/lib/virtual-environments/images/linux/scripts/installers/oras-cli.sh",
                        "${path.root}/lib/virtual-environments/images/linux/scripts/installers/php.sh",
                        "${path.root}/lib/virtual-environments/images/linux/scripts/installers/postgresql.sh",
                        "${path.root}/lib/virtual-environments/images/linux/scripts/installers/pulumi.sh",
                        "${path.root}/lib/virtual-environments/images/linux/scripts/installers/ruby.sh",
                        "${path.root}/lib/virtual-environments/images/linux/scripts/installers/r.sh",
                        "${path.root}/lib/virtual-environments/images/linux/scripts/installers/rust.sh",
                        "${path.root}/lib/virtual-environments/images/linux/scripts/installers/julia.sh",
                        "${path.root}/lib/virtual-environments/images/linux/scripts/installers/sbt.sh",
			"${path.root}/lib/virtual-environments/images/linux/scripts/installers/selenium.sh",
                        "${path.root}/lib/virtual-environments/images/linux/scripts/installers/terraform.sh",
                        "${path.root}/lib/virtual-environments/images/linux/scripts/installers/packer.sh",
                        "${path.root}/lib/virtual-environments/images/linux/scripts/installers/vcpkg.sh",
                        "${path.root}/lib/virtual-environments/images/linux/scripts/installers/dpkg-config.sh",
                        "${path.root}/lib/virtual-environments/images/linux/scripts/installers/yq.sh",
			"${path.root}/lib/virtual-environments/images/linux/scripts/installers/android.sh",
                        "${path.root}/lib/virtual-environments/images/linux/scripts/installers/pypy.sh",
                        "${path.root}/lib/virtual-environments/images/linux/scripts/installers/python.sh",
                        "${path.root}/lib/virtual-environments/images/linux/scripts/installers/graalvm.sh",
                        "${path.root}/lib/virtual-environments/images/linux/scripts/installers/zstd.sh"
                        ]
  }

  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} pwsh -f {{ .Path }}'"
    scripts          = ["${path.root}/lib/virtual-environments/images/linux/scripts/installers/Install-Toolset.ps1", "${path.root}/lib/virtual-environments/images/linux/scripts/installers/Configure-Toolset.ps1"]
  }

  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/lib/virtual-environments/images/linux/scripts/installers/pipx-packages.sh"]
  }

  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "DEBIAN_FRONTEND=noninteractive", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}"]
    execute_command  = "/bin/sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/lib/virtual-environments/images/linux/scripts/installers/homebrew.sh"]
  }

  provisioner "shell" {
    execute_command   = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts           = ["${path.root}/lib/virtual-environments/images/linux/scripts/base/snap.sh"]
  }

  provisioner "shell" {
    execute_command   = "/bin/sh -c '{{ .Vars }} {{ .Path }}'"
    expect_disconnect = true
    scripts           = ["${path.root}/lib/virtual-environments/images/linux/scripts/base/reboot.sh"]
  }

  provisioner "shell" {
    execute_command     = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    pause_before        = "1m0s"
    scripts             = ["${path.root}/lib/virtual-environments/images/linux/scripts/installers/cleanup.sh"]
    start_retry_timeout = "10m"
  }

  provisioner "shell" {
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    script          = "${path.root}/lib/virtual-environments/images/linux/scripts/base/apt-mock-remove.sh"
  }

  provisioner "shell" {
    environment_vars = ["IMAGE_VERSION=${var.image_version}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}"]
    inline           = ["pwsh -File ${var.image_folder}/SoftwareReport/SoftwareReport.Generator.ps1 -OutputDirectory ${var.image_folder}", "pwsh -File ${var.image_folder}/tests/RunAll-Tests.ps1 -OutputDirectory ${var.image_folder}"]
  }

  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPT_FOLDER=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}", "IMAGE_FOLDER=${var.image_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/lib/virtual-environments/images/linux/scripts/installers/post-deployment.sh"]
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
