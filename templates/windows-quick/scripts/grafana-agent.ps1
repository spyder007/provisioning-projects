param (
    $machineName = ""
)

$s = New-PSSession -ComputerName $machineName
Enter-PSSession -Session $s

Invoke-Command -Session $s -ScriptBlock {
    if (Test-Path grafanatmp) {
        Remove-Item grafanatmp -Recurse -Force
    }

    Write-Host "Downloading Grafana Agent"
    mkdir grafanatmp
    Push-Location grafanatmp
    Invoke-WebRequest https://github.com/grafana/agent/releases/download/v0.32.1/grafana-agent-installer.exe.zip -o grafana-agent-installer.zip
    Expand-Archive grafana-agent-installer.zip -Force

    Push-Location grafana-agent-installer
    Write-Host "Installing Grafana Agent"
    Invoke-Expression ".\grafana-agent-installer.exe /S /D=C:\grafana-agent"

    Write-Host "Waiting for install to complete"
    Start-Sleep -seconds 10
    Pop-Location
    Pop-Location
    Remove-Item grafanatmp -Recurse -Force
}
## TODO: configure yaml automatically


Remove-PSSession -Session $s
