function Invoke-UnifiApiWithRetry {
    <#
    .SYNOPSIS
    Execute a script block with retry logic for transient failures

    .DESCRIPTION
    Wraps API calls with automatic retry logic, handling transient network
    and API failures with configurable retry attempts and delays

    .PARAMETER ScriptBlock
    The script block to execute

    .PARAMETER MaxRetries
    Maximum number of retry attempts (default: 3)

    .PARAMETER RetryDelaySeconds
    Delay between retry attempts (default: 10 seconds)

    .PARAMETER OperationName
    Descriptive name for the operation (for logging)

    .EXAMPLE
    PS> Invoke-UnifiApiWithRetry -ScriptBlock { Invoke-RestMethod $url } -OperationName "Get Cluster DNS"
    #>
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,

        [int]$MaxRetries = 3,

        [int]$RetryDelaySeconds = 10,

        [string]$OperationName = "Unifi API call"
    )

    $attempt = 0
    $lastError = $null

    while ($attempt -lt $MaxRetries) {
        $attempt++

        try {
            Write-Verbose "$OperationName (attempt $attempt/$MaxRetries)"
            $result = & $ScriptBlock
            return $result
        }
        catch {
            $lastError = $_
            Write-Warning "$OperationName failed (attempt $attempt/$MaxRetries): $($_.Exception.Message)"

            if ($attempt -lt $MaxRetries) {
                Write-Host "Retrying in $RetryDelaySeconds seconds..."
                Start-Sleep -Seconds $RetryDelaySeconds
            }
        }
    }

    throw "Operation '$OperationName' failed after $MaxRetries attempts. Last error: $lastError"
}

function Test-UnifiApiAvailable {
    <#
    .SYNOPSIS
    Check if the Unifi API is available and responding

    .DESCRIPTION
    Performs a health check on the Unifi API to verify availability before operations

    .PARAMETER TimeoutSeconds
    Maximum time to wait for health check response (default: 10 seconds)

    .EXAMPLE
    PS> Test-UnifiApiAvailable
    #>
    param(
        [int]$TimeoutSeconds = 10
    )

    $apiUrl = [System.Environment]::GetEnvironmentVariable('API_PROVISION_URL', [System.EnvironmentVariableTarget]::User)

    if ($null -eq $apiUrl) {
        Write-Warning "Unifi API URL not configured (API_PROVISION_URL environment variable)"
        return $false
    }

    try {
        # Try to get auth token as a basic health check
        $authToken = Get-AuthToken -scope "unifi.ipmanager"

        if ([string]::IsNullOrWhiteSpace($authToken)) {
            return $false
        }

        return $true
    }
    catch {
        Write-Warning "Unifi API health check failed: $($_.Exception.Message)"
        return $false
    }
}

