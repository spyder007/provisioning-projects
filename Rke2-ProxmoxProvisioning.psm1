function Add-PxNodeToRke2Cluster {
    <#
    .SYNOPSIS
    Create a new Rke2 Cluster node.

    .DESCRIPTION
    Based on the cluster name and node type, generate a machine name and provision a new node.  If useUnifi is true, DNS entries
    will be made.

    .PARAMETER clusterName
    The name of the cluster where the node will be added

    .PARAMETER dnsDomain
    The dnsDomain of the cluster, used to build the cluster address

    .PARAMETER vmType
    The type of the vm.  Current valid value is ubuntu-2204

    .PARAMETER vmSize
    The size of the vm.  Corresponds to a variable file in ./templates/ubuntu/rke2/{vmSize}-worker.pkrvars.hcl 
    or ./templates/ubuntu/rke2/{vmSize}-server.pkrvars.hcl

    .PARAMETER nodeType
    The type of node to create.  Valid values are "first-server" (the first server in a cluster), "server", or "agent"

    .PARAMETER packerErrorAction
    The ErrorAction to use for the Packer Command.  Valid values are "cleanup", "abort", "ask", and "run-cleanup-provisioner".
    See https://developer.hashicorp.com/packer/docs/commands/build for information on the -on-error option details.

    .PARAMETER OutputFolder
    The base folder where the VM information will be stored.

    .PARAMETER useUnifi
    If true, use the Unifi.psm1 to manage DNS entries.

    .PARAMETER bwlimit
    Bandwidth limit in MiB/s for VM cloning operation. Default is 20480 MiB/s (20 GiB/s). Use 0 for no limit.

    .PARAMETER rke2Version
    Specific RKE2 version to install (e.g., "v1.28.5+rke2r1"). If specified, takes precedence over rke2Channel.

    .PARAMETER rke2Channel
    RKE2 channel to use (stable, latest, testing, or specific minor like v1.28). Defaults to "stable". Ignored if rke2Version is specified.

    .EXAMPLE
    PS> Add-NodeToRke2Cluster -clusterName "test" -dnsDomain "domain.local" -vmSize "med" -nodeType "agent"

    .EXAMPLE
    PS> Add-NodeToRke2Cluster -clusterName "test" -dnsDomain "domain.local" -vmSize "med" -nodeType "agent" -bwlimit 100

    .EXAMPLE
    PS> Add-NodeToRke2Cluster -clusterName "test" -dnsDomain "domain.local" -vmSize "med" -nodeType "agent" -rke2Version "v1.28.5+rke2r1"
    #>
    param(
        $clusterName,
        $dnsDomain,
        $vmSize,
        [ValidateSet("server", "agent")]
        $nodeType,
        [ValidateSet("cleanup", "abort", "ask", "run-cleanup-provisioner")]
        $packerErrorAction = "cleanup",
        [bool] $useUnifi = $true,
        [string] $unifiNetwork = "Lab",
        [string] $vmNotes = "",
        [int] $bwlimit = 20480,
        [string] $rke2Version = "",
        [string] $rke2Channel = "stable"
    )
    Test-Imports $useUnifi

    Import-Module powershell-yaml   
    $rke2Settings = Get-PxRke2Settings
    if (-not (Test-Path "$($rke2Settings.clusterStorage)/$clusterName/node-token")) {
        Write-Error "Could not find server token."
        return -1;    
    }
    
    $nodeDetail = New-PxRke2ClusterNode -clusterName $clusterName -dnsDomain $dnsDomain -vmSize $vmSize -nodeType $nodeType -packerErrorAction $packerErrorAction -useUnifi $useUnifi -unifiNetwork $unifiNetwork -bwlimit $bwlimit -rke2Version $rke2Version -rke2Channel $rke2Channel

    
    if ($nodeDetail.success) {
        if ($useUnifi) {
            $clusterDns = Get-ClusterDns -clusterName $clusterName -dnsZone $dnsDomain
            if ($null -eq $clusterDns -or $clusterDns -eq $false) {
                Write-Warning "Could not retrieve cluster DNS record for '$clusterName' — skipping DNS update."
            }
            else {
                # Servers get added to the cp-<cluster name>, while agents get added to tfx-<cluster name>
                if ($nodeType -eq "server" -or $nodeType -eq "first-server") {
                    $clusterDns.controlPlane += @{
                        hostName   = "cp-$($clusterName).$($dnsDomain)"
                        ipAddress  = "$($nodeDetail.ipAddress)"
                        recordType = "A"
                        macAddress = $null
                        deviceLock = $false
                    }
                }
                else {
                    $clusterDns.traffic += @{
                        hostName   = "tfx-$($clusterName).$($dnsDomain)"
                        ipAddress  = "$($nodeDetail.ipAddress)"
                        recordType = "A"
                        macAddress = $null
                        deviceLock = $false
                    }
                }
                $clusterDns = Update-ClusterDns $clusterDns
            }
        }
    }
    return $nodeDetail;
}

