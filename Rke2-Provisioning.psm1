function New-Rke2Cluster {
    <#
        .SYNOPSIS
        Create a new RKE2 cluster

        .DESCRIPTION
        Provision new RKE2 Servers and Agents in Hyper-V to create a new cluster

        .PARAMETER clusterName
        The name of the cluster to be created.  This will be used in naming templates for VMs and DNS Entries (if using Unifi)

        .PARAMETER dnsDomain
        The DNS 

        .PARAMETER type
        The type of node.  Current supported types are ubuntu-2204 and ubuntu-2004

        .PARAMETER OutputFolder
        The base folder where the VM information will be stored.

        .PARAMETER packerErrorAction
        The ErrorAction to use for the Packer Command.  Valid values are "cleanup", "abort", "ask", and "run-cleanup-provisioner".
        See https://developer.hashicorp.com/packer/docs/commands/build for information on the -on-error option details.

        .PARAMETER nodeSize
        This parameter is used to locate a pkrvars.hcl file in ./templates/ubuntu/docker/ which corresponds to the nodeSize.  It uses the
        following format: {nodeSize}-node.pkrvars.hcl.  If this file does not exist, the script will exit.  

        Node Size files are not included in this repository:  they must be created based on ./templates/ubuntu/docker/docker.pkrvars.hcl.template.

        .PARAMETER useUnifi
        If true, the machine will be provisioned using the Unifi module to request VM Network information.

        .EXAMPLE
        PS> .\Create-NewBuildAgent.ps1 -type ubuntu-2204 -OutputFolder "c:\my\virtualmachines"
    #>

    param (
        [Parameter(Mandatory=$true,Position=1)]
        $clusterName,
        [Parameter(Mandatory=$true,Position=2)]
        $dnsDomain,
        [Parameter()]
        [ValidateSet("ubuntu-2204")]
        $type = "ubuntu-2204",
        [ValidateSet("sm", "med")]
        $nodeSize="med",
        [ValidateSet("cleanup", "abort", "ask", "run-cleanup-provisioner")]
        $packerErrorAction = "cleanup",
        [Parameter()]
        $OutputFolder="d:\\Hyper-V\\",
        $serverNodeCount=3,
        $agentNodeCount=0,
        $nodeCountStart=1,
        [bool]$useUnifi = $true
    )
    
    Import-Module ./HyperV-Provisioning.psm1
    Import-Module powershell-yaml
    
    $rke2Settings = Get-Rke2Settings

    if (Test-Path "$($rke2Settings.clusterStorage)/$clusterName/node-token") {
        Write-Error "Cluster with name $clusterName already found.  Use Add-NodeToCluster or Remove-NodeFromRke2Cluster to manage."
        return
    }

    if (-not (Test-Path ".\templates\ubuntu\rke2\$nodeSize-server.pkrvars.hcl")) {
        Write-Error "Server Variable file not found: .\templates\ubuntu\rke2\$nodeSize-server.pkrvars.hcl"
        return
    }

    if (-not (Test-Path ".\templates\ubuntu\rke2\$nodeSize-agent.pkrvars.hcl")) {
        Write-Error "Agent Variable file not found: .\templates\ubuntu\rke2\$nodeSize-agent.pkrvars.hcl"
        return
    }
    
    $nodes = @()
    
    for ($i=$nodeCountStart; $i -lt $serverNodeCount + $nodeCountStart; $i++) {

        if ($i -eq $nodeCountStart) {
            $nodeType = "first-server"
        }
        else {
            $nodeType = "server"
        }
        $machineName = Get-Rke2NodeMachineName $clusterName $nodeType $i
        $nodeDetail = New-Rke2ClusterNode -machineName $machineName -clusterName $clusterName -dnsDomain $dnsDomain -vmtype $type -vmsize $nodeSize -nodeType $nodeType -OutputFolder $OutputFolder -packerErrorAction $packerErrorAction
   
        if ($nodeDetail.success) {
            $nodes += $nodeDetail;
            if ($useUnifi) {
                if ($nodeType -eq "first-server") {
                    $clusterDns = New-ClusterDns -clusterName "$clusterName" -dnsZone "$dnsDomain" -controlPlaneIps (,"$($nodeDetail.ipAddress)") -trafficIps (,"$($nodeDetail.ipAddress)")
                }
                else {
                    $clusterDns.controlPlane += @{
                        zoneName = "$dnsDomain"
                        hostName = "cp-$($clusterName)"
                        data = "$($nodeDetail.ipAddress)"
                    }
                    $clusterDns.traffic += @{
                        zoneName = "$dnsDomain"
                        hostName = "tfx-$($clusterName)"
                        data = "$($nodeDetail.ipAddress)"
                    }
                    $clusterDns = Update-ClusterDns $clusterDns
                }
            }
        }
    }

    $agentCountStart = $serverNodeCount + $nodeCountStart

    # Create Agents
    for ($i=$agentCountStart; $i -lt $agentNodeCount + $agentCountStart; $i++) {
        $machineName = Get-Rke2NodeMachineName $clusterName "agent" $i
        
        Write-Host "Building $machineName"
    
        $nodeDetail = New-Rke2ClusterNode -machineName $machineName -clusterName $clusterName -dnsDomain $dnsDomain -vmtype $type -vmsize $nodeSize -nodeType "agent" -OutputFolder $OutputFolder -packerErrorAction $packerErrorAction

        if ($nodeDetail.success) {
            $nodes += $nodeDetail;
            if ($useUnifi) {
                # Agents are traffic only
                $clusterDns.traffic += @{
                    zoneName = "$dnsDomain"
                    hostName = "tfx-$($clusterName)"
                    data = "$($nodeDetail.ipAddress)"
                }
                $clusterDns = Update-ClusterDns $clusterDns
            }
        }
    }
    
    $nodes | Format-Table
}

