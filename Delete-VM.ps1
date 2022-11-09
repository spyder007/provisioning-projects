param (
    [Parameter(Mandatory=$true)]
    $machineName,
    [Parameter(Mandatory=$true)]
    $userName,
    [Parameter(Mandatory=$true)]
    $hyperVisor,
    [bool]
    $isMsAgent=$false,
    [Parameter()]
    $msAgentPAT
)

Import-Module ./Unifi.psm1

if ($isMsAgent) {
  ssh "$userName@$machineName" "export MS_AGENT_PAT=$msAgentPAT;cd /imagegeneration; sudo chmod 777 remove-agent.sh; ./remove-agent.sh"
}

$vm = Get-Vm -ComputerName $hyperVisor $machineName
if ($null -eq $vm) {
    Write-Error "$machineName not found on $hyperVisor"
    return -1
}

$macAddress = $vm.NetworkAdapters[0].MacAddress
$macAddress = ($macAddress -replace '..(?!$)', '$&:').ToLower();

Write-Host "Deleting Mac Address $macAddress from Unifi Controller"
$deleteResult = Remove-UnifiClient $macAddress

#$vmPath = "\\$hyperVisor\{0}" -f ($vm.Path -replace "^(\w{1}):(.*)", '$1$$$2')

Write-Host "Stopping VM" -nonewline
Stop-Vm -Name $machineName -ComputerName $hyperVisor
while ((Get-Vm -computername $hyperVisor $machineName).State -ne "Off"){
    Write-Host "." -nonewline
    Start-Sleep -s 5
}
Write-Host "Stopped"

Write-Host "Removing VM"
Remove-Vm -Name $machineName -ComputerName $hyperVisor -Force