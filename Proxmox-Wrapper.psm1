Function Invoke-ProxmoxLogin {
    <#
    .SYNOPSIS
    Login to Proxmox

    .DESCRIPTION
    Login to Proxmox and set the environment variables for the API token and host.

    .EXAMPLE
    PS> Login  
    #>

    $settings = Get-ProxmoxSettings

    return Connect-PveCluster -HostsAndPorts $settings.hostsAndPorts -SkipCertificateCheck -ApiToken $settings.apiToken

}


function Copy-PxVmTemplate {
    param (
        [Parameter(Mandatory = $true, Position = 1)]
        [string]
        $pxNode,
        [Parameter(Mandatory = $true, Position = 2)]
        [int]
        $vmId,
        [Parameter(Mandatory = $true, Position = 3)]
        [string]
        $name,
        [Parameter(Position = 4)]
        [string]
        $vmDescription = "",
        [Parameter(Position = 5)]
        [int]
        $newIdMin = 200,
        [int]
        $newIdMax = 299,
        [Parameter(Position = 6)]
        [string]
        $macAddress = $null,
        [Parameter(Position = 7)]
        [int]
        $cpuCores = 2,
        [Parameter(Position = 8)]
        [int]
        $memory = 2048,
        [int]
        $order = 999,
        [bool]
        $fullClone = $true,
        [string]
        $vmStorage = "vmthin"
    )
    
    $ticket = Invoke-ProxmoxLogin

    $newId = $newIdMin

    $idCheck = Get-PveClusterNextid -PveTicket $ticket -VmId $newId
    while (-not $idCheck.IsSuccessStatusCode) {
        Write-Host "VM ID $newId is already in use, trying next ID..."
        $newId++
        if ($newId -gt $newIdMax) {
            Write-Host "No available VM IDs in the range $newIdMin to $newIdMax."
            return
        }
        $idCheck = Get-PveClusterNextid -PveTicket $ticket -VmId $newId
    }
    
    Write-Host "Copying Proxmox VM Template: $name"
    $createAction =  New-PveNodesQemuClone -PveTicket $ticket -Description $vmDescription -Name $name -newid $newId -node $pxNode -VmId $vmId -Full $fullClone -Storage $vmStorage

    $finished = $false
    $upId = $createAction.Response.data;

    if (-not $upId) {
        Write-Host "Failed to initiate VM creation. Please check the parameters and try again."
        Write-Host ($createAction | ConvertTo-Json -Depth 10)
        return $false
    }

    Write-Host "Checking status of VM creation with UPID: $upId"
    while (-not $finished) {
        Start-Sleep -Seconds 5
        $status = Get-PveNodesTasksStatus -PveTicket $script:pv_ticket -node $pxNode -upid $upId
        if ($status.Response.data.status -eq "stopped") {
            Write-Host "VM creation finished successfully."
            $finished = $true
        } elseif ($status.Response.data.status -eq "running") {
            Write-Host "VM creation is still running..."
        } else {
            Write-Host "VM creation failed with status: $($status.Response.data.status)"
            Write-Host ($status | ConvertTo-Json -Depth 10)
            return $false
        }
    }


    $netConfig = @{ 0 = "virtio=$macAddress,bridge=vmbr0" }
    $ipconfig = @{ 0 = "ip=dhcp,ip6=dhcp" }

    Write-Host "Setting Proxmox VM Config: $name"
    $config = Set-PveNodesQemuConfig -PveTicket $ticket -Cores $cpuCores -Memory "$memory" -Node $pxNode -VmId $newId -IpconfigN $ipconfig -netn $netConfig -Onboot $true -Startup "order=$order"

    if (-not $config.IsSuccessStatusCode) {
        Write-Host "Failed to set VM configuration. Please check the parameters and try again."
        Write-Host ($config | ConvertTo-Json -Depth 10)
        return $false
    }

    Write-Host "Starting Proxmox VM: $name"
    $start = New-PveNodesQemuStatusStart -PveTicket $ticket -Node $pxNode -VmId $newId
    if (-not $start.IsSuccessStatusCode) {
        Write-Host "Failed to start VM. Please check the parameters and try again."
        Write-Host ($start | ConvertTo-Json -Depth 10)
        return $false
    }
    return $true
}

Function Get-PxVms {
    <#
    .SYNOPSIS
    Get Proxmox VMs

    .DESCRIPTION
    Retrieve a list of Proxmox VMs.

    .EXAMPLE
    PS> Get-PxVms
    #>

    $ticket = Invoke-ProxmoxLogin

    $vms = @()

    foreach ($node in (Get-PveNodes -PveTicket $ticket).Response.data) {

        foreach ($vm in (Get-PveNodesQemu -PveTicket $ticket -Node $node.node).Response.data) {
            
            $vm | Add-Member -MemberType NoteProperty -Name "node" -Value $node.node -Force
            $vms += $vm
        }
    }

    return $vms 
}

Function Get-PxVmByName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$vmName
    )

    $ticket = Invoke-ProxmoxLogin
    $vms = Get-PxVms -PveTicket $ticket

    $vm = $vms | Where-Object { $_.name -eq $vmName }

    if ($vm) {
        return $vm
    } else {
        Write-Host "No VM found with name: $vmName on node: $pxNode"
        return $null
    }
}

