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
        Create an Ubuntu Proxmox Template using Packer

        .DESCRIPTION
        Create an Ubuntu Proxmox Template using Packer.  This script does some specific work to translate passwords
        that are specific to Ubuntu.

        .PARAMETER TemplateFile
        The location of the Packer template file (*.json or *.hcl)

        .PARAMETER HostHttpFolder
        The locatikon of the HostHTTP Folder.  This folder is mounted for the network installer to read.

        .PARAMETER SecretVariableFile
        The location of the .pkvars file for this run

        .PARAMETER packerErrorAction
        The ErrorAction to use for the Packer Command.  Valid values are "cleanup", "abort", "ask", and "run-cleanup-provisioner".
        See https://developer.hashicorp.com/packer/docs/commands/build for information on the -on-error option details.

        .PARAMETER machineName
        The machine name to use for the final VM

        .EXAMPLE
        PS> .\Build-Ubuntu.ps1 ".\templates\ubuntu\ubuntu-2004.json" .\templates\ubuntu\basic\http .\templates\ubuntu\basic\basic.pkvars -machinename ubuntuHost
    #>

    param (
        [Parameter(Mandatory = $true, Position = 1)]
        $TemplateFile,
        [Parameter(Mandatory = $true, Position = 2)]
        $HostHttpFolder,
        [Parameter(Mandatory = $true, Position = 3)]
        $SecretVariableFile,
        [Parameter(Position = 4)]
        [ValidateSet("cleanup", "abort", "ask", "run-cleanup-provisioner")]
        $packerErrorAction = "cleanup",
        [Parameter(Position = 6)]
        [String]
        $machineName = $null,
        [string]
        $ExtraVariableFile = "",
        [string]
        $ExtraPackerArguments = ""
    )
    Test-Imports $false

    $vars = @{}
    ## Grab the variables file
    if (($null -ne $SecretVariableFile) -and (Test-Path $SecretVariableFile)) {
        $variableLines = Get-Content $SecretVariableFile
    
        foreach ($varLine in $variableLines) {
            if ($varLine -match "(?<var>[^=]*)=(?<value>.*)") {
                $vars[$matches.var.Trim().ToLower()] = $matches.value.Trim().Trim("`"")
            }
        }
    }
    else {
        Write-Error "Variable file is required";
        return -1;
    }
    if ($null -eq $machineName) {
        $machineName = $vars["vm_name"]
    }

    ## crypt the password (unix style) so that it can go into the autoinstall folder
    $cryptedPass = (Write-Output "$($vars["password"])" | openssl passwd -6 -salt "FFFDFSDFSDF" -stdin)

    if (Test-Path $HostHttpFolder) {
        if (Test-Path "packerhttp") {
            Remove-Item -Force -Recurse "packerhttp"
        }

        # Copy the contents
        mkdir "packerhttp" | Out-Null
        Copy-Item -Recurse "$HostHttpFolder\*" "packerhttp"

        $user_data_content = Get-Content "packerhttp\user-data"
        $user_data_content = $user_data_content -replace "{{username}}", "$($vars["username"])"
        $user_data_content = $user_data_content -replace "{{crypted_password}}", "$cryptedPass"
        $user_data_content = $user_data_content -replace "{{hostname}}", "$($machineName)"
        $user_data_content | Set-Content "packerhttp\user-data"

        $httpArgument = "-var `"http=packerhttp`""
    }
    else {
        Write-Warning "Host HTTP Folder not found";
        $httpArgument = ""
    }

    $global:LASTEXITCODE = 0
    $onError = "-on-error=$packerErrorAction"

    if ([string]::IsNullOrWhiteSpace($ExtraVariableFile)) {
        $extraVarFileArgument = ""
    }
    else {
        $extraVarFileArgument = "-var-file `"$ExtraVariableFile`""
    }

    Invoke-Expression "packer init `"$TemplateFile`"" | Out-Host
    Invoke-Expression "packer build $onError -var-file `"$SecretVariableFile`" $extraVarFileArgument $httpArgument -var `"vm_name=$machineName`" $ExtraPackerArguments `"$TemplateFile`"" | Out-Host

    $success = ($global:LASTEXITCODE -eq 0);

    return @{
        success     = $success
        machineName = "$machineName"
    }  
}

function Copy-PXUbuntuTemplate {
    <#
        .SYNOPSIS
        Create an Ubuntu Proxmox VM from a PX VM Template

        .DESCRIPTION
        Create an Ubuntu Proxmox VM from a PX VM Template.  This script does some specific work to translate passwords
        that are specific to Ubuntu.

        .PARAMETER TemplateFile
        The location of the Packer template file (*.json or *.hcl)

        .PARAMETER HostHttpFolder
        The locatikon of the HostHTTP Folder.  This folder is mounted for the network installer to read.

        .PARAMETER SecretVariableFile
        The location of the .pkvars file for this run

        .PARAMETER packerErrorAction
        The ErrorAction to use for the Packer Command.  Valid values are "cleanup", "abort", "ask", and "run-cleanup-provisioner".
        See https://developer.hashicorp.com/packer/docs/commands/build for information on the -on-error option details.

        .PARAMETER machineName
        The machine name to use for the final VM

        .EXAMPLE
        PS> .\Build-Ubuntu.ps1 ".\templates\ubuntu\ubuntu-2004.json" .\templates\ubuntu\basic\http .\templates\ubuntu\basic\basic.pkvars -machinename ubuntuHost
    #>

    param (
        [Parameter(Mandatory = $true, Position = 1)]
        $TemplateFile,
        [Parameter(Mandatory = $true, Position = 2)]
        $HostHttpFolder,
        [Parameter(Mandatory = $true, Position = 3)]
        $SecretVariableFile,
        [Parameter(Position = 4)]
        [ValidateSet("cleanup", "abort", "ask", "run-cleanup-provisioner")]
        $packerErrorAction = "cleanup",
        [Parameter(Position = 6)]
        [String]
        $machineName = $null,
        [string]
        $ExtraVariableFile = "",
        [string]
        $ExtraPackerArguments = "",
        [bool]
        $useUnifi = $true
    )

    Test-Imports $useUnifi

    $global:LASTEXITCODE = 0
    $onError = "-on-error=$packerErrorAction"

    if ([string]::IsNullOrWhiteSpace($ExtraVariableFile)) {
        $extraVarFileArgument = ""
    }
    else {
        $extraVarFileArgument = "-var-file `"$ExtraVariableFile`""
    }

    Invoke-Expression "packer init `"$TemplateFile`"" | Out-Host
    Invoke-Expression "packer build $onError -var-file `"$SecretVariableFile`" $extraVarFileArgument $httpArgument -var `"vm_name=$machineName`" $ExtraPackerArguments `"$TemplateFile`"" | Out-Host

    $success = ($global:LASTEXITCODE -eq 0);

    return @{
        success     = $success
        machineName = "$machineName"
    }  
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