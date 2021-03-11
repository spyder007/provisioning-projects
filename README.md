# Provisioning Scripts - Hyper-V

These are working examples of using Packer to install and provision Hyper-V VMs.

Powershell build scripts (like [Build-Ubuntu.ps1][1]) utilize a call to a personal API that randomly generates a Hyper-V Mac


The Packer templates are based on the work of [Nick Charlton's work][2] and related [post][3]


## Usage

```powershell
.\Build-Ubuntu.ps1 ".\Templates\ubuntu\ubuntu-2004.json" .\templates\ubuntu\basic\http .\templates\ubuntu\bsaic\basic.pkrvars -provisionGroup "virtual"
```

## Notes
The *Basic* template assumes there is a file called `authorized_keys` in `/templates/ubuntu/basic/files` that contains your public SSH key.  The template configures SSH to require key authentication and disables password authentication.

## Author

Copyright (c) 2021 Matt Gerega. MIT Licensed.

[Packer]: https://packer.io
[1]: ./Build-Ubuntu.ps1
[2]: https://github.com/nickcharlton/packer-ubuntu-2004
[3]: https://nickcharlton.net/posts/automating-ubuntu-2004-installs-with-packer.html
