<#
.SYNOPSIS
    Validates test case values against policy restrictions (e.g. forbidden priorities).
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
    $val = Get-Prop $Obj "new_cases"
    if (-not $val) { $val = Get-Prop $Obj "NEW_CASES" }
    if (-not $val) { $val = @() }
    return @{ new_cases = @($val) }
}

$pols = if ($Policy.testrail.restrictions.forbidden_priorities) { $Policy.testrail.restrictions.forbidden_priorities } else { @() }
$forbidden = @($pols) | ForEach-Object { "$_".ToLower() }
$cats = Normalize-Categories -Obj $TestCases

$hits = New-Object System.Collections.Generic.List[object]

$i = 0
foreach ($c in @($cats.new_cases)) {
    $i++
    $p = (Get-Prop $c "priority")
    if (-not $p) { continue }
    if ($forbidden -contains ("$p".ToLower())) {
        $hits.Add(@{ path = "new_cases[$i].priority"; value = $p }) | Out-Null
    }
}

$status = if ($hits.Count -gt 0) { "Fail" } else { "Pass" }

return @{
    name = "forbidden_values"
    status = $status
    details = @{
        forbidden_priorities = if ($Policy.testrail.restrictions.forbidden_priorities) { $Policy.testrail.restrictions.forbidden_priorities } else { @() }
        violations = $hits
    }
}

