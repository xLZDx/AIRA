Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "Aira.Common.psm1") -Force

function Write-AiraTelemetryEvent {
    <#
    .SYNOPSIS
        Append a telemetry event to `.aira/telemetry.jsonl` if opted-in by policy.

    .DESCRIPTION
        Telemetry is opt-in via `preferences.telemetry_opt_in` in the effective policy.
        Events must not include secrets (tokens/passwords).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Action,

        [string]$JiraKey,
        [string]$Outcome,
        [hashtable]$Data,
        [string]$RepoRoot
    )

    $root = if ($RepoRoot) { $RepoRoot } else { Get-AiraRepoRoot }

    # Load policy if available
    $optIn = $false
    try {
        $configModule = Join-Path $root "core/modules/Aira.Config.psm1"
        if (Test-Path $configModule) {
            Import-Module $configModule -Force -ErrorAction SilentlyContinue | Out-Null
            if (Get-Command Get-AiraEffectivePolicy -ErrorAction SilentlyContinue) {
                $policy = Get-AiraEffectivePolicy -PolicyRoot (Join-Path $root ".aira") -RepoRoot $root
                if ($policy.preferences -and ($policy.preferences.PSObject.Properties.Name -contains "telemetry_opt_in")) {
                    $optIn = [bool]$policy.preferences.telemetry_opt_in
                }
            } elseif (Get-Command Get-AiraPolicy -ErrorAction SilentlyContinue) {
                $policy = Get-AiraPolicy -PolicyRoot (Join-Path $root ".aira")
                if ($policy.preferences -and ($policy.preferences.PSObject.Properties.Name -contains "telemetry_opt_in")) {
                    $optIn = [bool]$policy.preferences.telemetry_opt_in
                }
            }
        }
    } catch {
        $optIn = $false
    }

    if (-not $optIn) { return $false }

    $path = Join-Path $root ".aira/telemetry.jsonl"
    $dir = Split-Path -Parent $path
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    $evt = @{
        timestamp = (Get-Date).ToString("s")
        action = $Action
        jira_key = $JiraKey
        outcome = $Outcome
        data = $Data
    }

    ($evt | ConvertTo-Json -Depth 20 -Compress) + "`n" | Out-File -FilePath $path -Encoding UTF8 -Append
    return $true
}

Export-ModuleMember -Function Write-AiraTelemetryEvent