Function Get-AuthToken {
    param (
        [Parameter(Mandatory = $true)]
        $scope,
        $clientId,
        $clientSecret,
        $userName,
        $password,
        $authUrl
    )

    $envVars = Get-AuthApiEnvironmentVariables

    if ([System.String]::IsNullOrWhiteSpace($clientId)) {
        $clientId = $envVars.clientId;
    }
    
    if ([System.String]::IsNullOrWhiteSpace($clientSecret)) {
        $clientSecret = $envVars.clientSecret
    }
    
    if ([System.String]::IsNullOrWhiteSpace($userName)) {
        $userName = $envVars.username;
    }
    
    if ([System.String]::IsNullOrWhiteSpace($password)) {
        $password = $envVars.password
    }
    
    if ([System.String]::IsNullOrWhiteSpace($authUrl)) {
        $authUrl = $envVars.authUrl
    }
    
    $body = @{
        grant_type    = "password"
        client_id     = "$clientId"
        client_secret = "$clientSecret"
        scope         = "$scope"
        username      = "$userName"
        password      = "$password"
    }

    $contentType = 'application/x-www-form-urlencoded'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $result = ConvertFrom-Json (Invoke-WebRequest -method Post -Uri "$authUrl" -body $body -ContentType $contentType -UseBasicParsing)
    
    return $result.access_token
}
Function Set-AuthAPIEnvironmentVariables {
    param (
        $clientId,
        $clientSecret,
        $userName,
        $password,
        $authUrl
    )

    $env:API_CLIENT_ID = "$clientId"
    $env:API_CLIENT_SECRET = "$clientSecret"
    $env:API_USERNAME = "$userName"
    $env:API_PASSWORD = "$password"
    $env:API_AUTH_URL = "$authUrl"

    [System.Environment]::SetEnvironmentVariable('API_CLIENT_ID', "$clientId", [System.EnvironmentVariableTarget]::User)
    [System.Environment]::SetEnvironmentVariable('API_CLIENT_SECRET', "$clientSecret", [System.EnvironmentVariableTarget]::User)
    [System.Environment]::SetEnvironmentVariable('API_USERNAME', "$userName", [System.EnvironmentVariableTarget]::User)
    [System.Environment]::SetEnvironmentVariable('API_PASSWORD', "$password", [System.EnvironmentVariableTarget]::User)
    [System.Environment]::SetEnvironmentVariable('API_AUTH_URL', "$authUrl", [System.EnvironmentVariableTarget]::User)
}

Function Get-AuthApiEnvironmentVariables {
    param()

    $clientId = $env:API_CLIENT_ID;
    if ($null -eq $clientId) {
        $clientId = [System.Environment]::GetEnvironmentVariable('API_CLIENT_ID', [System.EnvironmentVariableTarget]::User)   
    }

    $clientSecret = $env:API_CLIENT_SECRET
    if ($null -eq $clientSecret) {
        $clientSecret = [System.Environment]::GetEnvironmentVariable('API_CLIENT_SECRET', [System.EnvironmentVariableTarget]::User) 
    }

    $userName = $env:API_USERNAME
    if ($null -eq $userName) {
        $userName = [System.Environment]::GetEnvironmentVariable('API_USERNAME', [System.EnvironmentVariableTarget]::User)
    }


    $password = $env:API_PASSWORD
    if ($null -eq $password) {
        $password = [System.Environment]::GetEnvironmentVariable('API_PASSWORD', [System.EnvironmentVariableTarget]::User)
    }

    $authUrl = $env:API_AUTH_URL
    if ($null -eq $authUrl) {
        $authUrl = [System.Environment]::GetEnvironmentVariable('API_AUTH_URL', [System.EnvironmentVariableTarget]::User)
    }

    return @{
        clientId      = "$clientId"
        clientSecret  = "$clientSecret"
        username      = "$userName"
        password      = "$password"
        authUrl       = "$authUrl"
    }
}


Function Set-UnifiEnvironmentVariables {
    param (
        $provisionUrl
    )

    if (-not [System.String]::IsNullOrWhiteSpace($provisionUrl)) {
        $env:API_PROVISION_URL = "$provisionUrl"
        [System.Environment]::SetEnvironmentVariable('API_PROVISION_URL', "$provisionUrl", [System.EnvironmentVariableTarget]::User)
    }
}

Function Get-UnifiEnvironmentVariables {
    param()
    
    $apiUrl = $env:API_PROVISION_URL
    if ($null -eq $apiUrl) {
        $apiUrl = [System.Environment]::GetEnvironmentVariable('API_PROVISION_URL', [System.EnvironmentVariableTarget]::User)
    }

    return @{
        unifiUrl = "$apiUrl"
    }
}

