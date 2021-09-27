# Provisioning Scripts - Hyper-V

These are working examples of using Packer to install and provision Hyper-V VMs.  Currently they are only setup to generate various flavors of Ubuntu images, but the templates can be used to build out templates for other OS provisioning.

The Packer templates are based on the work of [Nick Charlton's work][2] and related [post][3]

## Prerequisites

* Hyper-V - You must have the Hyper-V Windows components installed on your computer.  There is no way to run these scripts against a remote Hyper-V host:  they must be run on a machine with Hyper-V installed
* [Packer][Packer] - These were developed and tested against 1.7.0.  Newer versions should work, but your mileage will vary.


## Scripts

There are two main Powershell Scripts in this repository.

### Build-Ubuntu.ps1

This script has the following parameters.

* **TemplateFile** - The location of the Packer Template file.  Currenly, two ubuntu-2004.json files (located [here](./templates/ubuntu/ubuntu-2004.json) and [here](./templates/buildagents/ubuntu-2004.json) are the only Packer templates in this repository.
* **HostHttpFolder** - This is the folder that will be used as the *http_directory* in the Packer build. See the [Packer Docs](https://www.packer.io/docs/builders/hyperv/iso#http_directory) for more details.
* **VarableFile** - The .pkvars file for your build.  I have included `*.pkvars.template` files for reference.
* **OutputFolder** - (optional) - The final location of the Hyper-V machine
* **machineName** - (optional) - Override the `vm_name` parameter from the variables file

#### Hyper-V Export/Import

Since Packer automatically exports the Hyper-V image, this script performs and import and a start of the VM.

#### Usage

```powershell
.\Build-Ubuntu.ps1 ".\Templates\ubuntu\ubuntu-2004.pkr.hcl" .\templates\ubuntu\basic\http .\templates\ubuntu\basic\basic.pkrvars.hcl -machinename newhost
```

### Create-NewBuildAgent.ps1

This script uses Build-Ubuntu.ps1 to provision a new build agent based on Microsoft's hosted build agents for Github/Azure DevOps, specifically the [Ubuntu 20.04 agent](https://github.com/actions/virtual-environments/blob/main/images/linux/Ubuntu2004-README.md) 

If you are going to use this script, make sure to pull the submodule by running either of the following commands

```
git submodule init
git submodule update
```
OR
```
git clone --recurse-submodules https://github.com/spyder007/provisioning-projects
```

This will populate the proper commit of the ./templates/buildagents/lib folder, which is used for provisioning these agents.

#### Usage
* Make sure you create `./templates/buildagents/buildagent.pkrvars.hcl` by copying [./templates/buildagents/buildagent.pkrvars.hcl.template](./templates/buildagents/buildagent.pkrvars.template) and modifying the data accordingly
* Make sure you have a properly formatted `authorized_keys` file in your `files_dirs` location (rom the above pkrvars file)
* Create a Personal Access Token [PAT](https://docs.microsoft.com/en-us/azure/devops/organizations/accounts/use-personal-access-tokens-to-authenticate?view=azure-devops&tabs=preview-page) that has permissions to add and modify build agents.

```powershell
.\Create-NewBuildAgent.ps1
```

## Unifi Controller Provisioning
I have an API that wraps my Unifi Controller and allows me to randomly generate a Hyper-V appropriate MAC address and assign that MAC address a fixed IP in my DHCP (through my Unifi Security Gateway).  Obviously, this functionality is only useful for me, so this functionality is enabled based on environment variables and disabled by default.

## Notes
The *Basic* template assumes there is a file called `authorized_keys` in `/templates/ubuntu/basic/files` that contains your public SSH key.  The template configures SSH to require key authentication and disables password authentication.

## Author

Copyright (c) 2021 Matt Gerega. MIT Licensed.

[Packer]: https://packer.io
[1]: ./Build-Ubuntu.ps1
[2]: https://github.com/nickcharlton/packer-ubuntu-2004
[3]: https://nickcharlton.net/posts/automating-ubuntu-2004-installs-with-packer.html
[4]: ./Create-NewBuildAgent.ps1
