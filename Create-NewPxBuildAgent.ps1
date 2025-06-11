<#
        .SYNOPSIS
        Create a New Azure DevOps Build Agent (Ubuntu)

        .DESCRIPTION
        Create an Ubuntu Azure DevOps build agent.  This script utilizes provisioning from the GitHub Actions
        Runner Images repository (https://github.com/actions/runner-images).  Make sure you initialize the submodules
        in this repository before running this script.

        .PARAMETER type
        The type of Agent.  Current supported types are ubuntu-2204 and ubuntu-2404

        .PARAMETER OutputFolder
        The base folder where the VM information will be stored.

        .PARAMETER packerErrorAction
        The ErrorAction to use for the Packer Command.  Valid values are "cleanup", "abort", "ask", and "run-cleanup-provisioner".
        See https://developer.hashicorp.com/packer/docs/commands/build for information on the -on-error option details.

        .PARAMETER useUnifi
        If true, the machine will be provisioned using the Unifi module to request VM Network information.

        .EXAMPLE
        PS> .\Create-NewBuildAgent.ps1 -type ubuntu-2204 -OutputFolder "c:\my\virtualmachines"
    #>

param (
    [string] $settingsFile = "msBuildAgentVmSettings.json",
    [ValidateSet("cleanup", "abort", "ask", "run-cleanup-provisioner")]
    $packerErrorAction = "cleanup",
    [bool] $useUnifi = $true,
    [string] $secretVariableFile = ".\templates\buildagents\secrets.pkrvars.hcl",
    [string] $extraVariableFile = ".\templates\buildagents\buildagent.pkrvars.hcl"
)

$templateFile = Join-Path -Path $PSScriptRoot -ChildPath ".\templates\buildagents\null.pkr.hcl"
if (-not (Test-Path $settingsFile)) {
    Write-Error "Settings file not found: $settingsFile"
    return
}

if (-not (Test-Path $secretVariableFile)) {
    Write-Error "Secret variable file not found: $secretVariableFile"
    return
}

if (-not (Test-Path $extraVariableFile)) {
    Write-Error "Extra variable file not found: $extraVariableFile"
    return
}

Import-Module ./Proxmox-Provisioning.psm1 -Force

## Generate agent name
$agentDate = (Get-Date).ToString("yyMMdd")
$machineName = "agt-ubt-$agentDate"

$vmSettings = (Get-Content $settingsFile -Raw | ConvertFrom-Json -Depth 10)
if ($null -eq $vmSettings) {
    Write-Error "Failed to load VM settings from $settingsFile"
    return
}

$vmSettings.Name = $machineName
$vmSettings.Description = "$($vmSettings.Description) $agentDate"

Write-Host "Creating new agent: $($vmSettings.Name)"

## Create and Provision agent
Copy-PXUbuntuTemplateAndProvision $vmSettings $templateFile "$secretVariableFile" -ExtraVariableFile "$extraVariablFile" -packerErrorAction "$packerErrorAction"