function Deploy-NewRke2ClusterNodes{
        <#
        .SYNOPSIS
        Create a set of docker-enabled Ubuntu nodes for a Kubernetes cluster.

        .DESCRIPTION
        Create a set of docker-enabled Ubuntu nodes for a Kubernetes cluster.  This script will provision multiple machines, using the nodeCount
        and nodeStart parameters to determine machine name.

        .PARAMETER baseName
        The base name of the VM nodes.  This name will be appended with a count, which is a six-digit hexidecimal representation of the
        VM.

        .PARAMETER type
        The type of node.  Current supported types are ubuntu-2204 and ubuntu-2004

        .PARAMETER OutputFolder
        The base folder where the VM information will be stored.

        .PARAMETER packerErrorAction
        The ErrorAction to use for the Packer Command.  Valid values are "cleanup", "abort", "ask", and "run-cleanup-provisioner".
        See https://developer.hashicorp.com/packer/docs/commands/build for information on the -on-error option details.

        .PARAMETER nodeSize
        This parameter is used to locate a pkrvars.hcl file in ./templates/ubuntu/docker/ which corresponds to the nodeSize.  It uses the
        following format: {nodeSize}-node.pkrvars.hcl.  If this file does not exist, the script will exit.  

        Node Size files are not included in this repository:  they must be created based on ./templates/ubuntu/docker/docker.pkrvars.hcl.template.

        .PARAMETER useUnifi
        If true, the machine will be provisioned using the Unifi module to request VM Network information.

        .EXAMPLE
        PS> .\Create-NewBuildAgent.ps1 -type ubuntu-2204 -OutputFolder "c:\my\virtualmachines"
        #>

    param (
        [Parameter(Mandatory=$true,Position=1)]
        $clusterName,
        [Parameter()]
        $dnsDomain = "domain.local",
        [Parameter()]
        [ValidateSet("ubuntu-2204")]
        $type = "ubuntu-2204",
        [ValidateSet("sm", "med")]
        $nodeSize="med",
        [ValidateSet("cleanup", "abort", "ask", "run-cleanup-provisioner")]
        $packerErrorAction = "cleanup",
        [Parameter()]
        $OutputFolder="d:\\Hyper-V\\",
        [bool]$useUnifi = $true
    )

    Import-Module ./HyperV-Provisioning.psm1
    if ($useUnifi) {
        Import-Module ./Unifi.psm1 -Force
    }
    Import-Module powershell-yaml   
    $rke2Settings = Get-Rke2Settings

    if (-not (Test-Path "$($rke2Settings.clusterStorage)$clusterName/node-token")) {
        Write-Error "Could not find server token."
        return;    
    }

    if ($useUnifi) {
        $clusterDns = Get-ClusterDns -clusterName $clusterName
    }

    # Get all of the current VM Nodes for this cluster
    $clusterInfo = Get-ClusterInfo $clusterName
    
    # Start servers at max plus 1.
    $newNodeStart = $clusterInfo.Stats.Maximum + 1
    # If we are going to hit the max node count, cycle back to the beginning
    if ($clusterInfo.Stats.Maximum + $clusterInfo.Stats.Count -ge [int]"0xfff") {
        $newNodeStart = 1
    }

    $nodes = @()
    $currentNodeIndex = 0;
    for ($i=$newNodeStart; $i -lt $clusterInfo.Stats.Count + $newNodeStart; $i++) {
        $currentNodeName = $clusterInfo.VirtualMachineNames[$currentNodeIndex];

        if ($currentNodeName.Contains("-agt-")) {
            $nodeType = "agent"
        }
        else {
            $nodeType = "server"
        }
        $machineName = Get-Rke2NodeMachineName $clusterName $nodeType $i

        Write-Host "Building $machineName to replace $($currentNodeName)"
        
        $nodeDetail = New-Rke2ClusterNode -machineName $machineName -clusterName $clusterName -dnsDomain $dnsDomain -vmtype $type -vmsize $nodeSize -nodeType $nodeType -OutputFolder $OutputFolder -packerErrorAction $packerErrorAction
        
        if (-not ($nodeDetail.success)) {
            Write-Error "Unable to provision server"
            return -1;
        }
        
        if ($useUnifi) {
            $oldNetInfo = Get-HyperVNetworkInfo -vmname $currentNodeName

            # replace the current server IP with the new server IP in both the traffic and control plane
            $clusterDns.traffic | ForEach-Object { if ($_.data -eq $oldNetInfo.IpV4Address) { $_.data = $nodeDetail.IpAddress } }
            $clusterDns.controlPlane | ForEach-Object { if ($_.data -eq $oldNetInfo.IpV4Address) { $_.data = $nodeDetail.IpAddress } }

            $clusterDns = Update-ClusterDns $clusterDns
        }
        
        Remove-NodeFromRke2Cluster -machineName $currentNodeName -clusterName $clusterName -useUnifi $useUnifi
        
        $nodes += $nodeDetail;
        $currentNodeIndex++;
    }

    $nodes | Format-Table
}
function Add-NodeToRke2Cluster {
    param(
        $clusterName,
        $dnsDomain,
        [ValidateSet("ubuntu-2204")]
        $vmType,
        $vmSize,
        [ValidateSet("server", "agent")]
        $nodeType,
        [ValidateSet("cleanup", "abort", "ask", "run-cleanup-provisioner")]
        $packerErrorAction = "cleanup",
        [Parameter()]
        $OutputFolder="d:\\Hyper-V\\",
        [bool] $useUnifi = $true
    )
    Import-Module ./HyperV-Provisioning.psm1
    
    if ($useUnifi) {
        Import-Module ./Unifi.psm1 -Force
    }
    Import-Module powershell-yaml   
    $rke2Settings = Get-Rke2Settings
    if (-not (Test-Path "$($rke2Settings.clusterStorage)/$clusterName/node-token")) {
        Write-Error "Could not find server token."
        return -1;    
    }

    $clusterInfo = Get-ClusterInfo $clusterName

    $nodeNumber = $clusterInfo.Stats.Maximum + 1
    if ($nodeNumber -gt [int]"0xfff") {
        $nodeNumber = 1
    }
    
    $machineName = Get-Rke2NodeMachineName $clusterName $nodeType $nodeNumber
    
    $nodeDetail = New-Rke2ClusterNode -machineName $machineName -clusterName $clusterName -dnsDomain $dnsDomain -vmType $vmType -vmSize $vmSize -nodeType $nodeType -OutputFolder $OutputFolder -packerErrorAction $packerErrorAction

    if ($nodeDetail.success) {
        if ($useUnifi) {
            $clusterDns = Get-ClusterDns -clusterName $clusterName
            if ($nodeType -eq "server") {
                $clusterDns.controlPlane += @{
                    zoneName = "$dnsDomain"
                    hostName = "cp-$($clusterName)"
                    data = "$($nodeDetail.ipAddress)"
                }
            }
                
            $clusterDns.traffic += @{
                zoneName = "$dnsDomain"
                hostName = "tfx-$($clusterName)"
                data = "$($nodeDetail.ipAddress)"
            }
            $clusterDns = Update-ClusterDns $clusterDns
        }
    }
}

