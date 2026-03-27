<#
.SYNOPSIS
    Runs AIRA validation checks against test case design JSON or context directories.

.DESCRIPTION
    Loads policies (.aira/*.policy.json) and runs enabled validation checks from:
    - core/validation/checks/
    - plugins/*/validation/checks/

    Supports two modes:
    1. Design validation (default) - validates test case design JSON
    2. Context validation - validates context directory for completeness, quality, safety

    Module import order matters for PowerShell 5.1:
      Common -> Validation -> Config  (Config MUST be last)

    The script outputs JSON to stdout and optionally writes to a file via -OutputPath.

.PARAMETER TestCasesJson
    Path to a design.json file, or a raw JSON string, containing the test cases object
    (must have new_cases / enhance_cases / prereq_cases structure).

.PARAMETER ContextPath
    Path to a context directory (e.g., context/local/AIRA/AIRA-3) to validate.
    When specified, runs context integrity validation instead of design validation.

.PARAMETER Promote
    When used with -ContextPath, promotes context from raw to processed if validation passes.

.PARAMETER UserApproved
    When used with -Promote, indicates user has reviewed and approved the context.
    Allows promotion despite High-severity findings (Critical still blocks).

.PARAMETER OutputPath
    Optional file path to write the validation results JSON.

.PARAMETER PolicyRoot
    Relative or absolute path to the policy directory (default: ".aira").

.EXAMPLE
    # Validate test case design:
    powershell -NoProfile -ExecutionPolicy Bypass -File core/scripts/validate.ps1 `
        -TestCasesJson "artifacts/MAV-1852/testrail/design.json"

.EXAMPLE
    # Validate context directory:
    powershell -NoProfile -ExecutionPolicy Bypass -File core/scripts/validate.ps1 `
        -ContextPath "context/local/AIRA/AIRA-3"

.EXAMPLE
    # Validate and promote context to processed:
    powershell -NoProfile -ExecutionPolicy Bypass -File core/scripts/validate.ps1 `
        -ContextPath "context/local/AIRA/AIRA-3" -Promote -UserApproved

.NOTES
    Always invoke via:  powershell -NoProfile -ExecutionPolicy Bypass -File core/scripts/validate.ps1 ...
    Do NOT use -Command for this script as variable names may be stripped.
#>

[CmdletBinding(DefaultParameterSetName = 'Design')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Design')]
    [string]$TestCasesJson,

    [Parameter(Mandatory = $true, ParameterSetName = 'Context')]
    [string]$ContextPath,

    [Parameter(ParameterSetName = 'Context')]
    [switch]$Promote,

    [Parameter(ParameterSetName = 'Context')]
    [switch]$UserApproved,

    [string]$OutputPath,

    [string]$PolicyRoot = ".aira"
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path

$commonModule     = Join-Path $repoRoot "core/modules/Aira.Common.psm1"
$validationModule = Join-Path $repoRoot "core/modules/Aira.Validation.psm1"
$configModule     = Join-Path $repoRoot "core/modules/Aira.Config.psm1"

# Import order matters for PowerShell 5.1 scope visibility:
#   1. Common   - shared helpers used by every other module
#   2. Validation - loads Common internally; does NOT import Config
#   3. Config   - MUST be last so Get-AiraPolicy stays in the script scope
Import-Module $commonModule     -Force -WarningAction SilentlyContinue
Import-Module $validationModule -Force -WarningAction SilentlyContinue
Import-Module $configModule     -Force -WarningAction SilentlyContinue

$policy = Get-AiraPolicy -PolicyRoot (Join-Path $repoRoot $PolicyRoot)

# --- Context validation mode ---
if ($PSCmdlet.ParameterSetName -eq 'Context') {
    $resolvedCtx = if ([System.IO.Path]::IsPathRooted($ContextPath)) {
        $ContextPath
    } else {
        (Join-Path $repoRoot $ContextPath)
    }

    if ($Promote) {
        $results = Invoke-AiraContextPromote -ContextPath $resolvedCtx -Policy $policy -UserApproved:$UserApproved
    } else {
        $results = Invoke-AiraContextValidation -ContextPath $resolvedCtx -Policy $policy
    }
}
# --- Design validation mode (default) ---
else {
    $testCases = if (Test-Path $TestCasesJson) {
        Get-Content $TestCasesJson -Raw -Encoding UTF8 | ConvertFrom-Json
    } else {
        $TestCasesJson | ConvertFrom-Json
    }

    $results = Invoke-AiraValidation -TestCases $testCases -Policy $policy
}

if ($OutputPath) {
    $resolvedOut = if ([System.IO.Path]::IsPathRooted($OutputPath)) { $OutputPath } else { (Join-Path $repoRoot $OutputPath) }
    $dir = Split-Path -Parent $resolvedOut
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $results | ConvertTo-Json -Depth 50 | Out-File -FilePath $resolvedOut -Encoding UTF8
}

$results | ConvertTo-Json -Depth 50