Function Get-PxVmMacAddress {
    param(
        [Parameter(Mandatory = $true)]
        [string]$vmId,
        [Parameter(Mandatory = $true)]
        [string]$pxNode
    )

    $ticket = Invoke-ProxmoxLogin
    $response = Get-PveNodesQemuConfig -PveTicket $ticket -Node $pxNode -VmId $vmId

    if ($response.IsSuccessStatusCode) {
        $data = $response.Response.data
        if ($data -and $data.net0) {
            $macAddress = $data.net0 -replace 'virtio=', '' -replace ',bridge=.*', ''
            return $macAddress
        } else {
            Write-Host "No MAC address found for VM ID: $vmId on node: $pxNode"
            return $null
        }
    } else {
        Write-Host "Failed to retrieve VM configuration for VM ID: $vmId on node: $pxNode"
        return $null
    }
}

Function Remove-PxVmById {
    param(
        [Parameter(Mandatory = $true)]
        [string]$vmId,
        [Parameter(Mandatory = $true)]
        [string]$pxNode
    )

    $ticket = Invoke-ProxmoxLogin
    Write-Host "Stopping VM $($vmId)"
    $stopRequest = Stop-PveVm -PveTicket $ticket -VmIdOrName $vmId

    if (-not $stopRequest.IsSuccessStatusCode) {
        Write-Host "Failed to stop VM $($vmId). Error: $($stopRequest | ConvertTo-Json -Depth 10)"
        return $false
    }

    $taskWait = Start-SleepOnPveTask -upid $stopRequest.Response.data -pxNode $pxNode

    if (-not $taskWait) {
        Write-Host "Failed to wait for VM stop task to complete."
        return $false
    }
    
    Write-Host "Removing Proxmox VM with ID: $vmId on node: $pxNode"
    $response = Remove-PveNodesQemu -PveTicket $ticket -Node $pxNode -VmId $vmId

    if ($response.IsSuccessStatusCode) {
        Write-Host "VM with ID: $vmId removed successfully."
        return $true
    } else {
        Write-Host "Failed to remove VM with ID: $vmId. Error: $($response | ConvertTo-Json -Depth 10)"
        return $false
    }
}

Function Start-SleepOnPveTask {
    param (
        [Parameter(Mandatory = $true)]
        [string]$upid,
        [Parameter(Mandatory = $true)]
        [string]$pxNode,
        [int]$interval = 15
    )

    $ticket = Invoke-ProxmoxLogin

    Write-Host "Checking status of task with UPID: $upid"
    while ($true) {
        Start-Sleep -Seconds $interval
        $status = Get-PveNodesTasksStatus -PveTicket $ticket -node $pxNode -upid $upid
        if ($status.Response.data.status -eq "stopped") {
            Write-Host "Task finished successfully."
            return $true
        } elseif ($status.Response.data.status -eq "running") {
            Write-Host "Task is still running..."
        } else {
            Write-Host "Task failed with status: $($status | ConvertTo-Json -Depth 10)"
            return $false
        }
    }

    return $true
}

Function Get-ProxmoxSettings {
    <#
    .SYNOPSIS
    Get settings used for Rke2 Provisioning Module

    .DESCRIPTION
    Retrieve settings used for Rke2 Provisioning Module.  If set, these settings are stored in your environment variables.

    .EXAMPLE
    PS> Get-Rke2Settings
    #>
    param ()

    $hostsAndPorts = $env:PX_HOSTS_AND_PORTS
    if ([string]::IsNullOrWhiteSpace($hostsAndPorts)) {
        $hostsAndPorts = [System.Environment]::GetEnvironmentVariable('PX_HOSTS_AND_PORTS', [System.EnvironmentVariableTarget]::User)
    }
    if ([string]::IsNullOrWhiteSpace($hostsAndPorts)) {
        $hostsAndPorts = "192.168.1.1:8006"
    }

    $apiToken = $env:PX_API_TOKEN
    if ([string]::IsNullOrWhiteSpace($apiToken)) {
        $apiToken = [System.Environment]::GetEnvironmentVariable('PX_API_TOKEN', [System.EnvironmentVariableTarget]::User)
    }
    if ([string]::IsNullOrWhiteSpace($apiToken)){
        $apiToken = ""
    }

    return @{
        hostsAndPorts = "$hostsAndPorts"
        apiToken = "$apiToken"
    }
}

Function Set-ProxmoxSettings {
    param (
        $hostsAndPorts,
        $apiToken
    )


    $env:PX_HOSTS_AND_PORTS = "$hostsAndPorts"
    $env:PX_API_TOKEN = "$apiToken"

    [System.Environment]::SetEnvironmentVariable('PX_HOSTS_AND_PORTS', "$hostsAndPorts", [System.EnvironmentVariableTarget]::User)
    [System.Environment]::SetEnvironmentVariable('PX_API_TOKEN', "$apiToken", [System.EnvironmentVariableTarget]::User)
}