function New-Rke2ClusterNode
{
    param (
        $machineName,
        $clusterName,
        $dnsDomain,
        [ValidateSet("ubuntu-2204")]
        $vmType,
        $vmSize,
        [ValidateSet("first-server", "server", "agent")]
        $nodeType,
        [ValidateSet("cleanup", "abort", "ask", "run-cleanup-provisioner")]
        $packerErrorAction = "cleanup",
        [Parameter()]
        $OutputFolder="d:\\Hyper-V\\"
    )
    $rke2Settings = Get-Rke2Settings
    if ($nodeType -ne "first-server") 
    {
        if (-not (Test-Path "$($rke2Settings.clusterStorage)/$clusterName/node-token")) {
            Write-Error "Could not find server token."
            return;    
        }
        $existingClusterToken = (Get-Content -Raw "$($rke2Settings.clusterStorage)/$clusterName/node-token")
    }
    $packerTemplate = ".\templates\ubuntu\$vmType.pkr.hcl"
    $httpFolder = ".\templates\ubuntu\basic\http\"
    
    if ($nodeType -eq "server" -or $nodeType -eq "first-server") {
        New-Rke2ServerConfig -machineName $machineName -clusterName $clusterName -dnsDomain $dnsDomain -existingClusterToken $existingClusterToken
        $packerVariables = ".\templates\ubuntu\rke2\$vmSize-server.pkrvars.hcl"
    }
    else {
        New-Rke2AgentConfig -machineName $machineName -clusterName $clusterName -dnsDomain $dnsDomain -existingClusterToken $existingClusterToken
        $packerVariables = ".\templates\ubuntu\rke2\$vmSize-agent.pkrvars.hcl"
    }  

    Write-Host "Building $machineName"
    $detail = Build-Ubuntu -TemplateFile "$packerTemplate" -HostHttpFolder "$httpFolder" -OutputFolder "$OutputFolder" -VariableFile "$packerVariables" -packerErrorAction "$packerErrorAction" -machineName "$machineName" -useUnifi $useUnifi

    if ($detail.Success -and $nodeType -eq "first-server") {
        Write-Host "Waiting 3 minutes to ensure the Server is up and running"
        Start-Sleep -Seconds 180

        if (Test-Path "c:\tmp") {
            Remove-Item -Recurse "c:\tmp"
        }
        if (-Not (Test-Path("$($rke2Settings.clusterStorage)/$clusterName"))) {
            New-Item -ItemType Directory "$($rke2Settings.clusterStorage)/$clusterName" | Out-Null
        }
        Invoke-Expression "scp -o `"StrictHostKeyChecking no`" -o `"UserKnownHostsFile c:\tmp`" -o `"CheckHostIP no`" $($detail.userName)@$($detail.ipAddress):rke2.yaml `"$($rke2Settings.clusterStorage)/$clusterName/rke2.yaml`""
        Invoke-Expression "scp -o `"StrictHostKeyChecking no`" -o `"UserKnownHostsFile c:\tmp`" -o `"CheckHostIP no`" $($detail.userName)@$($detail.ipAddress):node-token `"$($rke2Settings.clusterStorage)/$clusterName/node-token`""
        
        $config = (Get-Content -Raw "$($rke2Settings.clusterStorage)/$clusterName/rke2.yaml")
        $config = $config.Replace("https://127.0.0.1", "https://cp-$($clusterName).$($dnsDomain)")
        Set-Content -Path "$($rke2Settings.clusterStorage)/$clusterName/remote.yaml" -Value $config
        
        $existingClusterToken = (Get-Content -Raw "$($rke2Settings.clusterStorage)/$clusterName/node-token")
    }
    return $detail;
}

