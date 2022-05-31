Import-Module .\Unifi.psm1

$unifiClients = Get-UnifiClients

$vms =  get-vm -ComputerName hyperv03 | Where-Object {$_.State -eq "Running"} | Select-Object Name, State, @{n='Mac';e={$_.NetworkAdapters[0].MacAddress}}, @{n='Ip';e={$_.NetworkAdapters[0].IpAddresses[0]}}


foreach ($vm in $vms) {
    $uniClient = $unifiClients | Where-Object { $_.mac.Replace(":", "") -eq $vm.Mac }

    if ($null -ne $uniClient) {
        if ($uniClient.fixed_ip -ne $vm.Ip) {
            Write-Host "Found MAC match with different IP: " -NoNewline
            Write-Host "Unifi - $($uniClient.fixed_ip), VM $($vm.Ip) "
        }
    }
    else {
        Write-Host "No match for $($vm.Name)"
        Write-Host "  VM MAC: $($vm.Mac)"
        Write-Host "  VM IP: $($vm.Ip)"
    }
}