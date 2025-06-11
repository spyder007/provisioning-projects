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
        $vmStorage = "vmthin",
        [bool]
        $startVm = $true
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
    $createAction = New-PveNodesQemuClone -PveTicket $ticket -Description $vmDescription -Name $name -newid $newId -node $pxNode -VmId $vmId -Full $fullClone -Storage $vmStorage

    $upId = $createAction.Response.data;

    if (-not $upId) {
        Write-Host "Failed to initiate VM creation. Please check the parameters and try again."
        Write-Host ($createAction | ConvertTo-Json -Depth 10)
        return $false
    }

    $sleepResult = Start-SleepOnPveTask -upid $upId -pxNode $pxNode -message "Waiting for VM creation..."

    if (-not $sleepResult) {
        Write-Host "Failed to wait for VM creation task to complete."
        return $false
    }

    if ($null -eq $macAddress) {
        Write-Host "No MAC address provided, generating a new one for VM ID: $newId"
        $macAddress = "02:00:" + (Get-Random -Minimum 0 -Maximum 255).ToString("X2") + ":" + (Get-Random -Minimum 0 -Maximum 255).ToString("X2") + ":" + (Get-Random -Minimum 0 -Maximum 255).ToString("X2")
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

    if ($startVm) {
        Start-PxVm -name $name
    }
    return $true
}

Function Set-PxVmTagsById {
    param(
        [Parameter(Mandatory = $true)]
        [string]$vmId,
        [Parameter(Mandatory = $true)]
        [string]$pxNode,
        [Parameter(Mandatory = $true)]
        [string[]]$tags
    )

    $ticket = Invoke-ProxmoxLogin

    Write-Host "Setting tags for VM ID: $vmId on node: $pxNode"

    $response = Set-PveNodesQemuConfig -PveTicket $ticket -Node $pxNode -VmId $vmId -Tags ($tags -join ",")

    if ($response.IsSuccessStatusCode) {
        Write-Host "Tags set successfully for VM ID: $vmId"
        return $true
    }
    else {
        Write-Host "Failed to set tags for VM ID: $vmId. Error: $($response | ConvertTo-Json -Depth 10)"
        return $false
    }
}

Function Start-PxVm {
    param(
        [Parameter(Mandatory = $true)]
        [string]$name
    )

    $ticket = Invoke-ProxmoxLogin

    $vm = Get-PxVmByName -vmName $name
    if (-not $vm) {
        Write-Host "VM with name $name not found."
        return $false
    }

    Write-Host "Starting Proxmox VM: $($vm.name)"
    $start = New-PveNodesQemuStatusStart -PveTicket $ticket -Node $vm.node -VmId $vm.vmid
    if (-not $start.IsSuccessStatusCode) {
        Write-Host "Failed to start VM. Please check the parameters and try again."
        Write-Host ($start | ConvertTo-Json -Depth 10)
        return $false
    }
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
    }
    else {
        Write-Debug "No VM found with name: $vmName on node: $pxNode"
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
        }
        else {
            Write-Host "No MAC address found for VM ID: $vmId on node: $pxNode"
            return $null
        }
    }
    else {
        Write-Host "Failed to retrieve VM configuration for VM ID: $vmId on node: $pxNode"
        return $null
    }
}

Function Get-PxVmIpAddress {
    param(
        [Parameter(Mandatory = $true)]
        [string]$vmId,
        [Parameter(Mandatory = $true)]
        [string]$pxNode
    )

    $ticket = Invoke-ProxmoxLogin

    Write-Host "Retrieving IP address for VM ID: $vmId on node: $pxNode"

    $response = Get-PveNodesQemuAgentNetworkGetInterfaces -PveTicket $ticket -Node $pxNode -VmId $vmId

    if ($response.IsSuccessStatusCode) {
        $ipaddress = $response.Response.data.result | Where-Object { $_.name -eq "eth0" } | ForEach-Object { $_.'ip-addresses' } | Where-Object { $_.'ip-address-type' -eq "ipv4" } | ForEach-Object { $_."ip-address" }
        if ($null -eq $ipaddress) {
            Write-Host "No MAC address found for VM ID: $vmId on node: $pxNode"
            return $null
        }
        return $ipaddress
    }
    else {
        Write-Host "Failed to retrieve network interfaces for VM ID: $vmId on node: $pxNode"
        return $null
    }
}