function New-PxRke2ClusterNode {
    <#
    .SYNOPSIS
    Create a new Rke2 Cluster node

    .DESCRIPTION
    Provision a new VM as a node in the given cluster.

    .PARAMETER machineName
    The machine name to create

    .PARAMETER clusterName
    The name of the cluster where the node will be added

    .PARAMETER dnsDomain
    The dnsDomain of the cluster, used to build the cluster address

    .PARAMETER vmType
    The type of the vm.  Current valid value is ubuntu-2204

    .PARAMETER vmSize
    The size of the vm.  Corresponds to a variable file in ./templates/ubuntu/rke2/{vmSize}-worker.pkrvars.hcl 
    or ./templates/ubuntu/rke2/{vmSize}-server.pkrvars.hcl

    .PARAMETER nodeType
    The type of node to create.  Valid values are "first-server" (the first server in a cluster), "server", or "agent"

    .PARAMETER packerErrorAction
    The ErrorAction to use for the Packer Command.  Valid values are "cleanup", "abort", "ask", and "run-cleanup-provisioner".
    See https://developer.hashicorp.com/packer/docs/commands/build for information on the -on-error option details.

    .PARAMETER OutputFolder
    The base folder where the VM information will be stored.

    .PARAMETER bwlimit
    Bandwidth limit in MiB/s for VM cloning operation. Default is 20480 MiB/s (20 GiB/s). Use 0 for no limit.

    .PARAMETER rke2Version
    Specific RKE2 version to install (e.g., "v1.28.5+rke2r1"). If specified, takes precedence over rke2Channel.

    .PARAMETER rke2Channel
    RKE2 channel to use (stable, latest, testing, or specific minor like v1.28). Defaults to "stable". Ignored if rke2Version is specified.

    .EXAMPLE
    PS> New-Rke2ClusterNode -machineName "test-srv-001" -clusterName "test" -dnsDomain "domain.local" -vmSize "med" -nodeType "agent"

    .EXAMPLE
    PS> New-Rke2ClusterNode -machineName "test-srv-001" -clusterName "test" -dnsDomain "domain.local" -vmSize "med" -nodeType "agent" -bwlimit 100

    .EXAMPLE
    PS> New-Rke2ClusterNode -machineName "test-srv-001" -clusterName "test" -dnsDomain "domain.local" -vmSize "med" -nodeType "agent" -rke2Version "v1.28.5+rke2r1"
    #>
    param (
        $clusterName,
        $dnsDomain,
        $vmSize,
        [ValidateSet("first-server", "server", "agent")]
        $nodeType,
        [ValidateSet("cleanup", "abort", "ask", "run-cleanup-provisioner")]
        $packerErrorAction = "cleanup",
        [bool] $useUnifi = $true,
        [string] $unifiNetwork = "Lab",
        [int] $bwlimit = 20480,
        [string] $rke2Version = "",
        [string] $rke2Channel = "stable"
    )

    Test-Imports $useUnifi

    $rkeSettings = Get-PxRke2Settings

    $clusterInfo = Get-ClusterInfo $clusterName
    $nodeNumber = $clusterInfo.Stats.Maximum + 1
    if ($nodeNumber -gt [int]"0xfff") {
        $nodeNumber = 1
    }

    $machineName = Get-Rke2NodeMachineName -clusterName $clusterName -nodeType $nodeType -nodeNumber $nodeNumber

    $macAddress = $null;
    if ($useUnifi) {
        $macAddress = Invoke-ProvisionUnifiClient -name "$($machineName)" -hostname "$($machineName)" -network $unifiNetwork
        if ($null -eq $macAddress) {
            Write-Host "Using random mac address"
        }
        else {
            $macAddress | Format-Table | Out-Host
            Write-Host "Mac Address = $($macAddress.RawMacAddress)"
        }
    }

    if ([System.String]::IsNullOrWhiteSpace($macAddress.MacAddress)) {
        Write-Host "Invalid Mac Address.  Stopping"
        return;
    }

    $vmSettings = Get-PxVmSettings -vmSize $vmSize

    # Select the best node based on weighted distribution
    $selectedNode = $rkeSettings.clusterNode
    if ($rkeSettings.nodeWeights.Count -gt 1) {
        Write-Host "Selecting balanced Proxmox node for $machineName..."
        $balancedNode = Get-BalancedProxmoxNode -NodeWeights $rkeSettings.nodeWeights
        if ($null -ne $balancedNode) {
            $selectedNode = $balancedNode
        }
        else {
            Write-Warning "Node balancing failed, using default node: $selectedNode"
        }
    }
    else {
        Write-Host "Using configured node: $selectedNode (single node configuration)"
    }

    # Select the best storage pool on the selected node
    Write-Host "Selecting balanced storage pool on $selectedNode for $machineName..."
    $selectedStorage = Get-BalancedStoragePool -ProxmoxNode $selectedNode -ExcludeStoragePools @("local-lvm", "local")
    if ($null -ne $selectedStorage) {
        Write-Host "Selected storage pool: $selectedStorage"
    }
    else {
        Write-Warning "Storage balancing failed, using default: $($rkeSettings.clusterNodeStorage)"
        $selectedStorage = $rkeSettings.clusterNodeStorage
    }

    $success = Copy-PxVmTemplate -pxNode $selectedNode -vmId $rkeSettings.baseVmId -name $machineName -vmDescription "RKE2 Node for $clusterName" -newIdMin $clusterInfo.MinVmId -newIdMax $clusterInfo.MaxVmId -macAddress $macAddress.MacAddress -cpuCores $vmSettings.cores -memory $vmSettings.memory -vmStorage $selectedStorage -bwlimit $bwlimit

    if (-not $success) {
        Write-Error "Could not copy VM Template for $machineName"
        if ($useUnifi) {
            if ($null -ne $macAddress) {
                Remove-UnifiClient -macAddress $macAddress.MacAddress
            }
        }
        return;
    }

    $secretContent = Get-Content -Raw -Path ".\templates\proxmox\rke-quick\secrets-template.pkrvars.hcl"
    $secretContent = $secretContent -replace "{SSH_HOST_IP}", $macAddress.IPAddress
    $secretContent = $secretContent -replace "{username}", $rkeSettings.baseVmUsername
    $secretContent = $secretContent -replace "{password}", $rkeSettings.baseVmPassword

    # Create Secrets File
    $secretsFile = ".\templates\proxmox\rke-quick\secrets.pkrvars.hcl"
    Set-Content -Path $secretsFile -Value $secretContent

    $rke2Settings = Get-PxRke2Settings
    if ($nodeType -ne "first-server") {
        if (-not (Test-Path "$($rke2Settings.clusterStorage)/$clusterName/node-token")) {
            Write-Error "Could not find server token."
            return;    
        }
        $existingClusterToken = (Get-Content -Raw "$($rke2Settings.clusterStorage)/$clusterName/node-token")
    }
    $packerTemplate = ".\templates\proxmox\rke-quick\null.pkr.hcl"
    #$httpFolder = ".\templates\proxmox\rke-quick\http\"
    
    if ($nodeType -eq "server" -or $nodeType -eq "first-server") {
        New-Rke2ServerConfig -machineName $machineName -clusterName $clusterName -dnsDomain $dnsDomain -existingClusterToken $existingClusterToken
        $packerVariables = ".\templates\proxmox\rke-quick\server.pkrvars.hcl"
    }
    else {
        New-Rke2AgentConfig -machineName $machineName -clusterName $clusterName -dnsDomain $dnsDomain -existingClusterToken $existingClusterToken
        $packerVariables = ".\templates\proxmox\rke-quick\agent.pkrvars.hcl"
    }  

    $secretVariableFile = ".\templates\proxmox\rke-quick\secrets.pkrvars.hcl"

    # Build RKE2 version arguments
    $rke2VersionArg = ""
    $rke2ChannelArg = ""

    if (-not [string]::IsNullOrWhiteSpace($rke2Version)) {
        $rke2VersionArg = "-var `"rke2_version=$rke2Version`""
        Write-Host "Using RKE2 version: $rke2Version" -ForegroundColor Cyan
    }
    else {
        $rke2ChannelArg = "-var `"rke2_channel=$rke2Channel`""
        Write-Host "Using RKE2 channel: $rke2Channel" -ForegroundColor Cyan
    }

    $extraPackerArguments = "$rke2VersionArg $rke2ChannelArg";

    Write-Host "Building $machineName"
    $onError = "-on-error=$packerErrorAction"

    if ([string]::IsNullOrWhiteSpace($packerVariables)) {
        $extraVarFileArgument = ""
    }
    else {
        $extraVarFileArgument = "-var-file `"$packerVariables`""
    }

    #Read-Host "Press Enter to continue with Packer Build"
    Write-Host "Waiting 5 minutes before starting Packer Build to ensure VM is fully ready (especially after long clone operations with bwlimit throttling)..."
    Start-Sleep -Seconds (60 * 5)

    Write-Host "=== Starting Packer Build ===" -ForegroundColor Cyan
    Invoke-Expression "packer init `"$packerTemplate`"" | Out-Host

    # Capture Packer output for error analysis
    $packerOutput = Invoke-Expression "packer build $onError -var-file `"$secretVariableFile`" $extraVarFileArgument $httpArgument $ExtraPackerArguments `"$packerTemplate`"" 2>&1
    $packerOutput | Out-Host

    $success = ($global:LASTEXITCODE -eq 0)

    if (-not $success) {
        Write-Host "`n=== Packer Build Failed ===" -ForegroundColor Red
        Write-Host "Analyzing error output...`n" -ForegroundColor Yellow

        # Parse output for specific errors
        $outputString = $packerOutput | Out-String

        if ($outputString -match "status: error") {
            Write-Host "ERROR: cloud-init failed during VM initialization" -ForegroundColor Red
            Write-Host "This usually indicates:" -ForegroundColor Yellow
            Write-Host "  - VM is not fully booted yet" -ForegroundColor Yellow
            Write-Host "  - cloud-init configuration issues" -ForegroundColor Yellow
            Write-Host "  - Network connectivity problems" -ForegroundColor Yellow
        }

        if ($outputString -match "Waiting for SSH") {
            Write-Host "ERROR: SSH connection failed" -ForegroundColor Red
            Write-Host "This usually indicates:" -ForegroundColor Yellow
            Write-Host "  - VM is not reachable at IP: $($macAddress.IPAddress)" -ForegroundColor Yellow
            Write-Host "  - SSH service not started" -ForegroundColor Yellow
            Write-Host "  - Firewall blocking connection" -ForegroundColor Yellow
        }

        if ($outputString -match "Script exited with non-zero exit status") {
            Write-Host "ERROR: Provisioning script failed" -ForegroundColor Red
            Write-Host "Check the detailed output above for specific script errors" -ForegroundColor Yellow
        }

        Write-Host "`nFor detailed logs, check the Packer output above`n" -ForegroundColor Yellow
    }

    if ($success) {
        return @{
            success     = $true
            machineName = "$machineName"
            macAddress  = "$($macAddress.MacAddress)"
            ipAddress   = "$($macAddress.IPAddress)"
        }
    }
    else {
        if ($useUnifi) {
            if ($null -ne $macAddress) {
                Remove-UnifiClient -macAddress $macAddress.MacAddress
            }
        }
        return @{
            success = $false
        }
    }
}

function Remove-NodeFromPxRke2Cluster {
    <#
    .SYNOPSIS
    Remove the given machine from the cluster

    .DESCRIPTION
    Using the cluster name, retrieve the matching VMs and associated information.
    Supports optional drain with monitoring for improved observability.

    .PARAMETER machineName
    The VM Name to delete

    .PARAMETER clusterName
    Used to find cluster connection data to drain and delete node

    .PARAMETER useUnifi
    If true, use Unifi module to remove fixed IP records

    .PARAMETER SkipDrain
    If set, skips the drain step (assumes node was already drained separately)

    .PARAMETER MonitorDrain
    If set, enables detailed monitoring during drain with progress updates

    .PARAMETER DrainTimeoutMinutes
    Maximum time to wait for drain to complete (default: 15 minutes)

    .EXAMPLE
    PS> Remove-NodeFromRke2Cluster -machineName "test-srv-001" -clusterName "test"

    .EXAMPLE
    PS> Remove-NodeFromRke2Cluster -machineName "test-srv-001" -clusterName "test" -SkipDrain

    .EXAMPLE
    PS> Remove-NodeFromRke2Cluster -machineName "test-srv-001" -clusterName "test" -MonitorDrain -DrainTimeoutMinutes 30
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$machineName,

        [Parameter(Mandatory = $true)]
        [string]$clusterName,

        [bool]$useUnifi = $true,

        [switch]$SkipDrain,

        [switch]$MonitorDrain,

        [int]$DrainTimeoutMinutes = 15
    )

    Test-Imports $useUnifi

    $rke2Settings = Get-PxRke2Settings
    if (-not (Test-Path "$($rke2Settings.clusterStorage)/$clusterName/remote.yaml")) {
        Write-Error "Could not find remote kube configuration: $($rke2Settings.clusterStorage)/$clusterName/remote.yaml"
        return;
    }

    # Drain node if not skipped
    if (-not $SkipDrain) {
        Write-Host "Draining node: $machineName"

        # Cordon the node first
        try {
            Invoke-K8Command "cordon $machineName" -clusterName $clusterName | Out-Host
            Write-Host "Node cordoned successfully."
        }
        catch {
            Write-Warning "Failed to cordon node: $_"
        }

        # Perform drain with optional monitoring
        if ($MonitorDrain) {
            Write-Host "Starting monitored drain (timeout: $DrainTimeoutMinutes minutes)..."

            # Note: Start-NodeDrainWithMonitoring will be implemented in next task
            # For now, use basic drain with enhanced timeout
            $drainResult = Start-NodeDrainWithMonitoring `
                -ClusterName $clusterName `
                -NodeName $machineName `
                -TimeoutMinutes $DrainTimeoutMinutes `
                -GracePeriodSeconds 300 `
                -IgnoreDaemonSets $true `
                -DeleteEmptyDirData $true `
                -MonitoringIntervalSeconds 30

            if (-not $drainResult.Success) {
                Write-Warning "Drain did not complete successfully: $($drainResult.Error)"
                Write-Warning "Continuing with node deletion..."
            }
        }
        else {
            # Standard drain without monitoring
            try {
                $drainCommand = "drain --ignore-daemonsets --delete-emptydir-data --timeout=$($DrainTimeoutMinutes)m --grace-period=300 $machineName"
                Invoke-K8Command $drainCommand -clusterName $clusterName -ErrorAction SilentlyContinue | Out-Host
                Write-Host "Node drained successfully."
            }
            catch {
                Write-Warning "Exception during drain: $_"
                Write-Warning "Continuing with node deletion..."
            }
        }

        Write-Host "Waiting 60 seconds for workloads to stabilize..."
        Start-Sleep 60
    }
    else {
        Write-Host "Skipping drain (SkipDrain flag set)"
    }

    # Update DNS records if using Unifi
    if ($useUnifi) {
        Write-Host "Updating cluster DNS records..."
        try {
            $clusterDns = Get-ClusterDns -clusterName $clusterName

            $nodeInfo = Invoke-K8CommandJson "get nodes" -clusterName $clusterName
            $ipAddress = $nodeInfo.items | Where-Object {$_.metadata.name -eq "$machineName" } | ForEach-Object { $_.status.addresses } | Where-Object { $_.type -eq "InternalIP" }

            # Remove the IP from the control plane and traffic pools
            $clusterDns.controlPlane = @($clusterDns.controlPlane | Where-Object { $_.ipAddress -ne $ipAddress.address })
            $clusterDns.traffic = @($clusterDns.traffic | Where-Object { $_.ipAddress -ne $ipAddress.address })

            $clusterDns = Update-ClusterDns $clusterDns
            Write-Host "DNS records updated successfully."
        }
        catch {
            Write-Warning "Failed to update DNS records: $_"
            Write-Warning "Continuing with node deletion..."
        }
    }

    # Delete node from Kubernetes
    Write-Host "Deleting node from Kubernetes: $machineName"
    try {
        Invoke-K8Command "delete node/$($machineName)" -clusterName $clusterName | Out-Host
        Write-Host "Node deleted from Kubernetes."
    }
    catch {
        Write-Warning "Failed to delete node from Kubernetes: $_"
    }

    # Remove VM from Proxmox and Unifi
    Write-Host "Removing VM and cleaning up resources..."
    Remove-PxVm -machinename $machineName -useUnifi $useUnifi

    Write-Host "Node removal completed: $machineName"
}

function Get-PodsOnNode {
    <#
    .SYNOPSIS
    Get all pods running on a specific node

    .DESCRIPTION
    Query Kubernetes for all pods on a given node and return structured information

    .PARAMETER ClusterName
    The cluster name

    .PARAMETER NodeName
    The node name to query pods for

    .EXAMPLE
    PS> Get-PodsOnNode -ClusterName "production" -NodeName "prod-agent-001"
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ClusterName,

        [Parameter(Mandatory = $true)]
        [string]$NodeName
    )

    try {
        $pods = Invoke-K8CommandJson "get pods --all-namespaces --field-selector spec.nodeName=$NodeName" -clusterName $ClusterName

        return $pods.items | Select-Object `
            @{N="Namespace";E={$_.metadata.namespace}},
            @{N="Name";E={$_.metadata.name}},
            @{N="Phase";E={$_.status.phase}},
            @{N="Reason";E={$_.status.reason}},
            @{N="OwnerKind";E={
                if ($_.metadata.ownerReferences -and $_.metadata.ownerReferences.Count -gt 0) {
                    $_.metadata.ownerReferences[0].kind
                } else {
                    $null
                }
            }},
            @{N="DeletionTimestamp";E={$_.metadata.deletionTimestamp}}
    }
    catch {
        Write-Warning "Failed to get pods on node ${NodeName}: $_"
        return @()
    }
}

function Get-PDBBlockers {
    <#
    .SYNOPSIS
    Find PodDisruptionBudgets that may block pod eviction

    .DESCRIPTION
    Check all PDBs in the cluster to identify which ones have 0 disruptions allowed
    and may block pod eviction from the specified node

    .PARAMETER ClusterName
    The cluster name

    .PARAMETER NodeName
    The node name to check PDBs for

    .EXAMPLE
    PS> Get-PDBBlockers -ClusterName "production" -NodeName "prod-agent-001"
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ClusterName,

        [Parameter(Mandatory = $true)]
        [string]$NodeName
    )

    try {
        # Get all PDBs
        $pdbs = Invoke-K8CommandJson "get pdb --all-namespaces" -clusterName $ClusterName

        # Get pods on node
        $podsOnNode = Get-PodsOnNode -ClusterName $ClusterName -NodeName $NodeName

        $blockers = @()
        foreach ($pdb in $pdbs.items) {
            $currentHealthy = $pdb.status.currentHealthy
            $minAvailable = $pdb.spec.minAvailable
            $disruptionsAllowed = $pdb.status.disruptionsAllowed

            if ($disruptionsAllowed -eq 0) {
                # Check if any pods on this node match this PDB
                # Note: This is a simplified check - real implementation would need full label matching
                $matchingPods = $podsOnNode | Where-Object {
                    $_.Namespace -eq $pdb.metadata.namespace
                }

                if ($matchingPods.Count -gt 0) {
                    $blockers += @{
                        PDBName = "$($pdb.metadata.namespace)/$($pdb.metadata.name)"
                        DisruptionsAllowed = $disruptionsAllowed
                        CurrentHealthy = $currentHealthy
                        MinAvailable = $minAvailable
                        BlockedPods = $matchingPods
                    }
                }
            }
        }

        return $blockers
    }
    catch {
        Write-Warning "Failed to get PDB blockers: $_"
        return @()
    }
}

function Start-NodeDrainWithMonitoring {
    <#
    .SYNOPSIS
    Drain a node with detailed progress monitoring

    .DESCRIPTION
    Initiates a node drain operation and monitors progress, reporting pod evacuation status,
    stuck pods, and PDB blockers. Provides detailed diagnostics for troubleshooting drain issues.

    .PARAMETER ClusterName
    The cluster name

    .PARAMETER NodeName
    The node to drain

    .PARAMETER TimeoutMinutes
    Maximum time to wait for drain completion (default: 30 minutes)

    .PARAMETER MonitoringIntervalSeconds
    How often to check progress (default: 30 seconds)

    .PARAMETER GracePeriodSeconds
    Grace period for pod termination (default: 300 seconds)

    .PARAMETER IgnoreDaemonSets
    Whether to ignore DaemonSet pods (default: true)

    .PARAMETER DeleteEmptyDirData
    Whether to delete emptyDir data (default: true)

    .EXAMPLE
    PS> Start-NodeDrainWithMonitoring -ClusterName "production" -NodeName "prod-agent-001" -TimeoutMinutes 30
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ClusterName,

        [Parameter(Mandatory = $true)]
        [string]$NodeName,

        [int]$TimeoutMinutes = 30,

        [int]$MonitoringIntervalSeconds = 30,

        [int]$GracePeriodSeconds = 300,

        [bool]$IgnoreDaemonSets = $true,

        [bool]$DeleteEmptyDirData = $true
    )

    $startTime = Get-Date
    $timeoutTime = $startTime.AddMinutes($TimeoutMinutes)

    # Get initial pod count
    $initialPods = Get-PodsOnNode -ClusterName $ClusterName -NodeName $NodeName |
        Where-Object { $_.OwnerKind -ne "DaemonSet" }
    $initialCount = $initialPods.Count

    Write-Host "Starting drain of $NodeName ($initialCount pods to evacuate)"

    # Build drain command
    $drainCommand = "drain $NodeName --grace-period=$GracePeriodSeconds --timeout=$($TimeoutMinutes)m"
    if ($IgnoreDaemonSets) {
        $drainCommand += " --ignore-daemonsets"
    }
    if ($DeleteEmptyDirData) {
        $drainCommand += " --delete-emptydir-data"
    }
    $drainCommand += " --force"

    # Start drain in background job
    $drainJob = Start-Job -ScriptBlock {
        param($ClusterName, $DrainCommand, $ClusterStorage)

        $kubeconfig = "$ClusterStorage\$ClusterName\remote.yaml"

        $cmd = "kubectl --kubeconfig=`"$kubeconfig`" $DrainCommand"

        try {
            Invoke-Expression $cmd 2>&1
        }
        catch {
            return @{
                Success = $false
                Error = $_.Exception.Message
            }
        }
    } -ArgumentList $ClusterName, $drainCommand, (Get-PxRke2Settings).clusterStorage

    # Monitor progress
    while ((Get-Date) -lt $timeoutTime) {
        Start-Sleep -Seconds $MonitoringIntervalSeconds

        # Check if drain job completed
        $jobState = $drainJob.State
        if ($jobState -eq "Completed") {
            $jobOutput = $drainJob | Receive-Job
            Remove-Job $drainJob
            Write-Host "Drain completed successfully"
            return @{ Success = $true; Output = $jobOutput }
        }
        elseif ($jobState -eq "Failed") {
            $drainError = $drainJob | Receive-Job
            Remove-Job $drainJob
            Write-Error "Drain job failed: $drainError"
            return @{ Success = $false; Error = $drainError }
        }

        # Get current pod count
        $currentPods = Get-PodsOnNode -ClusterName $ClusterName -NodeName $NodeName |
            Where-Object { $_.OwnerKind -ne "DaemonSet" }
        $currentCount = $currentPods.Count
        $evacuated = $initialCount - $currentCount
        $progress = if ($initialCount -gt 0) { [Math]::Round(($evacuated / $initialCount) * 100, 1) } else { 100 }

        Write-Host "Drain progress: $evacuated/$initialCount pods evacuated ($progress%)"

        # List remaining pods (if 10 or fewer)
        if ($currentPods.Count -gt 0 -and $currentPods.Count -le 10) {
            Write-Host "Remaining pods:"
            foreach ($pod in $currentPods) {
                $phase = $pod.Phase
                $reason = if ($pod.Reason) { $pod.Reason } else { "" }
                Write-Host "  - $($pod.Namespace)/$($pod.Name) [$phase] $reason"
            }
        }

        # Check for stuck pods in Terminating state
        $stuckPods = $currentPods | Where-Object {
            $_.Phase -eq "Terminating" -and
            $_.DeletionTimestamp -and
            ((Get-Date) - [DateTime]$_.DeletionTimestamp).TotalMinutes -gt 10
        }

        if ($stuckPods.Count -gt 0) {
            Write-Warning "Stuck pods detected (Terminating > 10 minutes):"
            foreach ($pod in $stuckPods) {
                Write-Warning "  - $($pod.Namespace)/$($pod.Name)"

                # Attempt to force delete
                Write-Host "Attempting force delete..."
                try {
                    Invoke-K8Command "delete pod $($pod.Name) -n $($pod.Namespace) --force --grace-period=0" `
                        -clusterName $ClusterName | Out-Null
                }
                catch {
                    Write-Warning "Force delete failed: $_"
                }
            }
        }

        # Check PodDisruptionBudgets blocking eviction
        $pdbBlockers = Get-PDBBlockers -ClusterName $ClusterName -NodeName $NodeName
        if ($pdbBlockers.Count -gt 0) {
            Write-Warning "PodDisruptionBudgets blocking eviction:"
            foreach ($blocker in $pdbBlockers) {
                Write-Warning "  - $($blocker.PDBName): $($blocker.BlockedPods.Count) pods blocked"
            }
        }
    }

    # Timeout reached
    Write-Error "Drain timeout reached after $TimeoutMinutes minutes"
    Stop-Job $drainJob
    Remove-Job $drainJob

    $remainingPods = Get-PodsOnNode -ClusterName $ClusterName -NodeName $NodeName
    Write-Host "Remaining pods on node:"
    $remainingPods | Format-Table Namespace, Name, Phase, Reason

    return @{
        Success = $false
        Error = "Timeout after $TimeoutMinutes minutes"
        RemainingPods = $remainingPods
    }
}

