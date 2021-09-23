
param (
	$clientId,
    $clientSecret,
	$userName,
    $password,
    $authUrl,
    $provisionUrl,
    $provisionGroup
)

[System.Environment]::SetEnvironmentVariable('API_CLIENT_ID', "$clientId",[System.EnvironmentVariableTarget]::User)
[System.Environment]::SetEnvironmentVariable('API_CLIENT_SECRET', "$clientSecret",[System.EnvironmentVariableTarget]::User)
[System.Environment]::SetEnvironmentVariable('API_USERNAME', "$userName",[System.EnvironmentVariableTarget]::User)
[System.Environment]::SetEnvironmentVariable('API_PASSWORD', "$password",[System.EnvironmentVariableTarget]::User)
[System.Environment]::SetEnvironmentVariable('API_AUTH_URL', "$authUrl",[System.EnvironmentVariableTarget]::User)
[System.Environment]::SetEnvironmentVariable('API_PROVISION_URL', "$provisionUrl",[System.EnvironmentVariableTarget]::User)
[System.Environment]::SetEnvironmentVariable('API_PROVISION_GROUP', "$provisionGroup",[System.EnvironmentVariableTarget]::User)

