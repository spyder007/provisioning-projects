Get-NetFirewallRule | ? { $_.DisplayGroup -like "*firewall*" } | Enable-NetFirewallRule