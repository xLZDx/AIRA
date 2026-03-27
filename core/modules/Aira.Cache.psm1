Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "Aira.Common.psm1") -Force

function Resolve-CachePath {
    param(
        [string]$RepoRoot,
        [string]$CachePath,
        [string]$JiraKey,
        [ValidateSet("issue", "comments", "linked_issues", "sources", "manifest", "context")]
        [string]$JiraArtifact = "issue",
        [int]$CaseId,
        [string]$CoverageJiraKey,
        [int]$ProjectId,
        [ValidateSet("testrail_case", "testrail_coverage", "jira", "confluence")]
        [string]$Kind,
        [string]$ConfluencePageId,
        [string]$ConfluenceProjectKey,
        [string]$ConfluencePageTitle,
        [ValidateSet("page", "context")]
        [string]$ConfluenceArtifact = "page"
    )

    if ($CachePath) { return (Resolve-AiraPath -RepoRoot $RepoRoot -Path $CachePath) }

    switch ($Kind) {
        "jira" {
            if (-not $JiraKey) { throw "JiraKey is required for Kind=jira" }
            $base = Join-Path (Join-Path $RepoRoot "context/jira") $JiraKey
            switch ($JiraArtifact) {
                "issue" { return (Join-Path $base "issue.json") }
                "comments" { return (Join-Path $base "comments.json") }
                "linked_issues" { return (Join-Path $base "linked_issues.json") }
                "sources" { return (Join-Path $base "sources.json") }
                "manifest" { return (Join-Path $base "manifest.json") }
                "context" { return (Join-Path $base "context.md") }
            }
        }
        "testrail_case" {
            if (-not $CaseId) { throw "CaseId is required for Kind=testrail_case" }
            $pid = if ($ProjectId) { "$ProjectId" } else { "_global" }
            return (Join-Path (Join-Path (Join-Path $RepoRoot "context/testrail/$pid") "cases") "$CaseId.json")
        }
        "testrail_coverage" {
            if (-not $CoverageJiraKey) { throw "CoverageJiraKey is required for Kind=testrail_coverage" }
            $pid = if ($ProjectId) { "$ProjectId" } else { "_global" }
            return (Join-Path (Join-Path (Join-Path $RepoRoot "context/testrail/$pid") "coverage") "$CoverageJiraKey.json")
        }
        "confluence" {
            if (-not $ConfluencePageId) { throw "ConfluencePageId is required for Kind=confluence" }
            if ($ConfluenceProjectKey -and $ConfluencePageTitle) {
                $dirName = "$ConfluencePageTitle ($ConfluencePageId)"
                $base = Join-Path $RepoRoot "context/local/$ConfluenceProjectKey/confluence/$dirName"
            } else {
                # Legacy fallback: flat path by page ID
                $base = Join-Path (Join-Path $RepoRoot "context/confluence") $ConfluencePageId
            }
            if ($ConfluenceArtifact -eq "page") { return (Join-Path $base "page.json") }
            return (Join-Path $base "context.md")
        }
        default {
            throw "CachePath or Kind is required."
        }
    }
}

