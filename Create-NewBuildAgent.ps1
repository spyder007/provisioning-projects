param (
    [Parameter()]
    [ValidateSet("ubuntu-22.04", "ubuntu-20.04")]
    $type,
    [Parameter()]
    $OutputFolder="d:\\Virtual Machines\\"
)

## Generate agent name
$agentDate=(Get-Date).ToString("yyMMdd")
$machineName = "agt-ubt-$agentDate"

## Create and Provision agent
.\Build-Ubuntu.ps1 ".\templates\buildagents\$($type).pkr.hcl" .\templates\buildagents\http\ .\templates\buildagents\buildagent.pkrvars.hcl -OutputFolder "$OutputFolder" -machineName $machineName
