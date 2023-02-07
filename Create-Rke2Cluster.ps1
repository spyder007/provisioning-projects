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
    [Parameter(Mandatory=$true,Position=2)]
	$clusterDnsName,
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
Import-Module powershell-yaml

$packerTemplate = ".\templates\ubuntu\$type.pkr.hcl"
$httpFolder = ".\templates\ubuntu\basic\http\"
$packerVariables = ".\templates\ubuntu\rke2\$nodeSize-server.pkrvars.hcl"

if (-not (Test-Path $packerVariables)) {
    Write-Error "Variable file not found: $packerVariables"
    return -1
}
$nodes = @()

$machineName = "{0}-srv-{1:x3}" -f $baseName, $countStart

$serverConfig = convertfrom-yaml (get-content .\templates\ubuntu\rke2\configuration\server-config.yaml -Raw)
$serverConfig."node-name" = $machineName
$serverConfig."tls-san" = @()
$serverConfig."tls-san" += $clusterDnsName
$serverConfig."tls-san" += $clusterDnsName.SubString(0, $clusterDnsName.IndexOf("."));

(ConvertTo-Yaml $serverConfig) | Set-Content -Path .\templates\ubuntu\rke2\files\server-config.yaml

Write-Host "Building $machineName"
$detail = Build-Ubuntu -TemplateFile "$packerTemplate" -HostHttpFolder "$httpFolder" -OutputFolder "$OutputFolder" -VariableFile "$packerVariables" -packerErrorAction "$packerErrorAction" -machineName "$machineName" -useUnifi $useUnifi

if (-not ($detail.success)) {
    Write-Error "Unable to provision server"
    exit -1;
}

$nodes += $detail;

$serverIp = $detail.ipAddress

Write-Host "Waiting 3 minutes to ensure the Server is up and running"
Start-Sleep -Seconds 180

if (Test-Path "c:\tmp") {
    Remove-Item -Recurse "c:\tmp"
}

# This step assumes that the user running this script has an SSH key listed in the ./templates/ubuntu/basic/files/authorized_keys file.  See the README for details.
Invoke-Expression "scp -o `"StrictHostKeyChecking no`" -o `"UserKnownHostsFile c:\tmp`" -o `"CheckHostIP no`" $($detail.userName)@$($serverip):rke2.yaml ./templates/ubuntu/rke2/files/rke2.yaml"
Invoke-Expression "scp -o `"StrictHostKeyChecking no`" -o `"UserKnownHostsFile c:\tmp`" -o `"CheckHostIP no`" $($detail.userName)@$($serverip):node-token ./templates/ubuntu/rke2/files/node-token"

$nodeToken = Get-Content -Raw ./templates/ubuntu/rke2/files/node-token

$packerVariables = ".\templates\ubuntu\rke2\$nodeSize-worker.pkrvars.hcl"

# Create Nodes
for ($i=$countStart+1; $i -lt $nodeCount + $countStart; $i++) {
    $machineName = "{0}-agt-{1:x3}" -f $baseName, $i
    Write-Host "Building $machineName"

    $agentConfig = convertfrom-yaml (get-content .\templates\ubuntu\rke2\configuration\agent-config.yaml -Raw)
    $agentConfig."node-name" = $machineName
    $agentConfig."server" = "https://$($clusterDnsName):9345"
    $agentConfig."token" = "$nodeToken"

    (ConvertTo-Yaml $agentConfig) | Set-Content -Path .\templates\ubuntu\rke2\files\agent-config.yaml

    $detail = Build-Ubuntu -TemplateFile "$packerTemplate" -HostHttpFolder "$httpFolder" -OutputFolder "$OutputFolder" -VariableFile "$packerVariables" -packerErrorAction "$packerErrorAction" -machineName "$machineName" -useUnifi $useUnifi

    if ($detail.success) {
        $nodes += $detail;
    }
}

$nodes | Format-Table