function New-Rke2AgentConfig {
    <#
    .SYNOPSIS
    Generate a new agent-config.yaml file which will be used to configure an agent node.

    .DESCRIPTION
    Create a new agent-config.yaml file used for the install-agent.sh provisioning script

    .PARAMETER machineName
    Used to set the node-name for the RKE2 node

    .PARAMETER clusterName
    Used with dnsDomain to set the server url

    .PARAMETER dnsDomain
    Used to build alternative the server url

    .PARAMETER existingClusterToken
    Secret token for previously created server.  If null or empty an error will be printed.

    .EXAMPLE
    PS> New-Rke2AgentConfig -machineName "test-srv-001" -clusterName "test" -dnsDomain "domain.local" -existingClusterToken "secretTokenValue"
    #>
    param(
        [string] $machineName,
        [string] $clusterName,
        [string] $dnsDomain,
        [string] $existingClusterToken
    )
    if (-not ([string]::IsNullOrWhiteSpace($dnsDomain))) {
        $serverUrl = "cp-$($clusterName).$($dnsDomain)"
    }
    else {
        $serverUrl = "cp-$($clusterName)"
    }
    
    $agentConfig = convertfrom-yaml (get-content .\templates\proxmox\rke-quick\configuration\agent-config.yaml -Raw)
    $agentConfig."node-name" = $machineName
    $agentConfig."server" = "https://$($serverUrl):9345"
    $agentConfig."token" = "$existingClusterToken"

    (ConvertTo-Yaml $agentConfig) | Set-Content -Path .\templates\proxmox\rke-quick\files\agent-config.yaml
}

function New-Rke2ServerConfig {
    <#
    .SYNOPSIS
    Generate a new server-config.yaml file which will be used to configure a server node.

    .DESCRIPTION
    Generate a server-config.yaml file for use in the install-server.sh provisioning script

    .PARAMETER machineName
    Used to set the node-name for the RKE2 node

    .PARAMETER clusterName
    Used with dnsDomain to set tls-san values

    .PARAMETER dnsDomain
    Used to build alternative tls-san values

    .PARAMETER existingClusterToken
    Secret token for previously created server.  If null or empty, this will be treated as the first server in the cluster.

    .EXAMPLE
    PS> New-Rke2ServerConfig -machineName "test-srv-001" -clusterName "test" -dnsDomain "domain.local" -existingClusterToken "secretTokenValue"
    #>
    param(
        [string] $machineName,
        [string] $clusterName,
        [string] $dnsDomain,
        [string] $existingClusterToken
    )
    if (-not ([string]::IsNullOrWhiteSpace($dnsDomain))) {
        $serverUrl = "cp-$($clusterName).$($dnsDomain)"
    }
    else {
        $serverUrl = "cp-$($clusterName)"
    }

    $serverConfig = convertfrom-yaml (get-content .\templates\proxmox\rke-quick\configuration\server-config.yaml -Raw)
    $serverConfig."node-name" = $machineName
    $serverConfig."tls-san" = @()
    $serverConfig."tls-san" += "cp-$clusterName"
    if (-not ([string]::IsNullOrWhiteSpace($dnsDomain))) {
        $serverConfig."tls-san" += "cp-$($clusterName).$($dnsDomain)";
    }
    if (-not ([string]::IsNullOrWhiteSpace($existingClusterToken))) {
        $serverConfig."token" = $existingClusterToken;
        $serverConfig."server" = "https://$($serverUrl):9345"
    }
    $serverConfig."node-taint" = @("CriticalAddonsOnly=true:NoExecute")
    (ConvertTo-Yaml $serverConfig) | Set-Content -Path .\templates\proxmox\rke-quick\files\server-config.yaml
}

function Get-ClusterInfo {
    <#
    .SYNOPSIS
    Get information on the VMs for the given cluster

    .DESCRIPTION
    Using the cluster name, retrieve the matching VMs and associated information

    .PARAMETER clusterName
    The name of the cluster, used to search VMs

    .EXAMPLE
    PS> Get-ClusterInfo -clusterName "test" -nodeType "server" 1
    #>
    param(
        [string] $clusterName
    )

    if (-not (Test-ClusterInfo -clusterName $clusterName)) {
        Write-Error "Cluster $clusterName does not exist or is not configured."
        return;
    }

    $rke2Settings = Get-PxRke2Settings

    $info = Get-Content -Raw -Path "$($rke2Settings.clusterStorage)/$clusterName/info.json" | ConvertFrom-Json

    if ($null -eq $info) {
        Write-Warning "Could not read cluster info for $clusterName, using global settings instead."
        $maxVmId = $rke2Settings.maxVmId
        $minVmId = $rke2Settings.minVmId
    }

    if ($null -eq $info.maxVmId) {
        $maxVmId = $rke2Settings.maxVmId
    }
    else {
        $maxVmId = $info.maxVmId
    }

    if ($null -eq $info.minVmId) {
        $minVmId = $rke2Settings.minVmId
    }
    else {
        $minVmId = $info.minVmId
    }

    $clusterNodes = Invoke-K8CommandJson "get nodes" -clusterName $clusterName
    
    $clusterVmPrefix = Get-ClusterVmPrefix($clusterName)
    $currentNodes = $clusterNodes.items | Where-Object { $_.metadata.name -like "$clusterVmPrefix-*" }

    $nodeStats = ($currentNodes | ForEach-Object { [int] ("0x{0}" -f $_.metadata.name.Substring($_.metadata.name.LastIndexOf("-") + 1)) } | Measure-Object -Max -Min)
    $currentNodeNames = $currentNodes | ForEach-Object { $_.metadata.name }

    return @{
        ClusterName         = $clusterName
        VirtualMachines     = $currentNodes
        Stats               = $nodeStats
        VirtualMachineNames = $currentNodeNames
        MaxVmId             = $maxVmId
        MinVmId             = $minVmId
    }
}

function Get-Rke2AgedNodes {
    <#
    .SYNOPSIS
    Get information on the VMs for the given cluster

    .DESCRIPTION
    Using the cluster name, retrieve the matching VMs and associated information

    .PARAMETER clusterName
    The name of the cluster, used to search VMs

    .EXAMPLE
    PS> Get-ClusterInfo -clusterName "test" -nodeType "server" 1
    #>
    param(
        [string] $clusterName,
        [int] $maxAgeDays = 25
    )

    $cutoffDate = [DateTime]::UtcNow.AddDays($maxAgeDays * -1)
    $nodeOutput = Invoke-K8CommandJson "get nodes" -clusterName $clusterName
    $oldNodes = $nodeOutput.Items | Where-Object { [DateTime]::Parse($_.metadata.creationTimeStamp) -lt $cutoffDate }
    return ($oldNodes | Foreach-Object { $_.metadata.name })
}

function Get-Rke2NodesToCycle {
    <#
    .SYNOPSIS
    Get the oldest N nodes that need cycling (controlled batch approach)

    .DESCRIPTION
    Returns the oldest nodes that exceed the age threshold, limited to MaxCount.
    This prevents cycling all nodes at once when the pipeline runs infrequently.

    .PARAMETER ClusterName
    The name of the cluster

    .PARAMETER NodeType
    Node type filter: "server", "agent", or "all"

    .PARAMETER MaxAgeDays
    Age threshold in days (nodes older than this are candidates)

    .PARAMETER MaxCount
    Maximum number of nodes to cycle per run (default: unlimited)

    .EXAMPLE
    # Get up to 2 oldest servers that are older than 14 days
    Get-Rke2NodesToCycle -ClusterName "nonprod" -NodeType "server" -MaxAgeDays 14 -MaxCount 2

    .EXAMPLE
    # Get up to 3 oldest agents
    Get-Rke2NodesToCycle -ClusterName "production" -NodeType "agent" -MaxAgeDays 14 -MaxCount 3
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ClusterName,

        [Parameter(Mandatory = $true)]
        [ValidateSet("server", "agent", "all")]
        [string]$NodeType,

        [int]$MaxAgeDays = 14,

        [int]$MaxCount = 0  # 0 = unlimited (cycle all aged nodes)
    )

    $cutoffDate = [DateTime]::UtcNow.AddDays($MaxAgeDays * -1)
    $nodeOutput = Invoke-K8CommandJson "get nodes -o json" -clusterName $ClusterName

    # Filter by age
    $agedNodes = $nodeOutput.items | Where-Object {
        [DateTime]::Parse($_.metadata.creationTimestamp) -lt $cutoffDate
    }

    # Filter by node type
    if ($NodeType -eq "server") {
        $agedNodes = $agedNodes | Where-Object {
            $_.metadata.labels."node-role.kubernetes.io/control-plane" -eq "true" -or
            $_.metadata.labels."node-role.kubernetes.io/master" -eq "true"
        }
    } elseif ($NodeType -eq "agent") {
        $agedNodes = $agedNodes | Where-Object {
            -not ($_.metadata.labels."node-role.kubernetes.io/control-plane" -eq "true" -or
                  $_.metadata.labels."node-role.kubernetes.io/master" -eq "true")
        }
    }

    # Sort by age (oldest first)
    $sortedNodes = $agedNodes | Sort-Object { [DateTime]::Parse($_.metadata.creationTimestamp) }

    # Limit to MaxCount if specified
    if ($MaxCount -gt 0) {
        $sortedNodes = $sortedNodes | Select-Object -First $MaxCount
    }

    # Return as custom objects with useful info
    $result = $sortedNodes | ForEach-Object {
        $creationTime = [DateTime]::Parse($_.metadata.creationTimestamp)
        $age = ([DateTime]::UtcNow - $creationTime).TotalDays

        [PSCustomObject]@{
            Name = $_.metadata.name
            Age = [Math]::Round($age, 1)
            CreationTime = $creationTime
            Status = $_.status.conditions | Where-Object { $_.type -eq "Ready" } | Select-Object -ExpandProperty status
            Roles = ($_.metadata.labels.Keys | Where-Object { $_ -like "node-role.kubernetes.io/*" } | ForEach-Object { $_.Split('/')[-1] }) -join ","
        }
    }

    return $result
}

Function Get-Rke2NodeMachineName {
    <#
    .SYNOPSIS
    Create a Machine Name for the node

    .DESCRIPTION
    Create a Machine Name for the node        

    .PARAMETER clusterName
    The name of the cluster to be created.  This will be used in naming templates for VMs and DNS Entries (if using Unifi)

    .PARAMETER nodeType
    The Node type.  Allowed values are "agent", "server", or "first-server"

    .PARAMETER nodeNumber
    The number of the node to be using as hex in the machine name.

    .EXAMPLE
    PS> Get-Rke2NodeMachineName -clusterName "test" -nodeType "server" 1
    #>
    param (
        [string] $clusterName,
        [ValidateSet("first-server", "server", "agent")]
        [string] $nodeType,
        [int] $nodeNumber
    )
    
    $typeNotation = "srv";
    if ($nodeType -eq "agent") {
        $typeNotation = "agt"
    }
    $vmPrefix = Get-ClusterVmPrefix($clusterName)
    return [string]::Format("{0}-{1}-{2:x3}", $vmPrefix, $typeNotation, $nodeNumber)
}