Function Invoke-ProvisionUnifiClient {
    param (
        [Parameter(Mandatory = $true)]
        $name,
        [Parameter(Mandatory = $true)]
        $hostName,
        $staticIp = $true,
        $syncDns = $true,
        $network = "Lab"
    )

    $unifiVars = Get-UnifiEnvironmentVariables

    $apiUrl = $unifiVars.unifiUrl
    if ($null -eq $apiUrl) {
        return $null
    }

    # Use retry logic for provisioning
    return Invoke-UnifiApiWithRetry -OperationName "Provision Unifi client '$name'" -ScriptBlock {
        $authToken = Get-AuthToken -scope "unifi.ipmanager"

        $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
        $headers.Add("Authorization", "Bearer $authToken")

        $body = @{
            name      = "$name"
            hostName  = "$hostName"
            static_ip = $staticIp
            sync_dns  = $syncDns
            network   = "$network"
        }

        $apiUrl = $apiUrl.TrimEnd("/")

        $bodyJson = $body | ConvertTo-Json

        Write-Host "Provisioning with $apiUrl/client/provision"
        $result = Invoke-RestMethod "$apiUrl/client/provision" -headers $headers -method Post -Body $bodyJson -ContentType 'application/json' -SkipHttpErrorCheck -SkipCertificateCheck

        if ($false -eq $result.Success) {
            Write-Host "Error provisioning client: $($result | ConvertTo-Json -Depth 5)"
            throw "Error provisioning client: $($result.Errors)"
        }

        return @{
            RawMacAddress = $result.data.mac.Replace(":", "")
            MacAddress    = $result.data.mac
            IpAddress     = $result.data.fixed_ip
        }
    }
}

function New-ClusterDns {
    param (
        $clusterName,
        $dnsZone,
        $controlPlaneIps = @(),
        $trafficIps = @()
    )
    $apiUrl = [System.Environment]::GetEnvironmentVariable('API_PROVISION_URL', [System.EnvironmentVariableTarget]::User)

    if ($null -eq $apiUrl) {
        return $null
    }

    $requestData = @{
        name = "$clusterName"
        zoneName = "$dnsZone"
        controlPlaneIps = $controlPlaneIps
        trafficIps = $trafficIps
    }

    $authToken = Get-AuthToken -scope "unifi.ipmanager"

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Authorization", "Bearer $authToken")
    $headers.Add("Content-Type", "application/json")

    $apiUrl = $apiUrl.TrimEnd("/")
    $result = Invoke-RestMethod "$apiUrl/clusterdns" -headers $headers -method Post -Body (ConvertTo-Json $requestData)

    if ($false -eq $result.Success) {
        Write-Error "Error Creating new Cluster DNS: $($result.Errors)"
        return $false
    }
    return $result.data
}

function Get-ClusterDns {
    param(
        $clusterName,
        $dnsZone
    )
    $apiUrl = [System.Environment]::GetEnvironmentVariable('API_PROVISION_URL', [System.EnvironmentVariableTarget]::User)

    if ($null -eq $apiUrl) {
        return $null
    }

    
    $authToken = Get-AuthToken -scope "unifi.ipmanager"
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Authorization", "Bearer $authToken")

    $apiUrl = $apiUrl.TrimEnd("/")
    Write-Host "Retrieving clusterdns"
    $result = Invoke-RestMethod "$apiUrl/clusterdns/$($clusterName)?zone=$dnsZone" -headers $headers -method Get
    
    if ($false -eq $result.Success) {
        Write-Error "Error getting clients: $($result.Errors)"
        return $false
    }
    return $result.data
}

function Update-ClusterDns {
    param(
        $clusterDnsRecord
    )
    $apiUrl = [System.Environment]::GetEnvironmentVariable('API_PROVISION_URL', [System.EnvironmentVariableTarget]::User)

    if ($null -eq $apiUrl) {
        return $null
    }

    # Use retry logic for DNS updates
    return Invoke-UnifiApiWithRetry -OperationName "Update cluster DNS for '$($clusterDnsRecord.name)'" -ScriptBlock {
        $authToken = Get-AuthToken -scope "unifi.ipmanager"

        $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
        $headers.Add("Authorization", "Bearer $authToken")
        $headers.Add("Content-Type", "application/json")

        $apiUrl = $apiUrl.TrimEnd("/")

        $result = Invoke-RestMethod "$apiUrl/clusterdns/$($clusterDnsRecord.name)" -headers $headers -method Put -Body (ConvertTo-Json $clusterDnsRecord)

        if ($false -eq $result.Success) {
            $errorMessage = "Error updating Cluster DNS Record: $($result.Errors | ForEach-Object { $_ }) | $($result.messages | ForEach-Object { $_ })"
            throw $errorMessage
        }
        return $result.data
    }
}

