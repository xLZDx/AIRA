<#
.SYNOPSIS
    AIRA memory utilities (corrections + preferences).

.DESCRIPTION
    Wrapper over core/modules/Aira.Memory.psm1.
#>

[CmdletBinding(DefaultParameterSetName = "Help")]
param(
    [Parameter(ParameterSetName = "LogCorrection", Mandatory = $true)]
    [switch]$LogCorrection,

    [Parameter(ParameterSetName = "ShowPreferences", Mandatory = $true)]
    [switch]$ShowPreferences,

    [Parameter(ParameterSetName = "SetPreference", Mandatory = $true)]
    [switch]$SetPreference,

    [Parameter(ParameterSetName = "PromotePreferences", Mandatory = $true)]
    [switch]$PromotePreferences,

    [Parameter(ParameterSetName = "AddNote", Mandatory = $true)]
    [switch]$AddNote,

    [Parameter(ParameterSetName = "ShowNotes", Mandatory = $true)]
    [switch]$ShowNotes,

    [Parameter(ParameterSetName = "AddDirectPreference", Mandatory = $true)]
    [switch]$AddDirectPreference,

    [Parameter(ParameterSetName = "LogCorrection", Mandatory = $true)]
    [string]$Kind,

    [Parameter(ParameterSetName = "LogCorrection")]
    [string]$JiraKey,

    [Parameter(ParameterSetName = "LogCorrection")]
    [string]$BeforeJson,

    [Parameter(ParameterSetName = "LogCorrection")]
    [string]$AfterJson,

    [Parameter(ParameterSetName = "LogCorrection")]
    [string]$Rationale,

    [Parameter(ParameterSetName = "SetPreference", Mandatory = $true)]
    [Parameter(ParameterSetName = "AddDirectPreference", Mandatory = $true)]
    [string]$PreferenceJson,

    [Parameter(ParameterSetName = "AddDirectPreference")]
    [string]$PreferenceRationale,

    [Parameter(ParameterSetName = "AddDirectPreference")]
    [string]$PreferenceJiraKey,

    [Parameter(ParameterSetName = "AddNote", Mandatory = $true)]
    [ValidateSet("preference", "definition", "structure", "requirement", "convention", "general")]
    [string]$Category,

    [Parameter(ParameterSetName = "AddNote", Mandatory = $true)]
    [string]$Topic,

    [Parameter(ParameterSetName = "AddNote", Mandatory = $true)]
    [string]$Content,

    [Parameter(ParameterSetName = "AddNote")]
    [string]$NoteJiraKey,

    [Parameter(ParameterSetName = "AddNote")]
    [string[]]$Tags = @(),

    [Parameter(ParameterSetName = "ShowNotes")]
    [string]$FilterCategory,

    [Parameter(ParameterSetName = "ShowNotes")]
    [string]$FilterTopic,

    [Parameter(ParameterSetName = "ShowNotes")]
    [int]$Last = 0,

    [Parameter(ParameterSetName = "PromotePreferences")]
    [ValidateRange(1, 5000)]
    [int]$Window = 50,

    [Parameter(ParameterSetName = "PromotePreferences")]
    [ValidateRange(2, 100)]
    [int]$Threshold = 3,

    [Parameter(ParameterSetName = "PromotePreferences")]
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$memModule = Join-Path $repoRoot "core/modules/Aira.Memory.psm1"
Import-Module $memModule -Force

function ConvertTo-Hashtable($obj) {
    if ($null -eq $obj) { return $null }
    if ($obj -is [hashtable]) { return $obj }
    $ht = @{}
    foreach ($p in $obj.PSObject.Properties) {
        if ($p.Value -is [PSCustomObject]) { $ht[$p.Name] = ConvertTo-Hashtable $p.Value }
        elseif ($p.Value -is [System.Collections.IEnumerable] -and $p.Value -isnot [string]) {
            $ht[$p.Name] = @($p.Value | ForEach-Object { if ($_ -is [PSCustomObject]) { ConvertTo-Hashtable $_ } else { $_ } })
        }
        else { $ht[$p.Name] = $p.Value }
    }
    return $ht
}

function Parse-JsonMaybe([string]$JsonInput) {
    if (-not $JsonInput) { return $null }
    $candidate = Join-Path $repoRoot $JsonInput
    if (Test-Path $JsonInput) { return (ConvertTo-Hashtable (Get-Content $JsonInput -Raw -Encoding UTF8 | ConvertFrom-Json)) }
    if (Test-Path $candidate) { return (ConvertTo-Hashtable (Get-Content $candidate -Raw -Encoding UTF8 | ConvertFrom-Json)) }
    return (ConvertTo-Hashtable ($JsonInput | ConvertFrom-Json))
}

if ($LogCorrection) {
    $before = Parse-JsonMaybe -JsonInput $BeforeJson
    $after = Parse-JsonMaybe -JsonInput $AfterJson
    Add-AiraCorrection -Kind $Kind -JiraKey $JiraKey -Before $before -After $after -Rationale $Rationale -RepoRoot $repoRoot | Out-Null
    @{ status = "ok" } | ConvertTo-Json -Depth 5
    exit 0
}

if ($ShowPreferences) {
    (Get-AiraUserPreferences -RepoRoot $repoRoot) | ConvertTo-Json -Depth 50
    exit 0
}

if ($SetPreference) {
    $prefs = Parse-JsonMaybe -JsonInput $PreferenceJson
    if (-not $prefs) { throw "PreferenceJson must be valid JSON (string or file path)." }
    Set-AiraUserPreferences -Preferences $prefs -RepoRoot $repoRoot | Out-Null
    @{ status = "ok" } | ConvertTo-Json -Depth 5
    exit 0
}

if ($AddDirectPreference) {
    $prefs = Parse-JsonMaybe -JsonInput $PreferenceJson
    if (-not $prefs) { throw "PreferenceJson must be valid JSON (string or file path)." }
    $result = Add-AiraDirectPreference -Preference $prefs -Rationale $PreferenceRationale -JiraKey $PreferenceJiraKey -RepoRoot $repoRoot
    $result | ConvertTo-Json -Depth 10
    exit 0
}

if ($AddNote) {
    $result = Add-AiraUserNote -Category $Category -Topic $Topic -Content $Content -JiraKey $NoteJiraKey -Tags $Tags -RepoRoot $repoRoot
    $result | ConvertTo-Json -Depth 10
    exit 0
}

if ($ShowNotes) {
    $params = @{ RepoRoot = $repoRoot }
    if ($FilterCategory) { $params.Category = $FilterCategory }
    if ($FilterTopic)    { $params.TopicFilter = $FilterTopic }
    if ($Last -gt 0)     { $params.Last = $Last }
    $notes = Get-AiraUserNotes @params
    if (-not $notes -or $notes.Count -eq 0) {
        @{ notes = @(); count = 0 } | ConvertTo-Json -Depth 10
    } else {
        @{ notes = $notes; count = $notes.Count } | ConvertTo-Json -Depth 10
    }
    exit 0
}

if ($PromotePreferences) {
    (Promote-AiraPreferencesFromCorrections -RepoRoot $repoRoot -Window $Window -Threshold $Threshold -DryRun:$DryRun) | ConvertTo-Json -Depth 50
    exit 0
}

Write-Host "Usage:" -ForegroundColor Cyan
Write-Host "  powershell ./core/scripts/memory.ps1 -ShowPreferences" -ForegroundColor Gray
Write-Host "  powershell ./core/scripts/memory.ps1 -SetPreference -PreferenceJson '{\"testrail\":{\"defaults\":{\"priority\":\"High\"}}}'" -ForegroundColor Gray
Write-Host "  powershell ./core/scripts/memory.ps1 -AddDirectPreference -PreferenceJson '{\"testrail\":{\"defaults\":{\"priority\":\"High\"}}}' -PreferenceRationale 'user requested'" -ForegroundColor Gray
Write-Host "  powershell ./core/scripts/memory.ps1 -LogCorrection -Kind rename_case -JiraKey MARD-719 -BeforeJson '{\"title\":\"Old\"}' -AfterJson '{\"title\":\"New\"}' -Rationale 'better naming'" -ForegroundColor Gray
Write-Host "  powershell ./core/scripts/memory.ps1 -AddNote -Category definition -Topic 'AUM' -Content 'Assets Under Management'" -ForegroundColor Gray
Write-Host "  powershell ./core/scripts/memory.ps1 -ShowNotes [-FilterCategory definition] [-FilterTopic 'AUM'] [-Last 10]" -ForegroundColor Gray
Write-Host "  powershell ./core/scripts/memory.ps1 -PromotePreferences [-Window 50] [-Threshold 3] [-DryRun]" -ForegroundColor Gray
exit 1

