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

$authToken = ./Get-AuthToken.ps1 -scope "unifi.ipmanager"

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

$macAddress = $result.data.mac.Replace(":", "")

return $macAddress;