Function Resize-PxVmDisk {
    param(
        [Parameter(Mandatory = $true)]
        [string]$vmId,
        [Parameter(Mandatory = $true)]
        [string]$pxNode,
        [Parameter(Mandatory = $true)]
        [int]$diskSizeGB,
        [string]$diskName = "scsi0" # Default disk name, can be changed if needed
    )

    $ticket = Invoke-ProxmoxLogin

    Write-Host "Resizing disk for VM ID: $vmId on node: $pxNode to size: $diskSizeGB"

    $resizeAction = Set-PveNodesQemuResize -PveTicket $ticket -Node $pxNode -VmId $vmId -Disk $diskName -Size "$($diskSizeGB)G"

    Write-Debug "Resize action response: $($resizeAction | ConvertTo-Json -Depth 10)"

    if ($resizeAction.IsSuccessStatusCode) {
        $sleepResult = Start-SleepOnPveTask -upid $resizeAction.Response.data -pxNode $pxNode -message "Resizing disk for VM ID $vmId on node $pxNode..."
        
        if (-not $sleepResult) {
            Write-Host "Failed to wait for disk resize task to complete."
            return $false
        }
        return $true
    }
    else {
        Write-Host "Failed to resize disk. Error: $($resizeAction | ConvertTo-Json -Depth 10)"
        return $false
    }
}

Function Wait-QemuAgent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$vmId,
        [Parameter(Mandatory = $true)]
        [string]$pxNode,
        [int]$timeoutSeconds = (60 * 10) # Default timeout of 10 minutes
    )

    $ticket = Invoke-ProxmoxLogin

    Write-Host "Waiting for QEMU agent to be ready for VM ID: $vmId on node: $pxNode.." -NoNewline

    $startTime = Get-Date
    while ((Get-Date) -lt $startTime.AddSeconds($timeoutSeconds)) {
        $response = Get-PveNodesQemuAgentInfo -PveTicket $ticket -Node $pxNode -VmId $vmId

        if ($response.IsSuccessStatusCode) {
            Write-Host "ready."
            return $true
        }

        Write-Host "." -NoNewline
        Start-Sleep -Seconds 15
    }

    Write-Host "Timeout reached, QEMU agent is still not ready."
    return $false
}

Function Remove-PxVmById {
    param(
        [Parameter(Mandatory = $true)]
        [string]$vmId,
        [Parameter(Mandatory = $true)]
        [string]$pxNode
    )

    $ticket = Invoke-ProxmoxLogin
    $stopRequest = Stop-PveVm -PveTicket $ticket -VmIdOrName $vmId

    if (-not $stopRequest.IsSuccessStatusCode) {
        Write-Host "Failed to stop VM $($vmId). Error: $($stopRequest | ConvertTo-Json -Depth 10)"
        return $false
    }

    $taskWait = Start-SleepOnPveTask -upid $stopRequest.Response.data -pxNode $pxNode -message "Stopping VM $($vmId)..."

    if (-not $taskWait) {
        Write-Host "Failed to wait for VM stop task to complete."
        return $false
    }
    
    Write-Host "Removing Proxmox VM with ID: $vmId on node: $pxNode"
    $response = Remove-PveNodesQemu -PveTicket $ticket -Node $pxNode -VmId $vmId

    if ($response.IsSuccessStatusCode) {
        Write-Host "VM with ID: $vmId removed successfully."
        return $true
    }
    else {
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
        [string]$message = "Waiting for task to complete...",
        [int]$interval = 15
    )

    $ticket = Invoke-ProxmoxLogin

    Write-Debug "Checking status of task with UPID: $upid"
    Write-Host $message -NoNewline
    while ($true) {
        Start-Sleep -Seconds $interval
        $status = Get-PveNodesTasksStatus -PveTicket $ticket -node $pxNode -upid $upid
        if ($status.Response.data.status -eq "stopped") {
            Write-Host "completed."
            return $true
        }
        elseif ($status.Response.data.status -eq "running") {
            Write-Host "." -NoNewline
        }
        else {
            Write-Host "failed."
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
    if ([string]::IsNullOrWhiteSpace($apiToken)) {
        $apiToken = ""
    }

    return @{
        hostsAndPorts = "$hostsAndPorts"
        apiToken      = "$apiToken"
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