Function Get-UnifiClients {
    $apiUrl = [System.Environment]::GetEnvironmentVariable('API_PROVISION_URL', [System.EnvironmentVariableTarget]::User)

    if ($null -eq $apiUrl) {
        return $true
    }

    $authToken = Get-AuthToken -scope "unifi.ipmanager"

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Authorization", "Bearer $authToken")

    $apiUrl = $apiUrl.TrimEnd("/")

    $result = Invoke-RestMethod "$apiUrl/client/" -headers $headers -method Get

    if ($false -eq $result.Success) {
        Write-Error "Error getting clients: $($result.Errors)"
        return $false
    }
    return $result.data
}
Function Remove-UnifiClient {
    param (
        [Parameter(Mandatory = $true)]
        $macAddress
    )

    $apiUrl = [System.Environment]::GetEnvironmentVariable('API_PROVISION_URL', [System.EnvironmentVariableTarget]::User)

    if ($null -eq $apiUrl) {
        return $true
    }

    # Use retry logic for client removal
    try {
        Invoke-UnifiApiWithRetry -OperationName "Remove Unifi client with MAC '$macAddress'" -ScriptBlock {
            Write-Host "Retrieving Auth Token"
            $authToken = Get-AuthToken -scope "unifi.ipmanager"

            $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
            $headers.Add("Authorization", "Bearer $authToken")

            $apiUrl = $apiUrl.TrimEnd("/")

            Write-Host "Deleting with $apiUrl/client/$macAddress"
            $result = Invoke-RestMethod "$apiUrl/client/$macAddress" -headers $headers -method Delete

            if ($false -eq $result.Success) {
                throw "Error deleting client: $($result.Errors)"
            }
            return $true
        }
        return $true
    }
    catch {
        Write-Error "Failed to remove Unifi client: $_"
        return $false
    }
}

function Get-UnifiNetworkInfo {
    param(
        [Parameter(Mandatory = $true)]
        $networkName
    )

    $apiUrl = [System.Environment]::GetEnvironmentVariable('API_PROVISION_URL', [System.EnvironmentVariableTarget]::User)

    if ($null -eq $apiUrl) {
        return $null
    }

    Write-Host "Retrieving Network Info for $networkName"

    # Use retry logic for network info retrieval
    try {
        return Invoke-UnifiApiWithRetry -OperationName "Get Unifi network info for '$networkName'" -ScriptBlock {
            $authToken = Get-AuthToken -scope "unifi.ipmanager"

            $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
            $headers.Add("Authorization", "Bearer $authToken")

            $apiUrl = $apiUrl.TrimEnd("/")

            Write-Debug "Getting with $apiUrl/network/$networkName"
            $result = Invoke-RestMethod "$apiUrl/network/$networkName" -headers $headers -method Get

            if ($false -eq $result.Success) {
                throw "Error getting network info: $($result.Errors)"
            }
            return $result.data
        }
    }
    catch {
        Write-Error "Failed to get network info: $_"
        return $null
    }
}

