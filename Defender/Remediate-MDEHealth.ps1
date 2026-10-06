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
.SYNOPSIS
    Conservative MDE health remediation for Windows 11.

.DESCRIPTION
    Attempts only low-risk recovery actions:
      - Starts Sense if it exists but is stopped.
      - Starts WinDefend if it exists but is stopped.
      - Requests a Defender security-intelligence update if stale.
      - Performs a post-remediation health check.

    This script does not:
      - Modify onboarding registry values.
      - Run an onboarding package.
      - Change Defender policy.
      - Disable tamper protection.
      - Change service startup types.
      - Change AV active/passive mode.
      - Add exclusions.

.NOTES
    Run as SYSTEM in 64-bit PowerShell.
    Save as UTF-8.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# Customer-adjustable threshold
$MaxSignatureAgeDays = 2

$Actions = [System.Collections.Generic.List[string]]::new()
$Failures = [System.Collections.Generic.List[string]]::new()

try {
    # ------------------------------------------------------------
    # 1. Verify Windows 11
    # ------------------------------------------------------------
    # <optional>
    # Exit if the operating system is not Windows 11 or Windows 10
   <# 
    $OS = Get-CimInstance -ClassName Win32_OperatingSystem
    if ($OS.Caption -notlike '*Windows 11*' -and $OS.Caption -notlike 'Windows 10*') {
        Write-Output "Not applicable: $($OS.Caption)"
        exit 0
    }
    #>

    # ------------------------------------------------------------
    # 2. Attempt to start the MDE sensor
    # ------------------------------------------------------------
    $SenseService = Get-Service -Name 'Sense' -ErrorAction SilentlyContinue

    if ($null -eq $SenseService) {
        $Failures.Add('Sense service missing; repair or onboarding required')
    }
    elseif ($SenseService.Status -ne 'Running') {
        try {
            Start-Service -Name 'Sense' -ErrorAction Stop
            Start-Sleep -Seconds 10

            $SenseService = Get-Service -Name 'Sense'

            if ($SenseService.Status -eq 'Running') {
                $Actions.Add('Started Sense')
            }
            else {
                $Failures.Add(
                    "Sense remained $($SenseService.Status)"
                )
            }
        }
        catch {
            $Failures.Add(
                "Could not start Sense: $($_.Exception.Message)"
            )
        }
    }

    # ------------------------------------------------------------
    # 3. Attempt to start Defender Antivirus
    # ------------------------------------------------------------
    $WinDefendService = Get-Service `
        -Name 'WinDefend' `
        -ErrorAction SilentlyContinue

    if ($null -eq $WinDefendService) {
        $Failures.Add('WinDefend service missing')
    }
    elseif ($WinDefendService.Status -ne 'Running') {
        try {
            Start-Service -Name 'WinDefend' -ErrorAction Stop
            Start-Sleep -Seconds 10

            $WinDefendService = Get-Service -Name 'WinDefend'

            if ($WinDefendService.Status -eq 'Running') {
                $Actions.Add('Started WinDefend')
            }
            else {
                $Failures.Add(
                    "WinDefend remained $($WinDefendService.Status)"
                )
            }
        }
        catch {
            $Failures.Add(
                "Could not start WinDefend: $($_.Exception.Message)"
            )
        }
    }

    # ------------------------------------------------------------
    # 4. Request a signature update when stale
    # ------------------------------------------------------------
    try {
        $MpStatus = Get-MpComputerStatus -ErrorAction Stop

        if (($null -eq $MpStatus.AntivirusSignatureAge) -or
            ([int]$MpStatus.AntivirusSignatureAge -gt
                $MaxSignatureAgeDays)) {

            Update-MpSignature -ErrorAction Stop
            $Actions.Add('Requested signature update')

            Start-Sleep -Seconds 15
        }
    }
    catch {
        $Failures.Add(
            "Signature update failed: $($_.Exception.Message)"
        )
    }

    # ------------------------------------------------------------
    # 5. Post-remediation verification
    # ------------------------------------------------------------
    $SenseService = Get-Service -Name 'Sense' -ErrorAction SilentlyContinue

    if (($null -eq $SenseService) -or
        ($SenseService.Status -ne 'Running')) {
        $Failures.Add('Sense unhealthy after remediation')
    }

    $OnboardingState = $null

    try {
        $OnboardingState = (
            Get-ItemProperty `
                -Path 'HKLM:\SOFTWARE\Microsoft\Windows Advanced Threat Protection\Status' `
                -Name 'OnboardingState' `
                -ErrorAction Stop
        ).OnboardingState

        if ([int]$OnboardingState -ne 1) {
            $Failures.Add(
                "OnboardingState=$OnboardingState; onboarding action required"
            )
        }
    }
    catch {
        $Failures.Add('Unable to verify MDE onboarding state')
    }

    try {
        $MpStatus = Get-MpComputerStatus -ErrorAction Stop

        if (-not $MpStatus.AMServiceEnabled) {
            $Failures.Add('Defender AV service remains disabled')
        }

        $ActiveModes = @('Normal', 'Active')

        if (($ActiveModes -contains [string]$MpStatus.AMRunningMode) -and
            (-not $MpStatus.RealTimeProtectionEnabled)) {
            $Failures.Add('Real-time protection remains disabled')
        }

        if (($null -eq $MpStatus.AntivirusSignatureAge) -or
            ([int]$MpStatus.AntivirusSignatureAge -gt
                $MaxSignatureAgeDays)) {
            $Failures.Add(
                "Signatures remain $($MpStatus.AntivirusSignatureAge) days old"
            )
        }
    }
    catch {
        $Failures.Add('Unable to verify Defender AV health')
    }

    # ------------------------------------------------------------
    # 6. Return remediation result
    # ------------------------------------------------------------
    $ActionText = if ($Actions.Count -gt 0) {
        $Actions -join '; '
    }
    else {
        'No local corrective action available'
    }

    if ($Failures.Count -gt 0) {
        $FailureText = $Failures -join '; '

        Write-Output (
            "Remediation incomplete: $ActionText | $FailureText"
        )

        exit 1
    }

    Write-Output "Remediation successful: $ActionText"
    exit 0
}
catch {
    $Message = $_.Exception.Message

    if ($Message.Length -gt 500) {
        $Message = $Message.Substring(0, 500)
    }

    Write-Output "Remediation failed: $Message"
    exit 1
}