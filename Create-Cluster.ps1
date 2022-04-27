param (
    [Parameter(Mandatory=$true,Position=1)]
	$baseName,
    $nodeCount=3
)

$packerTemplate = ".\templates\ubuntu\ubuntu-2204.pkr.hcl"
$httpFolder = ".\templates\ubuntu\basic\http\"
$packerVariables = ".\templates\ubuntu\docker\k8-nonprod-main.pkrvars.hcl"

## Create Nodes
for ($i=1; $i -le $nodeCount; $i++) {
    $machineName = "$baseName-n$i"
    Write-Host "Building $machineName"
    Invoke-Expression ".\Build-Ubuntu.ps1 $packerTemplate $httpFolder $packerVariables -machineName $machineName"
}