function Invoke-DnsRefresh {
    <#
    .SYNOPSIS
    Force DNS refresh on the DNS server

    .DESCRIPTION
    Restarts DNS services on the specified DNS server to force cache refresh.
    Requires SSH access to the DNS server.

    .PARAMETER DnsServerHost
    DNS server hostname or IP address (default: 192.168.1.18)

    .PARAMETER SshUser
    SSH username for DNS server access (default: admin)

    .EXAMPLE
    PS> Invoke-DnsRefresh -DnsServerHost "192.168.1.18"
    #>
    param(
        [string]$DnsServerHost = "192.168.1.18",
        [string]$SshUser = "admin"
    )

    Write-Host "Forcing DNS refresh on $DnsServerHost..."

    # Commands to restart DNS services
    $commands = @(
        "sudo systemctl restart systemd-resolved",
        "sudo systemctl restart nginx",
        "sleep 5"
    )

    foreach ($cmd in $commands) {
        try {
            $sshCommand = "ssh $SshUser@$DnsServerHost `"$cmd`""
            Invoke-Expression $sshCommand 2>&1 | Out-Null
            Write-Host "  Executed: $cmd"
        }
        catch {
            Write-Warning "  Failed to execute: $cmd - $_"
        }
    }

    Write-Host "DNS refresh complete"
}

function Wait-DnsRecord {
    <#
    .SYNOPSIS
    Wait for a DNS record to propagate and resolve to the expected IP

    .DESCRIPTION
    Polls DNS for a hostname until it resolves to the expected IP address.
    Includes automatic retry with DNS cache refresh if propagation fails.

    .PARAMETER Hostname
    The fully qualified domain name to resolve

    .PARAMETER ExpectedIp
    The expected IP address the hostname should resolve to

    .PARAMETER TimeoutSeconds
    Maximum time to wait for DNS propagation (default: 120 seconds)

    .PARAMETER DnsServer
    DNS server to query (default: 192.168.1.18)

    .PARAMETER PollIntervalSeconds
    How often to check DNS resolution (default: 5 seconds)

    .EXAMPLE
    PS> Wait-DnsRecord -Hostname "test-srv-001.lab.local" -ExpectedIp "192.168.1.100"
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Hostname,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedIp,

        [int]$TimeoutSeconds = 120,

        [string]$DnsServer = "192.168.1.18",

        [int]$PollIntervalSeconds = 5
    )

    $startTime = Get-Date
    $timeoutTime = $startTime.AddSeconds($TimeoutSeconds)

    Write-Host "Waiting for DNS record: $Hostname -> $ExpectedIp"

    while ((Get-Date) -lt $timeoutTime) {
        try {
            $resolved = Resolve-DnsName -Name $Hostname -Server $DnsServer -ErrorAction Stop

            # Handle multiple IP addresses in response
            $resolvedIps = @()
            foreach ($record in $resolved) {
                if ($record.IPAddress) {
                    $resolvedIps += $record.IPAddress
                }
            }

            if ($resolvedIps -contains $ExpectedIp) {
                $elapsed = [Math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)
                Write-Host "DNS record resolved successfully after $elapsed seconds"
                return $true
            }

            Write-Verbose "DNS returned: $($resolvedIps -join ', '), expected: $ExpectedIp"
        }
        catch {
            Write-Verbose "DNS resolution failed: $($_.Exception.Message)"
        }

        Start-Sleep -Seconds $PollIntervalSeconds
    }

    Write-Warning "DNS record did not propagate within $TimeoutSeconds seconds"

    # Force DNS refresh and try one more time
    Write-Host "Attempting DNS cache refresh..."
    Invoke-DnsRefresh -DnsServerHost $DnsServer
    Start-Sleep -Seconds 10

    try {
        $resolved = Resolve-DnsName -Name $Hostname -Server $DnsServer -ErrorAction Stop

        $resolvedIps = @()
        foreach ($record in $resolved) {
            if ($record.IPAddress) {
                $resolvedIps += $record.IPAddress
            }
        }

        if ($resolvedIps -contains $ExpectedIp) {
            Write-Host "DNS record resolved after forced refresh"
            return $true
        }
    }
    catch {
        Write-Verbose "DNS resolution still failed after refresh: $_"
    }

    Write-Error "DNS record failed to propagate: $Hostname -> $ExpectedIp"
    return $false
}
