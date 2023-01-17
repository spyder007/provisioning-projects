param (
    [Parameter(Mandatory=$true,Position=1)]
	$baseName,
    [ValidateSet("sm", "med")]
    $nodeSize="med",
    [ValidateSet("cleanup", "abort", "ask", "run-cleanup-provisioner")]
    $packerErrorAction = "cleanup",
    $nodeCount=3,
    $countStart=1
)

Import-Module ./HyperV-Provisioning.psm1

$packerTemplate = ".\templates\ubuntu\ubuntu-2204.pkr.hcl"
$httpFolder = ".\templates\ubuntu\basic\http\"
$packerVariables = ".\templates\ubuntu\docker\$nodeSize-node.pkrvars.hcl"

## Create Nodes
for ($i=$countStart; $i -lt $nodeCount + $countStart; $i++) {
    $machineName = "$baseName-n$i"
    Write-Host "Building $machineName"
    Build-Ubuntu -TemplateFile "$packerTemplate" -HostHttpFolder "$httpFolder" -VariableFile "$packerVariables" -packerErrorAction "$packerErrorAction" -machineName "$machineName"
}