<#
.SYNOPSIS
    Ensures all steps include action + expected results.
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

function Is-NullOrEmptyString([object]$v) {
    return ($null -eq $v) -or (($v -is [string]) -and ([string]::IsNullOrWhiteSpace($v)))
}

function Normalize {
    param([object]$Obj)
    $n = Get-Prop $Obj "new_cases"
    if (-not $n) { $n = Get-Prop $Obj "NEW_CASES" }
    if (-not $n) { $n = @() }

    $e = Get-Prop $Obj "enhance_cases"
    if (-not $e) { $e = Get-Prop $Obj "ENHANCE_CASES" }
    if (-not $e) { $e = @() }

    return @{ new_cases = @($n); enhance_cases = @($e) }
}

$cats = Normalize -Obj $TestCases
$issues = New-Object System.Collections.Generic.List[object]

$i = 0
foreach ($c in @($cats.new_cases)) {
    $i++
    $steps = Get-Prop $c "steps"
    $sIdx = 0
    foreach ($s in @($steps)) {
        $sIdx++
        $act = Get-Prop $s "action"
        if (-not $act) { $act = Get-Prop $s "content" }
        $action = $act
        
        $expected = Get-Prop $s "expected"
        if ((Is-NullOrEmptyString $action) -or (Is-NullOrEmptyString $expected)) {
            $issues.Add(@{ path = "new_cases[$i].steps[$sIdx]"; action = $action; expected = $expected }) | Out-Null
        }
    }
}

$i = 0
foreach ($c in @($cats.enhance_cases)) {
    $i++
    $steps = Get-Prop $c "new_steps"
    $sIdx = 0
    foreach ($s in @($steps)) {
        $sIdx++
        $act = Get-Prop $s "action"
        if (-not $act) { $act = Get-Prop $s "content" }
        $action = $act

        $expected = Get-Prop $s "expected"
        if ((Is-NullOrEmptyString $action) -or (Is-NullOrEmptyString $expected)) {
            $issues.Add(@{ path = "enhance_cases[$i].new_steps[$sIdx]"; action = $action; expected = $expected }) | Out-Null
        }
    }
}

$status = if ($issues.Count -gt 0) { "Fail" } else { "Pass" }

return @{
    name = "step_completeness"
    status = $status
    details = @{
        issue_count = $issues.Count
        issues = $issues
    }
}

