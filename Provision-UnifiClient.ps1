param (
    [Parameter(Mandatory=$true)]
    $authToken,
    [Parameter(Mandatory=$true)]
    $apiUrl,
    [Parameter(Mandatory=$true)]
    $group,
    [Parameter(Mandatory=$true)]
    $name,
    [Parameter(Mandatory=$true)]
    $hostName,
    $staticIp=$true
)

$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add("Authorization", "Bearer $authToken")

$body = @{
    group="$group"
    name="$name"
    hostName="$hostName"
    static_ip=$staticIp
}

$apiUrl = $apiUrl.TrimEnd("/")

$bodyJson = $body | ConvertTo-Json

$result = Invoke-RestMethod "$apiUrl/client/provision" -headers $headers -method Post -Body $bodyJson -ContentType 'application/json'

return $result;