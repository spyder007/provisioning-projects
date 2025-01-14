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
    [Parameter()]
    [ValidateSet("ubuntu-2204", "ubuntu-2404")]
    $type,
    [Parameter()]
    $OutputFolder="d:\\Virtual Machines\\",
    [ValidateSet("cleanup", "abort", "ask", "run-cleanup-provisioner")]
    $packerErrorAction = "cleanup",
    [bool] $useUnifi = $true,
    [string] $secretVariableFile = ".\templates\buildagents\secrets.pkrvars.hcl",
    [string] $extraVariableFile = ".\templates\buildagents\buildagent.pkrvars.hcl"
)

Import-Module ./HyperV-Provisioning.psm1

## Generate agent name
$agentDate=(Get-Date).ToString("yyMMdd")
$machineName = "agt-ubt-$agentDate"

Write-Host "Creating new agent: $machineName"

## Create and Provision agent
Build-Ubuntu -TemplateFile ".\templates\buildagents\$($type).pkr.hcl" -HostHttpFolder ".\templates\buildagents\http\" -SecretVariableFile "$secretVariableFile" -ExtraVariableFile "$extraVariableFile" -packerErrorAction "$packerErrorAction" -OutputFolder "$OutputFolder" -machineName $machineName -useUnifi $useUnifi -importAndStart $true