function Get-CachedData {
    [CmdletBinding(DefaultParameterSetName = "Path")]
    param(
        [Parameter(ParameterSetName = "Path", Mandatory = $true)]
        [string]$CachePath,

        [Parameter(ParameterSetName = "Jira", Mandatory = $true)]
        [string]$JiraKey,

        [Parameter(ParameterSetName = "Jira")]
        [ValidateSet("issue", "comments", "linked_issues", "sources", "manifest", "context")]
        [string]$JiraArtifact = "issue",

        [Parameter(ParameterSetName = "TestRailCase", Mandatory = $true)]
        [int]$CaseId,

        [Parameter(ParameterSetName = "TestRailCase")]
        [int]$ProjectId,

        [Parameter(ParameterSetName = "TestRailCoverage", Mandatory = $true)]
        [string]$CoverageJiraKey,

        [Parameter(ParameterSetName = "TestRailCoverage")]
        [int]$CoverageProjectId,

        [Parameter(ParameterSetName = "Confluence", Mandatory = $true)]
        [string]$ConfluencePageId,

        [Parameter(ParameterSetName = "Confluence")]
        [string]$ConfluenceProjectKey,

        [Parameter(ParameterSetName = "Confluence")]
        [string]$ConfluencePageTitle,

        [Parameter(ParameterSetName = "Confluence")]
        [ValidateSet("page", "context")]
        [string]$ConfluenceArtifact = "page",

        [int]$MaxAgeMinutes = 60
    )

    $repoRoot = Get-AiraRepoRoot

    $kind = $null
    $resolved = $null

    switch ($PSCmdlet.ParameterSetName) {
        "Path" {
            $resolved = Resolve-CachePath -RepoRoot $repoRoot -CachePath $CachePath
            break
        }
        "Jira" {
            $kind = "jira"
            $resolved = Resolve-CachePath -RepoRoot $repoRoot -Kind $kind -JiraKey $JiraKey -JiraArtifact $JiraArtifact
            break
        }
        "TestRailCase" {
            $kind = "testrail_case"
            $resolved = Resolve-CachePath -RepoRoot $repoRoot -Kind $kind -CaseId $CaseId -ProjectId $ProjectId
            break
        }
        "TestRailCoverage" {
            $kind = "testrail_coverage"
            $resolved = Resolve-CachePath -RepoRoot $repoRoot -Kind $kind -CoverageJiraKey $CoverageJiraKey -ProjectId $CoverageProjectId
            break
        }
        "Confluence" {
            $kind = "confluence"
            $resolved = Resolve-CachePath -RepoRoot $repoRoot -Kind $kind -ConfluencePageId $ConfluencePageId -ConfluenceProjectKey $ConfluenceProjectKey -ConfluencePageTitle $ConfluencePageTitle -ConfluenceArtifact $ConfluenceArtifact
            break
        }
    }

    if (-not (Test-Path $resolved)) { return $null }

    $age = (Get-Date) - (Get-Item $resolved).LastWriteTime
    if ($age.TotalMinutes -ge $MaxAgeMinutes) { return $null }

    if ($resolved -like "*.md") { return (Get-Content $resolved -Raw -Encoding UTF8) }
    return (Get-Content $resolved -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Set-CachedData {
    [CmdletBinding(DefaultParameterSetName = "Path")]
    param(
        [Parameter(ParameterSetName = "Path", Mandatory = $true)]
        [string]$CachePath,

        [Parameter(ParameterSetName = "Jira", Mandatory = $true)]
        [string]$JiraKey,

        [Parameter(ParameterSetName = "Jira")]
        [ValidateSet("issue", "comments", "linked_issues", "sources", "manifest", "context")]
        [string]$JiraArtifact = "issue",

        [Parameter(ParameterSetName = "TestRailCase", Mandatory = $true)]
        [int]$CaseId,

        [Parameter(ParameterSetName = "TestRailCase")]
        [int]$ProjectId,

        [Parameter(ParameterSetName = "TestRailCoverage", Mandatory = $true)]
        [string]$CoverageJiraKey,

        [Parameter(ParameterSetName = "TestRailCoverage")]
        [int]$CoverageProjectId,

        [Parameter(ParameterSetName = "Confluence", Mandatory = $true)]
        [string]$ConfluencePageId,

        [Parameter(ParameterSetName = "Confluence")]
        [string]$ConfluenceProjectKey,

        [Parameter(ParameterSetName = "Confluence")]
        [string]$ConfluencePageTitle,

        [Parameter(ParameterSetName = "Confluence")]
        [ValidateSet("page", "context")]
        [string]$ConfluenceArtifact = "page",

        [Parameter(Mandatory = $true)]
        [object]$Data
    )

    $repoRoot = Get-AiraRepoRoot

    $kind = $null
    $resolved = $null

    switch ($PSCmdlet.ParameterSetName) {
        "Path" {
            $resolved = Resolve-CachePath -RepoRoot $repoRoot -CachePath $CachePath
            break
        }
        "Jira" {
            $kind = "jira"
            $resolved = Resolve-CachePath -RepoRoot $repoRoot -Kind $kind -JiraKey $JiraKey -JiraArtifact $JiraArtifact
            break
        }
        "TestRailCase" {
            $kind = "testrail_case"
            $resolved = Resolve-CachePath -RepoRoot $repoRoot -Kind $kind -CaseId $CaseId -ProjectId $ProjectId
            break
        }
        "TestRailCoverage" {
            $kind = "testrail_coverage"
            $resolved = Resolve-CachePath -RepoRoot $repoRoot -Kind $kind -CoverageJiraKey $CoverageJiraKey -ProjectId $CoverageProjectId
            break
        }
        "Confluence" {
            $kind = "confluence"
            $resolved = Resolve-CachePath -RepoRoot $repoRoot -Kind $kind -ConfluencePageId $ConfluencePageId -ConfluenceProjectKey $ConfluenceProjectKey -ConfluencePageTitle $ConfluencePageTitle -ConfluenceArtifact $ConfluenceArtifact
            break
        }
    }

    Ensure-Dir -Path (Split-Path -Parent $resolved)

    if ($resolved -like "*.md") {
        [string]$content = if ($Data -is [string]) { $Data } else { ($Data | Out-String) }
        $content | Out-File -FilePath $resolved -Encoding UTF8
        return $resolved
    }

    $Data | ConvertTo-Json -Depth 50 | Out-File -FilePath $resolved -Encoding UTF8
    return $resolved
}

Export-ModuleMember -Function Get-CachedData, Set-CachedData