function Get-ClusterVmPrefix {
    param (
        [string] $clusterName
    )
    $rke2Settings = Get-PxRke2Settings
    return "{0}-{1}" -f $rke2Settings.nodePrefix, $clusterName
}

function Get-PxVmSettings {
    <#
    .SYNOPSIS
    Get the VM Settings for the given vmSize

    .DESCRIPTION
    Get the VM Settings for the given vmSize.  This will return a hashtable with the settings for the given vmSize.

    .PARAMETER vmSize
    The size of the VM to get settings for.  Valid values are "small", "med", "large".

    .EXAMPLE
    PS> Get-PxVmSettings -vmSize "med"
    #>
    param (
        [string] $vmSize = "med"
    )

    $cores = 2
    $memory = 4096

    if ($vmSize -eq "small") {
        $cores = 2
        $memory = 3072
    }

    if ($vmSize -eq "large") {
        $cores = 4
        $memory = 8192
    }

    return @{
        cores  = $cores
        memory = $memory
    }
}

Function Test-ClusterConnectionInfo {
    param (
        [string] $clusterName
    )
    $rke2Settings = Get-PxRke2Settings
    return Test-Path "$($rke2Settings.clusterStorage)/$clusterName/remote.yaml"
}

Function Test-ClusterInfo {
    param (
        [string] $clusterName
    )
    $rke2Settings = Get-PxRke2Settings
    return Test-Path "$($rke2Settings.clusterStorage)/$clusterName/info.json"
}


Function Invoke-K8Command {
    [CmdletBinding()]
    param (
        [string] $command,
        [string] $clusterName
    )

    if (-not (Test-ClusterConnectionInfo -clusterName $clusterName)) {
        Write-Error "Cluster $clusterName does not exist or is not configured."
        return;
    }

    $rke2Settings = Get-PxRke2Settings
    return Invoke-Expression "kubectl --kubeconfig `"$($rke2Settings.clusterStorage)/$clusterName/remote.yaml`" $($command)"
}

Function Invoke-K8CommandJson {
    [CmdletBinding()]
    param (
        [string] $command,
        [string] $clusterName
    )

    if (-not (Test-ClusterConnectionInfo -clusterName $clusterName)) {
        Write-Error "Cluster $clusterName does not exist or is not configured."
        return;
    }

    $rke2Settings = Get-PxRke2Settings
    return Invoke-Expression "kubectl --kubeconfig `"$($rke2Settings.clusterStorage)/$clusterName/remote.yaml`" $($command) -o json | ConvertFrom-Json"
}

Function Get-PxRke2Settings {
    <#
    .SYNOPSIS
    Get settings used for Rke2 Provisioning Module

    .DESCRIPTION
    Retrieve settings used for Rke2 Provisioning Module.  If set, these settings are stored in your environment variables.

    .EXAMPLE
    PS> Get-PxRke2Settings
    #>
    param ()

    if ($null -ne $Script:px_rke2Settings) {
        return $Script:px_rke2Settings
    }

    $Script:px_rke2Settings = Get-PxRke2SettingsFromEnvironment

    return $Script:px_rke2Settings
}

Function Set-PxRke2Settings {
    param (
        $nodePrefix,
        $clusterStorage,
        $secretsVariableFile,
        $baseVmcxPath,
        $baseVmId,
        $baseVmUsername,
        $baseVmPassword,
        $minVmId,
        $maxVmId,
        $clusterNode,
        $clusterNodeStorage
    )

    if ($null -ne $clusterStorage -and -not (Test-Path $clusterStorage)) {
        Write-Error "Invalid Cluster Storage Path $clusterStorage"
        return;
    }
    
    if ($null -ne $secretsVariableFile -and -not (Test-Path $secretsVariableFile)) {
        Write-Error "Invalid Secrets Path $secretsVariableFile"
        return;
    }

    if ($null -ne $clusterStorage) {
        [System.Environment]::SetEnvironmentVariable('RKE2_PROVISION_CLUSTER_STORAGE', "$clusterStorage", [System.EnvironmentVariableTarget]::User)
        $env:RKE2_PROVISION_CLUSTER_STORAGE = "$clusterStorage"
    }

    if ($null -ne $secretsVariableFile) {
        [System.Environment]::SetEnvironmentVariable('RKE2_PROVISION_SECRETS_FILE', "$secretsVariableFile", [System.EnvironmentVariableTarget]::User)
        $env:RKE2_PROVISION_SECRETS_FILE = "$secretsVariableFile"
    }

    if ($null -ne $nodePrefix) {
        $env:RKE2_PROVISION_NODE_PREFIX = "$nodePrefix"
        [System.Environment]::SetEnvironmentVariable('RKE2_PROVISION_NODE_PREFIX', "$nodePrefix", [System.EnvironmentVariableTarget]::User)
    }

    if ($null -ne $baseVmId) {
        $env:RKE2_PROVISION_BASE_VM_PX_ID = "$baseVmId"
        [System.Environment]::SetEnvironmentVariable('RKE2_PROVISION_BASE_VM_PX_ID', "$baseVmId", [System.EnvironmentVariableTarget]::User)
    }

    if ($null -ne $baseVmUsername) {
        $env:RKE2_PROVISION_BASE_VM_USERNAME = "$baseVmUsername"
        [System.Environment]::SetEnvironmentVariable('RKE2_PROVISION_BASE_VM_USERNAME', "$baseVmUsername", [System.EnvironmentVariableTarget]::User)
    }

    if ($null -ne $baseVmPassword) {
        $env:RKE2_PROVISION_BASE_VM_PASSWORD = "$baseVmPassword"
        [System.Environment]::SetEnvironmentVariable('RKE2_PROVISION_BASE_VM_PASSWORD', "$baseVmPassword", [System.EnvironmentVariableTarget]::User)
    }

    if ($null -ne $minVmId) {
        $env:RKE2_PROVISION_MIN_VM_PX_ID = "$minVmId"
        [System.Environment]::SetEnvironmentVariable('RKE2_PROVISION_MIN_VM_PX_ID', "$minVmId", [System.EnvironmentVariableTarget]::User)
    }
    
    if ($null -ne $maxVmId) {
        $env:RKE2_PROVISION_MAX_VM_PX_ID = "$maxVmId"
        [System.Environment]::SetEnvironmentVariable('RKE2_PROVISION_MAX_VM_PX_ID', "$maxVmId", [System.EnvironmentVariableTarget]::User)
    }

    if ($null -ne $clusterNode) {
        $env:RKE2_PROVISION_CLUSTER_NODE = "$clusterNode"
        [System.Environment]::SetEnvironmentVariable('RKE2_PROVISION_CLUSTER_NODE', "$clusterNode", [System.EnvironmentVariableTarget]::User)
    }

    if ($null -ne $clusterNodeStorage) {
        $env:RKE2_PROVISION_CLUSTER_NODE_STORAGE = "$clusterNodeStorage"
        [System.Environment]::SetEnvironmentVariable('RKE2_PROVISION_CLUSTER_NODE_STORAGE', "$clusterStorage", [System.EnvironmentVariableTarget]::User)
    }

    $Script:px_rke2Settings = Get-PxRke2SettingsFromEnvironment
}

function Get-PxRke2SettingsFromEnvironment {

    $nodePrefix = $env:RKE2_PROVISION_NODE_PREFIX
    if ([string]::IsNullOrWhiteSpace($nodePrefix)) {
        $nodePrefix = [System.Environment]::GetEnvironmentVariable('RKE2_PROVISION_NODE_PREFIX', [System.EnvironmentVariableTarget]::User)
    }
    if ([string]::IsNullOrWhiteSpace($nodePrefix)) {
        $nodePrefix = "rke"
    }

    $clusterStorage = $env:RKE2_PROVISION_CLUSTER_STORAGE
    if ([string]::IsNullOrWhiteSpace($clusterStorage)) {
        $clusterStorage = [System.Environment]::GetEnvironmentVariable('RKE2_PROVISION_CLUSTER_STORAGE', [System.EnvironmentVariableTarget]::User)
    }
    if ([string]::IsNullOrWhiteSpace($clusterStorage)) {
        $clusterStorage = Resolve-Path "./rke2-servers"
    }

    $secretsVariableFile = $env:RKE2_PROVISION_SECRETS_FILE
    if ([string]::IsNullOrWhiteSpace($secretsVariableFile)) {
        $secretsVariableFile = [System.Environment]::GetEnvironmentVariable('RKE2_PROVISION_SECRETS_FILE', [System.EnvironmentVariableTarget]::User)
    }
    if ([string]::IsNullOrWhiteSpace($secretsVariableFile)) {
        $secretsVariableFile = Resolve-Path "./rke2-servers/secrets.pkrvars.hcl"
    }

    $baseVmId = $env:RKE2_PROVISION_BASE_VM_PX_ID
    if ([string]::IsNullOrWhiteSpace($baseVmId)) {
        $baseVmId = [System.Environment]::GetEnvironmentVariable('RKE2_PROVISION_BASE_VM_PX_ID', [System.EnvironmentVariableTarget]::User)
    }
    if ([string]::IsNullOrWhiteSpace($baseVmId)) {
        $baseVmId = "0"
    }

    $baseVmUserName = $env:RKE2_PROVISION_BASE_VM_USERNAME
    if ([string]::IsNullOrWhiteSpace($baseVmUserName)) {
        $baseVmUserName = [System.Environment]::GetEnvironmentVariable('RKE2_PROVISION_BASE_VM_USERNAME', [System.EnvironmentVariableTarget]::User)
    }

    $baseVmPassword = $env:RKE2_PROVISION_BASE_VM_PASSWORD
    if ([string]::IsNullOrWhiteSpace($baseVmPassword)) {
        $baseVmPassword = [System.Environment]::GetEnvironmentVariable('RKE2_PROVISION_BASE_VM_PASSWORD', [System.EnvironmentVariableTarget]::User)
    }

    $minVmId = $env:RKE2_PROVISION_MIN_VM_PX_ID
    if ([string]::IsNullOrWhiteSpace($minVmId)) {
        $minVmId = [System.Environment]::GetEnvironmentVariable('RKE2_PROVISION_MIN_VM_PX_ID', [System.EnvironmentVariableTarget]::User)
    }
    if ([string]::IsNullOrWhiteSpace($minVmId)) {
        $minVmId = "200"
    }

    $maxVmId = $env:RKE2_PROVISION_MAX_VM_PX_ID
    if ([string]::IsNullOrWhiteSpace($maxVmId)) {
        $maxVmId = [System.Environment]::GetEnvironmentVariable('RKE2_PROVISION_MAX_VM_PX_ID', [System.EnvironmentVariableTarget]::User)
    }
    if ([string]::IsNullOrWhiteSpace($maxVmId)) {
        $maxVmId = "299"
    }

    $clusterNode = $env:RKE2_PROVISION_CLUSTER_NODE
    if ([string]::IsNullOrWhiteSpace($clusterNode)) {
        $clusterNode = [System.Environment]::GetEnvironmentVariable('RKE2_PROVISION_CLUSTER_NODE', [System.EnvironmentVariableTarget]::User)
    }
    if ([string]::IsNullOrWhiteSpace($clusterNode)) {
        $clusterNode = "pxhp"
    }

    $clusterNodeStorage = $env:RKE2_PROVISION_CLUSTER_NODE_STORAGE
    if ([string]::IsNullOrWhiteSpace($clusterNodeStorage)) {
        $clusterNodeStorage = [System.Environment]::GetEnvironmentVariable('RKE2_PROVISION_CLUSTER_NODE_STORAGE', [System.EnvironmentVariableTarget]::User)
    }
    if ([string]::IsNullOrWhiteSpace($clusterNodeStorage)) {
        $clusterNodeStorage = "vmthin"
    }

    # Parse node weights from JSON environment variable
    # Example: {"pxhp": 90, "pmxdell": 10}
    $nodeWeightsJson = $env:RKE2_PROVISION_NODE_WEIGHTS
    if ([string]::IsNullOrWhiteSpace($nodeWeightsJson)) {
        $nodeWeightsJson = [System.Environment]::GetEnvironmentVariable('RKE2_PROVISION_NODE_WEIGHTS', [System.EnvironmentVariableTarget]::User)
    }

    $nodeWeights = $null
    if (-not [string]::IsNullOrWhiteSpace($nodeWeightsJson)) {
        try {
            $nodeWeights = $nodeWeightsJson | ConvertFrom-Json -AsHashtable
        }
        catch {
            Write-Warning "Failed to parse RKE2_PROVISION_NODE_WEIGHTS: $_. Using default single node."
            $nodeWeights = $null
        }
    }

    # If no weights specified, default to 100% on the configured cluster node
    if ($null -eq $nodeWeights) {
        $nodeWeights = @{ "$clusterNode" = 100 }
    }

    return @{
        nodePrefix          = "$nodePrefix"
        clusterStorage      = "$clusterStorage"
        secretsVariableFile = "$secretsVariableFile"
        baseVmId            = "$baseVmId"
        baseVmUsername      = "$baseVmUsername"
        baseVmPassword      = "$baseVmPassword"
        minVmId             = "$minVmId"
        maxVmId             = "$maxVmId"
        clusterNode         = "$clusterNode"
        clusterNodeStorage  = "$clusterNodeStorage"
        nodeWeights         = $nodeWeights
    }
}

