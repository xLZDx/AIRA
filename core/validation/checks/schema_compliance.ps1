<#
.SYNOPSIS
    Validates required JSON fields for AIRA test design output.

.PARAMETER TestCases
    The test case design object (should include new/enhance/prereq categories).

.PARAMETER Policy
    Effective policy object.
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

function Normalize-Categories {
    param([object]$Obj)
    $n = Get-Prop $Obj "new_cases"
    if (-not $n) { $n = Get-Prop $Obj "NEW_CASES" }
    if (-not $n) { $n = @() }

    $e = Get-Prop $Obj "enhance_cases"
    if (-not $e) { $e = Get-Prop $Obj "ENHANCE_CASES" }
    if (-not $e) { $e = @() }

    $p = Get-Prop $Obj "prereq_cases"
    if (-not $p) { $p = Get-Prop $Obj "PREREQ_CASES" }
    if (-not $p) { $p = @() }

    return @{ new_cases = @($n); enhance_cases = @($e); prereq_cases = @($p) }
}

function Is-NullOrEmptyString([object]$v) {
    return ($null -eq $v) -or (($v -is [string]) -and ([string]::IsNullOrWhiteSpace($v)))
}

$cats = Normalize-Categories -Obj $TestCases
$errors = New-Object System.Collections.Generic.List[object]

if ($null -eq $cats.new_cases) { $errors.Add(@{ path = "new_cases"; issue = "Missing category" }) | Out-Null }
if ($null -eq $cats.enhance_cases) { $errors.Add(@{ path = "enhance_cases"; issue = "Missing category" }) | Out-Null }
if ($null -eq $cats.prereq_cases) { $errors.Add(@{ path = "prereq_cases"; issue = "Missing category" }) | Out-Null }

# Validate NEW_CASES
$i = 0
foreach ($c in @($cats.new_cases)) {
    $i++
    if (Is-NullOrEmptyString (Get-Prop $c "title")) { $errors.Add(@{ path = "new_cases[$i].title"; issue = "Required" }) | Out-Null }
    if (Is-NullOrEmptyString (Get-Prop $c "priority")) { $errors.Add(@{ path = "new_cases[$i].priority"; issue = "Required" }) | Out-Null }
    if (Is-NullOrEmptyString (Get-Prop $c "type")) { $errors.Add(@{ path = "new_cases[$i].type"; issue = "Required" }) | Out-Null }
    if (Is-NullOrEmptyString (Get-Prop $c "references")) { $errors.Add(@{ path = "new_cases[$i].references"; issue = "Required" }) | Out-Null }

    $steps = Get-Prop $c "steps"
    if (-not $steps -or @($steps).Count -eq 0) {
        $errors.Add(@{ path = "new_cases[$i].steps"; issue = "At least 1 step required" }) | Out-Null
    } else {
        $sIdx = 0
        foreach ($s in @($steps)) {
            $sIdx++
            $act = Get-Prop $s "action"
            if (-not $act) { $act = Get-Prop $s "content" }
            $action = $act
            $expected = Get-Prop $s "expected"
            if (Is-NullOrEmptyString $action) { $errors.Add(@{ path = "new_cases[$i].steps[$sIdx].action"; issue = "Required" }) | Out-Null }
            if (Is-NullOrEmptyString $expected) { $errors.Add(@{ path = "new_cases[$i].steps[$sIdx].expected"; issue = "Required" }) | Out-Null }
        }
    }
}

# Validate ENHANCE_CASES
$i = 0
foreach ($c in @($cats.enhance_cases)) {
    $i++
    $id = Get-Prop $c "existing_case_id"
    if ($null -eq $id) { $errors.Add(@{ path = "enhance_cases[$i].existing_case_id"; issue = "Required" }) | Out-Null }
    if (Is-NullOrEmptyString (Get-Prop $c "existing_title")) { $errors.Add(@{ path = "enhance_cases[$i].existing_title"; issue = "Required" }) | Out-Null }
    if (Is-NullOrEmptyString (Get-Prop $c "rationale")) { $errors.Add(@{ path = "enhance_cases[$i].rationale"; issue = "Required" }) | Out-Null }
    if (Is-NullOrEmptyString (Get-Prop $c "updated_references")) { $errors.Add(@{ path = "enhance_cases[$i].updated_references"; issue = "Required" }) | Out-Null }

    $newSteps = Get-Prop $c "new_steps"
    if (-not $newSteps -or @($newSteps).Count -eq 0) {
        $errors.Add(@{ path = "enhance_cases[$i].new_steps"; issue = "At least 1 new step required" }) | Out-Null
    } else {
        $sIdx = 0
        foreach ($s in @($newSteps)) {
            $sIdx++
            $act = Get-Prop $s "action"
            if (-not $act) { $act = Get-Prop $s "content" }
            $action = $act
            $expected = Get-Prop $s "expected"
            if (Is-NullOrEmptyString $action) { $errors.Add(@{ path = "enhance_cases[$i].new_steps[$sIdx].action"; issue = "Required" }) | Out-Null }
            if (Is-NullOrEmptyString $expected) { $errors.Add(@{ path = "enhance_cases[$i].new_steps[$sIdx].expected"; issue = "Required" }) | Out-Null }
        }
    }
}

# Validate PREREQ_CASES
$i = 0
foreach ($c in @($cats.prereq_cases)) {
    $i++
    if ($null -eq (Get-Prop $c "case_id")) { $errors.Add(@{ path = "prereq_cases[$i].case_id"; issue = "Required" }) | Out-Null }
    if (Is-NullOrEmptyString (Get-Prop $c "title")) { $errors.Add(@{ path = "prereq_cases[$i].title"; issue = "Required" }) | Out-Null }
    if (Is-NullOrEmptyString (Get-Prop $c "usage")) { $errors.Add(@{ path = "prereq_cases[$i].usage"; issue = "Required" }) | Out-Null }
}

$status = if ($errors.Count -gt 0) { "Fail" } else { "Pass" }

return @{
    name = "schema_compliance"
    status = $status
    details = @{
        error_count = $errors.Count
        errors = $errors
    }
}

