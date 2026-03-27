Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "Aira.Common.psm1") -Force

function Render-AiraTemplate {
    <#
    .SYNOPSIS
        Renders a simple AIRA template using {{PLACEHOLDER}} replacements.

    .DESCRIPTION
        - Replaces tokens matching {{ KEY }} (KEY: A-Z0-9_).
        - Missing keys are left as-is (so templates can keep placeholders).
        - Values are rendered as strings; arrays are joined with newlines.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Template,

        [Parameter(Mandatory = $true)]
        [hashtable]$Data
    )

    $pattern = [regex]'{{\s*([A-Z0-9_]+)\s*}}'

    $result = $pattern.Replace($Template, {
        param($m)
        $key = $m.Groups[1].Value
        if (-not $Data.ContainsKey($key)) {
            return $m.Value
        }

        $v = $Data[$key]
        if ($null -eq $v) { return "" }

        if (($v -is [array]) -or ($v -is [System.Collections.IList])) {
            return ((@($v) | ForEach-Object { "$_" }) -join "`n")
        }

        return "$v"
    })

    return $result
}

Export-ModuleMember -Function Render-AiraTemplate

