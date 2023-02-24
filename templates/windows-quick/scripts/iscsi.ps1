Start-Service -Name MSiSCSI
Set-Service -Name MSiSCSI -StartupType Automatic

New-IscsiTargetPortal -TargetPortalAddress "192.168.1.30"
Connect-IscsiTarget -NodeAddress iqn.1991-05.com.microsoft:rx-7-iscsitarget01-target -IsPersistent $True 

# TODO: Set Disk Online



E:\Setup.exe /QS /SAPWD="" /ConfigurationFile="Config.ini" /IAcceptSQLServerLicenseTerms