function Wait-K8NodeReady {
    <#
    .SYNOPSIS
    Wait for a Kubernetes node to reach Ready status

    .DESCRIPTION
    Polls the Kubernetes API until the specified node reaches Ready status,
    or until the timeout is reached

    .PARAMETER NodeName
    The name of the node to wait for

    .PARAMETER ClusterName
    The cluster name

    .PARAMETER TimeoutSeconds
    Maximum time to wait for node to be ready (default: 600 seconds / 10 minutes)

    .PARAMETER PollIntervalSeconds
    How often to check node status (default: 15 seconds)

    .EXAMPLE
    PS> Wait-K8NodeReady -NodeName "test-agent-001" -ClusterName "test" -TimeoutSeconds 600
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$NodeName,

        [Parameter(Mandatory = $true)]
        [string]$ClusterName,

        [int]$TimeoutSeconds = 600,

        [int]$PollIntervalSeconds = 15
    )

    $startTime = Get-Date
    $timeoutTime = $startTime.AddSeconds($TimeoutSeconds)

    Write-Host "Waiting for node $NodeName to be ready..." -NoNewline

    while ((Get-Date) -lt $timeoutTime) {
        try {
            $node = Invoke-K8CommandJson "get node $NodeName" -clusterName $ClusterName

            $conditions = $node.status.conditions
            $readyCondition = $conditions | Where-Object { $_.type -eq "Ready" }

            if ($readyCondition.status -eq "True") {
                $elapsed = [Math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)
                Write-Host "ready ($elapsed seconds)"
                return $true
            }

            Write-Host "." -NoNewline
        }
        catch {
            Write-Verbose "Node not found yet: $_"
            Write-Host "." -NoNewline
        }

        Start-Sleep -Seconds $PollIntervalSeconds
    }

    Write-Host "timeout"
    Write-Error "Node $NodeName did not become ready within $TimeoutSeconds seconds"
    return $false
}

function Wait-AllAgentsReady {
    <#
    .SYNOPSIS
    Wait for all agent nodes in a cluster to be ready

    .DESCRIPTION
    Checks all agent nodes in the cluster and waits for them to reach Ready status

    .PARAMETER ClusterName
    The cluster name

    .PARAMETER TimeoutMinutes
    Maximum time to wait in minutes (default: 5 minutes)

    .EXAMPLE
    PS> Wait-AllAgentsReady -ClusterName "production" -TimeoutMinutes 10
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ClusterName,

        [int]$TimeoutMinutes = 5
    )

    $startTime = Get-Date
    $timeoutTime = $startTime.AddMinutes($TimeoutMinutes)

    Write-Host "Waiting for all agents to be ready..."

    while ((Get-Date) -lt $timeoutTime) {
        try {
            $nodes = Invoke-K8CommandJson "get nodes" -clusterName $ClusterName

            $agentNodes = $nodes.items | Where-Object {
                $roles = $_.metadata.labels.'kubernetes.io/role'
                $roles -eq "agent" -or $roles -eq "worker" -or $null -eq $roles
            }

            $notReadyAgents = $agentNodes | Where-Object {
                $conditions = $_.status.conditions
                $readyCondition = $conditions | Where-Object { $_.type -eq "Ready" }
                $readyCondition.status -ne "True"
            }

            if ($notReadyAgents.Count -eq 0) {
                $elapsed = [Math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)
                Write-Host "All agents ready ($elapsed seconds)"
                return $true
            }

            Write-Host "Waiting for $($notReadyAgents.Count) agents to be ready..."
            Start-Sleep -Seconds 15
        }
        catch {
            Write-Warning "Error checking agent status: $_"
            Start-Sleep -Seconds 15
        }
    }

    Write-Error "Not all agents became ready within $TimeoutMinutes minutes"
    return $false
}

function Get-UnhealthyPods {
    <#
    .SYNOPSIS
    Get all pods that are not in Running or Succeeded state

    .DESCRIPTION
    Queries all pods in the cluster and returns those that are unhealthy
    (not Running or Succeeded)

    .PARAMETER ClusterName
    The cluster name

    .EXAMPLE
    PS> Get-UnhealthyPods -ClusterName "production"
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ClusterName
    )

    try {
        $pods = Invoke-K8CommandJson "get pods --all-namespaces" -clusterName $ClusterName

        $unhealthyPods = $pods.items | Where-Object {
            $phase = $_.status.phase
            $phase -ne "Running" -and $phase -ne "Succeeded"
        }

        return $unhealthyPods | Select-Object `
            @{N="Namespace";E={$_.metadata.namespace}},
            @{N="Name";E={$_.metadata.name}},
            @{N="Phase";E={$_.status.phase}},
            @{N="Reason";E={$_.status.reason}},
            @{N="Message";E={$_.status.message}}
    }
    catch {
        Write-Warning "Failed to get unhealthy pods: $_"
        return @()
    }
}

function Test-ClusterHealth {
    <#
    .SYNOPSIS
    Perform basic health check on the cluster

    .DESCRIPTION
    Checks cluster connectivity, node health, and pod health

    .PARAMETER ClusterName
    The cluster name

    .EXAMPLE
    PS> Test-ClusterHealth -ClusterName "production"
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ClusterName
    )

    Write-Host "Performing cluster health check for: $ClusterName"

    # Check cluster connectivity
    try {
        Invoke-K8Command "cluster-info" -clusterName $ClusterName | Out-Null
        Write-Host "  Cluster connectivity: OK"
    }
    catch {
        Write-Error "  Cluster connectivity: FAILED - $_"
        return $false
    }

    # Check node status
    try {
        $nodes = Invoke-K8CommandJson "get nodes" -clusterName $ClusterName

        $notReadyNodes = $nodes.items | Where-Object {
            $conditions = $_.status.conditions
            $readyCondition = $conditions | Where-Object { $_.type -eq "Ready" }
            $readyCondition.status -ne "True"
        }

        if ($notReadyNodes.Count -gt 0) {
            Write-Warning "  Nodes not ready: $($notReadyNodes.Count)"
            foreach ($node in $notReadyNodes) {
                Write-Warning "    - $($node.metadata.name)"
            }
        }
        else {
            Write-Host "  All nodes ready: $($nodes.items.Count) nodes"
        }
    }
    catch {
        Write-Error "  Node status check: FAILED - $_"
        return $false
    }

    # Check for unhealthy pods
    $unhealthyPods = Get-UnhealthyPods -ClusterName $ClusterName

    if ($unhealthyPods.Count -gt 0) {
        Write-Warning "  Unhealthy pods found: $($unhealthyPods.Count)"
        if ($unhealthyPods.Count -le 10) {
            foreach ($pod in $unhealthyPods) {
                Write-Warning "    - $($pod.Namespace)/$($pod.Name): $($pod.Phase)"
            }
        }
    }
    else {
        Write-Host "  Pod health: OK"
    }

    Write-Host "Cluster health check completed"
    return $true
}

function Test-EtcdClusterHealth {
    <#
    .SYNOPSIS
    Check etcd cluster health for RKE2 server nodes

    .DESCRIPTION
    Verifies that the etcd cluster is healthy and has proper quorum

    .PARAMETER ClusterName
    The cluster name

    .EXAMPLE
    PS> Test-EtcdClusterHealth -ClusterName "production"
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ClusterName
    )

    Write-Host "Checking etcd cluster health..."

    try {
        # Get server nodes
        $nodes = Invoke-K8CommandJson "get nodes" -clusterName $ClusterName

        $serverNodes = $nodes.items | Where-Object {
            $labels = $_.metadata.labels
            $labels.'node-role.kubernetes.io/control-plane' -eq "true" -or
            $labels.'node-role.kubernetes.io/master' -eq "true" -or
            $labels.'kubernetes.io/role' -eq "server"
        }

        $serverCount = $serverNodes.Count
        Write-Host "  Server nodes found: $serverCount"

        if ($serverCount -lt 1) {
            Write-Error "  No server nodes found"
            return $false
        }

        if ($serverCount -lt 3) {
            Write-Warning "  Less than 3 server nodes - cluster does not have high availability"
        }

        # Check if all server nodes are ready
        $notReadyServers = $serverNodes | Where-Object {
            $conditions = $_.status.conditions
            $readyCondition = $conditions | Where-Object { $_.type -eq "Ready" }
            $readyCondition.status -ne "True"
        }

        if ($notReadyServers.Count -gt 0) {
            Write-Error "  Server nodes not ready: $($notReadyServers.Count)"
            foreach ($server in $notReadyServers) {
                Write-Error "    - $($server.metadata.name)"
            }
            return $false
        }

        Write-Host "  All server nodes are ready"
        Write-Host "  Etcd cluster health: OK"
        return $true
    }
    catch {
        Write-Error "  Etcd health check failed: $_"
        return $false
    }
}

function Get-ProxmoxStorageCapacity {
    <#
    .SYNOPSIS
    Get storage capacity information from Proxmox

    .DESCRIPTION
    Queries Proxmox for storage capacity metrics including total, used, and available space

    .PARAMETER ProxmoxNode
    The Proxmox node name

    .PARAMETER StorageName
    The storage pool name

    .EXAMPLE
    PS> Get-ProxmoxStorageCapacity -ProxmoxNode "pxhp" -StorageName "vmthin"
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProxmoxNode,

        [Parameter(Mandatory = $true)]
        [string]$StorageName
    )

    try {
        $ticket = Invoke-ProxmoxLogin

        # First, check if storage is active on this node
        $allStorage = Get-PveNodesStorage -PveTicket $ticket -Node $ProxmoxNode

        if ($allStorage.IsSuccessStatusCode -and $allStorage.Response.data) {
            $storageInfo = $allStorage.Response.data | Where-Object { $_.storage -eq $StorageName }

            if ($null -eq $storageInfo) {
                Write-Warning "Storage '$StorageName' not found on node '$ProxmoxNode'"
                return @{ Success = $false; Error = "Storage not found on node" }
            }

            # Check if storage is active/enabled
            if ($storageInfo.active -eq 0 -and $storageInfo.enabled -eq 0) {
                Write-Warning "Storage '$StorageName' is not active on node '$ProxmoxNode' (active: $($storageInfo.active), enabled: $($storageInfo.enabled))"
                return @{ Success = $false; Error = "Storage is not active or enabled on this node" }
            }
        }

        # Now get detailed storage status
        $storageStatus = Get-PveNodesStorageStatus -PveTicket $ticket -Node $ProxmoxNode -Storage $StorageName

        Write-Verbose "API Response Status: $($storageStatus.IsSuccessStatusCode)"

        if ($storageStatus.IsSuccessStatusCode) {
            $data = $storageStatus.Response.data

            Write-Verbose "Response data: $($data | ConvertTo-Json -Depth 3 -Compress)"

            $total = $data.total
            $used = $data.used
            $available = $data.avail

            Write-Verbose "Extracted values - Total: $total, Used: $used, Available: $available"

            # Check if storage is reporting zero capacity (inactive or unmounted)
            if ($total -eq 0 -and $used -eq 0 -and $available -eq 0) {
                Write-Warning "Storage '$StorageName' is reporting zero capacity (may be inactive or unmounted)"
                Write-Verbose "Storage type: $($data.type), Active: $($data.active), Enabled: $($data.enabled)"
                return @{ Success = $false; Error = "Storage is reporting zero capacity (inactive or unmounted)" }
            }

            # Check if values are null
            if ($null -eq $total -or $null -eq $used -or $null -eq $available) {
                Write-Warning "One or more storage values are null. Total: $total, Used: $used, Available: $available"
                return @{ Success = $false; Error = "Storage values are null or missing" }
            }

            if ($total -gt 0) {
                $usedPercent = ($used / $total) * 100
                $freePercent = 100 - $usedPercent

                return @{
                    StorageName = $StorageName
                    Node = $ProxmoxNode
                    TotalBytes = $total
                    UsedBytes = $used
                    AvailableBytes = $available
                    TotalGB = [Math]::Round($total / 1GB, 2)
                    UsedGB = [Math]::Round($used / 1GB, 2)
                    AvailableGB = [Math]::Round($available / 1GB, 2)
                    UsedPercent = [Math]::Round($usedPercent, 2)
                    FreePercent = [Math]::Round($freePercent, 2)
                    Success = $true
                }
            }
            else {
                Write-Warning "Storage total is 0 or invalid. Total: $total"
                return @{ Success = $false; Error = "Invalid storage capacity data - total is 0" }
            }
        }
        else {
            Write-Warning "Failed to retrieve storage status from Proxmox"
            Write-Warning "Status Code: $($storageStatus.StatusCode)"
            return @{ Success = $false; Error = "Proxmox API call failed: $($storageStatus.ReasonPhrase)" }
        }
    }
    catch {
        Write-Warning "Error getting storage capacity: $_"
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

function Test-ClusterReadyForCycling {
    <#
    .SYNOPSIS
    Pre-flight validation before starting cluster cycling

    .DESCRIPTION
    Performs comprehensive checks to ensure the cluster is healthy and ready
    for node cycling operations. This includes node counts, cluster health,
    storage capacity, and dependency availability.

    .PARAMETER ClusterName
    The cluster name

    .PARAMETER MinServerCount
    Minimum number of server nodes required (default: 3)

    .PARAMETER MinAgentCount
    Minimum number of agent nodes required (default: 3)

    .PARAMETER MinStoragePercentFree
    Minimum free storage percentage on Proxmox (default: 25%)

    .PARAMETER CheckUnifiApi
    Whether to check Unifi API availability (default: true)

    .EXAMPLE
    PS> Test-ClusterReadyForCycling -ClusterName "production" -MinServerCount 3 -MinAgentCount 3
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ClusterName,

        [int]$MinServerCount = 3,

        [int]$MinAgentCount = 3,

        [int]$MinStoragePercentFree = 25,

        [bool]$CheckUnifiApi = $true
    )

    Write-Host "=== Pre-Flight Validation for Cluster Cycling: $ClusterName ==="
    $allChecksPassed = $true

    # 1. Verify cluster connectivity
    Write-Host "`n1. Checking cluster connectivity..."
    try {
        Invoke-K8Command "cluster-info" -clusterName $ClusterName | Out-Null
        Write-Host "   PASS: Cluster is accessible"
    }
    catch {
        Write-Error "   FAIL: Cannot connect to cluster - $_"
        $allChecksPassed = $false
    }

    # 2. Check cluster node count meets minimum
    Write-Host "`n2. Checking node counts..."
    try {
        $nodes = Invoke-K8CommandJson "get nodes" -clusterName $ClusterName

        $serverNodes = $nodes.items | Where-Object {
            $labels = $_.metadata.labels
            $labels.'node-role.kubernetes.io/control-plane' -eq "true" -or
            $labels.'node-role.kubernetes.io/master' -eq "true" -or
            $labels.'kubernetes.io/role' -eq "server"
        }

        $agentNodes = $nodes.items | Where-Object {
            $labels = $_.metadata.labels
            $roles = $labels.'kubernetes.io/role'
            $roles -eq "agent" -or $roles -eq "worker" -or $null -eq $roles
        }

        $serverCount = $serverNodes.Count
        $agentCount = $agentNodes.Count

        Write-Host "   Server nodes: $serverCount (minimum: $MinServerCount)"
        Write-Host "   Agent nodes: $agentCount (minimum: $MinAgentCount)"

        if ($serverCount -lt $MinServerCount) {
            Write-Error "   FAIL: Not enough server nodes"
            $allChecksPassed = $false
        }
        else {
            Write-Host "   PASS: Sufficient server nodes"
        }

        if ($agentCount -lt $MinAgentCount) {
            Write-Error "   FAIL: Not enough agent nodes"
            $allChecksPassed = $false
        }
        else {
            Write-Host "   PASS: Sufficient agent nodes"
        }
    }
    catch {
        Write-Error "   FAIL: Could not check node counts - $_"
        $allChecksPassed = $false
    }

    # 3. Validate no pending node drains
    Write-Host "`n3. Checking for cordoned nodes..."
    try {
        $nodes = Invoke-K8CommandJson "get nodes" -clusterName $ClusterName

        $cordonedNodes = $nodes.items | Where-Object {
            $_.spec.unschedulable -eq $true
        }

        if ($cordonedNodes.Count -gt 0) {
            Write-Warning "   WARNING: $($cordonedNodes.Count) cordoned nodes found:"
            foreach ($node in $cordonedNodes) {
                Write-Warning "     - $($node.metadata.name)"
            }
            Write-Warning "   These nodes may be in the middle of draining"
        }
        else {
            Write-Host "   PASS: No cordoned nodes"
        }
    }
    catch {
        Write-Warning "   Could not check for cordoned nodes: $_"
    }

    # 4. Check Proxmox storage capacity across all cluster nodes
    Write-Host "`n4. Checking Proxmox storage capacity across cluster nodes..."
    try {
        $rke2Settings = Get-PxRke2Settings
        $ticket = Invoke-ProxmoxLogin

        # Get all nodes from node weights configuration
        $nodesToCheck = $rke2Settings.nodeWeights.Keys
        Write-Host "   Checking $($nodesToCheck.Count) Proxmox node(s): $($nodesToCheck -join ', ')"

        $clusterWideAllStorageLowOnSpace = $true
        $clusterWideTotalCapacity = 0
        $clusterWideTotalUsed = 0
        $clusterWideTotalAvailable = 0

        foreach ($pxNode in $nodesToCheck) {
            Write-Host "`n   === Node: $pxNode ==="

            # Get all available lvmthin storage pools on this node
            $allStorage = Get-PveNodesStorage -PveTicket $ticket -Node $pxNode

            if ($allStorage.IsSuccessStatusCode -and $allStorage.Response.data) {
                # Filter for lvmthin storage that supports images and is active
                # Exclude 'local-lvm' as it's reserved for Proxmox system data
                $lvmthinPools = $allStorage.Response.data | Where-Object {
                    $_.type -eq 'lvmthin' -and
                    $_.storage -ne 'local-lvm' -and
                    ($_.content -split ',' -contains 'images') -and
                    ($_.active -eq 1 -or $_.enabled -eq 1)
                }

                if ($lvmthinPools.Count -eq 0) {
                    Write-Warning "   WARNING: No active lvmthin storage pools found on $pxNode"
                }
                else {
                    Write-Host "   Found $($lvmthinPools.Count) active lvmthin storage pool(s)"

                    $nodeHasSufficientStorage = $false
                    $nodeTotalCapacity = 0
                    $nodeTotalUsed = 0
                    $nodeTotalAvailable = 0

                    foreach ($pool in $lvmthinPools) {
                        $storageInfo = Get-ProxmoxStorageCapacity -ProxmoxNode $pxNode -StorageName $pool.storage

                        if ($storageInfo.Success) {
                            Write-Host "`n   Storage: $($pool.storage) on $pxNode"
                            Write-Host "     Total: $($storageInfo.TotalGB) GB"
                            Write-Host "     Used: $($storageInfo.UsedGB) GB ($($storageInfo.UsedPercent)%)"
                            Write-Host "     Available: $($storageInfo.AvailableGB) GB ($($storageInfo.FreePercent)% free)"

                            $nodeTotalCapacity += $storageInfo.TotalBytes
                            $nodeTotalUsed += $storageInfo.UsedBytes
                            $nodeTotalAvailable += $storageInfo.AvailableBytes

                            $clusterWideTotalCapacity += $storageInfo.TotalBytes
                            $clusterWideTotalUsed += $storageInfo.UsedBytes
                            $clusterWideTotalAvailable += $storageInfo.AvailableBytes

                            if ($storageInfo.FreePercent -ge $MinStoragePercentFree) {
                                $nodeHasSufficientStorage = $true
                                $clusterWideAllStorageLowOnSpace = $false
                                Write-Host "     PASS: Sufficient space available"
                            }
                            else {
                                Write-Warning "     WARNING: Storage free ($($storageInfo.FreePercent)%) below minimum ($MinStoragePercentFree%)"
                            }
                        }
                        else {
                            Write-Warning "   Could not get capacity for $($pool.storage) on $pxNode : $($storageInfo.Error)"
                        }
                    }

                    # Show node aggregate capacity
                    if ($nodeTotalCapacity -gt 0) {
                        $nodeUsedPercent = [Math]::Round(($nodeTotalUsed / $nodeTotalCapacity) * 100, 2)
                        $nodeFreePercent = [Math]::Round(100 - $nodeUsedPercent, 2)

                        Write-Host "`n   Node $pxNode Aggregate:"
                        Write-Host "     Total: $([Math]::Round($nodeTotalCapacity / 1GB, 2)) GB"
                        Write-Host "     Used: $([Math]::Round($nodeTotalUsed / 1GB, 2)) GB ($nodeUsedPercent%)"
                        Write-Host "     Available: $([Math]::Round($nodeTotalAvailable / 1GB, 2)) GB ($nodeFreePercent% free)"

                        if ($nodeHasSufficientStorage) {
                            Write-Host "     Status: At least one storage pool has sufficient space"
                        }
                        else {
                            Write-Warning "     Status: All storage pools below minimum threshold"
                        }
                    }
                }
            }
            else {
                Write-Warning "   WARNING: Could not retrieve storage list from Proxmox for node $pxNode"
            }
        }

        # Show cluster-wide aggregate capacity
        if ($clusterWideTotalCapacity -gt 0) {
            $clusterUsedPercent = [Math]::Round(($clusterWideTotalUsed / $clusterWideTotalCapacity) * 100, 2)
            $clusterFreePercent = [Math]::Round(100 - $clusterUsedPercent, 2)

            Write-Host "`n   === Cluster-Wide Storage Summary ==="
            Write-Host "     Total: $([Math]::Round($clusterWideTotalCapacity / 1GB, 2)) GB"
            Write-Host "     Used: $([Math]::Round($clusterWideTotalUsed / 1GB, 2)) GB ($clusterUsedPercent%)"
            Write-Host "     Available: $([Math]::Round($clusterWideTotalAvailable / 1GB, 2)) GB ($clusterFreePercent% free)"
        }

        # Only fail if ALL storage pools across ALL nodes are low on space
        if ($clusterWideAllStorageLowOnSpace) {
            Write-Error "   FAIL: All storage pools across all nodes are below minimum threshold ($MinStoragePercentFree%)"
            $allChecksPassed = $false
        }
        else {
            Write-Host "`n   PASS: At least one storage pool has sufficient space across the cluster"
        }
    }
    catch {
        Write-Warning "   Could not check Proxmox storage: $_"
    }

    # 5. Verify Unifi API availability
    if ($CheckUnifiApi) {
        Write-Host "`n5. Checking Unifi API availability..."
        try {
            $unifiAvailable = Test-UnifiApiAvailable
            if ($unifiAvailable) {
                Write-Host "   PASS: Unifi API is available"
            }
            else {
                Write-Warning "   WARNING: Unifi API is not available"
                Write-Warning "   This may cause provisioning failures"
            }
        }
        catch {
            Write-Warning "   Could not check Unifi API: $_"
        }
    }

    # 6. Check for failed pods or unschedulable workloads
    Write-Host "`n6. Checking for unhealthy pods..."
    $unhealthyPods = Get-UnhealthyPods -ClusterName $ClusterName

    if ($unhealthyPods.Count -gt 0) {
        Write-Warning "   WARNING: $($unhealthyPods.Count) unhealthy pods found"
        if ($unhealthyPods.Count -le 5) {
            foreach ($pod in $unhealthyPods) {
                Write-Warning "     - $($pod.Namespace)/$($pod.Name): $($pod.Phase)"
            }
        }
        Write-Warning "   Consider fixing these before cycling"
    }
    else {
        Write-Host "   PASS: All pods are healthy"
    }

    # 7. Validate etcd cluster health
    Write-Host "`n7. Checking etcd cluster health..."
    $etcdHealthy = Test-EtcdClusterHealth -ClusterName $ClusterName
    if ($etcdHealthy) {
        Write-Host "   PASS: Etcd cluster is healthy"
    }
    else {
        Write-Error "   FAIL: Etcd cluster is not healthy"
        $allChecksPassed = $false
    }

    # Summary
    Write-Host "`n=== Pre-Flight Validation Summary ==="
    if ($allChecksPassed) {
        Write-Host "PASS: Cluster is ready for cycling" -ForegroundColor Green
        return $true
    }
    else {
        Write-Error "FAIL: Cluster is NOT ready for cycling. Please address the failures above."
        return $false
    }
}

