<#
.SYNOPSIS
    Microsoft Defender for Endpoint health detection script for Windows 11.

.DESCRIPTION
    Designed for Microsoft Intune Remediations.

    Exit 0 = Healthy
    Exit 1 = Health issue detected; run remediation

.NOTES
    Run as SYSTEM in 64-bit PowerShell.
    Save as UTF-8.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# Customer-adjustable threshold
$MaxSignatureAgeDays = 2

$Issues = [System.Collections.Generic.List[string]]::new()
$Details = [ordered]@{
    Device             = $env:COMPUTERNAME
    OS                  = $null
    Sense               = 'Unknown'
    OnboardingState     = 'Unknown'
    AVMode              = 'Unknown'
    WinDefend           = 'Unknown'
    RealTimeProtection  = 'Unknown'
    SignatureAge        = 'Unknown'
    SignatureVersion    = 'Unknown'
    EngineVersion       = 'Unknown'
    PlatformVersion     = 'Unknown'
}

try {
    # ------------------------------------------------------------
    # 1. Operating system
    # ------------------------------------------------------------
    $OS = Get-CimInstance -ClassName Win32_OperatingSystem
    $Details.OS = $OS.Caption

    if ($OS.Caption -notlike '*Windows 11*') {
        Write-Output "Not applicable: $($OS.Caption)"
        exit 0
    }

    # ------------------------------------------------------------
    # 2. MDE Sense service
    # ------------------------------------------------------------
    $SenseService = Get-Service -Name 'Sense' -ErrorAction SilentlyContinue

    if ($null -eq $SenseService) {
        $Details.Sense = 'Missing'
        $Issues.Add('Sense service missing')
    }
    else {
        $Details.Sense = $SenseService.Status.ToString()

        if ($SenseService.Status -ne 'Running') {
            $Issues.Add("Sense service $($SenseService.Status)")
        }
    }

    # ------------------------------------------------------------
    # 3. MDE onboarding state
    # ------------------------------------------------------------
    $MDEStatusPath = 'HKLM:\SOFTWARE\Microsoft\Windows Advanced Threat Protection\Status'

    try {
        $MDEStatus = Get-ItemProperty `
            -Path $MDEStatusPath `
            -Name 'OnboardingState' `
            -ErrorAction Stop

        $Details.OnboardingState = [int]$MDEStatus.OnboardingState

        if ([int]$MDEStatus.OnboardingState -ne 1) {
            $Issues.Add("OnboardingState=$($MDEStatus.OnboardingState)")
        }
    }
    catch {
        $Details.OnboardingState = 'Missing'
        $Issues.Add('Onboarding state missing')
    }

    # ------------------------------------------------------------
    # 4. Defender Antivirus health
    # ------------------------------------------------------------
    try {
        $MpStatus = Get-MpComputerStatus -ErrorAction Stop
    }
    catch {
        $Issues.Add('Get-MpComputerStatus failed')
        throw
    }

    $Details.AVMode             = [string]$MpStatus.AMRunningMode
    $Details.WinDefend          = [string]$MpStatus.AMServiceEnabled
    $Details.RealTimeProtection = [string]$MpStatus.RealTimeProtectionEnabled
    $Details.SignatureAge       = [string]$MpStatus.AntivirusSignatureAge
    $Details.SignatureVersion   = [string]$MpStatus.AntivirusSignatureVersion
    $Details.EngineVersion      = [string]$MpStatus.AMEngineVersion
    $Details.PlatformVersion    = [string]$MpStatus.AMProductVersion

    if (-not $MpStatus.AMServiceEnabled) {
        $Issues.Add('Defender AV service disabled')
    }

    if ([string]:: {
        $Issues.Add('AV running mode unavailable')
    }

    # Require real-time protection only when Defender AV is active.
    # Passive mode can be healthy when a third-party AV is intended.
    $ActiveModes = @('Normal', 'Active')

    if (($ActiveModes -contains [string]$MpStatus.AMRunningMode) -and
        (-not $MpStatus.RealTimeProtectionEnabled)) {
        $Issues.Add('Real-time protection disabled')
    }

    # Validate update metadata.
    if ([string]::
            [string]$MpStatus.AntivirusSignatureVersion)) {
        $Issues.Add('Signature version missing')
    }

    if ([string]::
            [string]$MpStatus.AMEngineVersion)) {
        $Issues.Add('Engine version missing')
    }

    if ([string]::
            [string]$MpStatus.AMProductVersion)) {
        $Issues.Add('Platform version missing')
    }

    # AntivirusSignatureAge is measured in whole days.
    if ($null -eq $MpStatus.AntivirusSignatureAge) {
        $Issues.Add('Signature age unavailable')
    }
    elseif ([int]$MpStatus.AntivirusSignatureAge -gt $MaxSignatureAgeDays) {
        $Issues.Add(
            "Signatures $($MpStatus.AntivirusSignatureAge) days old"
        )
    }

    # ------------------------------------------------------------
    # 5. Return result to Intune
    # ------------------------------------------------------------
    if ($Issues.Count -gt 0) {
        $IssueText = $Issues -join '; '

        Write-Output (
            "Unhealthy: {0} | Sense={1}; Onboarding={2}; " +
            "AVMode={3}; RTP={4}; SigAge={5}"
        ) -f `
            $IssueText,
            $Details.Sense,
            $Details.OnboardingState,
            $Details.AVMode,
            $Details.RealTimeProtection,
            $Details.SignatureAge

        exit 1
    }

    Write-Output (
        "Healthy: Sense={0}; Onboarding=1; AVMode={1}; " +
        "RTP={2}; SigAge={3}; Sig={4}; Platform={5}"
    ) -f `
        $Details.Sense,
        $Details.AVMode,
        $Details.RealTimeProtection,
        $Details.SignatureAge,
        $Details.SignatureVersion,
        $Details.PlatformVersion

    exit 0
}
catch {
    $Message = $_.Exception.Message

    if ($Message.Length -gt 500) {
        $Message = $Message.Substring(0, 500)
    }

    Write-Output "Unhealthy: health check failed: $Message"
    exit 1
}