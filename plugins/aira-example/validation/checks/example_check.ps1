<#
.SYNOPSIS
    Example validation check contributed by the aira-example plugin.

.DESCRIPTION
    Demonstrates the expected interface for plugin validation checks.
    A real check receives $TestCases and $Policy and returns an object with:
      - name: string (check identifier)
      - status: "Pass" | "Warn" | "Fail"
      - message: string (human-readable detail)
      - items: array (affected items, optional)

.PARAMETER TestCases
    The parsed test-design object (new_cases, enhance_cases, prereq_cases).

.PARAMETER Policy
    The effective merged policy hashtable.
#>
param(
    [Parameter(Mandatory = $true)]
    [object]$TestCases,

    [Parameter(Mandatory = $true)]
    [hashtable]$Policy
)

# This example always passes.
return @{
    name    = "example_check"
    status  = "Pass"
    message = "Example plugin check passed (no-op)."
    items   = @()
}