function Remove-NodeFromRke2Cluster {
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
    $rke2Settings = Get-Rke2Settings
    if (-not (Test-Path "$($rke2Settings.clusterStorage)/$clusterName/remote.yaml")) {
        Write-Error "Could not find remote kube configuration: $($rke2Settings.clusterStorage)/$clusterName/remote.yaml"
        return;    
    }
    
    Invoke-Expression "kubectl --kubeconfig `"$($rke2Settings.clusterStorage)/$clusterName/remote.yaml`" drain --ignore-daemonsets --delete-emptydir-data $machineName" | Out-Host
    Start-Sleep 30
    Invoke-Expression "kubectl --kubeconfig `"$($rke2Settings.clusterStorage)/$clusterName/remote.yaml`" delete node/$($machineName)" | Out-Host
    Remove-HyperVVm -machineName $machineName -useUnifi $useUnifi | Out-Host
}

function New-Rke2AgentConfig {
    <#
    .SYNOPSIS
    Generate a new server-config.yaml file which will be used to configure a server node.

    .DESCRIPTION
    Using the cluster name, retrieve the matching VMs and associated information

    .PARAMETER machineName
    Used to set the node-name for the RKE2 node

    .PARAMETER clusterName
    Used with dnsDomain to set tls-san values

    .PARAMETER dnsDomain
    Used to build alternative tls-san values

    .PARAMETER existingClusterToken
    Secret token for previously created server

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
    
    $agentConfig = convertfrom-yaml (get-content .\templates\ubuntu\rke2\configuration\agent-config.yaml -Raw)
    $agentConfig."node-name" = $machineName
    $agentConfig."server" = "https://$($serverUrl):9345"
    $agentConfig."token" = "$existingClusterToken"

    (ConvertTo-Yaml $agentConfig) | Set-Content -Path .\templates\ubuntu\rke2\files\agent-config.yaml
}

