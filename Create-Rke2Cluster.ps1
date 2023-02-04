    <#
        .SYNOPSIS
        Create a set of docker-enabled Ubuntu nodes for a Kubernetes cluster.

        .DESCRIPTION
        Create a set of docker-enabled Ubuntu nodes for a Kubernetes cluster.  This script will provision multiple machines, using the nodeCount
        and nodeStart parameters to determine machine name.

        .PARAMETER baseName
        The base name of the VM nodes.  This name will be appended with a count, which is a six-digit hexidecimal representation of the
        VM.

        .PARAMETER type
        The type of node.  Current supported types are ubuntu-2204 and ubuntu-2004

        .PARAMETER OutputFolder
        The base folder where the VM information will be stored.

        .PARAMETER packerErrorAction
        The ErrorAction to use for the Packer Command.  Valid values are "cleanup", "abort", "ask", and "run-cleanup-provisioner".
        See https://developer.hashicorp.com/packer/docs/commands/build for information on the -on-error option details.

        .PARAMETER nodeSize
        This parameter is used to locate a pkrvars.hcl file in ./templates/ubuntu/docker/ which corresponds to the nodeSize.  It uses the
        following format: {nodeSize}-node.pkrvars.hcl.  If this file does not exist, the script will exit.  

        Node Size files are not included in this repository:  they must be created based on ./templates/ubuntu/docker/docker.pkrvars.hcl.template.

        .PARAMETER useUnifi
        If true, the machine will be provisioned using the Unifi module to request VM Network information.

        .EXAMPLE
        PS> .\Create-NewBuildAgent.ps1 -type ubuntu-2204 -OutputFolder "c:\my\virtualmachines"
    #>

param (
    [Parameter(Mandatory=$true,Position=1)]
	$baseName,
    [Parameter()]
    [ValidateSet("ubuntu-2204")]
    $type = "ubuntu-2204",
    [ValidateSet("sm", "med")]
    $nodeSize="med",
    [ValidateSet("cleanup", "abort", "ask", "run-cleanup-provisioner")]
    $packerErrorAction = "cleanup",
    [Parameter()]
    $OutputFolder="d:\\Virtual Machines\\",
    $nodeCount=3,
    $countStart=1,
    [bool]$useUnifi = $true
)

Import-Module ./HyperV-Provisioning.psm1

$packerTemplate = ".\templates\ubuntu\$type.pkr.hcl"
$httpFolder = ".\templates\ubuntu\basic\http\"
$packerVariables = ".\templates\ubuntu\rke2\$nodeSize-server.pkrvars.hcl"

if (-not (Test-Path $packerVariables)) {
    Write-Error "Variable file not found: $packerVariables"
    return -1
}
$nodes = @()

$machineName = "{0}-server-{1:x3}" -f $baseName, $i
Write-Host "Building $machineName"
$detail = Build-Ubuntu -TemplateFile "$packerTemplate" -HostHttpFolder "$httpFolder" -OutputFolder "$OutputFolder" -VariableFile "$packerVariables" -packerErrorAction "$packerErrorAction" -machineName "$machineName" -useUnifi $useUnifi

if ($detail.success) {
    $nodes += $detail;
}

## Create Nodes
# for ($i=$countStart; $i -lt $nodeCount + $countStart; $i++) {
#     $machineName = "{0}-{1:x6}" -f $baseName, $i
#     Write-Host "Building $machineName"
#     $detail = Build-Ubuntu -TemplateFile "$packerTemplate" -HostHttpFolder "$httpFolder" -OutputFolder "$OutputFolder" -VariableFile "$packerVariables" -packerErrorAction "$packerErrorAction" -machineName "$machineName" -useUnifi $useUnifi

#     if ($detail.success) {
#         $nodes += $detail;
#     }
# }

$nodes | Format-Table