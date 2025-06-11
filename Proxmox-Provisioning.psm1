function Test-Imports {
    param (
        [bool] $useUnifi = $true
    )
    Import-Module ./Proxmox-Wrapper.psm1 -Force
    if ($useUnifi) {
        Import-Module ./Unifi.psm1 -Force
    }
}

function Build-PXUbuntuTemplate {
    <#
    .SYNOPSIS
        Copies a Proxmox Ubuntu template and provisions it with custom configuration.

    .DESCRIPTION
        This function creates a copy of an existing Ubuntu template in Proxmox VE and provisions it with specified settings such as network configuration, user accounts, and other customizations required for deployment.

    .PARAMETER TemplateName
        The name of the source Ubuntu template to copy from.

    .PARAMETER NewVMName
        The name for the new virtual machine that will be created from the template.

    .PARAMETER VMID
        The unique identifier for the new virtual machine in Proxmox.

    .PARAMETER TargetNode
        The Proxmox node where the new VM will be created.

    .PARAMETER Storage
        The storage location where the VM disk will be stored.

    .PARAMETER NetworkConfig
        Network configuration settings for the provisioned VM.

    .PARAMETER UserConfig
        User account configuration including username, password, and SSH keys.

    .EXAMPLE
        Copy-PXUbuntuTemplateAndProvision -TemplateName "ubuntu-20.04-template" -NewVMName "web-server-01" -VMID 101 -TargetNode "pve-node1"
        
        Creates a new VM from the Ubuntu template with the specified parameters.

    .NOTES
        Requires Proxmox VE API access and appropriate permissions to create and modify virtual machines.
    #>

    return @{
        success     = $success
        machineName = "$machineName"
    }  
}

