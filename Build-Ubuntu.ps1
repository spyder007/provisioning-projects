<#
        .SYNOPSIS
        Create an ubuntu hyper-v image using Packer

        .DESCRIPTION
        Create an ubuntu hyper-v image using Packer

        .PARAMETER TemplateFile
        The location of the Packer template file (*.json)

        .PARAMETER HostHttpFolder
        The locatikon of the HostHTTP Folder.  This folder is mounted for the network installer to read.

        .PARAMETER VariableFile
        The location of the .pkvars file for this run

        .PARAMETER machineName
        The machine name

        .EXAMPLE
        PS> .\Build-Ubuntu.ps1 ".\templates\ubuntu\ubuntu-2004.json" .\templates\ubuntu\basic\http .\templates\ubuntu\basic\basic.pkvars -machinename ubuntuHost
    #>

param (
    [Parameter(Mandatory=$true,Position=1)]
	$TemplateFile,
    [Parameter(Mandatory=$true, Position=2)]
    $HostHttpFolder,
    [Parameter(Mandatory=$true,Position=3)]
	$VariableFile,
    [Parameter(Position=4)]
    $OutputFolder="d:\\Virtual Machines\\",
    [Parameter(Position=5)]
    [String]
    $machineName=$null    
)


## Grab the variables file
if (($null -ne $VariableFile) -and (Test-Path $VariableFile)) {
    $inspectResult = packer inspect "$VariableFile" -machine-readable
    
    if ($inspectResult[1] -match "var\.username:\s`"(?<username>[^`"]*)`"") {
        $variableUserName = $Matches.username
    }

    if ($inspectResult[1] -match "var\.password:\s`"(?<password>[^`"]*)`"") {
        $variablePassword = $Matches.password
    }

    if ($inspectResult[1] -match "var\.vm_name:\s`"(?<vmname>[^`"]*)`"") {
        $variableMachineName = $Matches.vmname
    }
}
else {
    Write-Error "Variable file is required";
    return -1;
}

if ($null -eq $machineName) {
    $machineName = $variableMachineName
}

$macAddress = ./Provision-UnifiClient.ps1 -name "$($machineName)" -hostname "$($machineName)"
if ($null -eq $macAddress) {
    Write-Host "Using random mac address"
}
else {
    Write-Host "Mac Address = $macAddress"
}

## crypt the password (unix style) so that it can go into the autoinstall folder
$cryptedPass = (echo "$($variablePassword)" | openssl passwd -6 -salt "FFFDFSDFSDF" -stdin)

if (Test-Path "packerhttp") {
    Remove-Item -Force -Recurse "packerhttp"
}

# Copy the contents
mkdir "packerhttp" | Out-Null
Copy-Item -Recurse "$HostHttpFolder\*" "packerhttp"

$user_data_content = Get-Content "packerhttp\user-data"
$user_data_content = $user_data_content -replace "{{username}}", "$($variableUserName)"
$user_data_content = $user_data_content -replace "{{crypted_password}}", "$cryptedPass"
$user_data_content = $user_data_content -replace "{{hostname}}", "$($machineName)"
$user_data_content | Set-Content "packerhttp\user-data"

if ($null -eq $macAddress) {
    packer build -var-file "$VariableFile" -var "http=packerhttp" -var "output_dir=$OutputFolder" -var "vm_name=$machineName" "$TemplateFile"
}
else {
    packer build -var-file "$VariableFile" -var "http=packerhttp" -var "output_dir=$OutputFolder" -var "mac_address=$macAddress" -var "vm_name=$machineName" "$TemplateFile"
}

$vmFolder = [IO.Path]::Combine($OutputFolder, $machineName)

$vmcx = Get-ChildItem -Path "$vmFolder" -Recurse -Filter "*.vmcx"

Import-VM -Path "$($vmcx.FullName)"
Start-VM "$($machineName)"