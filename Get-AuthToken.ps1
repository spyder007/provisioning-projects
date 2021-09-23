
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