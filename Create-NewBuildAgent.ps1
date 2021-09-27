param (
    [Parameter(Mandatory=$true)]
    $msAgentPAT,
    [Parameter(Mandatory=$true)]
    $msAgentOrgUrl="https://dev.azure.com/<your_org>",
    [Parameter()]
    $msAgentPool="Default",
    [Parameter()]
    $msAgentUrl="https://vstsagentpackage.azureedge.net/agent/2.192.0",
    [Parameter()]
    $msAgentFilename="vsts-agent-linux-x64-2.192.0.tar.gz",
    [Parameter()]
    $OutputFolder="d:\\Virtual Machines\\"
)

## Generate agent name
$agentDate=(Get-Date).ToString("yyMMdd")
$machineName = "agt-ubt-$agentDate"

$env:PKR_VAR_ms_agent_pat = "$msAgentPAT"
[System.Environment]::SetEnvironmentVariable('PKR_VAR_ms_agent_pat', "$msAgentPAT",[System.EnvironmentVariableTarget]::User)
$env:PKR_VAR_ms_agent_url = "$msAgentUrl"
[System.Environment]::SetEnvironmentVariable('PKR_VAR_ms_agent_url', "$msAgentUrl",[System.EnvironmentVariableTarget]::User)
$env:PKR_VAR_ms_agent_filename = "$msAgentFilename"
[System.Environment]::SetEnvironmentVariable('PKR_VAR_ms_agent_filename', "$msAgentFilename",[System.EnvironmentVariableTarget]::User)
$env:PKR_VAR_ms_agent_org_url= "$msAgentOrgUrl"
[System.Environment]::SetEnvironmentVariable('PKR_VAR_ms_agent_org_url', "$msAgentOrgUrl",[System.EnvironmentVariableTarget]::User)
$env:PKR_VAR_ms_agent_pool_name = "$msAgentPool"
[System.Environment]::SetEnvironmentVariable('PKR_VAR_ms_agent_pool_name', "$msAgentPool",[System.EnvironmentVariableTarget]::User)

## Create and Provision agent
.\Build-Ubuntu.ps1 ".\templates\buildagents\ubuntu-2004.json" .\templates\buildagents\http\ .\templates\buildagents\buildagent.pkrvars -OutputFolder "$OutputFolder" -machineName $machineName
