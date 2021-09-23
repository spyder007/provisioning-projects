param (
    [Parameter(Mandatory=$true)]
    $authToken,
    [Parameter(Mandatory=$true)]
    $macAddress
)

$apiUrl = [System.Environment]::GetEnvironmentVariable('API_PROVISION_URL',[System.EnvironmentVariableTarget]::User)

if ($null -eq $apiUrl) {
    return $true
}

$authToken = ./Get-AuthToken.ps1 -scope "unifi.ipmanager"

$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add("Authorization", "Bearer $authToken")

$body = @{
    group="$group"
    name="$name"
    hostName="$hostName"
    static_ip=$staticIp
    sync_dns=$syncDns
}

$apiUrl = $apiUrl.TrimEnd("/")

$bodyJson = $body | ConvertTo-Json

$result = Invoke-RestMethod "$apiUrl/client/$macAddress" -headers $headers -method Delete

if ($false -eq $result.Success) {
    Write-Error "Error deleting result: $($deleteResult.Errors)"
    return $false
}
return $true