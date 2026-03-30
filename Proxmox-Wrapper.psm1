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
        $startVm = $true,
        [int]
        $vlanId = 50,
        [int]
        $bwlimit = 20480
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
    if ($bwlimit -gt 0) {
        Write-Host "  Applying bandwidth throttling: $bwlimit MiB/s"
        $createAction = New-PveNodesQemuClone -PveTicket $ticket -Description $vmDescription -Name $name -newid $newId -node $pxNode -VmId $vmId -Full $fullClone -Storage $vmStorage -Bwlimit $bwlimit
    }
    else {
        $createAction = New-PveNodesQemuClone -PveTicket $ticket -Description $vmDescription -Name $name -newid $newId -node $pxNode -VmId $vmId -Full $fullClone -Storage $vmStorage
    }

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

    $netConfigString = "virtio=$macAddress,bridge=vmbr0"
    if ($vlanId -gt 0) {
        $netConfigString += ",tag=$vlanId"
    }       

    $netConfig = @{ 0 = $netConfigString }
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

Function Get-PxVmTagsById {
    param(
        [Parameter(Mandatory = $true)]
        [string]$vmId,
        [Parameter(Mandatory = $true)]
        [string]$pxNode
    )

    $ticket = Invoke-ProxmoxLogin

    Write-Host "Retrieving tags for VM ID: $vmId on node: $pxNode"

    $response = Get-PveNodesQemuConfig -PveTicket $ticket -Node $pxNode -VmId $vmId

    if ($response.IsSuccessStatusCode) {
        $data = $response.Response.data
        if ($data -and $data.tags) {
            return $data.tags -split ","
        }
        else {
            Write-Host "No tags found for VM ID: $vmId on node: $pxNode"
            return @()
        }
    }
    else {
        Write-Host "Failed to retrieve VM configuration for VM ID: $vmId on node: $pxNode"
        return @()
    }
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
        [string]$vmName,
        [switch]$includeTags = $false
    )

    $ticket = Invoke-ProxmoxLogin
    $vms = Get-PxVms -PveTicket $ticket

    $vm = $vms | Where-Object { $_.name -like $vmName }

    if ($vm) {

        foreach ($v in $vm) {
            if ($includeTags) {
                $v | Add-Member -MemberType NoteProperty -Name "tags" -Value (Get-PxVmTagsById -vmId $v.vmid -pxNode $v.node) -Force
            }
        }

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

    Write-Debug "Retrieving IP address for VM ID $vmId on node $pxNode"

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

    Write-Host "Resizing disk for VM ID $vmId on node $pxNode to $diskSizeGB GB"

    $resizeAction = Set-PveNodesQemuResize -PveTicket $ticket -Node $pxNode -VmId $vmId -Disk $diskName -Size "$($diskSizeGB)G"

    Write-Debug "Resize action response: $($resizeAction | ConvertTo-Json -Depth 10)"

    if ($resizeAction.IsSuccessStatusCode) {
        $sleepResult = Start-SleepOnPveTask -upid $resizeAction.Response.data -pxNode $pxNode -message "Waiting for resize task..."
        
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

Function Get-BalancedStoragePool {
    <#
    .SYNOPSIS
    Select the most balanced storage pool for VM provisioning

    .DESCRIPTION
    Analyzes VM distribution and storage usage across multiple storage pools
    and returns the most balanced one based on usage percentage and VM count.
    Automatically discovers available storage pools from Proxmox if not specified.

    .PARAMETER ProxmoxNode
    The Proxmox node name (default: pxhp)

    .PARAMETER StoragePools
    Optional array of storage pool names to analyze. If not specified, will auto-discover
    all available storage pools that support VM images (lvmthin, dir, nfs, etc.)

    .PARAMETER StorageType
    Filter storage by type (e.g., 'lvmthin', 'dir', 'nfs'). If not specified, includes all VM-capable storage.

    .PARAMETER ExcludeStoragePools
    Array of storage pool names to exclude from auto-discovery. Useful for excluding backup storage,
    ISO storage, or other pools that shouldn't be used for VM provisioning.

    .PARAMETER PendingRemovalVMs
    Array of VM IDs or names that will be removed during node cycling. The function will adjust
    the balance calculation to account for these pending removals, ensuring the final state
    (after cycling) is balanced rather than just the current state.

    .EXAMPLE
    PS> Get-BalancedStoragePool -ProxmoxNode "pxhp"

    .EXAMPLE
    PS> Get-BalancedStoragePool -ProxmoxNode "pxhp" -StorageType "lvmthin"

    .EXAMPLE
    PS> Get-BalancedStoragePool -ProxmoxNode "pxhp" -StoragePools @("vmthin", "vmthin2")

    .EXAMPLE
    PS> Get-BalancedStoragePool -ProxmoxNode "pxhp" -ExcludeStoragePools @("backup-storage", "iso-storage")

    .EXAMPLE
    PS> Get-BalancedStoragePool -ProxmoxNode "pxhp" -PendingRemovalVMs @("prod-agt-001", "prod-agt-002")
    #>
    param(
        [string]$ProxmoxNode = "pxhp",
        [string[]]$StoragePools = $null,
        [string]$StorageType = $null,
        [string[]]$ExcludeStoragePools = @(),
        [string[]]$PendingRemovalVMs = @()
    )

    $ticket = Invoke-ProxmoxLogin

    Write-Host "Analyzing storage pool balance on $ProxmoxNode..."

    # Auto-discover storage pools if not specified
    if ($null -eq $StoragePools -or $StoragePools.Count -eq 0) {
        Write-Host "Auto-discovering storage pools on $ProxmoxNode..."
        if ($ExcludeStoragePools.Count -gt 0) {
            Write-Host "Excluding storage pools: $($ExcludeStoragePools -join ', ')"
        }

        try {
            # Get all storage on the node
            $allStorage = Get-PveNodesStorage -PveTicket $ticket -Node $ProxmoxNode

            if ($allStorage.IsSuccessStatusCode -and $allStorage.Response.data) {
                $StoragePools = @()

                foreach ($storage in $allStorage.Response.data) {
                    # Only include storage that supports VM images (content includes 'images')
                    $contentTypes = $storage.content -split ','
                    $supportsImages = $contentTypes -contains 'images'

                    if (-not $supportsImages) {
                        Write-Verbose "Skipping $($storage.storage): does not support images"
                        continue
                    }

                    # Always exclude 'local-lvm' as it's reserved for Proxmox system data
                    if ($storage.storage -eq 'local-lvm') {
                        Write-Verbose "Skipping $($storage.storage): reserved for Proxmox system data"
                        continue
                    }

                    # Filter by storage type if specified
                    if ($StorageType -and $storage.type -ne $StorageType) {
                        Write-Verbose "Skipping $($storage.storage): type $($storage.type) does not match filter $StorageType"
                        continue
                    }

                    # Exclude storage pools in the exclusion list
                    if ($ExcludeStoragePools -contains $storage.storage) {
                        Write-Verbose "Skipping $($storage.storage): in exclusion list"
                        continue
                    }

                    # Only include enabled/active storage
                    if ($storage.enabled -eq 1 -or $storage.active -eq 1 -or (-not $storage.PSObject.Properties['enabled'])) {
                        $StoragePools += $storage.storage
                        Write-Verbose "Added storage pool: $($storage.storage) (type: $($storage.type))"
                    }
                    else {
                        Write-Verbose "Skipping $($storage.storage): not enabled"
                    }
                }

                if ($StoragePools.Count -eq 0) {
                    Write-Warning "No suitable storage pools found on $ProxmoxNode"
                    Write-Host "Falling back to default storage pools: vmthin, vmthin2, vmthin3"
                    $StoragePools = @("vmthin", "vmthin2", "vmthin3")
                }
                else {
                    Write-Host "Discovered $($StoragePools.Count) storage pool(s): $($StoragePools -join ', ')"
                }
            }
            else {
                Write-Warning "Failed to retrieve storage list from Proxmox"
                Write-Host "Falling back to default storage pools: vmthin, vmthin2, vmthin3"
                $StoragePools = @("vmthin", "vmthin2", "vmthin3")
            }
        }
        catch {
            Write-Warning "Error discovering storage pools: $_"
            Write-Host "Falling back to default storage pools: vmthin, vmthin2, vmthin3"
            $StoragePools = @("vmthin", "vmthin2", "vmthin3")
        }
    }
    else {
        Write-Host "Using specified storage pools: $($StoragePools -join ', ')"

        # Apply exclusions to manually specified pools as well
        if ($ExcludeStoragePools.Count -gt 0) {
            $originalCount = $StoragePools.Count
            $StoragePools = @($StoragePools | Where-Object { $ExcludeStoragePools -notcontains $_ })

            $excludedCount = $originalCount - $StoragePools.Count
            if ($excludedCount -gt 0) {
                Write-Host "Applied exclusions: removed $excludedCount pool(s)"
                Write-Host "Final storage pools: $($StoragePools -join ', ')"
            }
        }
    }

    # Validate we have at least one storage pool
    if ($StoragePools.Count -eq 0) {
        Write-Error "No storage pools available after applying filters and exclusions"
        return $null
    }

    # Get current VM distribution across storage pools
    $vms = Get-PveNodesQemu -PveTicket $ticket -Node $ProxmoxNode

    $distribution = @{}
    $vmToStorageMap = @{}  # Track which storage each VM is on
    foreach ($pool in $StoragePools) {
        $distribution[$pool] = 0
    }

    # Count VMs per storage pool
    foreach ($vm in $vms.Response.data) {
        try {
            $vmConfig = Get-PveNodesQemuConfig -PveTicket $ticket -Node $ProxmoxNode -VmId $vm.vmid

            # Parse storage from disk configurations (scsi0, virtio0, etc.)
            $configData = $vmConfig.Response.data
            $diskConfigs = @($configData.scsi0, $configData.virtio0, $configData.ide0)

            foreach ($diskConfig in $diskConfigs) {
                if ($diskConfig -and $diskConfig -match "^([^:]+):") {
                    $storage = $Matches[1]
                    if ($distribution.ContainsKey($storage)) {
                        $distribution[$storage]++
                        $vmToStorageMap[$vm.name] = $storage
                        $vmToStorageMap["$($vm.vmid)"] = $storage  # Store by ID too
                        break  # Count each VM only once
                    }
                }
            }
        }
        catch {
            Write-Verbose "Could not get config for VM $($vm.vmid): $_"
        }
    }

    # Adjust distribution to account for pending removals (for node cycling)
    if ($PendingRemovalVMs.Count -gt 0) {
        Write-Host "Adjusting balance calculation for $($PendingRemovalVMs.Count) VM(s) pending removal..."
        foreach ($vmIdentifier in $PendingRemovalVMs) {
            if ($vmToStorageMap.ContainsKey($vmIdentifier)) {
                $storagePool = $vmToStorageMap[$vmIdentifier]
                $distribution[$storagePool]--
                Write-Verbose "  Adjusted: $vmIdentifier will be removed from $storagePool"
            }
            else {
                Write-Verbose "  Warning: Could not find storage for pending removal VM: $vmIdentifier"
            }
        }
        Write-Host "Calculating balance based on post-cycling state..."
    }

    # Get storage capacity for each pool
    $storageInfo = @{}
    foreach ($pool in $StoragePools) {
        try {
            $status = Get-PveNodesStorageStatus -PveTicket $ticket -Node $ProxmoxNode -Storage $pool

            if ($status.IsSuccessStatusCode) {
                $data = $status.Response.data
                $total = $data.total
                $used = $data.used
                $available = $data.avail

                $storageInfo[$pool] = @{
                    Total = $total
                    Used = $used
                    Available = $available
                    UsedPercent = if ($total -gt 0) { ($used / $total) * 100 } else { 0 }
                    VMCount = $distribution[$pool]
                }
            }
            else {
                Write-Warning "Could not get status for storage pool $pool"
                $storageInfo[$pool] = @{
                    Total = 0
                    Used = 0
                    Available = 0
                    UsedPercent = 100
                    VMCount = $distribution[$pool]
                }
            }
        }
        catch {
            Write-Warning "Error getting storage info for $($pool): $_"
            $storageInfo[$pool] = @{
                Total = 0
                Used = 0
                Available = 0
                UsedPercent = 100
                VMCount = $distribution[$pool]
            }
        }
    }

    # Calculate score for each pool (lower is better)
    $scores = @{}
    $avgVMCount = ($distribution.Values | Measure-Object -Average).Average
    if ($avgVMCount -eq 0) { $avgVMCount = 1 }

    foreach ($pool in $StoragePools) {
        $info = $storageInfo[$pool]

        # Score based on:
        # - Used percentage (weight: 0.6)
        # - VM count relative to average (weight: 0.4)
        $vmCountScore = ($info.VMCount / $avgVMCount) * 100

        $scores[$pool] = ($info.UsedPercent * 0.6) + ($vmCountScore * 0.4)
    }

    # Display distribution
    Write-Host "`nStorage Pool Distribution:"
    foreach ($pool in $StoragePools) {
        $info = $storageInfo[$pool]
        Write-Host "  $($pool):"
        Write-Host "    VMs: $($info.VMCount)"
        Write-Host "    Used: $([Math]::Round($info.UsedPercent, 1))%"
        Write-Host "    Score: $([Math]::Round($scores[$pool], 2))"
    }

    # Select pool with lowest score
    $selectedPool = ($scores.GetEnumerator() | Sort-Object Value | Select-Object -First 1).Name

    Write-Host "`nSelected storage pool: $selectedPool (best balance)"

    return $selectedPool
}

Function Get-BalancedProxmoxNode {
    <#
    .SYNOPSIS
    Select the most balanced Proxmox node for VM provisioning using weighted distribution

    .DESCRIPTION
    Analyzes VM distribution across Proxmox cluster nodes and returns the node that is most
    under its target weight. Supports weighted distribution (e.g., 90% on node1, 10% on node2).

    .PARAMETER NodeWeights
    Hash table of node names to weight percentages (must sum to 100).
    Example: @{ "pxhp" = 90; "pmxdell" = 10 }

    .PARAMETER ExcludeNodes
    Array of node names to exclude from selection (e.g., nodes under maintenance)

    .PARAMETER PendingRemovalVMs
    Array of VM IDs or names that will be removed during node cycling. The function will adjust
    the balance calculation to account for these pending removals, ensuring the final state
    (after cycling) is balanced rather than just the current state.

    .EXAMPLE
    PS> Get-BalancedProxmoxNode -NodeWeights @{ "pxhp" = 90; "pmxdell" = 10 }
    Returns "pmxdell" if it has fewer than 10% of total VMs

    .EXAMPLE
    PS> Get-BalancedProxmoxNode -NodeWeights @{ "pxhp" = 70; "pmxdell" = 20; "pxnode3" = 10 }
    Selects the node most under its target weight across three nodes

    .EXAMPLE
    PS> Get-BalancedProxmoxNode -NodeWeights @{ "pxhp" = 90; "pmxdell" = 10 } -PendingRemovalVMs @("prod-agt-001", "prod-agt-002")
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$NodeWeights,

        [string[]]$ExcludeNodes = @(),

        [string[]]$PendingRemovalVMs = @()
    )

    # Validate weights sum to 100
    $totalWeight = ($NodeWeights.Values | Measure-Object -Sum).Sum
    if ($totalWeight -ne 100) {
        Write-Error "Node weights must sum to 100. Current sum: $totalWeight"
        return $null
    }

    $ticket = Invoke-ProxmoxLogin

    Write-Host "Analyzing Proxmox cluster node distribution..."

    # Get all nodes in the cluster
    try {
        $clusterNodes = Get-PveNodes -PveTicket $ticket

        if (-not $clusterNodes.IsSuccessStatusCode) {
            Write-Error "Failed to retrieve cluster nodes from Proxmox"
            return $null
        }

        $availableNodes = $clusterNodes.Response.data | Where-Object {
            $NodeWeights.ContainsKey($_.node) -and
            $ExcludeNodes -notcontains $_.node -and
            $_.status -eq 'online'
        }

        if ($availableNodes.Count -eq 0) {
            Write-Error "No available nodes found matching the weight configuration"
            return $null
        }

        Write-Host "Found $($availableNodes.Count) online node(s) in cluster:"
        foreach ($node in $availableNodes) {
            Write-Host "  - $($node.node) (weight: $($NodeWeights[$node.node])%)"
        }
    }
    catch {
        Write-Error "Error querying cluster nodes: $_"
        return $null
    }

    # Analyze resource allocation per node (VMs, CPU cores, memory)
    $nodeResources = @{}
    $vmToNodeMap = @{}  # Track which node each VM is on
    $vmResourceMap = @{}  # Track CPU and memory for each VM
    $totalVMs = 0
    $totalCPU = 0
    $totalMemory = 0

    foreach ($node in $availableNodes) {
        $nodeName = $node.node

        try {
            $vms = Get-PveNodesQemu -PveTicket $ticket -Node $nodeName

            $vmCount = 0
            $cpuCores = 0
            $memoryMB = 0

            if ($vms.IsSuccessStatusCode) {
                $vmCount = $vms.Response.data.Count

                # Sum up CPU and memory allocations for all VMs
                foreach ($vm in $vms.Response.data) {
                    $cpuCores += $vm.cpus
                    $memoryMB += $vm.maxmem / 1MB

                    # Track VM to node mapping for pending removal adjustments
                    $vmToNodeMap[$vm.name] = $nodeName
                    $vmToNodeMap["$($vm.vmid)"] = $nodeName
                    $vmResourceMap[$vm.name] = @{
                        CPUCores = $vm.cpus
                        MemoryMB = $vm.maxmem / 1MB
                    }
                    $vmResourceMap["$($vm.vmid)"] = @{
                        CPUCores = $vm.cpus
                        MemoryMB = $vm.maxmem / 1MB
                    }
                }
            }
            else {
                Write-Warning "Could not get VM data for node $nodeName"
            }

            $nodeResources[$nodeName] = @{
                VMCount   = $vmCount
                CPUCores  = $cpuCores
                MemoryMB  = [Math]::Round($memoryMB, 0)
                MemoryGB  = [Math]::Round($memoryMB / 1024, 1)
            }

            $totalVMs += $vmCount
            $totalCPU += $cpuCores
            $totalMemory += $memoryMB
        }
        catch {
            Write-Warning "Error querying resources on node ${nodeName}: $_"
            $nodeResources[$nodeName] = @{
                VMCount   = 0
                CPUCores  = 0
                MemoryMB  = 0
                MemoryGB  = 0
            }
        }
    }

    # Adjust resources to account for pending removals (for node cycling)
    if ($PendingRemovalVMs.Count -gt 0) {
        Write-Host "`nAdjusting balance calculation for $($PendingRemovalVMs.Count) VM(s) pending removal..."
        foreach ($vmIdentifier in $PendingRemovalVMs) {
            if ($vmToNodeMap.ContainsKey($vmIdentifier) -and $vmResourceMap.ContainsKey($vmIdentifier)) {
                $nodeName = $vmToNodeMap[$vmIdentifier]
                $vmResources = $vmResourceMap[$vmIdentifier]

                $nodeResources[$nodeName].VMCount--
                $nodeResources[$nodeName].CPUCores -= $vmResources.CPUCores
                $nodeResources[$nodeName].MemoryMB -= $vmResources.MemoryMB
                $nodeResources[$nodeName].MemoryGB = [Math]::Round($nodeResources[$nodeName].MemoryMB / 1024, 1)

                $totalVMs--
                $totalCPU -= $vmResources.CPUCores
                $totalMemory -= $vmResources.MemoryMB

                Write-Verbose "  Adjusted: $vmIdentifier will be removed from $nodeName ($($vmResources.CPUCores) cores, $([Math]::Round($vmResources.MemoryMB / 1024, 1)) GB)"
            }
            else {
                Write-Verbose "  Warning: Could not find node for pending removal VM: $vmIdentifier"
            }
        }
        Write-Host "Calculating balance based on post-cycling state..."
    }

    Write-Host "`nCluster Resource Distribution $(if ($PendingRemovalVMs.Count -gt 0) { '(after pending removals)' } else { '(current state)' }):"
    Write-Host "  Total VMs: $totalVMs"
    Write-Host "  Total CPU Cores: $totalCPU"
    Write-Host "  Total Memory: $([Math]::Round($totalMemory / 1024, 1)) GB"

    # Calculate deviation from target for each node
    # We'll use a weighted score considering VMs (40%), CPU (30%), and Memory (30%)
    $deviations = @{}

    foreach ($node in $availableNodes) {
        $nodeName = $node.node
        $targetWeight = $NodeWeights[$nodeName]
        $resources = $nodeResources[$nodeName]

        # Calculate current percentages for each resource type
        $vmPercent = if ($totalVMs -gt 0) {
            ($resources.VMCount / $totalVMs) * 100
        } else { 0 }

        $cpuPercent = if ($totalCPU -gt 0) {
            ($resources.CPUCores / $totalCPU) * 100
        } else { 0 }

        $memPercent = if ($totalMemory -gt 0) {
            ($resources.MemoryMB / $totalMemory) * 100
        } else { 0 }

        # Calculate weighted resource percentage: 40% VMs, 30% CPU, 30% Memory
        $weightedPercent = ($vmPercent * 0.4) + ($cpuPercent * 0.3) + ($memPercent * 0.3)

        # Calculate how far under target this node is
        # Negative deviation = under target (good candidate)
        # Positive deviation = over target (avoid)
        $deviation = $weightedPercent - $targetWeight
        $deviations[$nodeName] = $deviation

        Write-Host "`n  ${nodeName}:"
        Write-Host "    VMs: $($resources.VMCount) ($([Math]::Round($vmPercent, 1))%)"
        Write-Host "    CPU Cores: $($resources.CPUCores) ($([Math]::Round($cpuPercent, 1))%)"
        Write-Host "    Memory: $($resources.MemoryGB) GB ($([Math]::Round($memPercent, 1))%)"
        Write-Host "    Weighted %: $([Math]::Round($weightedPercent, 1))% (target: ${targetWeight}%)"
        Write-Host "    Deviation: $([Math]::Round($deviation, 1))% $(if ($deviation -lt 0) { "(under target)" } elseif ($deviation -gt 0) { "(over target)" } else { "(at target)" })"
    }

    # Select node with most negative deviation (most under target)
    $selectedNode = ($deviations.GetEnumerator() | Sort-Object Value | Select-Object -First 1).Name

    Write-Host "`nSelected node: $selectedNode (most under target weight)"

    return $selectedNode
}