function Get-ClusterCyclingStatus {
    <#
    .SYNOPSIS
    Get comprehensive status of a cluster during cycling operations

    .DESCRIPTION
    Provides a detailed overview of cluster health, node status, pod health,
    and capacity metrics useful during cycling operations

    .PARAMETER ClusterName
    The cluster name

    .EXAMPLE
    PS> Get-ClusterCyclingStatus -ClusterName "production"
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ClusterName
    )

    Write-Host "=== Cluster Cycling Status: $ClusterName ==="

    # Node status
    Write-Host "`n--- Node Status ---"
    try {
        $nodes = Invoke-K8CommandJson "get nodes" -clusterName $ClusterName

        $nodeList = $nodes.items | Select-Object `
            @{N="Name";E={$_.metadata.name}},
            @{N="Status";E={
                $conditions = $_.status.conditions
                $readyCondition = $conditions | Where-Object { $_.type -eq "Ready" }
                if ($readyCondition.status -eq "True") { "Ready" } else { "NotReady" }
            }},
            @{N="Age";E={
                $created = [DateTime]::Parse($_.metadata.creationTimestamp)
                $age = (Get-Date) - $created
                "$([Math]::Floor($age.TotalDays))d"
            }},
            @{N="Roles";E={
                $labels = $_.metadata.labels
                if ($labels.'node-role.kubernetes.io/control-plane' -eq "true" -or
                    $labels.'node-role.kubernetes.io/master' -eq "true" -or
                    $labels.'kubernetes.io/role' -eq "server") {
                    "server"
                } else {
                    "agent"
                }
            }},
            @{N="Cordoned";E={ $_.spec.unschedulable -eq $true }}

        $nodeList | Format-Table -AutoSize
    }
    catch {
        Write-Error "Failed to get node status: $_"
    }

    # Pod health
    Write-Host "`n--- Pod Health ---"
    $unhealthyPods = Get-UnhealthyPods -ClusterName $ClusterName

    Write-Host "Unhealthy Pods: $($unhealthyPods.Count)"
    if ($unhealthyPods.Count -gt 0 -and $unhealthyPods.Count -le 20) {
        $unhealthyPods | Format-Table Namespace, Name, Phase, Reason -AutoSize
    }

    # PodDisruptionBudgets
    Write-Host "`n--- PodDisruptionBudgets ---"
    try {
        $pdbs = Invoke-K8CommandJson "get pdb --all-namespaces" -clusterName $ClusterName

        $blockedPdbs = $pdbs.items | Where-Object { $_.status.disruptionsAllowed -eq 0 }
        Write-Host "PDBs with 0 disruptions allowed: $($blockedPdbs.Count)"

        if ($blockedPdbs.Count -gt 0 -and $blockedPdbs.Count -le 10) {
            $blockedPdbs | Select-Object `
                @{N="Namespace";E={$_.metadata.namespace}},
                @{N="Name";E={$_.metadata.name}},
                @{N="CurrentHealthy";E={$_.status.currentHealthy}},
                @{N="MinAvailable";E={$_.spec.minAvailable}},
                @{N="DisruptionsAllowed";E={$_.status.disruptionsAllowed}} |
                Format-Table -AutoSize
        }
    }
    catch {
        Write-Warning "Failed to get PDB status: $_"
    }

    # Cluster capacity
    Write-Host "`n--- Cluster Capacity ---"
    try {
        $nodes = Invoke-K8CommandJson "get nodes" -clusterName $ClusterName

        $totalCPU = 0
        $totalMemory = 0

        foreach ($node in $nodes.items) {
            $cpu = $node.status.allocatable.cpu -replace '[^0-9]', ''
            $memory = $node.status.allocatable.memory -replace '[^0-9]', ''

            if ($cpu) { $totalCPU += [int]$cpu }
            if ($memory) { $totalMemory += [long]$memory }
        }

        Write-Host "Total Allocatable CPU: $totalCPU cores"
        Write-Host "Total Allocatable Memory: $([Math]::Round($totalMemory / 1GB, 1)) GB"
    }
    catch {
        Write-Warning "Failed to calculate cluster capacity: $_"
    }

    # Recent events
    Write-Host "`n--- Recent Cluster Events (Last 10) ---"
    try {
        $events = Invoke-K8Command "get events --all-namespaces --sort-by=.lastTimestamp" -clusterName $ClusterName
        Write-Host $events
    }
    catch {
        Write-Warning "Failed to get recent events: $_"
    }

    Write-Host "`n=== End of Status Report ==="
}

function Get-DrainBlockersDiagnostics {
    <#
    .SYNOPSIS
    Diagnose why a node drain is stuck or failing

    .DESCRIPTION
    Provides detailed diagnostics for a node that is stuck draining, including
    pod status, PDB blockers, finalizers, and remediation suggestions

    .PARAMETER ClusterName
    The cluster name

    .PARAMETER NodeName
    The node name that is stuck draining

    .EXAMPLE
    PS> Get-DrainBlockersDiagnostics -ClusterName "production" -NodeName "prod-agent-001"
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ClusterName,

        [Parameter(Mandatory = $true)]
        [string]$NodeName
    )

    Write-Host "=== Drain Blockers Diagnostics: $NodeName ==="

    # Pods still on node
    Write-Host "`n--- Pods Remaining on Node ---"
    $pods = Get-PodsOnNode -ClusterName $ClusterName -NodeName $NodeName
    Write-Host "Total pods remaining: $($pods.Count)"

    # Categorize by phase
    $podsByPhase = $pods | Group-Object Phase
    foreach ($group in $podsByPhase) {
        Write-Host "  $($group.Name): $($group.Count) pods"
    }

    # Check for pods in Terminating state
    $terminatingPods = $pods | Where-Object { $_.Phase -eq "Terminating" }
    if ($terminatingPods.Count -gt 0) {
        Write-Host "`n--- Terminating Pods (May Be Stuck) ---"
        foreach ($pod in $terminatingPods) {
            try {
                $podDetail = Invoke-K8CommandJson "get pod $($pod.Name) -n $($pod.Namespace)" -clusterName $ClusterName

                Write-Host "  Pod: $($pod.Namespace)/$($pod.Name)"
                Write-Host "    Deletion Timestamp: $($podDetail.metadata.deletionTimestamp)"
                Write-Host "    Grace Period: $($podDetail.metadata.deletionGracePeriodSeconds)s"

                if ($podDetail.metadata.finalizers -and $podDetail.metadata.finalizers.Count -gt 0) {
                    Write-Warning "    Finalizers: $($podDetail.metadata.finalizers -join ', ')"
                    Write-Warning "    Pod has finalizers that may be preventing deletion"
                }
            }
            catch {
                Write-Warning "  Could not get details for pod: $_"
            }
        }
    }

    # Check PodDisruptionBudgets
    Write-Host "`n--- PodDisruptionBudgets Blocking Eviction ---"
    $pdbBlockers = Get-PDBBlockers -ClusterName $ClusterName -NodeName $NodeName

    if ($pdbBlockers.Count -gt 0) {
        foreach ($blocker in $pdbBlockers) {
            Write-Host "  PDB: $($blocker.PDBName)"
            Write-Host "    Disruptions Allowed: $($blocker.DisruptionsAllowed)"
            Write-Host "    Current Healthy: $($blocker.CurrentHealthy)"
            Write-Host "    Min Available: $($blocker.MinAvailable)"
            Write-Host "    Affected Pods: $($blocker.BlockedPods.Count)"
        }
    }
    else {
        Write-Host "  No PDB blockers found"
    }

    # Check for local storage
    Write-Host "`n--- Pods with Local Storage ---"
    $podsWithLocalStorage = @()
    foreach ($pod in $pods) {
        try {
            $podDetail = Invoke-K8CommandJson "get pod $($pod.Name) -n $($pod.Namespace)" -clusterName $ClusterName

            $hasEmptyDir = $podDetail.spec.volumes | Where-Object { $null -ne $_.emptyDir }
            $hasHostPath = $podDetail.spec.volumes | Where-Object { $null -ne $_.hostPath }

            if ($hasEmptyDir -or $hasHostPath) {
                $podsWithLocalStorage += $pod
            }
        }
        catch {
            Write-Verbose "Could not check storage for pod $($pod.Name): $_"
        }
    }

    if ($podsWithLocalStorage.Count -gt 0) {
        foreach ($pod in $podsWithLocalStorage) {
            Write-Host "  - $($pod.Namespace)/$($pod.Name)"
        }
        Write-Host "  Note: These pods may require --delete-emptydir-data flag"
    }
    else {
        Write-Host "  No pods with local storage found"
    }

    # Suggest remediation
    Write-Host "`n=== Suggested Remediation ==="

    if ($terminatingPods.Count -gt 0) {
        Write-Host "`n1. Force delete stuck terminating pods:"
        foreach ($pod in $terminatingPods) {
            Write-Host "   kubectl --kubeconfig <config> delete pod $($pod.Name) -n $($pod.Namespace) --force --grace-period=0"
        }
    }

    if ($pdbBlockers.Count -gt 0) {
        Write-Host "`n2. Temporarily adjust PodDisruptionBudgets:"
        foreach ($blocker in $pdbBlockers) {
            $pdbName = $blocker.PDBName -replace '^[^/]+/', ''
            $pdbNamespace = $blocker.PDBName -replace '/.*$', ''
            Write-Host "   kubectl --kubeconfig <config> patch pdb $pdbName -n $pdbNamespace -p '{""spec"":{""minAvailable"":0}}'"
        }
    }

    if ($podsWithLocalStorage.Count -gt 0) {
        Write-Host "`n3. Ensure drain command includes --delete-emptydir-data flag"
    }

    if ($terminatingPods.Count -eq 0 -and $pdbBlockers.Count -eq 0 -and $podsWithLocalStorage.Count -eq 0) {
        Write-Host "No obvious blockers found. Check pod logs and events for more details."
    }

    Write-Host "`n=== End of Diagnostics ==="
}

function Test-ProxmoxStorageCapacity {
    <#
    .SYNOPSIS
    Tests if Proxmox storage has sufficient capacity for cluster cycling

    .PARAMETER Node
    Proxmox node name

    .PARAMETER MinFreePercent
    Minimum required free space percentage (default: 25)

    .PARAMETER Storage
    Storage pool name (optional, checks all if not specified)
    #>
    param(
        [string]$Node = "pxhp",
        [double]$MinFreePercent = 25,
        [string]$Storage = $null
    )

    $storageInfo = Get-ProxmoxStorageCapacity -Node $Node

    if ($Storage) {
        $storageInfo = $storageInfo | Where-Object { $_.Storage -eq $Storage }
    }

    $insufficientStorage = $storageInfo | Where-Object { $_.FreePercent -lt $MinFreePercent }

    $result = @{
        HasSufficientSpace = ($insufficientStorage.Count -eq 0)
        StorageDetails = $storageInfo
        InsufficientStorage = $insufficientStorage
        MinFreePercent = $MinFreePercent
        FreePercent = if ($Storage) { ($storageInfo | Select-Object -First 1).FreePercent } else { ($storageInfo | Measure-Object -Property FreePercent -Average).Average }
    }

    return $result
}

function Get-ClusterNodeInfo {
    <#
    .SYNOPSIS
    Get detailed information about cluster nodes (alias for Get-ClusterInfo)

    .PARAMETER ClusterName
    Name of the RKE2 cluster
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ClusterName
    )

    return Get-ClusterInfo -ClusterName $ClusterName
}

