
$domainUser = $env:DOMAIN_USER;
$domainPass = $env:DOMAIN_PASS;
$domainName = $env:DOMAIN_NAME;
$machineName = $env:VM_MACHINE_NAME;

$PWord = ConvertTo-SecureString -String "$domainPass" -AsPlainText -Force
$Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $domainUser, $PWord

Add-Computer -DomainName "$domainName" -Credential $Credential

Rename-Computer -NewName "$machineName" -DomainCredential $Credential