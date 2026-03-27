<#
.SYNOPSIS
    Detects likely duplicates against known existing TestRail coverage (when provided).

.DESCRIPTION
    This check is best-effort and depends on coverage metadata being included in the
    test design object under one of the following shapes:
    - TestCases.existing_coverage.direct_cases[]
    - TestCases.coverage.direct_cases[]
    - TestCases.direct_cases[]
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [object]$TestCases,

    [Parameter(Mandatory = $true)]
    [object]$Policy
)

function Get-Prop {
    param([object]$Obj, [string]$Name)
    if ($null -eq $Obj) { return $null }
    if ($Obj -is [hashtable]) {
        if ($Obj.ContainsKey($Name)) { return $Obj[$Name] }
        return $null
    }
    if ($Obj.PSObject.Properties.Name -contains $Name) { return $Obj.$Name }
    return $null
}

function Normalize-New {
    param([object]$Obj)
    $n = Get-Prop $Obj "new_cases"
    if (-not $n) { $n = Get-Prop $Obj "NEW_CASES" }
    if (-not $n) { $n = @() }
    return @($n)
}

function Get-ExistingTitles {
    param([object]$Obj)

    $direct = $null
    $existingCoverage = Get-Prop $Obj "existing_coverage"
    if ($existingCoverage) { $direct = Get-Prop $existingCoverage "direct_cases" }

    if (-not $direct) {
        $cov = Get-Prop $Obj "coverage"
        if ($cov) { $direct = Get-Prop $cov "direct_cases" }
    }

    if (-not $direct) {
        $direct = Get-Prop $Obj "direct_cases"
    }

    if (-not $direct) { return @() }

    $titles = @()
    foreach ($c in @($direct)) {
        $t = Get-Prop $c "title"
        if ($t) { $titles += "$t" }
    }

    return @($titles | Where-Object { $_ -and $_.Trim() } | ForEach-Object { $_.Trim() } | Select-Object -Unique)
}

$existingTitles = @(Get-ExistingTitles -Obj $TestCases)
$newCases = @(Normalize-New -Obj $TestCases)

if ($existingTitles.Count -eq 0) {
    return @{
        name = "duplicate_detection"
        status = "Warn"
        details = @{
            message = "No existing coverage titles provided; cannot perform robust duplicate detection."
        }
    }
}

$existingLookup = @{}
foreach ($t in $existingTitles) {
    $existingLookup[$t.ToLowerInvariant()] = $true
}

$dupes = New-Object System.Collections.Generic.List[object]

$i = 0
foreach ($c in @($newCases)) {
    $i++
    $title = (Get-Prop $c "title")
    if (-not $title) { continue }
    if ($existingLookup.ContainsKey($title.ToLowerInvariant())) {
        $dupes.Add(@{ path = "new_cases[$i].title"; title = $title }) | Out-Null
    }
}

$status = if ($dupes.Count -gt 0) { "Fail" } else { "Pass" }

return @{
    name = "duplicate_detection"
    status = $status
    details = @{
        existing_direct_title_count = $existingTitles.Count
        duplicate_count = $dupes.Count
        duplicates = $dupes
    }
}

