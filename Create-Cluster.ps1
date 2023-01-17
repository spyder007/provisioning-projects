param (
    [Parameter(Mandatory=$true,Position=1)]
	$baseName,
    [ValidateSet("sm", "med")]
    $nodeSize="med",
    [ValidateSet("cleanup", "abort", "ask", "run-cleanup-provisioner")]
    $errorAction = "cleanup",
    $nodeCount=3,
    $countStart=1
)

$packerTemplate = ".\templates\ubuntu\ubuntu-2204.pkr.hcl"
$httpFolder = ".\templates\ubuntu\basic\http\"
$packerVariables = ".\templates\ubuntu\docker\$nodeSize-node.pkrvars.hcl"

## Create Nodes
for ($i=$countStart; $i -lt $nodeCount + $countStart; $i++) {
    $machineName = "$baseName-n$i"
    Write-Host "Building $machineName"
    Invoke-Expression ".\Build-Ubuntu.ps1 $packerTemplate $httpFolder $packerVariables -errorAction $errorAction -machineName $machineName"
}