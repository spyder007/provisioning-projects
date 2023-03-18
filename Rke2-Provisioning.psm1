function New-Rke2Cluster {
    <#
        .SYNOPSIS
        Create a new RKE2 cluster

        .DESCRIPTION
        Provision new RKE2 Servers and Agents in Hyper-V to create a new cluster

        .PARAMETER clusterName
        The name of the cluster to be created.  This will be used in naming templates for VMs and DNS Entries (if using Unifi)

        .PARAMETER dnsDomain
        The DNS to be used for the cluster registration url

        .PARAMETER type
        The type of node.  Current supported types are ubuntu-2204

        .PARAMETER serverNodeCount
        The number of Control Plane nodes to create

        .PARAMETER agentNodeCount
        The number of agent nodes to create

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
        PS> New-Rke2Cluster -type ubuntu-2204 -OutputFolder "c:\my\virtualmachines"
    #>

    param (
        [Parameter(Mandatory=$true,Position=1)]
        [string] $clusterName,
        [Parameter(Mandatory=$true,Position=2)]
        [string] $dnsDomain,
        [Parameter()]
        [ValidateSet("ubuntu-2204")]
        [string] $type = "ubuntu-2204",
        [ValidateSet("sm", "med")]
        [string] $nodeSize="med",
        [ValidateSet("cleanup", "abort", "ask", "run-cleanup-provisioner")]
        [string] $packerErrorAction = "cleanup",
        [Parameter()]
        [string] $OutputFolder="d:\\Hyper-V\\",
        [int] $serverNodeCount=3,
        [int] $agentNodeCount=0,
        [bool] $useUnifi = $true
    )
    
    Import-Module ./HyperV-Provisioning.psm1
    Import-Module powershell-yaml
    
    $rke2Settings = Get-Rke2Settings

    if (Test-Path "$($rke2Settings.clusterStorage)/$clusterName/node-token") {
        Write-Error "Cluster with name $clusterName already found.  Use Add-NodeToCluster or Remove-NodeFromRke2Cluster to manage."
        return
    }

    if (-not (Test-Path ".\templates\ubuntu-quick\rke2\$nodeSize-server.pkrvars.hcl")) {
        Write-Error "Server Variable file not found: .\templates\ubuntu-quick\rke2\$nodeSize-server.pkrvars.hcl"
        return
    }

    if (-not (Test-Path ".\templates\ubuntu-quick\rke2\$nodeSize-agent.pkrvars.hcl")) {
        Write-Error "Agent Variable file not found: .\templates\ubuntu-quick\rke2\$nodeSize-agent.pkrvars.hcl"
        return
    }
    
    $nodes = @()
    # This is a new cluster, always start at 1
    $nodeCountStart = 1

    for ($i=$nodeCountStart; $i -lt $serverNodeCount + $nodeCountStart; $i++) {

        if ($i -eq $nodeCountStart) {
            $nodeType = "first-server"
        }
        else {
            $nodeType = "server"
        }
        $machineName = Get-Rke2NodeMachineName $clusterName $nodeType $i
        $nodeDetail = New-Rke2ClusterNode -machineName $machineName -clusterName $clusterName -dnsDomain $dnsDomain -vmtype $type -vmsize $nodeSize -nodeType $nodeType -OutputFolder $OutputFolder -packerErrorAction $packerErrorAction -useUnifi $useUnifi
   
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
    
        $nodeDetail = New-Rke2ClusterNode -machineName $machineName -clusterName $clusterName -dnsDomain $dnsDomain -vmtype $type -vmsize $nodeSize -nodeType "agent" -OutputFolder $OutputFolder -packerErrorAction $packerErrorAction  -useUnifi $useUnifi

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
        Cycle nodes in the current cluster based on age.

        .DESCRIPTION
        Create a set of docker-enabled Ubuntu nodes for a Kubernetes cluster.  This script will provision multiple machines, using the nodeCount
        and nodeStart parameters to determine machine name.

        .PARAMETER clusterName
        The base name of the VM nodes.  This name will be appended with a count, which is a six-digit hexidecimal representation of the
        VM.

        .PARAMETER dnsDomain
        The domain to be used for the server url.

        .PARAMETER type
        The type of node.  Current supported types are ubuntu-2204

        .PARAMETER nodeSize
        This parameter is used to locate a pkrvars.hcl file in ./templates/ubuntu/docker/ which corresponds to the nodeSize.  It uses the
        following format: {nodeSize}-node.pkrvars.hcl.  If this file does not exist, the script will exit.  

        Node Size files are not included in this repository:  they must be created based on ./templates/ubuntu/docker/docker.pkrvars.hcl.template.

        .PARAMETER OutputFolder
        The base folder where the VM information will be stored.

        .PARAMETER packerErrorAction
        The ErrorAction to use for the Packer Command.  Valid values are "cleanup", "abort", "ask", and "run-cleanup-provisioner".
        See https://developer.hashicorp.com/packer/docs/commands/build for information on the -on-error option details.


        .PARAMETER useUnifi
        If true, the machine will be provisioned using the Unifi module to request VM Network information.

        .EXAMPLE
        PS>  Deploy-NewRke2ClusterNodes -clusterName "test" -dnsDomain "domain.local" -type ubuntu-2204 -OutputFolder "c:\my\virtualmachines"
        #>

    param (
        [Parameter(Mandatory=$true,Position=1)]
        [string] $clusterName,
        [Parameter()]
        [string] $dnsDomain = "domain.local",
        [Parameter()]
        [ValidateSet("ubuntu-2204")]
        [string] $type = "ubuntu-2204",
        [ValidateSet("sm", "med")]
        [string] $nodeSize="med",
        [ValidateSet("cleanup", "abort", "ask", "run-cleanup-provisioner")]
        [string] $packerErrorAction = "cleanup",
        [Parameter()]
        [string] $OutputFolder="d:\\Hyper-V\\",
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
        return;    
    }

    # Get all of the current VM Nodes for this cluster
    $clusterInfo = Get-ClusterInfo $clusterName
    $currentNames = $clusterInfo.VirtualMachineNames

    $nodes = @()
    $serverCount = ($currentNames | Where-Object { $_ -like "*-srv-*"} | Measure-Object).Count
    $agentCount = ($currentNames | Where-Object { $_ -like "*-agt-*"} | Measure-Object).Count

    for ($i = 0; $i -lt $serverCount; $i++) {
        $newServer = Add-NodeToRke2Cluster -clusterName $clusterName -dnsDomain $dnsDomain -vmType $type -vmSize $nodeSize -nodeType "server" -packerErrorAction $packerErrorAction -OutputFolder $OutputFolder -useUnifi $useUnifi
        if ($newServer.success) {
            $nodes += $newServer
        }
    }

    for ($i = 0; $i -lt $agentCount; $i++) {
        $newAgent = Add-NodeToRke2Cluster -clusterName $clusterName -dnsDomain $dnsDomain -vmType $type -vmSize $nodeSize -nodeType "agent" -packerErrorAction $packerErrorAction -OutputFolder $OutputFolder -useUnifi $useUnifi
        if ($newAgent.success) {
            $nodes += $newAgent
        }
    }

    if ($nodes.Count -lt ($serverCount + $agentCount)) {
        Write-Warning "Could not provision all new nodes.  Exiting."
        return $nodes;
    }

    foreach ($currentNodeName in $currentNames) {
        Remove-NodeFromRke2Cluster -machineName $currentNodeName -clusterName $clusterName -useUnifi $useUnifi
    }

    $nodes | Format-Table
}

function Cycle-Rke2ClusterNodes {
    <#
    .SYNOPSIS
    Cycle nodes in the current cluster

    .DESCRIPTION
    Create a set of docker-enabled Ubuntu nodes for a Kubernetes cluster.  This script will provision multiple machines, using the nodeCount
    and nodeStart parameters to determine machine name.

    .PARAMETER clusterName
    The base name of the VM nodes.  This name will be appended with a count, which is a six-digit hexidecimal representation of the
    VM.

    .PARAMETER dnsDomain
    The domain to be used for the server url.

    .PARAMETER type
    The type of node.  Current supported types are ubuntu-2204

    .PARAMETER nodeSize
    This parameter is used to locate a pkrvars.hcl file in ./templates/ubuntu/docker/ which corresponds to the nodeSize.  It uses the
    following format: {nodeSize}-node.pkrvars.hcl.  If this file does not exist, the script will exit.  

    Node Size files are not included in this repository:  they must be created based on ./templates/ubuntu/docker/docker.pkrvars.hcl.template.

    .PARAMETER OutputFolder
    The base folder where the VM information will be stored.

    .PARAMETER packerErrorAction
    The ErrorAction to use for the Packer Command.  Valid values are "cleanup", "abort", "ask", and "run-cleanup-provisioner".
    See https://developer.hashicorp.com/packer/docs/commands/build for information on the -on-error option details.


    .PARAMETER useUnifi
    If true, the machine will be provisioned using the Unifi module to request VM Network information.

    .EXAMPLE
    PS>  Deploy-NewRke2ClusterNodes -clusterName "test" -dnsDomain "domain.local" -type ubuntu-2204 -OutputFolder "c:\my\virtualmachines"
    #>

param (
    [Parameter(Mandatory=$true,Position=1)]
    [string] $clusterName,
    [Parameter()]
    [string] $dnsDomain = "domain.local",
    [Parameter()]
    [ValidateSet("ubuntu-2204")]
    [string] $type = "ubuntu-2204",
    [ValidateSet("sm", "med")]
    [string] $nodeSize="med",
    [ValidateSet("cleanup", "abort", "ask", "run-cleanup-provisioner")]
    [string] $packerErrorAction = "cleanup",
    [Parameter()]
    [string] $OutputFolder="d:\\Hyper-V\\",
    [bool] $useUnifi = $true,
    [int] $maxAgeDays = 14
)

    Import-Module ./HyperV-Provisioning.psm1
    if ($useUnifi) {
        Import-Module ./Unifi.psm1 -Force
    }
    Import-Module powershell-yaml   
    $rke2Settings = Get-Rke2Settings

    if (-not (Test-Path "$($rke2Settings.clusterStorage)/$clusterName/node-token")) {
        Write-Error "Could not find server token."
        return;    
    }

    # Get all of the current VM Nodes for this cluster
    Write-Host "Replacing nodes older than $maxAgeDays days"
    $nodesToReplace = Get-Rke2AgedNodes -clusterName $clusterName -maxAgeDays $maxAgeDays

    $nodes = @()

    foreach ($currentNodeName in $nodesToReplace) {
        Replace-ExistingRke2Node -currentNodeName $currentNodeName -clusterName $clusterName -dnsDomain $dnsDomain -type $type -nodeSize $nodeSize -OutputFolder $OutputFolder -packerErrorAction $packerErrorAction -useUnifi $useUnifi
    }

    $nodes | Format-Table
}

function Replace-ExistingRke2Node {
    param (
        [Parameter(Mandatory=$true,Position=1)]
        [string] $currentNodeName,
        [Parameter(Mandatory=$true,Position=2)]
        [string] $clusterName,
        [Parameter()]
        [string] $dnsDomain = "domain.local",
        [Parameter()]
        [ValidateSet("ubuntu-2204")]
        [string] $type = "ubuntu-2204",
        [ValidateSet("sm", "med")]
        [string] $nodeSize="med",
        [ValidateSet("cleanup", "abort", "ask", "run-cleanup-provisioner")]
        [string] $packerErrorAction = "cleanup",
        [Parameter()]
        [string] $OutputFolder="d:\\Hyper-V\\",
        [bool]$useUnifi = $true
    )
    if ($currentNodeName.Contains("-agt-")) {
        $nodeType = "agent"
    }
    else {
        $nodeType = "server"
    }

    $clusterInfo = Get-ClusterInfo $clusterName
    $nextNodeCount = $clusterInfo.Stats.Maximum + 1
    if ($nextNodeCount -gt [int]"0xfff") {
        $nextNodeCount = 1
    }

    $rke2Settings = Get-Rke2Settings
    Write-Host "Replacing $($currentNodeName)"
    
    $nodeDetail = Add-NodeToRke2Cluster -clusterName $clusterName -dnsDomain $dnsDomain -vmtype $type -vmsize $nodeSize -nodeType $nodeType -OutputFolder $OutputFolder -packerErrorAction $packerErrorAction -useUnifi $useUnifi
    
    if (-not ($nodeDetail.success)) {
        Write-Error "Unable to provision server"
        return $null;
    }
    $machineName = $nodeDetail.machineName

    $timeout = [DateTime]::UtcNow.AddMinutes(10);
    $ready = $false;
    Write-Host "Waiting until $timeout for node to become available."
    while ((-not $ready) -or ([DateTime]::UtcNow -gt $timeout)) {
        $nodeOutput = Invoke-Expression "kubectl --kubeconfig `"$($rke2Settings.clusterStorage)/$clusterName/remote.yaml`" get nodes -o json | ConvertFrom-Json"
        $newNodeDetails = $nodeOutput.items | Where-Object { $_.metadata.annotations."rke2.io/hostname" -eq "$machineName" }
        if ($null -ne $newNodeDetails) {
            $newNodeStatus = $newNodeDetails.status.conditions | Where-Object {$_.type -eq "Ready"}
            if ($null -ne $newNodeStatus) {
                $ready = ($newNodeStatus.status -eq $true)
            }
            else {
                Write-Warning "Unable to locate 'Ready' node condition";
            }
        }
        else {
            Write-Warning "Unable to locate node record for '$machineName'"
        }
        Start-Sleep -Seconds 30
    }

    if (-not $ready) {
        Write-Error "New node never reached ready.  Leaving old node."
        return $nodeDetail
    }
    else
    {
        Remove-NodeFromRke2Cluster -machineName $currentNodeName -clusterName $clusterName -useUnifi $useUnifi
        return $nodeDetail
    }

    
}

function Add-NodeToRke2Cluster {
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
    
    $nodeDetail = New-Rke2ClusterNode -machineName $machineName -clusterName $clusterName -dnsDomain $dnsDomain -vmType $vmType -vmSize $vmSize -nodeType $nodeType -OutputFolder $OutputFolder -packerErrorAction $packerErrorAction -useUnifi $useUnifi

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
    return $nodeDetail;
}

function New-Rke2ClusterNode
{
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
        $machineName,
        $clusterName,
        $dnsDomain,
        [ValidateSet("ubuntu-2204")]
        $vmType = "ubuntu-2204",
        $vmSize,
        [ValidateSet("first-server", "server", "agent")]
        $nodeType,
        [ValidateSet("cleanup", "abort", "ask", "run-cleanup-provisioner")]
        $packerErrorAction = "cleanup",
        [Parameter()]
        $OutputFolder="d:\\Hyper-V\\",
        [bool] $useUnifi=$true
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
    $packerTemplate = ".\templates\ubuntu-quick\$vmType.pkr.hcl"
    $httpFolder = ".\templates\ubuntu-quick\basic\http\"
    
    if ($nodeType -eq "server" -or $nodeType -eq "first-server") {
        New-Rke2ServerConfig -machineName $machineName -clusterName $clusterName -dnsDomain $dnsDomain -existingClusterToken $existingClusterToken
        $packerVariables = ".\templates\ubuntu-quick\rke2\$vmSize-server.pkrvars.hcl"
    }
    else {
        New-Rke2AgentConfig -machineName $machineName -clusterName $clusterName -dnsDomain $dnsDomain -existingClusterToken $existingClusterToken
        $packerVariables = ".\templates\ubuntu-quick\rke2\$vmSize-agent.pkrvars.hcl"
    }  

    $extraPackerArguments = "";
    if (-not [string]::IsNullOrWhiteSpace($rke2Settings.baseVmName)) {
        $extraPackerArguments = "--var baseVmName=`"$($rke2Settings.baseVmName)`""
    }
    if (-not [string]::IsNullOrWhiteSpace($rke2Settings.baseVmcxPath)) {
        $extraPackerArguments += " --var vmcx_path=`"$($rke2Settings.baseVmcxPath)`""
    }

    Write-Host "Building $machineName"
    $detail = Build-Ubuntu -TemplateFile "$packerTemplate" -HostHttpFolder "$httpFolder" -OutputFolder "$OutputFolder" -SecretVariableFile "$($rke2Settings.secretsVariableFile)" -packerErrorAction "$packerErrorAction" -machineName "$machineName" -useUnifi $useUnifi -ExtraVariableFile "$packerVariables" -ExtraPackerArguments "$extraPackerArguments"

    if ($detail.Success -and $nodeType -eq "first-server") {
        Write-Host "Waiting 3 minutes to ensure the Server is up and running"
        Start-Sleep -Seconds 60

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
    
    Write-Host "Wait 5 minutes before removing to ensure all services have come up."
    Start-Sleep 600

    if ($useUnifi) {
        $clusterDns = Get-ClusterDns -clusterName $clusterName
        $oldNetInfo = Get-HyperVNetworkInfo -vmname $machineName

        #remove the IP From the control plane
        $clusterDns.controlPlane = $clusterDns.controlPlane | Where-Object { $_.data -ne $oldNetInfo.IPv4Address }
        $clusterDns.traffic = $clusterDns.traffic | Where-Object { $_.data -ne $oldNetInfo.IPv4Address }

        $clusterDns = Update-ClusterDns $clusterDns
    }

    Invoke-Expression "kubectl --kubeconfig `"$($rke2Settings.clusterStorage)/$clusterName/remote.yaml`" delete node/$($machineName)" | Out-Host

    Remove-HyperVVm -machineName $machineName -useUnifi $useUnifi | Out-Host
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
    
    $agentConfig = convertfrom-yaml (get-content .\templates\ubuntu-quick\rke2\configuration\agent-config.yaml -Raw)
    $agentConfig."node-name" = $machineName
    $agentConfig."server" = "https://$($serverUrl):9345"
    $agentConfig."token" = "$existingClusterToken"

    (ConvertTo-Yaml $agentConfig) | Set-Content -Path .\templates\ubuntu-quick\rke2\files\agent-config.yaml
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

    $serverConfig = convertfrom-yaml (get-content .\templates\ubuntu-quick\rke2\configuration\server-config.yaml -Raw)
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
    (ConvertTo-Yaml $serverConfig) | Set-Content -Path .\templates\ubuntu-quick\rke2\files\server-config.yaml
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

    $rke2Settings = Get-Rke2Settings
    $cutoffDate = [DateTime]::UtcNow.AddDays($maxAgeDays * -1)
    $nodeOutput = Invoke-Expression "kubectl --kubeconfig `"$($rke2Settings.clusterStorage)/$clusterName/remote.yaml`" get nodes -o json | ConvertFrom-Json"
    $oldNodes = $nodeOutput.Items | Where-Object { $_.metadata.creationTimeStamp -lt $cutoffDate }
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

    $secretsVariableFile = $env:RKE2_PROVISION_SECRETS_FILE
    if ([string]::IsNullOrWhiteSpace($secretsVariableFile)) {
        $secretsVariableFile = [System.Environment]::GetEnvironmentVariable('RKE2_PROVISION_SECRETS_FILE', [System.EnvironmentVariableTarget]::User)
    }
    if ([string]::IsNullOrWhiteSpace($secretsVariableFile)){
        $secretsVariableFile = Resolve-Path "./rke2-servers/secrets.pkrvars.hcl"
    }

    $baseVmcxPath = $env:RKE2_PROVISION_BASE_VM_PATH
    if ([string]::IsNullOrWhiteSpace($baseVmcxPath)) {
        $baseVmcxPath = [System.Environment]::GetEnvironmentVariable('RKE2_PROVISION_BASE_VM_PATH', [System.EnvironmentVariableTarget]::User)
    }
    if ([string]::IsNullOrWhiteSpace($baseVmcxPath)){
        $baseVmcxPath = Resolve-Path "D:\"
    }

    $baseVmName = $env:RKE2_PROVISION_BASE_VM_NAME
    if ([string]::IsNullOrWhiteSpace($baseVmName)) {
        $baseVmName = [System.Environment]::GetEnvironmentVariable('RKE2_PROVISION_BASE_VM_NAME', [System.EnvironmentVariableTarget]::User)
    }
    if ([string]::IsNullOrWhiteSpace($baseVmName)){
        $baseVmName = "ubuntu-2204-base"
    }


    return @{
        nodePrefix = "$nodePrefix"
        clusterStorage = "$clusterStorage"
        secretsVariableFile = "$secretsVariableFile"
        baseVmcxPath = "$baseVmcxPath"
        baseVmName = "$baseVmName"
    }
}

Function Set-Rke2Settings {
    param (
        $nodePrefix,
        $clusterStorage,
        $secretsVariableFile,
        $baseVmcxPath,
        $baseVmName
    )

    if (-not (Test-Path $clusterStorage)) {
        Write-Error "Invalid Cluster Storage Path $clusterStorage"
        return;
    }

    if (-not (Test-Path $secretsVariableFile)) {
        Write-Error "Invalid Secrets Path $secretsVariableFile"
        return;
    }

    $env:RKE2_PROVISION_NODE_PREFIX = "$nodePrefix"
    $env:RKE2_PROVISION_CLUSTER_STORAGE = "$clusterStorage"
    $env:RKE2_PROVISION_SECRETS_FILE = "$secretsVariableFile"
    $env:RKE2_PROVISION_BASE_VM_PATH = "$baseVmcxPath"
    $env:RKE2_PROVISION_BASE_VM_NAME = "$baseVmName"

    [System.Environment]::SetEnvironmentVariable('RKE2_PROVISION_NODE_PREFIX', "$nodePrefix", [System.EnvironmentVariableTarget]::User)
    [System.Environment]::SetEnvironmentVariable('RKE2_PROVISION_CLUSTER_STORAGE', "$clusterStorage", [System.EnvironmentVariableTarget]::User)
    [System.Environment]::SetEnvironmentVariable('RKE2_PROVISION_SECRETS_FILE', "$secretsVariableFile", [System.EnvironmentVariableTarget]::User)
    [System.Environment]::SetEnvironmentVariable('RKE2_PROVISION_BASE_VM_PATH', "$baseVmcxPath", [System.EnvironmentVariableTarget]::User)
    [System.Environment]::SetEnvironmentVariable('RKE2_PROVISION_BASE_VM_NAME', "$baseVmName", [System.EnvironmentVariableTarget]::User)
}