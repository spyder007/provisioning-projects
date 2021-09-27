param (
    [Parameter()]
    $OutputFolder="d:\\Virtual Machines\\"
)

## Generate agent name
$agentDate=(Get-Date).ToString("yyMMdd")
$machineName = "agt-ubt-$agentDate"

## Create and Provision agent
.\Build-Ubuntu.ps1 ".\templates\buildagents\ubuntu-2004.json" .\templates\buildagents\http\ .\templates\buildagents\buildagent.pkrvars -OutputFolder "$OutputFolder" -machineName $machineName
