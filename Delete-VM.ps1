param (
    [Parameter(Mandatory=$true)]
    $machineName,
    [bool]
    $isMsAgent=$false,
    [Parameter()]
    $msAgentPAT,
    [Parameter()]
    $userName
)

Import-Module ./Unifi.psm1

if ($isMsAgent) {
  ssh "$userName@$machineName" "export MS_AGENT_PAT=$msAgentPAT;cd /imagegeneration; sudo chmod 777 remove-agent.sh; ./remove-agent.sh"
}

$vm = Get-Vm $machineNameif ($null -eq $vm) {
    Write-Error "$machineName not found"
    return -1
}

$networkAdapter = (Get-VmNetworkAdapter -VMName $machineName)[0]
if ($null -eq $networkAdapter) {
    Write-Error "Could not find network adapter for $machineName"
    return -1
}

$macAddress = $networkAdapter.MacAddress
$macAddress = ($macAddress -replace '..(?!$)', '$&:').ToLower();

Write-Host "Deleting Mac Address $macAddress from Unifi Controller"
$deleteResult = Remove-UnifiClient $macAddress


if ($deleteResult -eq $false) {
    Write-Host "Could not delete IP.  Stopping";
    return -1
}

Write-Host "Stopping VM" -nonewline
Stop-Vm -Name $machineName
while ((Get-Vm $machineName).State -ne "Off"){
    Write-Host "." -nonewline
    Start-Sleep -s 5
}
Write-Host "Stopped"

Write-Host "Removing VM"
Remove-Vm -Name $machineName -Force