param (
    $OutputFolder="d:\\Virtual Machines\\",
    $provisionApi="http://docker-dev.gerega.net:9001/",
    $msAgentPAT,
    $msAgentOrgUrl="https://dev.azure.com/<your_org>"
    $msAgentPool="Default",
    $msAgentUrl="https://vstsagentpackage.azureedge.net/agent/2.184.2",
    $msAgentFilename="vsts-agent-linux-x64-2.184.2.tar.gz"
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

