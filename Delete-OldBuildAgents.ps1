<#
    .SYNOPSIS
    Create a New Azure DevOps Build Agent (Ubuntu)

    .DESCRIPTION
    Create an Ubuntu Azure DevOps build agent.  This script utilizes provisioning from the GitHub Actions
    Runner Images repository (https://github.com/actions/runner-images).  Make sure you initialize the submodules
    in this repository before running this script.

    .PARAMETER OutputFolder
    The base folder where the VM information will be stored.

    .PARAMETER packerErrorAction
    The ErrorAction to use for the Packer Command.  Valid values are "cleanup", "abort", "ask", and "run-cleanup-provisioner".
    See https://developer.hashicorp.com/packer/docs/commands/build for information on the -on-error option details.

    .PARAMETER useUnifi
    If true, the machine will be provisioned using the Unifi module to request VM Network information.

#>

param (
    [string] $devOpsOrg,    
    [string] $devOpsUsername,
    [string] $devOpsPat,
    [string] $devOpsPool, 
    [bool] $useUnifi = $true
)

Import-Module ./HyperV-Provisioning.psm1

# Turn the string into a base64 encoded string
$bytes = [System.Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f ($devOpsUsername, $devOpsPat)))
$token = [System.Convert]::ToBase64String($bytes)
# Define a basic 'Authorization' header with the token
$headers = @{
    Authorization = "Basic {0}" -f ($token)
}

$poolSearch = Invoke-RestMethod -Uri "https://dev.azure.com/$($devOpsOrg)/_apis/distributedtask/pools?poolName=$($devOpsPool)" -Headers $headers

if ($poolSearch.count -eq 0) {
    Write-Host "Pool $devOpsPool not found"
    exit
}

$poolId = $poolSearch.value.id

$agents = Invoke-RestMethod -Uri "https://dev.azure.com/$($devOpsOrg)/_apis/distributedtask/pools/$($poolId)/agents" -Headers $headers

$agentNames = $agents.value | Select-Object -Property name, id

$vms = Get-Vm agt-ubt-* | Where-Object { $_.Name -in $agentNames.name }

if ($vms.Count -gt 1) {
    Write-Host "Removing old agents"

    $vms  | Select-Object -Property Name, @{ Name="Date"; Expression={[DateTime]::ParseExact($_.Name.Replace("agt-ubt-", ""), 'yyMMdd', $null)}} 
        | sort-object -property date | Select-Object -First ($vms.Count - 1) 
        | ForEach-Object {
            
            $machineName = $_.Name
            Write-Host "Removing $($machineName)"
            
            $devOpsRecord = $agentNames | Where-Object { $_.name -eq $machineName }
            $url = "https://dev.azure.com/$($devOpsOrg)/_apis/distributedtask/pools/$($poolId)/agents/$($devOpsRecord.id)?api-version=7.2-preview.1"
            Write-Debug "Url: $url"
            Invoke-RestMethod -Uri "$url" -Method DELETE -Headers $headers
            Remove-HyperVVm -machinename $($_.Name)
        }
}
else {
    Write-Host "No old agents to remove"
}