function New-Rke2ServerConfig {
    <#
    .SYNOPSIS
    Generate a new server-config.yaml file which will be used to configure a server node.

    .DESCRIPTION
    Using the cluster name, retrieve the matching VMs and associated information

    .PARAMETER machineName
    Used to set the node-name for the RKE2 node

    .PARAMETER clusterName
    Used with dnsDomain to set tls-san values

    .PARAMETER dnsDomain
    Used to build alternative tls-san values

    .PARAMETER existingClusterToken
    Secret token for previously created server

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

    $serverConfig = convertfrom-yaml (get-content .\templates\ubuntu\rke2\configuration\server-config.yaml -Raw)
    $serverConfig."node-name" = $machineName
    $serverConfig."tls-san" = @()
    $serverConfig."tls-san" += "cp-$clusterName"
    if (-not ([string]::IsNullOrWhiteSpace($dnsDomain))) {
        $serverConfig."tls-san" += "cp-$($clusterName).$($dnsDomain)";
    }
    if ($null -ne $existingClusterToken) {
        $serverConfig."token" = $existingClusterToken;
        $serverConfig."server" = "https://$($serverUrl):9345"
    }
    (ConvertTo-Yaml $serverConfig) | Set-Content -Path .\templates\ubuntu\rke2\files\server-config.yaml
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
    $clusterVmPrefix = Get-ClusterVmPrefix($clusterName)
    $currentNodes = Get-Vm "$clusterVmPrefix-*"

    $nodeStats = ($currentNodes | ForEach-Object { [int] ("0x{0}" -f $_.Name.Substring($_.Name.LastIndexOf("-") + 1)) } | Measure-Object -Max -Min)
    $currentNodeNames = $currentNodes | ForEach-Object { $_.Name }

    return @{
        ClusterName = $clusterName
        VirtualMachines = $currentNodes
        Stats = $nodeStats
        VirtualMachineNames = $currentNodeNames
    }
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
    $rke2Settings = Get-Rke2Settings
    return "{0}-{1}" -f $rke2Settings.nodePrefix, $clusterName
}

Function Get-Rke2Settings {
    <#
    .SYNOPSIS
    Get settings used for Rke2 Provisioning Module

    .DESCRIPTION
    Retrieve settings used for Rke2 Provisioning Module.  If set, these settings are stored in your environment variables.

    .EXAMPLE
    PS> Get-Rke2Settings
    #>
    param ()

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
    if ([string]::IsNullOrWhiteSpace($clusterStorage)){
        $clusterStorage = Resolve-Path "./rke2-servers"
    }
    return @{
        nodePrefix = "$nodePrefix"
        clusterStorage = "$clusterStorage"
    }
}

Function Set-Rke2Settings {
    param (
        $nodePrefix,
        $clusterStorage
    )

    if (-not (Test-Path $clusterStorage)) {
        Write-Error "Invalid Cluster Storage Path $clusterStorage"
        return;
    }

    $env:RKE2_PROVISION_NODE_PREFIX = "$nodePrefix"
    $env:RKE2_PROVISION_CLUSTER_STORAGE = "$clusterStorage"

    [System.Environment]::SetEnvironmentVariable('RKE2_PROVISION_NODE_PREFIX', "$nodePrefix", [System.EnvironmentVariableTarget]::User)
    [System.Environment]::SetEnvironmentVariable('RKE2_PROVISION_CLUSTER_STORAGE', "$clusterStorage", [System.EnvironmentVariableTarget]::User)
}