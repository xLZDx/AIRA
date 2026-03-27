<#
.SYNOPSIS
    Exports AIRA design JSON to a TestRail-friendly Excel file.

.DESCRIPTION
    Uses the ImportExcel PowerShell module (https://github.com/dfinke/ImportExcel) when available.
    Field mapping is resolved with override precedence (overrides → plugins → core),
    defaulting to `core/templates/excel_mapping.json`.

.PARAMETER InputJson
    JSON string or file path containing the design output object.

.PARAMETER OutputPath
    Path to write the resulting .xlsx file.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputJson,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [string]$MappingPath = "core/templates/excel_mapping.json"
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path

function Resolve-RepoPath([string]$p) {
    if ([System.IO.Path]::IsPathRooted($p)) { return $p }
    return (Join-Path $repoRoot $p)
}

$configModule = Join-Path $repoRoot "core/modules/Aira.Config.psm1"
Import-Module $configModule -Force

if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
    throw "ImportExcel module is not installed. Install it with: Install-Module ImportExcel -Scope CurrentUser"
}

Import-Module ImportExcel -ErrorAction Stop

if ($PSBoundParameters.ContainsKey("MappingPath")) {
    $mappingFile = Resolve-RepoPath $MappingPath
} else {
    $resolved = Resolve-AiraResourcePath -Kind templates -Name "excel_mapping.json" -RepoRoot $repoRoot
    $mappingFile = if ($resolved) { $resolved } else { Resolve-RepoPath $MappingPath }
}
if (-not (Test-Path $mappingFile)) { throw "Excel mapping not found: $mappingFile" }
$mapping = Get-Content $mappingFile -Raw -Encoding UTF8 | ConvertFrom-Json

$design = if (Test-Path $InputJson) {
    Get-Content $InputJson -Raw -Encoding UTF8 | ConvertFrom-Json
} else {
    $InputJson | ConvertFrom-Json
}

function Get-PropValue {
    param([object]$Obj, [string]$Path)
    if (-not $Obj) { return $null }
    if (-not $Path) { return $null }
    $p = $Path
    if ($Obj.PSObject.Properties.Name -contains $p) { return $Obj.$p }
    return $null
}

function Format-Steps {
    param([object]$Steps)
    if (-not $Steps) { return "" }
    $lines = @()
    $i = 1
    foreach ($s in @($Steps)) {
        $act = if ($s.action) { $s.action } else { $s.content }
        $action = if ($act) { $act } else { "" }
        $expected = if ($s.expected) { $s.expected } else { "" }
        $lines += ("{0}. {1} | Expected: {2}" -f $i, $action, $expected).Trim()
        $i++
    }
    return ($lines -join "`n")
}

function Format-Array {
    param([object]$Value)
    if ($null -eq $Value) { return "" }
    if (($Value -is [array]) -or ($Value -is [System.Collections.IList])) {
        return ((@($Value) | ForEach-Object { "$_" }) -join ",")
    }
    return "$Value"
}

function Build-SheetRows {
    param([object[]]$Items, [object]$SheetMapping)
    $rows = @()
    foreach ($it in @($Items)) {
        $row = [ordered]@{}
        foreach ($col in @($SheetMapping.columns)) {
            $header = $col.header
            $path = $col.path
            $val = Get-PropValue -Obj $it -Path $path

            if ($path -eq "steps" -or $path -eq "new_steps") {
                $row[$header] = Format-Steps -Steps $val
            } elseif ($path -eq "prereq_case_ids") {
                $row[$header] = Format-Array -Value $val
            } else {
                $row[$header] = if ($null -eq $val) { "" } else { "$val" }
            }
        }
        $rows += [PSCustomObject]$row
    }
    return $rows
}

# Normalize design categories (support either snake_case or upper-case keys)
$n = if ($design.new_cases) { $design.new_cases } else { $design.NEW_CASES }
$newCases = if ($n) { $n } else { @() }

$e = if ($design.enhance_cases) { $design.enhance_cases } else { $design.ENHANCE_CASES }
$enhanceCases = if ($e) { $e } else { @() }

$p = if ($design.prereq_cases) { $design.prereq_cases } else { $design.PREREQ_CASES }
$prereqCases = if ($p) { $p } else { @() }

$resolvedOut = Resolve-RepoPath $OutputPath
$outDir = Split-Path -Parent $resolvedOut
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

Remove-Item $resolvedOut -Force -ErrorAction SilentlyContinue

# Sheet 1: New Cases
$sheet1 = $mapping.new_cases
$rows1 = Build-SheetRows -Items @($newCases) -SheetMapping $sheet1
$rows1 | Export-Excel -Path $resolvedOut -WorksheetName $sheet1.sheet_name -AutoSize -FreezeTopRow -BoldTopRow

# Sheet 2: Enhancements
$sheet2 = $mapping.enhance_cases
$rows2 = Build-SheetRows -Items @($enhanceCases) -SheetMapping $sheet2
$rows2 | Export-Excel -Path $resolvedOut -WorksheetName $sheet2.sheet_name -AutoSize -FreezeTopRow -BoldTopRow -Append

# Sheet 3: Prerequisites
$sheet3 = $mapping.prereq_cases
$rows3 = Build-SheetRows -Items @($prereqCases) -SheetMapping $sheet3
$rows3 | Export-Excel -Path $resolvedOut -WorksheetName $sheet3.sheet_name -AutoSize -FreezeTopRow -BoldTopRow -Append

@{
    status = "ok"
    output_path = $resolvedOut
    sheets = @($sheet1.sheet_name, $sheet2.sheet_name, $sheet3.sheet_name)
    counts = @{
        new_cases = @($newCases).Count
        enhance_cases = @($enhanceCases).Count
        prereq_cases = @($prereqCases).Count
    }
} | ConvertTo-Json -Depth 10