function Get-ClusterCapacity {
    <#
    .SYNOPSIS
    Get cluster CPU and memory capacity and utilization

    .PARAMETER ClusterName
    Name of the RKE2 cluster
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ClusterName
    )

    $settings = Get-PxRke2SettingsFromEnvironment
    $kubeconfigPath = Join-Path $settings.clusterStorage "$ClusterName\remote.yaml"

    if (-not (Test-Path $kubeconfigPath)) {
        throw "Kubeconfig not found: $kubeconfigPath"
    }

    # Get node metrics
    $nodesJson = kubectl --kubeconfig="$kubeconfigPath" get nodes -o json | ConvertFrom-Json

    $totalCPU = 0
    $allocatableCPU = 0
    $totalMemory = 0
    $allocatableMemory = 0

    foreach ($node in $nodesJson.items) {
        # Total capacity
        $nodeCPU = $node.status.capacity.cpu
        $nodeMemory = $node.status.capacity.memory

        # Allocatable (what's available for pods)
        $nodeAllocCPU = $node.status.allocatable.cpu
        $nodeAllocMemory = $node.status.allocatable.memory

        # Convert to numeric values
        $totalCPU += [int]$nodeCPU
        $allocatableCPU += [int]$nodeAllocCPU

        # Convert memory from Ki to bytes
        if ($nodeMemory -match '(\d+)Ki') {
            $totalMemory += [long]$Matches[1] * 1024
        }
        if ($nodeAllocMemory -match '(\d+)Ki') {
            $allocatableMemory += [long]$Matches[1] * 1024
        }
    }

    # Get current resource requests
    $podsJson = kubectl --kubeconfig="$kubeconfigPath" get pods --all-namespaces -o json | ConvertFrom-Json

    $requestedCPU = 0
    $requestedMemory = 0

    foreach ($pod in $podsJson.items) {
        if ($pod.status.phase -eq "Running") {
            foreach ($container in $pod.spec.containers) {
                if ($container.resources.requests) {
                    # CPU requests (can be in cores or millicores)
                    if ($container.resources.requests.cpu) {
                        $cpuRequest = $container.resources.requests.cpu
                        if ($cpuRequest -match '(\d+)m') {
                            $requestedCPU += [double]$Matches[1] / 1000
                        } else {
                            $requestedCPU += [double]$cpuRequest
                        }
                    }

                    # Memory requests
                    if ($container.resources.requests.memory) {
                        $memRequest = $container.resources.requests.memory
                        if ($memRequest -match '(\d+)Ki') {
                            $requestedMemory += [long]$Matches[1] * 1024
                        } elseif ($memRequest -match '(\d+)Mi') {
                            $requestedMemory += [long]$Matches[1] * 1024 * 1024
                        } elseif ($memRequest -match '(\d+)Gi') {
                            $requestedMemory += [long]$Matches[1] * 1024 * 1024 * 1024
                        }
                    }
                }
            }
        }
    }

    $cpuUtilization = if ($allocatableCPU -gt 0) { $requestedCPU / $allocatableCPU } else { 0 }
    $memoryUtilization = if ($allocatableMemory -gt 0) { $requestedMemory / $allocatableMemory } else { 0 }

    return @{
        TotalCPU = $totalCPU
        AllocatableCPU = $allocatableCPU
        RequestedCPU = $requestedCPU
        CPUUtilization = $cpuUtilization
        TotalMemory = $totalMemory
        AllocatableMemory = $allocatableMemory
        RequestedMemory = $requestedMemory
        MemoryUtilization = $memoryUtilization
    }
}

function Test-ProductionServicesAvailable {
    <#
    .SYNOPSIS
    Test availability of production service dependencies (Unifi API, Identity Server)
    #>
    param()

    $results = @{}

    # Test Unifi API Manager
    try {
        $unifiAvailable = Test-UnifiApiAvailable -TimeoutSeconds 10
        $results["UnifiApiManager"] = @{
            Available = $unifiAvailable
        }
    } catch {
        $results["UnifiApiManager"] = @{
            Available = $false
            Error = $_.Exception.Message
        }
    }

    # Test Identity Server (if configured)
    $identityServerUrl = $env:IDENTITY_SERVER_URL
    if ($identityServerUrl) {
        try {
            $response = Invoke-RestMethod -Uri "$identityServerUrl/.well-known/openid-configuration" -TimeoutSec 10 -ErrorAction Stop
            $results["IdentityServer"] = @{
                Available = $true
                Issuer = $response.issuer
            }
        } catch {
            $results["IdentityServer"] = @{
                Available = $false
                Error = $_.Exception.Message
            }
        }
    } else {
        $results["IdentityServer"] = @{
            Available = $true
            Skipped = "Not configured"
        }
    }

    # Check if all required services are available
    $allAvailable = ($results.Values | Where-Object { $_.Available -eq $false }).Count -eq 0

    return @{
        AllAvailable = $allAvailable
        Services = $results
    }
}

