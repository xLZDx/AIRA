<#
.SYNOPSIS
    Ensures Jira references are present and well-formed.
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

function Extract-JiraKeys([string]$Text) {
    if (-not $Text) { return @() }
    $matches = [regex]::Matches($Text, "\b[A-Z][A-Z0-9]+-\d+\b")
    return @($matches | ForEach-Object { $_.Value } | Select-Object -Unique)
}

$require = $false
try {
    $val = if ($Policy.testrail.restrictions.require_jira_reference) { $Policy.testrail.restrictions.require_jira_reference } else { $false }
    $require = [bool]$val
} catch { $require = $false }

$cats = Normalize -Obj $TestCases
$issues = New-Object System.Collections.Generic.List[object]

$i = 0
foreach ($c in @($cats.new_cases)) {
    $i++
    $refs = Get-Prop $c "references"
    $keys = @(Extract-JiraKeys -Text "$refs")
    if ($require -and $keys.Count -eq 0) {
        $issues.Add(@{ path = "new_cases[$i].references"; issue = "Missing Jira key reference"; value = $refs }) | Out-Null
    }
}

$i = 0
foreach ($c in @($cats.enhance_cases)) {
    $i++
    $refs = Get-Prop $c "updated_references"
    $keys = @(Extract-JiraKeys -Text "$refs")
    if ($require -and $keys.Count -eq 0) {
        $issues.Add(@{ path = "enhance_cases[$i].updated_references"; issue = "Missing Jira key reference"; value = $refs }) | Out-Null
    }
}

$status = if ($issues.Count -gt 0) { "Fail" } else { "Pass" }

return @{
    name = "reference_integrity"
    status = $status
    details = @{
        require_jira_reference = $require
        issue_count = $issues.Count
        issues = $issues
    }
}

