param (
    [Parameter(Mandatory=$true)]
    $msAgentPAT,
    [Parameter(Mandatory=$true)]
    $msAgentOrgUrl="https://dev.azure.com/<your_org>",
    [Parameter()]
    $provisionApi="http://docker-dev.gerega.net:9001/",
    [Parameter()]
    $msAgentPool="Default",
    [Parameter()]
    $msAgentUrl="https://vstsagentpackage.azureedge.net/agent/2.184.2",
    [Parameter()]
    $msAgentFilename="vsts-agent-linux-x64-2.184.2.tar.gz",
    [Parameter()]
    $OutputFolder="d:\\Virtual Machines\\",
)

## Generate agent name
$agentDate=(Get-Date).ToString("yyMMdd")
$machineName = "agt-ubt-$agentDate"

$env:PKR_VAR_ms_agent_pat = "$msAgentPAT"
$env:PKR_VAR_ms_agent_url = "$msAgentUrl"
$env:PKR_VAR_ms_agent_filename = "$msAgentFilename"
$env:PKR_VAR_ms_agent_org_url= "$msAgentOrgUrl"
$env:PKR_VAR_ms_agent_pool = "$msAgentPool"

## Create and Provision agent
.\Build-Ubuntu.ps1 ".\templates\buildagents\ubuntu-2004.json" .\templates\buildagents\http\ .\templates\buildagents\buildagent.pkrvars -provisionGroup "virtual" -OutputFolder "$OutputFolder" -machineName $machineName