function Invoke-Rke2ServerCycling {
    <#
    .SYNOPSIS
    Orchestrate server node cycling with zero downtime

    .PARAMETER ClusterName
    Name of the RKE2 cluster

    .PARAMETER DnsDomain
    DNS domain for nodes

    .PARAMETER VmSize
    VM size for servers

    .PARAMETER MaxAgeDays
    Age threshold for cycling nodes

    .PARAMETER MaxServersPerRun
    Maximum number of servers to cycle per pipeline run (0 = unlimited)
    Prevents cycling all servers at once when pipeline runs infrequently

    .PARAMETER MaxConcurrentProvision
    Maximum concurrent VM provisions (for I/O throttling)

    .PARAMETER Rke2Version
    Specific RKE2 version to install (e.g., "v1.28.5+rke2r1"). If specified, takes precedence over Rke2Channel.

    .PARAMETER Rke2Channel
    RKE2 channel to use (stable, latest, testing, or specific minor like v1.28). Defaults to "stable".
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ClusterName,

        [Parameter(Mandatory = $true)]
        [string]$DnsDomain,

        [string]$VmSize = "med",

        [int]$MaxAgeDays = 14,

        [int]$MaxServersPerRun = 0,  # 0 = unlimited (cycle all aged servers)

        [int]$MaxConcurrentProvision = 1,

        [string]$Rke2Version = "",

        [string]$Rke2Channel = "stable"
    )

    $ErrorActionPreference = "Stop"

    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Server Node Cycling: $ClusterName" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    $serversAdded = 0
    $serversRemoved = 0

    try {
        # Get old servers that need cycling (limited to MaxServersPerRun if specified)
        $oldServers = Get-Rke2NodesToCycle `
            -ClusterName $ClusterName `
            -NodeType "server" `
            -MaxAgeDays $MaxAgeDays `
            -MaxCount $MaxServersPerRun

        if ($oldServers.Count -eq 0) {
            Write-Host "No servers need cycling (all are less than $MaxAgeDays days old)" -ForegroundColor Green
            return @{
                Success = $true
                ServersAdded = 0
                ServersRemoved = 0
                Message = "No servers need cycling"
            }
        }

        Write-Host "`nFound $($oldServers.Count) servers to cycle:" -ForegroundColor Yellow
        if ($MaxServersPerRun -gt 0) {
            Write-Host "(Limited to $MaxServersPerRun oldest servers per run)" -ForegroundColor Cyan
        }
        $oldServers | Format-Table Name, Age, Status, CreationTime | Out-String | Write-Host

        # Step 1: Provision new servers (one at a time with delay)
        Write-Host "`n=== Step 1: Provisioning New Servers ===" -ForegroundColor Green

        for ($i = 0; $i -lt $oldServers.Count; $i++) {
            Write-Host "`nProvisioning server $($i + 1) of $($oldServers.Count)..." -ForegroundColor Cyan

            Add-PxNodeToRke2Cluster `
                -ClusterName $ClusterName `
                -DnsDomain $DnsDomain `
                -VmSize $VmSize `
                -NodeType "server" `
                -rke2Version $Rke2Version `
                -rke2Channel $Rke2Channel

            $serversAdded++

            # Get the newly added server
            $currentServers = Get-ClusterInfo -ClusterName $ClusterName | Where-Object { $_.Roles -contains "control-plane" }
            $newServer = $currentServers | Sort-Object Age | Select-Object -First 1

            Write-Host "New server: $($newServer.Name)" -ForegroundColor Green

            # Wait for node to be ready
            Write-Host "Waiting for node to be ready..." -ForegroundColor Cyan
            Wait-K8NodeReady -NodeName $newServer.Name -ClusterName $ClusterName -TimeoutSeconds 1200

            # Validate etcd cluster health
            Write-Host "Validating etcd cluster health..." -ForegroundColor Cyan
            $etcdHealth = Test-EtcdClusterHealth -ClusterName $ClusterName
            if (-not $etcdHealth.Healthy) {
                throw "Etcd cluster unhealthy after adding server: $($etcdHealth.Error)"
            }

            # Delay before next provision (I/O throttling)
            if ($i -lt $oldServers.Count - 1) {
                Write-Host "Waiting 5 minutes before next provision (I/O throttling)..." -ForegroundColor Yellow
                Start-Sleep -Seconds 300
            }
        }

        # Step 2: Remove old servers (one at a time)
        Write-Host "`n=== Step 2: Removing Old Servers ===" -ForegroundColor Green

        foreach ($server in $oldServers) {
            Write-Host "`nRemoving server: $($server.Name)" -ForegroundColor Cyan

            # Pre-removal validation - ensure we maintain quorum
            $currentServerCount = (Get-ClusterInfo -ClusterName $ClusterName | Where-Object { $_.Roles -contains "control-plane" }).Count
            if ($currentServerCount -le 3) {
                Write-Warning "Cannot remove server: Would violate minimum quorum (need at least 3 servers)"
                continue
            }

            # Remove with monitoring
            Remove-NodeFromPxRke2Cluster `
                -MachineName $server.Name `
                -ClusterName $ClusterName `
                -MonitorDrain $true `
                -DrainTimeoutMinutes 15

            $serversRemoved++

            # Validate cluster after removal
            Write-Host "Validating etcd cluster health after removal..." -ForegroundColor Cyan
            $etcdHealth = Test-EtcdClusterHealth -ClusterName $ClusterName
            if (-not $etcdHealth.Healthy) {
                throw "Etcd cluster unhealthy after removing server: $($etcdHealth.Error)"
            }

            # Delay before next removal
            Write-Host "Waiting 5 minutes before next removal..." -ForegroundColor Yellow
            Start-Sleep -Seconds 300
        }

        Write-Host "`n========================================" -ForegroundColor Green
        Write-Host "Server Cycling Complete!" -ForegroundColor Green
        Write-Host "  Servers Added: $serversAdded" -ForegroundColor Cyan
        Write-Host "  Servers Removed: $serversRemoved" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Green

        return @{
            Success = $true
            ServersAdded = $serversAdded
            ServersRemoved = $serversRemoved
        }

    } catch {
        Write-Error "Server cycling failed: $_"
        Write-Host $_.ScriptStackTrace

        return @{
            Success = $false
            ServersAdded = $serversAdded
            ServersRemoved = $serversRemoved
            Error = $_.Exception.Message
        }
    }
}

function Invoke-Rke2AgentCycling {
    <#
    .SYNOPSIS
    Orchestrate agent node cycling with zero downtime

    .PARAMETER ClusterName
    Name of the RKE2 cluster

    .PARAMETER DnsDomain
    DNS domain for nodes

    .PARAMETER VmSize
    VM size for agents

    .PARAMETER MaxAgeDays
    Age threshold for cycling nodes

    .PARAMETER MaxAgentsPerRun
    Maximum number of agents to cycle per pipeline run (0 = unlimited)
    Prevents cycling all agents at once when pipeline runs infrequently

    .PARAMETER MaxConcurrentProvision
    Maximum concurrent VM provisions (for I/O throttling)

    .PARAMETER Rke2Version
    Specific RKE2 version to install (e.g., "v1.28.5+rke2r1"). If specified, takes precedence over Rke2Channel.

    .PARAMETER Rke2Channel
    RKE2 channel to use (stable, latest, testing, or specific minor like v1.28). Defaults to "stable".
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ClusterName,

        [Parameter(Mandatory = $true)]
        [string]$DnsDomain,

        [string]$VmSize = "large",

        [int]$MaxAgeDays = 14,

        [int]$MaxAgentsPerRun = 0,  # 0 = unlimited (cycle all aged agents)

        [int]$MaxConcurrentProvision = 1,

        [string]$Rke2Version = "",

        [string]$Rke2Channel = "stable"
    )

    $ErrorActionPreference = "Stop"

    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Agent Node Cycling: $ClusterName" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    $agentsAdded = 0
    $agentsRemoved = 0

    try {
        # Get old agents that need cycling (limited to MaxAgentsPerRun if specified)
        $oldAgents = Get-Rke2NodesToCycle `
            -ClusterName $ClusterName `
            -NodeType "agent" `
            -MaxAgeDays $MaxAgeDays `
            -MaxCount $MaxAgentsPerRun

        if ($oldAgents.Count -eq 0) {
            Write-Host "No agents need cycling (all are less than $MaxAgeDays days old)" -ForegroundColor Green
            return @{
                Success = $true
                AgentsAdded = 0
                AgentsRemoved = 0
                Message = "No agents need cycling"
            }
        }

        Write-Host "`nFound $($oldAgents.Count) agents to cycle:" -ForegroundColor Yellow
        if ($MaxAgentsPerRun -gt 0) {
            Write-Host "(Limited to $MaxAgentsPerRun oldest agents per run)" -ForegroundColor Cyan
        }
        $oldAgents | Format-Table Name, Age, Status, CreationTime | Out-String | Write-Host

        # Step 1: Provision new agents (sequential for I/O throttling)
        Write-Host "`n=== Step 1: Provisioning New Agents ===" -ForegroundColor Green

        for ($i = 0; $i -lt $oldAgents.Count; $i++) {
            Write-Host "`nProvisioning agent $($i + 1) of $($oldAgents.Count)..." -ForegroundColor Cyan

            Add-PxNodeToRke2Cluster `
                -ClusterName $ClusterName `
                -DnsDomain $DnsDomain `
                -VmSize $VmSize `
                -NodeType "agent" `
                -rke2Version $Rke2Version `
                -rke2Channel $Rke2Channel

            $agentsAdded++

            # Get the newly added agent
            $currentAgents = Get-ClusterInfo -ClusterName $ClusterName | Where-Object { $_.Roles -notcontains "control-plane" }
            $newAgent = $currentAgents | Sort-Object Age | Select-Object -First 1

            Write-Host "New agent: $($newAgent.Name)" -ForegroundColor Green

            # Wait for node to be ready
            Write-Host "Waiting for node to be ready..." -ForegroundColor Cyan
            Wait-K8NodeReady -NodeName $newAgent.Name -ClusterName $ClusterName -TimeoutSeconds 600

            # Short delay before next provision (I/O throttling)
            if ($i -lt $oldAgents.Count - 1) {
                Write-Host "Waiting 1 minute before next provision (I/O throttling)..." -ForegroundColor Yellow
                Start-Sleep -Seconds 60
            }
        }

        # Wait for all agents to be ready
        Write-Host "`nValidating all agents are ready..." -ForegroundColor Cyan
        Wait-AllAgentsReady -ClusterName $ClusterName -TimeoutMinutes 5

        # Step 2: Cordon all old agents
        Write-Host "`n=== Step 2: Cordoning Old Agents ===" -ForegroundColor Green

        $settings = Get-PxRke2SettingsFromEnvironment
        $kubeconfigPath = Join-Path $settings.clusterStorage "$ClusterName\remote.yaml"

        foreach ($agent in $oldAgents) {
            Write-Host "Cordoning: $($agent.Name)" -ForegroundColor Cyan
            kubectl --kubeconfig="$kubeconfigPath" cordon $agent.Name
        }

        # Wait a bit for scheduling to stabilize
        Write-Host "Waiting 60 seconds for pod scheduling to stabilize..." -ForegroundColor Yellow
        Start-Sleep -Seconds 60

        # Step 3: Drain and remove old agents (one at a time)
        Write-Host "`n=== Step 3: Draining and Removing Old Agents ===" -ForegroundColor Green

        foreach ($agent in $oldAgents) {
            Write-Host "`n==== Draining Agent: $($agent.Name) ====" -ForegroundColor Cyan

            # Get pod count before drain
            $podsOnNode = Get-PodsOnNode -ClusterName $ClusterName -NodeName $agent.Name |
                Where-Object { $_.OwnerKind -ne "DaemonSet" }
            Write-Host "Pods to evacuate: $($podsOnNode.Count)" -ForegroundColor Yellow

            # Categorize pods
            $daemonSets = $podsOnNode | Where-Object { $_.OwnerKind -eq "DaemonSet" }
            $statefulSets = $podsOnNode | Where-Object { $_.OwnerKind -eq "StatefulSet" }
            $deployments = $podsOnNode | Where-Object { $_.OwnerKind -eq "Deployment" }
            $standalone = $podsOnNode | Where-Object { $null -eq $_.OwnerKind }

            Write-Host "  - DaemonSets: $($daemonSets.Count)" -ForegroundColor Gray
            Write-Host "  - StatefulSets: $($statefulSets.Count)" -ForegroundColor Gray
            Write-Host "  - Deployments: $($deployments.Count)" -ForegroundColor Gray
            Write-Host "  - Standalone: $($standalone.Count)" -ForegroundColor Gray

            # Check PodDisruptionBudgets
            $pdbViolations = Get-PDBBlockers -ClusterName $ClusterName -NodeName $agent.Name
            if ($pdbViolations.Count -gt 0) {
                Write-Warning "PodDisruptionBudgets may block some evictions:"
                $pdbViolations | ForEach-Object {
                    Write-Warning "  - $($_.PDBName): $($_.DisruptionsAllowed) disruptions allowed"
                }
            }

            # Initiate drain with monitoring
            $drainResult = Start-NodeDrainWithMonitoring `
                -ClusterName $ClusterName `
                -NodeName $agent.Name `
                -TimeoutMinutes 30 `
                -GracePeriodSeconds 300 `
                -IgnoreDaemonSets $true `
                -DeleteEmptyDirData $true `
                -MonitoringIntervalSeconds 30

            if (-not $drainResult.Success) {
                Write-Warning "Drain had issues for $($agent.Name): $($drainResult.Error)"

                # Show remaining pods
                Write-Host "Remaining pods:" -ForegroundColor Yellow
                Get-PodsOnNode -ClusterName $ClusterName -NodeName $agent.Name | Format-Table Namespace, Name, Phase, Reason

                Write-Warning "Continuing with removal despite drain issues..."
            }

            # Validate cluster health before removal
            Start-Sleep -Seconds 30
            $unhealthyPods = Get-UnhealthyPods -ClusterName $ClusterName
            if ($unhealthyPods.Count -gt 0) {
                Write-Warning "Found $($unhealthyPods.Count) unhealthy pods after drain"
                $unhealthyPods | Select-Object -First 10 | Format-Table Namespace, Name, Phase, Reason
            }

            # Remove node (skip drain since we just did it)
            Write-Host "Removing node from cluster..." -ForegroundColor Cyan
            Remove-NodeFromPxRke2Cluster `
                -MachineName $agent.Name `
                -ClusterName $ClusterName `
                -SkipDrain $true

            $agentsRemoved++

            # Post-removal validation
            Write-Host "Validating cluster health..." -ForegroundColor Cyan
            $clusterHealth = Test-ClusterHealth -ClusterName $ClusterName
            if (-not $clusterHealth.Healthy) {
                Write-Warning "Cluster health check has warnings: $($clusterHealth.Error)"
            }

            # Delay before next agent
            Write-Host "Waiting 3 minutes before next agent..." -ForegroundColor Yellow
            Start-Sleep -Seconds 180
        }

        Write-Host "`n========================================" -ForegroundColor Green
        Write-Host "Agent Cycling Complete!" -ForegroundColor Green
        Write-Host "  Agents Added: $agentsAdded" -ForegroundColor Cyan
        Write-Host "  Agents Removed: $agentsRemoved" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Green

        return @{
            Success = $true
            AgentsAdded = $agentsAdded
            AgentsRemoved = $agentsRemoved
        }

    } catch {
        Write-Error "Agent cycling failed: $_"
        Write-Host $_.ScriptStackTrace

        return @{
            Success = $false
            AgentsAdded = $agentsAdded
            AgentsRemoved = $agentsRemoved
            Error = $_.Exception.Message
        }
    }
}

function Test-Imports {
    param (
        [bool] $useUnifi = $true
    )
    Import-Module ./Proxmox-Provisioning.psm1 -Force
    Import-Module ./Proxmox-Wrapper.psm1 -Force
    if ($useUnifi) {
        Import-Module ./Unifi.psm1 -Force
    }
}