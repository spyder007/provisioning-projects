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
    $provisionGroup
)


## Grab the variables file
if ($null -ne $VariableFile) {
    $variables = Get-Content $VariableFile | ConvertFrom-Json    
}

## Provision the machine in the Unifi Controller
$token = ./Get-AuthToken.ps1 -scope "unifi.ipmanager"
$newClient = ./Provision-UnifiClient.ps1 -authToken $token -apiUrl "$provisionApi" -group "$provisionGroup" -name "$($variables.vm_name)" -hostname "$($variables.vm_name)"

$macAddress = $newClient.mac.Replace(":", "")
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
$user_data_content = $user_data_content -replace "{{hostname}}", "$($variables.vm_name)"
$user_data_content | Set-Content "packerhttp\user-data"

packer build -var-file "$VariableFile" -var "http=packerhttp" -var "`'output_dir=$OutputFolder`'" -var "\`mac_address=$macAddress`'" "$TemplateFile"

$vmcx = Get-ChildItem -Path "$OutputFolder" -Recurse -Filter "*.vmcx"

Import-VM -Path "$($vmcx.FullName)"