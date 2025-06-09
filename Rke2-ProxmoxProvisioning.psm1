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

    .EXAMPLE
    PS> Add-NodeToRke2Cluster -clusterName "test" -dnsDomain "domain.local" -vmSize "med" -nodeType "agent"
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
        [string] $vmNotes = ""
    )
    Test-Imports $useUnifi

    Import-Module powershell-yaml   
    $rke2Settings = Get-PxRke2Settings
    if (-not (Test-Path "$($rke2Settings.clusterStorage)/$clusterName/node-token")) {
        Write-Error "Could not find server token."
        return -1;    
    }
    
    $nodeDetail = New-PxRke2ClusterNode -clusterName $clusterName -dnsDomain $dnsDomain -vmSize $vmSize -nodeType $nodeType -packerErrorAction $packerErrorAction -useUnifi $useUnifi

    
    if ($nodeDetail.success) {
        if ($useUnifi) {
            $clusterDns = Get-ClusterDns -clusterName $clusterName
            # Servers get added to the cp-<cluster name>, while agents get added to tfx-<cluster name>
            if ($nodeType -eq "server" -or $nodeType -eq "first-server") {
                $clusterDns.controlPlane += @{
                    zoneName = "$dnsDomain"
                    hostName = "cp-$($clusterName)"
                    data     = "$($nodeDetail.ipAddress)"
                }
            }
            else {
                $clusterDns.traffic += @{
                    zoneName = "$dnsDomain"
                    hostName = "tfx-$($clusterName)"
                    data     = "$($nodeDetail.ipAddress)"
                }
            }
            $clusterDns = Update-ClusterDns $clusterDns
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

    .EXAMPLE
    PS> New-Rke2ClusterNode -machineName "test-srv-001" -clusterName "test" -dnsDomain "domain.local" -vmSize "med" -nodeType "agent"
    #>
    param (
        $clusterName,
        $dnsDomain,
        $vmSize,
        [ValidateSet("first-server", "server", "agent")]
        $nodeType,
        [ValidateSet("cleanup", "abort", "ask", "run-cleanup-provisioner")]
        $packerErrorAction = "cleanup",
        [bool] $useUnifi = $true
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
        $macAddress = Invoke-ProvisionUnifiClient -name "$($machineName)" -hostname "$($machineName)"
        if ($null -eq $macAddress) {
            Write-Host "Using random mac address"
        }
        else {
            $macAddress | Format-Table | Out-Host
            Write-Host "Mac Address = $($macAddress.RawMacAddress)"
        }
    }

    $vmSettings = Get-PxVmSettings -vmSize $vmSize  
    
    $success = Copy-PxVmTemplate -pxNode $rkeSettings.clusterNode -vmId $rkeSettings.baseVmId -name $machineName -vmDescription "RKE2 Node for $clusterName" -newIdMin $clusterInfo.MinVmId -newIdMax $clusterInfo.MaxVmId -macAddress $macAddress.MacAddress -cpuCores $vmSettings.cores -memory $vmSettings.memory -vmStorage $rkeSettings.clusterNodeStorage

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

    $extraPackerArguments = "";

    Write-Host "Building $machineName"
    $onError = "-on-error=$packerErrorAction"

    if ([string]::IsNullOrWhiteSpace($packerVariables)) {
        $extraVarFileArgument = ""
    }
    else {
        $extraVarFileArgument = "-var-file `"$packerVariables`""
    }

    #Read-Host "Press Enter to continue with Packer Build"
    Write-Host "Waiting 5 minutes before starting Packer Build to ensure Proxmox is ready..."
    Start-Sleep -Seconds (60 * 5)

    Invoke-Expression "packer init `"$packerTemplate`"" | Out-Host
    Invoke-Expression "packer build $onError -var-file `"$secretVariableFile`" $extraVarFileArgument $httpArgument $ExtraPackerArguments `"$packerTemplate`"" | Out-Host
    $success = ($global:LASTEXITCODE -eq 0);

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
    Using the cluster name, retrieve the matching VMs and associated information

    .PARAMETER machineName
    The VM Name to delete

    .PARAMETER clusterName
    Used to find cluster connection data to drain and delete node

    .PARAMETER useUnifi
    If true, use Unifi module to remove fixed IP records

    .EXAMPLE
    PS> Remove-NodeFromRke2Cluster -machineName "test-srv-001" -clusterName "test" -dnsDomain "domain.local" -existingClusterToken "secretTokenValue"
    #>
    param (
        $machineName,
        $clusterName,
        [bool]$useUnifi = $true
    )

    Test-Imports $useUnifi

    $rke2Settings = Get-PxRke2Settings
    if (-not (Test-Path "$($rke2Settings.clusterStorage)/$clusterName/remote.yaml")) {
        Write-Error "Could not find remote kube configuration: $($rke2Settings.clusterStorage)/$clusterName/remote.yaml"
        return;    
    }

    try {
        Invoke-K8Command "drain --ignore-daemonsets --delete-emptydir-data $machineName" -clusterName $clusterName -ErrorAction SilentlyContinue | Out-Host
    }
    catch {
        Write-Host "Exception calling kube drain: $_"
    }
    
    Write-Host "Wait 1 minutes before removing to ensure all services have come up."
    Start-Sleep 60

    if ($useUnifi) {
        # TODO: On remove, remove the DNS Entries for this machine...  need to be able to 
        #  get the IP address
        $clusterDns = Get-ClusterDns -clusterName $clusterName
        
        $nodeInfo = Invoke-K8CommandJson "get nodes" -clusterName $clusterName
        $ipAddress = $nodeInfo.items | Where-Object {$_.metadata.name -eq "gk-internal-srv-093" } | ForEach-Object { $_.status.addresses } | Where-Object { $_.type -eq "InternalIP" }

        # #remove the IP From the control plane
        $clusterDns.controlPlane = $clusterDns.controlPlane | Where-Object { $_.data -ne $ipAddress.address }
        $clusterDns.traffic = $clusterDns.traffic | Where-Object { $_.data -ne $ipAddress.address }

        $clusterDns = Update-ClusterDns $clusterDns
    }

    Invoke-K8Command "delete node/$($machineName)" -clusterName $clusterName | Out-Host

    # TODO - Stop and delete the VM from Proxmox, remove mac from Unifi
    Remove-PxVm -machinename $machineName -useUnifi $useUnifi 
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

    return @{
        nodePrefix          = "$nodePrefix"
        clusterStorage      = "$clusterStorage"
        secretsVariableFile = "$secretsVariableFile"
        baseVmId            = "$baseVmId"
        minVmId             = "$minVmId"    
        maxVmId             = "$maxVmId"
        clusterNode         = "$clusterNode"
        clusterNodeStorage  = "$clusterNodeStorage"
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