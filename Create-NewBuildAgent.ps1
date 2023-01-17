param (
    [Parameter()]
    [ValidateSet("ubuntu-2204", "ubuntu-2004")]
    $type,
    [Parameter()]
    $OutputFolder="d:\\Virtual Machines\\",
    [ValidateSet("cleanup", "abort", "ask", "run-cleanup-provisioner")]
    $packerErrorAction = "cleanup"
)

Import-Module ./HyperV-Provisioning.psm1

## Generate agent name
$agentDate=(Get-Date).ToString("yyMMdd")
$machineName = "agt-ubt-$agentDate"

## Create and Provision agent
Build-Ubuntu -TemplateFile ".\templates\buildagents\$($type).pkr.hcl" -HostHttpFolder ".\templates\buildagents\http\" -VariableFile ".\templates\buildagents\buildagent.pkrvars.hcl" -packerErrorAction "$packerErrorAction" -OutputFolder "$OutputFolder" -machineName $machineName
