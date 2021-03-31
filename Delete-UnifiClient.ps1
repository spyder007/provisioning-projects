param (
    [Parameter(Mandatory=$true)]
    $authToken,
    [Parameter(Mandatory=$true)]
    $apiUrl,
    [Parameter(Mandatory=$true)]
    $macAddress
)

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

return $result;