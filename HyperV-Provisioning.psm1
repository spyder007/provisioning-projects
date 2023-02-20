function Build-UbuntuBase {
      <#
        .SYNOPSIS
        Create an Ubuntu hyper-v image using Packer

        .DESCRIPTION
        Create an Ubuntu hyper-v image using Packer.  This script does some specific work to translate passwords
        that are specific to Ubuntu.

        .PARAMETER TemplateFile
        The location of the Packer template file (*.json or *.hcl)

        .PARAMETER HostHttpFolder
        The locatikon of the HostHTTP Folder.  This folder is mounted for the network installer to read.

        .PARAMETER VariableFile
        The location of the .pkvars file for this run

        .PARAMETER OutputFolder
        The base folder where the VM information will be stored.

        .PARAMETER packerErrorAction
        The ErrorAction to use for the Packer Command.  Valid values are "cleanup", "abort", "ask", and "run-cleanup-provisioner".
        See https://developer.hashicorp.com/packer/docs/commands/build for information on the -on-error option details.

        .PARAMETER machineName
        The machine name to use for the final VM

        .EXAMPLE
        PS> .\Build-Ubuntu.ps1 ".\templates\ubuntu\ubuntu-2004.json" .\templates\ubuntu\basic\http .\templates\ubuntu\basic\basic.pkvars -machinename ubuntuHost
    #>

    param (
        [Parameter(Position = 1)]
        $TemplateFile = ".\templates\ubuntu-base\ubuntu-2204-base.pkr.hcl",
        [Parameter(Position = 2)]
        $HostHttpFolder = ".\templates\ubuntu-base\http",
        [Parameter(Position = 3)]
        $VariableFile = ".\templates\ubuntu-base\base.pkrvars.hcl",
        [Parameter(Position = 4)]
        [ValidateSet("cleanup", "abort", "ask", "run-cleanup-provisioner")]
        $packerErrorAction = "cleanup",
        [Parameter(Position = 5)]
        $OutputFolder = "d:\\Virtual Machines\\",
        [Parameter(Position = 6)]
        [String]
        $machineName = "ubuntu-2204-base"
    )

    $vars = @{}
    ## Grab the variables file
    if (($null -ne $VariableFile) -and (Test-Path $VariableFile)) {
        $variableLines = Get-Content $VariableFile
    
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

    $global:LASTEXITCODE = 0
    $onError = "-on-error=$packerErrorAction"

    Invoke-Expression "packer build $onError -var-file `"$VariableFile`" -var `"http=packerhttp`" -var `"output_dir=$OutputFolder`" -var `"vm_name=$machineName`" `"$TemplateFile`"" | Out-Host

    $success = ($global:LASTEXITCODE -eq 0);

    if ($success) {
        $vmFolder = [IO.Path]::Combine($OutputFolder, $machineName)

        return @{
            success          = $true
            machineName      = "$machineName"
            baseLocation     = "$vmFolder"
        }
    }
}


function Build-Ubuntu {
    <#
        .SYNOPSIS
        Create an Ubuntu hyper-v image using Packer

        .DESCRIPTION
        Create an Ubuntu hyper-v image using Packer.  This script does some specific work to translate passwords
        that are specific to Ubuntu.

        .PARAMETER TemplateFile
        The location of the Packer template file (*.json or *.hcl)

        .PARAMETER HostHttpFolder
        The locatikon of the HostHTTP Folder.  This folder is mounted for the network installer to read.

        .PARAMETER VariableFile
        The location of the .pkvars file for this run

        .PARAMETER OutputFolder
        The base folder where the VM information will be stored.

        .PARAMETER packerErrorAction
        The ErrorAction to use for the Packer Command.  Valid values are "cleanup", "abort", "ask", and "run-cleanup-provisioner".
        See https://developer.hashicorp.com/packer/docs/commands/build for information on the -on-error option details.

        .PARAMETER machineName
        The machine name to use for the final VM

        .PARAMETER useUnifi
        If true, the machine will be provisioned using the Unifi module to request VM Network information.

        .EXAMPLE
        PS> .\Build-Ubuntu.ps1 ".\templates\ubuntu\ubuntu-2004.json" .\templates\ubuntu\basic\http .\templates\ubuntu\basic\basic.pkvars -machinename ubuntuHost
    #>

    param (
        [Parameter(Mandatory = $true, Position = 1)]
        $TemplateFile,
        [Parameter(Mandatory = $true, Position = 2)]
        $HostHttpFolder,
        [Parameter(Mandatory = $true, Position = 3)]
        $VariableFile,
        [Parameter(Position = 4)]
        [ValidateSet("cleanup", "abort", "ask", "run-cleanup-provisioner")]
        $packerErrorAction = "cleanup",
        [Parameter(Position = 5)]
        $OutputFolder = "d:\\Virtual Machines\\",
        [Parameter(Position = 6)]
        [String]
        $machineName = $null,
        [bool]
        $useUnifi = $true    
    )

    if ($useUnifi) {
        Import-Module ./Unifi.psm1
    }

    $vars = @{}
    ## Grab the variables file
    if (($null -ne $VariableFile) -and (Test-Path $VariableFile)) {
        $variableLines = Get-Content $VariableFile
    
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

    $macAddress = $null;
    if ($useUnifi) {
        $macAddress = Invoke-ProvisionUnifiClient -name "$($machineName)" -hostname "$($machineName)"
        if ($null -eq $macAddress) {
            Write-Host "Using random mac address"
        }
        else {
            $macAddress | Format-Table | Out-Host
            Write-Host "Mac Address = $($macAddress.RawMacAddress)"
        }
    }

    ## crypt the password (unix style) so that it can go into the autoinstall folder
    $cryptedPass = (Write-Output "$($vars["password"])" | openssl passwd -6 -salt "FFFDFSDFSDF" -stdin)

    if (Test-Path $HostHttpFolder)
    {
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
    $macArgument = ""
    if ($null -ne $macAddress) {
        $macArgument = "-var `"mac_address=$($macAddress.RawMacAddress)`""
    }
    $onError = "-on-error=$packerErrorAction"

    Invoke-Expression "packer build $onError -var-file `"$VariableFile`" $httpArgument -var `"output_dir=$OutputFolder`" $macArgument -var `"vm_name=$machineName`" `"$TemplateFile`"" | Out-Host

    $success = ($global:LASTEXITCODE -eq 0);

    if ($success) {
        $vmFolder = [IO.Path]::Combine($OutputFolder, $machineName)
        $vmcx = Get-ChildItem -Path "$vmFolder" -Recurse -Filter "*.vmcx"

        Import-VM -Path "$($vmcx.FullName)" | Out-Host
        Start-VM "$($machineName)" | Out-Host
        return @{
            success          = $true
            machineName      = "$machineName"
            macAddress       = "$($macAddress.MacAddress)"
            ipAddress        = "$($macAddress.IPAddress)"
            userName         = "$($vars["username"])"
        }
    }
    else {
        if ($useUnifi) {
            if ($null -ne $macAddress) {
                Remove-UnifiClient -macAddress $macAddress.MacAddress
            }
        }
        return @{
            success          = $false
        }
    }


}

function Build-Windows {
    <#
        .SYNOPSIS
        Create an Windows hyper-v image using Packer

        .DESCRIPTION
        Create an Ubuntu hyper-v image using Packer.  This script does some specific work to translate passwords
        that are specific to Ubuntu.

        .PARAMETER TemplateFile
        The location of the Packer template file (*.json or *.hcl)

        .PARAMETER HostHttpFolder
        The locatikon of the HostHTTP Folder.  This folder is mounted for the network installer to read.

        .PARAMETER VariableFile
        The location of the .pkvars file for this run

        .PARAMETER OutputFolder
        The base folder where the VM information will be stored.

        .PARAMETER packerErrorAction
        The ErrorAction to use for the Packer Command.  Valid values are "cleanup", "abort", "ask", and "run-cleanup-provisioner".
        See https://developer.hashicorp.com/packer/docs/commands/build for information on the -on-error option details.

        .PARAMETER machineName
        The machine name to use for the final VM

        .PARAMETER useUnifi
        If true, the machine will be provisioned using the Unifi module to request VM Network information.

        .EXAMPLE
        PS> .\Build-Ubuntu.ps1 ".\templates\ubuntu\ubuntu-2004.json" .\templates\ubuntu\basic\http .\templates\ubuntu\basic\basic.pkvars -machinename ubuntuHost
    #>

    param (
        [Parameter(Mandatory = $true, Position = 1)]
        $TemplateFile,
        [Parameter(Mandatory = $true, Position = 2)]
        $VariableFile,
        [Parameter(Position = 4)]
        [ValidateSet("cleanup", "abort", "ask", "run-cleanup-provisioner")]
        $packerErrorAction = "cleanup",
        [Parameter(Position = 5)]
        $OutputFolder = "d:\\Virtual Machines\\",
        [Parameter(Position = 6)]
        [String]
        $machineName = $null,
        [bool]
        $useUnifi = $true    
    )

    if ($useUnifi) {
        Import-Module ./Unifi.psm1
    }

    $vars = @{}
    ## Grab the variables file
    if (($null -ne $VariableFile) -and (Test-Path $VariableFile)) {
        $variableLines = Get-Content $VariableFile
    
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

    $macAddress = $null;
    if ($useUnifi) {
        $macAddress = Invoke-ProvisionUnifiClient -name "$($machineName)" -hostname "$($machineName)"
        if ($null -eq $macAddress) {
            Write-Host "Using random mac address"
        }
        else {
            $macAddress | Format-Table | Out-Host
            Write-Host "Mac Address = $($macAddress.RawMacAddress)"
        }
    }

    $global:LASTEXITCODE = 0
    $macArgument = ""
    if ($null -ne $macAddress) {
        $macArgument = "-var `"mac_address=$($macAddress.RawMacAddress)`""
    }
    $onError = "-on-error=$packerErrorAction"

    Invoke-Expression "packer build $onError -var-file `"$VariableFile`" -var `"output_dir=$OutputFolder`" $macArgument -var `"vm_name=$machineName`" `"$TemplateFile`"" | Out-Host

    $success = ($global:LASTEXITCODE -eq 0);

    if ($success) {
        $vmFolder = [IO.Path]::Combine($OutputFolder, $machineName)
        $vmcx = Get-ChildItem -Path "$vmFolder" -Recurse -Filter "*.vmcx"

        Import-VM -Path "$($vmcx.FullName)" | Out-Host
        Start-VM "$($machineName)" | Out-Host
        return @{
            success          = $true
            machineName      = "$machineName"
            macAddress       = "$($macAddress.MacAddress)"
            ipAddress        = "$($macAddress.IPAddress)"
            userName         = "$($vars["username"])"
        }
    }
    else {
        if ($useUnifi) {
            if ($null -ne $macAddress) {
                Remove-UnifiClient -macAddress $macAddress.MacAddress
            }
        }
        return @{
            success          = $false
        }
    }


}



function Remove-HyperVVm {
    param (
        [Parameter(Mandatory = $true)]
        $machineName,
        [bool]
        $isMsAgent = $false,
        [Parameter()]
        $msAgentPAT,
        [Parameter()]
        $userName,
        [bool] $useUnifi = $true
    )
    
    if ($useUnifi) {
        Import-Module ./Unifi.psm1
    }
    
    if ($isMsAgent) {
        ssh "$userName@$machineName" "export MS_AGENT_PAT=$msAgentPAT;cd /imagegeneration; sudo chmod 777 remove-agent.sh; ./remove-agent.sh"
    }
    
    $vm = Get-Vm $machineName

    if ($null -eq $vm) {
        Write-Error "$machineName not found"
        return -1
    }
    
    $vmPath = $vm.Path

    if ($useUnifi) {

        $netInfo = Get-HyperVNetworkInfo -vmname $machineName
        if ($null -ne $netInfo) {
            $macAddress = $netInfo.MacAddress
            
            Write-Host "Deleting Mac Address $macAddress from Unifi Controller"
        
            $deleteResult = Remove-UnifiClient $macAddress
                
            if ($deleteResult -eq $false) {
                Write-Error "Could not delete IP.  Stopping";
                return -1
            }
        }
        else {
            Write-Error "Could not find VM IP Address.  Stopping";
            return -1
        }
    }
    
    Write-Host "Stopping VM" -nonewline
    Stop-Vm -Name $machineName
    while ((Get-Vm $machineName).State -ne "Off") {
        Write-Host "." -nonewline
        Start-Sleep -s 5
    }
    Write-Host "Stopped"
    
    Write-Host "Removing VM"
    Remove-Vm -Name $machineName -Force

    Remove-Item -Recurse $vmPath
}

function Get-HyperVNetworkInfo{
    param(
        $vmname
    )
    $ipv4Regex = '^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'
    $networkAdapter = (Get-VmNetworkAdapter -VMName $vmname)[0]
    if ($null -eq $networkAdapter) {
        Write-Error "Could not find network adapter for $vmname"
        return $null
    }
    return @{
        MacAddressRaw = $networkAdapter.MacAddress
        MacAddress = ($networkAdapter.MacAddress -replace '..(?!$)', '$&:').ToLower()
        IpV4Address =  ($networkAdapter.IPAddresses | Where-Object {$_ -match $ipv4Regex } )
    }
}