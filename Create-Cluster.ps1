param (
    [Parameter(Mandatory=$true,Position=1)]
	$baseName,
    $additionalNodes=2
)

$packerTemplate = ".\templates\ubuntu\ubuntu-2204.pkr.hcl"
$httpFolder = ".\templates\ubuntu\basic\http\"
$packerVariables = ".\templates\ubuntu\docker\k8-nonprod-main.pkrvars.hcl"

## Create Main

$machineName = "$baseName-main"
Write-Host "Building $machineName"
Invoke-Expression ".\Build-Ubuntu.ps1 $packerTemplate $httpFolder $packerVariables -machineName $machineName"

## Create Additional Nodes
for ($i=1; $i -le $additionalNodes; $i++) {
    $machineName = "$baseName-$i"
    Write-Host "Building $machineName"
    Invoke-Expression ".\Build-Ubuntu.ps1 $packerTemplate $httpFolder $packerVariables -machineName $machineName"
}