<#
.SYNOPSIS
    Validates prerequisite references (best-effort).
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

function Normalize-Prereq {
    param([object]$Obj)
    $p = Get-Prop $Obj "prereq_cases"
    if (-not $p) { $p = Get-Prop $Obj "PREREQ_CASES" }
    if (-not $p) { $p = @() }
    return @($p)
}

function Get-ExistingIds {
    param([object]$Obj)
    $existingCoverage = Get-Prop $Obj "existing_coverage"
    $direct = if ($existingCoverage) { Get-Prop $existingCoverage "direct_cases" } else { $null }
    $related = if ($existingCoverage) { Get-Prop $existingCoverage "related_cases" } else { $null }

    if (-not $direct) {
        $cov = Get-Prop $Obj "coverage"
        if ($cov) { $direct = Get-Prop $cov "direct_cases" }
        if (-not $direct) { $direct = Get-Prop $Obj "direct_cases" }
    }
    if (-not $related) {
        $cov = Get-Prop $Obj "coverage"
        if ($cov) { $related = Get-Prop $cov "related_cases" }
        if (-not $related) { $related = Get-Prop $Obj "related_cases" }
    }

    $ids = New-Object System.Collections.Generic.HashSet[int]
    foreach ($c in @($direct)) { if ($c -and (Get-Prop $c "id")) { [void]$ids.Add([int](Get-Prop $c "id")) } }
    foreach ($c in @($related)) { if ($c -and (Get-Prop $c "id")) { [void]$ids.Add([int](Get-Prop $c "id")) } }
    return @($ids)
}

$prereqs = Normalize-Prereq -Obj $TestCases
$issues = New-Object System.Collections.Generic.List[object]
$existingIds = Get-ExistingIds -Obj $TestCases
$existingLookup = @{}
foreach ($id in $existingIds) { $existingLookup[$id] = $true }

$seen = New-Object System.Collections.Generic.HashSet[int]

$i = 0
foreach ($p in @($prereqs)) {
    $i++
    $cid = Get-Prop $p "case_id"
    if ($null -eq $cid) {
        $issues.Add(@{ path = "prereq_cases[$i].case_id"; issue = "Missing" }) | Out-Null
        continue
    }

    try { $cidInt = [int]$cid } catch { $cidInt = $null }
    if ($null -eq $cidInt) {
        $issues.Add(@{ path = "prereq_cases[$i].case_id"; issue = "Not an integer"; value = $cid }) | Out-Null
        continue
    }

    if ($seen.Contains($cidInt)) {
        $issues.Add(@{ path = "prereq_cases[$i].case_id"; issue = "Duplicate prereq case_id"; value = $cidInt }) | Out-Null
        continue
    }
    [void]$seen.Add($cidInt)

    if ($existingIds.Count -gt 0 -and -not $existingLookup.ContainsKey($cidInt)) {
        $issues.Add(@{ path = "prereq_cases[$i].case_id"; issue = "Prereq not found in provided coverage lists"; value = $cidInt }) | Out-Null
    }
}

$status = if ($issues.Count -gt 0) { "Warn" } else { "Pass" }

return @{
    name = "prerequisite_exists"
    status = $status
    details = @{
        issue_count = $issues.Count
        issues = $issues
    }
}

