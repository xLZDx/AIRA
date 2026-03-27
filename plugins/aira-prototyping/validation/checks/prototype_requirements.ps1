<#
.SYNOPSIS
    Validates prototype requirement completeness and uniqueness.

.DESCRIPTION
    Checks that all prototype requirements have required fields (id, title, description,
    priority, status) and that no duplicate requirement IDs exist.

.PARAMETER TestCases
    The test case design object — expected to have a 'prototype_requirements' property
    containing an array of requirement objects.

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

$reqs = Get-Prop $TestCases "prototype_requirements"
if (-not $reqs) {
    return @{
        name    = "prototype_requirements"
        status  = "Pass"
        details = @{ message = "No prototype_requirements found — skipping check." }
    }
}

$reqs = @($reqs)
$errors = New-Object System.Collections.Generic.List[object]
$seenIds = @{}

$i = 0
foreach ($r in $reqs) {
    $i++
    $id = Get-Prop $r "id"
    $title = Get-Prop $r "title"
    $desc = Get-Prop $r "description"
    $priority = Get-Prop $r "priority"
    $status = Get-Prop $r "status"

    if (-not $id) {
        $errors.Add(@{ path = "prototype_requirements[$i].id"; issue = "Required" }) | Out-Null
    } elseif ($seenIds.ContainsKey($id)) {
        $errors.Add(@{ path = "prototype_requirements[$i].id"; issue = "Duplicate ID: $id" }) | Out-Null
    } else {
        $seenIds[$id] = $true
    }

    if (-not $title -or ([string]::IsNullOrWhiteSpace("$title"))) {
        $errors.Add(@{ path = "prototype_requirements[$i].title"; issue = "Required" }) | Out-Null
    }
    if (-not $desc -or ([string]::IsNullOrWhiteSpace("$desc"))) {
        $errors.Add(@{ path = "prototype_requirements[$i].description"; issue = "Required" }) | Out-Null
    }
    if (-not $priority -or ([string]::IsNullOrWhiteSpace("$priority"))) {
        $errors.Add(@{ path = "prototype_requirements[$i].priority"; issue = "Required" }) | Out-Null
    }
    if ("$status" -ne "prototype") {
        $errors.Add(@{ path = "prototype_requirements[$i].status"; issue = "Must be 'prototype', got '$status'" }) | Out-Null
    }
}

$checkStatus = if ($errors.Count -gt 0) { "Fail" } else { "Pass" }

return @{
    name    = "prototype_requirements"
    status  = $checkStatus
    details = @{
        requirement_count = $reqs.Count
        error_count       = $errors.Count
        errors            = $errors
    }
}
