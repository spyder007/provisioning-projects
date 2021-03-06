param (
    [Parameter(Mandatory=$true,Position=1)]
	$TemplateFile,
    [Parameter(Mandatory=$true, Position=2)]
    $HostHttpFolder,
    [Parameter(Mandatory=$true,Position=3)]
	$VariableFile,
    [Parameter(Position=4)]
    $OutputFolder="d:\\Virtual Machines\\",
    $provisionApi="http://docker-dev.gerega.net:9001/",
    [ValidateSet("physical", "virtual", "camera", "enduser")]
    [String]
    $provisionGroup,
    [String]
    $machineName=$null
)


## Grab the variables file
if (($null -ne $VariableFile) -and (Test-Path $VariableFile)) {
    $variables = Get-Content $VariableFile | ConvertFrom-Json    
}
else {
    Write-Error "Variable file is required";
    return -1;
}

if ($null -eq $machineName) {
    $machineName = $variables.vm_name
}

## Provision the machine in the Unifi Controller
$token = ./Get-AuthToken.ps1 -scope "unifi.ipmanager"
$newClient = ./Provision-UnifiClient.ps1 -authToken $token -apiUrl "$provisionApi" -group "$provisionGroup" -name "$($machineName)" -hostname "$($machineName)"

$macAddress = $newClient.data.mac.Replace(":", "")
Write-Host "Mac Address = $macAddress"

## crypt the password (unix style) so that it can go into the autoinstall folder
$cryptedPass = (echo "$($variables.password)" | openssl passwd -6 -salt "FFFDFSDFSDF" -stdin)

if (Test-Path "packerhttp") {
    Remove-Item -Force -Recurse "packerhttp"
}

# Copy the contents
mkdir "packerhttp" | Out-Null
Copy-Item -Recurse "$HostHttpFolder\*" "packerhttp"

$user_data_content = Get-Content "packerhttp\user-data"
$user_data_content = $user_data_content -replace "{{username}}", "$($variables.username)"
$user_data_content = $user_data_content -replace "{{crypted_password}}", "$cryptedPass"
$user_data_content = $user_data_content -replace "{{hostname}}", "$($machineName)"
$user_data_content | Set-Content "packerhttp\user-data"

packer build -var-file "$VariableFile" -var "http=packerhttp" -var "output_dir=$OutputFolder" -var "mac_address=$macAddress" -var "vm_name=$machineName" "$TemplateFile"

$vmFolder = [IO.Path]::Combine($OutputFolder, $machineName)

$vmcx = Get-ChildItem -Path "$vmFolder" -Recurse -Filter "*.vmcx"

Import-VM -Path "$($vmcx.FullName)"
Start-VM "$($machineName)"