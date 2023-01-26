# Provisioning Scripts - Hyper-V

These are working examples of using Packer to install and provision Hyper-V VMs.  Currently they are only setup to generate various flavors of Ubuntu images, but the templates can be used to build out templates for other OS provisioning.

The Packer templates are based on the work of [Nick Charlton's work][1] and related [post][2]

## Prerequisites

* Hyper-V - You must have the Hyper-V Windows components installed on your computer.  There is no way to run these scripts against a remote Hyper-V host:  they must be run on a machine with Hyper-V installed
* [Packer][Packer] - These were developed and tested against 1.8.4.  Newer versions should work, but your mileage will vary.
* [OpenSSL][OpenSSL] - Windows OpenSSL is used to hash the passwords for Ubuntu images
  
I use [Chocolatey][Chocolatey] to install and update both Packer and OpenSSL on my server.

```powershell
choco install packer
choco install openssl
```

### A note on Packer HTTP

The Ubuntu image provisioner is setup to use a `cloud-config` file to autoinstall.  This requires the use of the Packer HTTP server, and, more specifically, that the server's firewall is configured to accept ports 8000-9000.  

```powershell
New-NetFirewallRule -DisplayName "Allow Packer HTTP" -Direction Inbound -Action Allow -EdgeTraversalPolicy Allow -Protocol TCP -LocalPort 8000-9000
```

## Modules

There are two Powershell Modules in this repository.

### Hyper-V Provisioning

The Hyper-V Provisioning Module ([HyperV-Provisioning.psm1](./HyperV-Provisioning.psm1)) provides functions for provisioning Hyper-V images.  Each module and its functions are documented, so see the file for more details.

### Unifi Module

I have an API that wraps my Unifi Controller and allows me to randomly generate a Hyper-V appropriate MAC address and assign that MAC address a fixed IP in my DHCP (through my Unifi Security Gateway).  Obviously, this functionality is only useful for me, so this functionality is enabled based on environment variables and disabled by default.

The Unifi Module ([Unifi.psm1](./Unifi.psm1)) provides functionality for authenticating and making calls to this wrapper.  The Hyper-V Provisioning module functions provider for a `-useUnifi` parameter that can be set to `false` to ignore this module.

## Scripts

All scripts are self documented.  To see the documentation, either examine the script or run `get-help` with the script name.

```powershell
get-help .\Create-NewBuildAgent.ps1 -Detailed
```

## Variable Files

This repository contains template *.pkrvars.hcl files for all of the templates.  You are responsible for creating the appropriate variables files.  

For example, create `./templates/buildagents/buildagent.pkrvars.hcl` by copying [./templates/buildagents/buildagent.pkrvars.hcl.template](./templates/buildagents/buildagent.pkrvars.template) and modifying the data accordingly.

## `authorized_keys` Files

All Ubuntu templates, including the Azure DevOps Build Agents, assume there is a file called `authorized_keys` in `/templates/ubuntu/basic/files` that contains your public SSH key.  The template configures SSH to require key authentication and disables password authentication.

Make sure you have a properly formatted `authorized_keys` file in your `files_dirs` location (from the above pkrvars file).

## Azure DevOps Build Agents

Create a Personal Access Token [PAT][3] that has permissions to add and modify build agents.  This value is then saved in your `buildagent.pkrvars.hcl` file.

### Git Submodule

The `Create-NewBuildAgent.ps1` script uses the Hyper-V Provisioning Module to provision a new build agent based on Microsoft's hosted build agents for Github/Azure DevOps.  In order to stay up to date, the runner-images repository is a submodule of this repository.

If you are going to use the `Create-NewBuildAgent.ps1` script, make sure to pull the submodule by running either of the following commands

```bash
git submodule init
git submodule update
```

OR

```bash
git clone --recurse-submodules https://github.com/spyder007/provisioning-projects
```

This will populate the proper commit of the ./templates/buildagents/lib folder, which is used for provisioning these agents.

## Author

Copyright (c) 2023 Matt Gerega. MIT Licensed.

[Packer]: https://packer.io
[OpenSSL]: https://www.openssl.org/
[Chocolatey]: https://chocolatey.org/
[1]: https://github.com/nickcharlton/packer-ubuntu-2004
[2]: https://nickcharlton.net/posts/automating-ubuntu-2004-installs-with-packer.html
[3]: https://docs.microsoft.com/en-us/azure/devops/organizations/accounts/use-personal-access-tokens-to-authenticate?view=azure-devops&tabs=preview-page
