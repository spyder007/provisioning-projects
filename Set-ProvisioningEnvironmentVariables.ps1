
param (
    $provisionUrl,
    $provisionGroup
)

[System.Environment]::SetEnvironmentVariable('API_PROVISION_URL', "$provisionUrl",[System.EnvironmentVariableTarget]::User)
[System.Environment]::SetEnvironmentVariable('API_PROVISION_GROUP', "$provisionGroup",[System.EnvironmentVariableTarget]::User)

