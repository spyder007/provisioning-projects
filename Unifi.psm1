

Function Get-AuthToken {
    param (
        [Parameter(Mandatory=$true)]
        $scope,
        $clientId,
        $clientSecret,
        $userName,
        $password,
        $authUrl
    )
    
    if ([System.String]::IsNullOrWhiteSpace($clientId)) {
        $clientId = $env:API_CLIENT_ID;
        if ($null -eq $clientId) {
            $clientId = [System.Environment]::GetEnvironmentVariable('API_CLIENT_ID',[System.EnvironmentVariableTarget]::User)   
        }
    }
    
    if ([System.String]::IsNullOrWhiteSpace($clientSecret)) {
        $clientSecret = $env:API_CLIENT_SECRET
        if ($null -eq $clientSecret) {
            $clientSecret = [System.Environment]::GetEnvironmentVariable('API_CLIENT_SECRET',[System.EnvironmentVariableTarget]::User) 
        }
    }
    
    if ([System.String]::IsNullOrWhiteSpace($userName)) {
        $userName = $env:API_USERNAME
        if ($null -eq $userName) {
            $userName = [System.Environment]::GetEnvironmentVariable('API_USERNAME',[System.EnvironmentVariableTarget]::User)
        }
    }
    
    if ([System.String]::IsNullOrWhiteSpace($password)) {
        $password = $env:API_PASSWORD
        if ($null -eq $password) {
            $password = [System.Environment]::GetEnvironmentVariable('API_PASSWORD',[System.EnvironmentVariableTarget]::User)
        }
    }
    
    if ([System.String]::IsNullOrWhiteSpace($authUrl)) {
        $authUrl = $env:API_AUTH_URL
        if ($null -eq $authUrl) {
            $authUrl = [System.Environment]::GetEnvironmentVariable('API_AUTH_URL',[System.EnvironmentVariableTarget]::User)
        }
    }
    
    $body = @{
        grant_type="password"
        client_id="$clientId"
        client_secret="$clientSecret"
        scope="$scope"
        username="$userName"
        password="$password"
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
    
    [System.Environment]::SetEnvironmentVariable('API_CLIENT_ID', "$clientId",[System.EnvironmentVariableTarget]::User)
    [System.Environment]::SetEnvironmentVariable('API_CLIENT_SECRET', "$clientSecret",[System.EnvironmentVariableTarget]::User)
    [System.Environment]::SetEnvironmentVariable('API_USERNAME', "$userName",[System.EnvironmentVariableTarget]::User)
    [System.Environment]::SetEnvironmentVariable('API_PASSWORD', "$password",[System.EnvironmentVariableTarget]::User)
    [System.Environment]::SetEnvironmentVariable('API_AUTH_URL', "$authUrl",[System.EnvironmentVariableTarget]::User)
}

Function Set-UnifiEnvironmentVariables {
    param (
        $provisionUrl,
        $provisionGroup
    )

    [System.Environment]::SetEnvironmentVariable('API_PROVISION_URL', "$provisionUrl",[System.EnvironmentVariableTarget]::User)
    [System.Environment]::SetEnvironmentVariable('API_PROVISION_GROUP', "$provisionGroup",[System.EnvironmentVariableTarget]::User)
}

Function Invoke-ProvisionUnifiClient {
    param (
        [Parameter(Mandatory=$true)]
        $name,
        [Parameter(Mandatory=$true)]
        $hostName,
        $staticIp=$true,
        $syncDns=$true
    )

    $apiUrl = $env:API_PROVISION_URL
    if ($null -eq $apiUrl) {
        $apiUrl = [System.Environment]::GetEnvironmentVariable('API_PROVISION_URL',[System.EnvironmentVariableTarget]::User)
    }


    if ($null -eq $apiUrl) {
        return $null
    }

    $provisionGroup = $env:API_PROVISION_GROUP
    if ($null -eq $provisionGroup) {
        $provisionGroup = [System.Environment]::GetEnvironmentVariable('API_PROVISION_GROUP',[System.EnvironmentVariableTarget]::User)
    }

    $authToken = Get-AuthToken -scope "unifi.ipmanager"

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Authorization", "Bearer $authToken")

    $body = @{
        group="$provisionGroup"
        name="$name"
        hostName="$hostName"
        static_ip=$staticIp
        sync_dns=$syncDns
    }

    $apiUrl = $apiUrl.TrimEnd("/")

    $bodyJson = $body | ConvertTo-Json

    $result = Invoke-RestMethod "$apiUrl/client/provision" -headers $headers -method Post -Body $bodyJson -ContentType 'application/json'

    return @{
        RawMacAddress = $result.data.mac.Replace(":", "")
        MacAddress = $result.data.mac
        IpAddress = $result.data.fixed_ip
    }
}

Function Get-UnifiClients {
    $apiUrl = [System.Environment]::GetEnvironmentVariable('API_PROVISION_URL',[System.EnvironmentVariableTarget]::User)

    if ($null -eq $apiUrl) {
        return $true
    }

    $authToken = Get-AuthToken -scope "unifi.ipmanager"

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Authorization", "Bearer $authToken")

    $apiUrl = $apiUrl.TrimEnd("/")

    $result = Invoke-RestMethod "$apiUrl/client/" -headers $headers -method Get

    if ($false -eq $result.Success) {
        Write-Error "Error deleting result: $($deleteResult.Errors)"
        return $false
    }
    return $result.data
}
Function Remove-UnifiClient {
    param (
        [Parameter(Mandatory=$true)]
        $macAddress
    )

    $apiUrl = [System.Environment]::GetEnvironmentVariable('API_PROVISION_URL',[System.EnvironmentVariableTarget]::User)

    if ($null -eq $apiUrl) {
        return $true
    }

    $authToken = Get-AuthToken -scope "unifi.ipmanager"

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Authorization", "Bearer $authToken")

    $apiUrl = $apiUrl.TrimEnd("/")

    try {
        $result = Invoke-RestMethod "$apiUrl/client/$macAddress" -headers $headers -method Delete
    }
    catch {
        Write-Host $_.Exception.ToString();
        return $false;
    }

    if ($false -eq $result.Success) {
        Write-Error "Error deleting result: $($deleteResult.Errors)"
        return $false
    }
    return $true
}