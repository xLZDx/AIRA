Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-AiraRepoRoot {
    <#
    .SYNOPSIS
        Returns the absolute path to the AIRA repository root.

    .DESCRIPTION
        All core modules live at <repo>/core/modules/.
        Repo root is two levels up from this file.
    #>
    [CmdletBinding()]
    param(
        [string]$StartPath = $PSScriptRoot
    )

    try {
        $candidate = Resolve-Path -Path (Join-Path $StartPath "../..") -ErrorAction Stop
        return $candidate.Path
    } catch {
        return (Get-Location).Path
    }
}

function Resolve-AiraPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$Path
    )

    if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
    return (Join-Path $RepoRoot $Path)
}

function Ensure-Dir([string]$Path) {
    if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
}

function Convert-PSObjectToHashtable($obj) {
    if ($null -eq $obj) { return $null }
    if ($obj -is [PSCustomObject] -or $obj -is [System.Collections.IDictionary]) {
        $hash = @{}
        foreach ($prop in $obj.PSObject.Properties) {
            $hash[$prop.Name] = Convert-PSObjectToHashtable $prop.Value
        }
        return $hash
    } elseif ($obj -is [System.Collections.IList] -and $obj -isnot [string]) {
        $arr = @()
        foreach ($item in $obj) {
            $arr += Convert-PSObjectToHashtable $item
        }
        return ,$arr
    } else {
        return $obj
    }
}

Export-ModuleMember -Function Get-AiraRepoRoot, Resolve-AiraPath, Ensure-Dir, Convert-PSObjectToHashtable
