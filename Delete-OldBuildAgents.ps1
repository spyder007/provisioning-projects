<#
    .SYNOPSIS
    Create a New Azure DevOps Build Agent (Ubuntu)

    .DESCRIPTION
    Create an Ubuntu Azure DevOps build agent.  This script utilizes provisioning from the GitHub Actions
    Runner Images repository (https://github.com/actions/runner-images).  Make sure you initialize the submodules
    in this repository before running this script.

    .PARAMETER type
    The type of Agent.  Current supported types are ubuntu-2204 and ubuntu-2004

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
    [string] $devOpsPat,
    [string] $devOpsPool,
    [string] $agentUser,
    [string] $agentPassword,   
    [bool] $useUnifi = $true
)

Import-Module ./HyperV-Provisioning.psm1


$vms = Get-Vm agt-ubt-*

if ($vms.Count -gt 1) {
    Write-Host "Removing old agents"

    $vms | Select-Object -Property Name, @{ Name="Date"; Expression={[DateTime]::ParseExact($_.Name.Replace("agt-ubt-", ""), 'yyMMdd', $null)}} 
        | sort-object -property date | Select-Object -First ($vms.Count - 1) 
        | ForEach-Object {
            Write-Host "Removing $($_.Name)"
            ##Remove-HyperVVm -machinename $($_.Name) -isMsAgent $true -msAgentPAT $devOpsPat -userName $agentUser -password $agentPassword
        }
}