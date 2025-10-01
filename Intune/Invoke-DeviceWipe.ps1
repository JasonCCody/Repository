<#
/////////////////////////////////////////////////////////////////////////////////////
//                                                                               
//  Disclaimer:                                                                  
//  The sample scripts are not supported under any Microsoft standard support    
//  program or service. The sample scripts are provided AS IS without warranty   
//  of any kind. Microsoft further disclaims all implied warranties including,   
//  without limitation, any implied warranties of merchantability or of fitness  
//  for a particular purpose. The entire risk arising out of the use or          
//  performance of the sample scripts and documentation remains with you. In no  
//  event shall Microsoft, its authors, or anyone else involved in the creation, 
//  production, or delivery of the scripts be liable for any damages whatsoever  
//  (including, without limitation, damages for loss of business profits,        
//  business interruption, loss of business information, or other pecuniary      
//  loss) arising out of the use of or inability to use the sample scripts or    
//  documentation, even if Microsoft has been advised of the  possibility of     
//  such damages.                                                                
//                                                                               
/////////////////////////////////////////////////////////////////////////////////////
#>

<# 
// !WARNING! THIS SCRIPT will remove all data from the device it is executed on!
>#

#######################################################
# remove OneDrive from device to prevent conflicts    #
#######################################################

if(Get-Process -Name OneDrive -ErrorAction SilentlyContinue){ Stop-Process -Name OneDrive -Force }
if(Test-Path C:\Windows\System32\OneDriveSetup.exe -ErrorAction SilentlyContinue){ & C:\Windows\System32\OneDriveSetup.exe /uninstall}
elseif(Test-Path C:\Windows\SysWOW64\OneDriveSetup.exe -ErrorAction SilentlyContinue){ & C:\Windows\SysWOW64\OneDriveSetup.exe /uninstall }


#######################################################
# create enablecustomizations.cmd in the oem folder   #
#######################################################

$path = "C:\recovery\oem"
If(!(test-path $path))
{
      New-Item -ItemType Directory -Force -Path $path
}


$content = @'
for /F "tokens=1,2,3 delims= " %%A in ('reg query "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\RecoveryEnvironment" /v TargetOS') DO SET TARGETOS=%%C
for /F "tokens=1 delims=\" %%A in ('Echo %TARGETOS%') DO SET TARGETOSDRIVE=%%A
if not exist "%TARGETOS%\Setup\Scripts\" mkdir "%TARGETOS%\Setup\Scripts"
rmdir /s /q C:\windows.old\users
'@

Out-File -FilePath c:\recovery\oem\CommonCustomizations.cmd  -Encoding utf8 -Force -InputObject $content -Confirm:$false


$MyPath = "c:\recovery\oem\CommonCustomizations.cmd"
$utf8 = New-Object System.Text.UTF8Encoding $false
$MyFile = Get-Content $MyPath -Raw
Set-Content -Value $utf8.GetBytes($MyFile) -Encoding Byte -Path $MyPath


#######################################################
# create ResetConfig.xml in the oem folder            #
#######################################################


$content2 = @'
<?xml version="1.0" encoding="utf-8"?>
<!-- ResetConfig.xml -->
<Reset>
  <Run Phase="BasicReset_AfterImageApply">
    <Path>CommonCustomizations.cmd</Path>
    <Duration>2</Duration>
  </Run>
  <Run Phase="FactoryReset_AfterImageApply">
    <Path>CommonCustomizations.cmd</Path>
    <Duration>2</Duration>
  </Run>
  <!-- May be combined with Recovery Media Creator
       configurations "" insert SystemDisk element here -->
</Reset>
'@

Out-File -FilePath c:\recovery\oem\ResetConfig.xml -Encoding utf8 -Force -InputObject $content2 -Confirm:$false

$MyPath = "c:\recovery\oem\ResetConfig.xml"
$utf8 = New-Object System.Text.UTF8Encoding $false
$MyFile = Get-Content $MyPath -Raw
Set-Content -Value $utf8.GetBytes($MyFile) -Encoding Byte -Path $MyPath


#######################################################
# begin the device wipe process                       #
#######################################################


$namespaceName = "root\cimv2\mdm\dmmap"
$className = "MDM_RemoteWipe"
$methodName = "doWipeProtectedMethod"
$InstanceID = "RemoteWipe"

$session = New-CimSession

$params = New-Object Microsoft.Management.Infrastructure.CimMethodParametersCollection
$param = [Microsoft.Management.Infrastructure.CimMethodParameter]::Create("param", "exec", "String", "In")
$params.Add($param)

try
{
    $instance = Get-CimInstance -Namespace $namespaceName -ClassName $className -Filter "ParentID='./Vendor/MSFT' and InstanceID='$InstanceID'"
    $session.InvokeMethod($namespaceName, $instance, $methodName, $params)
}
catch [Exception]
{
    write-host $_ | out-string
}