function Copy-PXUbuntuTemplateAndProvision {
    
    <#
        .SYNOPSIS
        Create an Ubuntu Proxmox VM from a PX VM Template

        .DESCRIPTION
        Create an Ubuntu Proxmox VM from a PX VM Template.  This script does some specific work to translate passwords
        that are specific to Ubuntu.

        .PARAMETER vmSettings
        Settings for the VM to create.  This should be a hashtable with the following keys:
            - Name: The name of the VM
            - Description: A description of the VM
            - Cores: The number of CPU cores to allocate
            - Memory: The amount of memory in MB to allocate
            - DiskSizeGB: The size of the disk in GB
            - ClusterNodeStorage: The storage location for the VM
            - ClusterNode: The Proxmox node where the VM will be created
            - BaseVmId: The ID of the base PX VM template to copy from
            - MinVmId: The minimum VM ID to use for this VM
            - MaxVmId: The maximum VM ID to use for this VM

            @{
                Name               = "ubuntuHost"
                Description        = null
                Cores              = 2
                Memory             = 2048
                DiskSizeGB         = 50
                ClusterNodeStorage = "vmthin"
                ClusterNode        = ""
                BaseVmId           = 0
                MinVmId            = 200
                MaxVmId            = 299
            }

        .PARAMETER TemplateFile
        The location of the Packer template file (*.json or *.hcl)

        .PARAMETER SecretVariableFile
        The location of the .pkvars file for this run

        .PARAMETER ExtraVariableFile
        An optional file with extra variables to pass to Packer.  This should be a .pkvars file.

        .PARAMETER ExtraPackerArguments
        An optional string with extra arguments to pass to Packer.  This should be a string with the arguments you want to pass.

        .PARAMETER useUnifi
        If true, the machine will be provisioned using the Unifi module to request VM Network information.

        .PARAMETER packerErrorAction
        The ErrorAction to use for the Packer Command.  Valid values are "cleanup", "abort", "ask", and "run-cleanup-provisioner".
        See https://developer.hashicorp.com/packer/docs/commands/build for information on the -on-error option details.

    #>

    param (
        [Parameter(Mandatory = $true, Position = 1)]
        $vmSettings,
        [Parameter(Mandatory = $true, Position = 2)]
        $TemplateFile,
        [Parameter(Mandatory = $true, Position = 3)]
        $SecretVariableFile,
        [string]
        $ExtraVariableFile = "",
        [string]
        $ExtraPackerArguments = "",
        [bool]
        $useUnifi = $true,
        [ValidateSet("cleanup", "abort", "ask", "run-cleanup-provisioner")]
        $packerErrorAction = "cleanup"
    )

    Test-Imports $useUnifi

    $existingVm = Get-PxVmByName $vmSettings.Name
    if ($null -ne $existingVm) {
        Write-Error "A VM with the name $($vmSettings.Name) already exists.  Please choose a different name.";
        return @{
            success = $false
        }  
    }

    if ($null -eq $vmSettings.Description) {
        $vmDescription = "Px VM $($vmSettings.Name)"
    }
    else {
        $vmDescription = $vmSettings.Description
    }

    if ($useUnifi) {
        $macAddress = Invoke-ProvisionUnifiClient -name "$($vmSettings.Name)" -hostname "$($vmSettings.Name)"
        if ($null -eq $macAddress) {
            Write-Host "Using random mac address"
        }
        else {
            $macAddress | Format-Table | Out-Host
            Write-Host "Mac Address = $($macAddress.RawMacAddress)"
        }
    }
    else {
        $macAddress = $null
    }

    $success = Copy-PxVmTemplate -pxNode $vmSettings.ClusterNode -vmId $vmSettings.BaseVmId -name $vmSettings.Name -vmDescription $vmDescription -newIdMin $vmSettings.MinVmId -newIdMax $vmSettings.MaxVmId -macAddress $macAddress.MacAddress -cpuCores $vmSettings.cores -memory $vmSettings.memory -vmStorage $vmSettings.ClusterNodeStorage -startVm $false

    $newVm = Get-PxVmByName $vmSettings.Name
    if (-not $success -or $null -eq $newVm) {
        Write-Error "Could not copy PX VM Template";
        if ($useUnifi) {
            if ($null -ne $macAddress) {
                Remove-UnifiClient -macAddress $macAddress.MacAddress
            }
        }
        return @{
            success = $false
        }  
    }
    
    if ($newVm.maxdisk -eq 0) {
        Write-Error "The PX VM Template did not have a disk.  Cannot continue.";
        if ($useUnifi) {
            if ($null -ne $macAddress) {
                Remove-UnifiClient -macAddress $macAddress.MacAddress
            }
        }
        return @{
            success = $false
        }  
    }

    Write-Debug "New Vm $($newVm | ConvertTo-Json -Depth 5)";

    # Check SCSI disk size and resize if needed
    $currentDisk = $newVm.maxdisk / 1GB

    if ($currentDisk -lt $vmSettings.DiskSizeGB) {
        Write-Host "Resizing disk from $currentDisk GB to $($vmSettings.DiskSizeGB) GB"
        $resizeResult = Resize-PxVmDisk -vmId $newVm.vmid -pxNode $newVm.node -diskSizeGB $vmSettings.DiskSizeGB
        if (-not $resizeResult) {
            Write-Error "Could not resize disk";
            if ($useUnifi) {
                if ($null -ne $macAddress) {
                    Remove-UnifiClient -macAddress $macAddress.MacAddress
                }
            }
            return @{
                success = $false
            }  
        }
    }

    Start-PxVm $newVm.name

    $qemuAgentStarted = Wait-QemuAgent -vmId $newVm.vmid -pxNode $newVm.node

    if (-not $qemuAgentStarted) {
        Write-Error "QEMU Agent did not start.  Cannot continue.";
        if ($useUnifi) {
            if ($null -ne $macAddress) {
                Remove-UnifiClient -macAddress $macAddress.MacAddress
            }
        }
        return @{
            success = $false
        }  
    }

    $ipaddress = Get-PxVmIpAddress -vmId $newVm.vmid -pxNode $newVm.node

    Write-Host "New VM $($newVm.name) started with IP address $ipaddress"

    $sshHostArgument = "-var `"ssh_host=$ipaddress`""

    # Execute the Packer build
    $global:LASTEXITCODE = 0
    $onError = "-on-error=$packerErrorAction"

    if ([string]::IsNullOrWhiteSpace($ExtraVariableFile)) {
        $extraVarFileArgument = ""
    }
    else {
        $extraVarFileArgument = "-var-file `"$ExtraVariableFile`""
    }

    Invoke-Expression "packer init `"$TemplateFile`"" | Out-Host
    Invoke-Expression "packer build $onError -var-file `"$SecretVariableFile`" $extraVarFileArgument $ExtraPackerArguments $sshHostArgument `"$TemplateFile`"" | Out-Host

    $success = ($global:LASTEXITCODE -eq 0);

    return @{
        success     = $success
        machineName = "$machineName"
    }  
}

Function Set-PxVmTags {
    param (
        [Parameter(Mandatory = $true)]
        $machineName,
        [Parameter(Mandatory = $true)]
        [string[]] $tags
    )
    Test-Imports $false
    
    $vm = Get-PxVmByName $machineName

    if ($null -eq $vm -or $vm.name -ne $machineName) {
        Write-Error "$machineName not found"
        return -1
    }

    Set-PxVmTagsById -vmId $vm.vmid -pxNode $vm.node -tags $tags
}

function Remove-PxVm {
    param (
        [Parameter(Mandatory = $true)]
        $machineName,
        [bool] $useUnifi = $true
    )
    Test-Imports $useUnifi
    
    $vm = Get-PxVmByName $machineName

    if ($null -eq $vm -or $vm.name -ne $machineName) {
        Write-Error "$machineName not found"
        return -1
    }
    
    if ($useUnifi) {

        $macAddress = Get-PxVmMacAddress -vmId $vm.vmid -pxNode $vm.node
        if ($null -ne $macAddress) {           
            Write-Host "Deleting Mac Address $macAddress from Unifi Controller"
        
            $deleteResult = Remove-UnifiClient $macAddress
                
            if ($deleteResult -eq $false) {
                Write-Error "Could not delete IP.  Stopping";
                return -1
            }
        }
        else {
            Write-Error "Could not find VM Mac Address.  Stopping";
            return -1
        }
    }
    
    Remove-PxVmById -vmId $vm.vmid -pxNode $vm.node
}