<#
.SYNOPSIS
    Session management helper for AIRA v2.

.DESCRIPTION
    Thin wrapper over core/modules/Aira.Session.psm1 to create/load/update session checkpoints.

.EXAMPLE
    powershell ./core/scripts/session.ps1 -NewSession -JiraKey "MARD-719"

.EXAMPLE
    powershell ./core/scripts/session.ps1 -GetSession -SessionId "session_20240215_143022_MARD719"

.EXAMPLE
    powershell ./core/scripts/session.ps1 -UpdateCheckpoint -SessionId "session_..." -Name context -State CONTEXT_READY -Path "context/jira/MARD-719/context.md"
#>

[CmdletBinding(DefaultParameterSetName = "Help")]
param(
    [Parameter(ParameterSetName = "New", Mandatory = $true)]
    [switch]$NewSession,

    [Parameter(ParameterSetName = "Get", Mandatory = $true)]
    [switch]$GetSession,

    [Parameter(ParameterSetName = "Update", Mandatory = $true)]
    [switch]$UpdateCheckpoint,

    [Parameter(ParameterSetName = "New", Mandatory = $true)]
    [Parameter(ParameterSetName = "GetByJiraKey", Mandatory = $true)]
    [string]$JiraKey,

    [Parameter(ParameterSetName = "Get", Mandatory = $true)]
    [Parameter(ParameterSetName = "Update", Mandatory = $true)]
    [string]$SessionId,

    [Parameter(ParameterSetName = "Update", Mandatory = $true)]
    [ValidateSet("context", "analysis", "design", "validation")]
    [string]$Name,

    [Parameter(ParameterSetName = "Update")]
    [string]$State,

    [Parameter(ParameterSetName = "Update")]
    [string]$Path,

    [Parameter(ParameterSetName = "Update")]
    [string]$DataJson,

    [string]$SessionRoot = ".aira/sessions"
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$sessionModule = Join-Path $repoRoot "core/modules/Aira.Session.psm1"
Import-Module $sessionModule -Force

function Resolve-JsonInput {
    param([string]$Input)
    if (-not $Input) { return $null }
    $candidate = Join-Path $repoRoot $Input
    if (Test-Path $Input) {
        return (Get-Content $Input -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
    if (Test-Path $candidate) {
        return (Get-Content $candidate -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
    return ($Input | ConvertFrom-Json)
}

if ($NewSession) {
    $s = New-AiraSession -JiraKey $JiraKey -SessionRoot $SessionRoot
    $s | ConvertTo-Json -Depth 50
    exit 0
}

if ($GetSession) {
    $s = Get-AiraSession -SessionId $SessionId -SessionRoot $SessionRoot
    $s | ConvertTo-Json -Depth 50
    exit 0
}

if ($UpdateCheckpoint) {
    $data = Resolve-JsonInput -Input $DataJson
    $s = Update-Checkpoint -SessionId $SessionId -Name $Name -State $State -Path $Path -Data $data -SessionRoot $SessionRoot
    $s | ConvertTo-Json -Depth 50
    exit 0
}

Write-Host "No operation specified. Use -NewSession, -GetSession, or -UpdateCheckpoint." -ForegroundColor Yellow
exit 1

