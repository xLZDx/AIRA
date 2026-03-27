<#
.SYNOPSIS
    Jira integration (read-only) for AIRA v2.

.DESCRIPTION
    Fetches issue details, acceptance criteria, comments, and linked issue dependencies (depth per policy).

.PARAMETER IssueKey
    Jira issue key to fetch (Feature/Story recommended).

.PARAMETER ProjectKey
    Optional: list recent issues for a project (summary output).

.PARAMETER TestConnection
    Tests Jira connectivity/auth (read-only) and exits.
#>

[CmdletBinding(DefaultParameterSetName = "GetIssue")]
param(
    [Parameter(ParameterSetName = "GetIssue", Mandatory = $true)]
    [string]$IssueKey,

    [Parameter(ParameterSetName = "ListProject", Mandatory = $true)]
    [string]$ProjectKey,

    [Parameter(ParameterSetName = "TestConnection", Mandatory = $true)]
    [switch]$TestConnection,

    [ValidateSet("auto", "bearer", "basic")]
    [string]$AuthMode = "auto",

    [int]$MaxDependencyDepth,

    [string]$JiraUrl,
    [string]$Email,
    [string]$ApiToken,
    [string]$EnvPath
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$configModule = Join-Path $repoRoot "core/modules/Aira.Config.psm1"
Import-Module $configModule -Force -WarningAction SilentlyContinue

$creds = Get-AiraCredentials -RepoRoot $repoRoot -EnvPath $EnvPath

if (-not $JiraUrl) { $JiraUrl = $creds.jira.url }
if (-not $Email) { $Email = $creds.jira.email }
if (-not $ApiToken) { $ApiToken = $creds.jira.api_token }

if (-not $JiraUrl) { throw "JIRA_URL not configured" }
if (-not $ApiToken) { throw "JIRA_API_TOKEN not configured" }

$JiraUrl = $JiraUrl.TrimEnd("/")

function Get-EffectiveAuthMode {
    param([string]$Url, [string]$Mode)
    if ($Mode -ne "auto") { return $Mode }
    if ($Url -match "atlassian\\.net") { return "basic" }
    return "bearer"
}

function New-AuthHeaders {
    param(
        [string]$Url,
        [string]$Email,
        [string]$Token,
        [string]$Mode
    )

    $effective = Get-EffectiveAuthMode -Url $Url -Mode $Mode
    if ($effective -eq "basic") {
        if (-not $Email) { throw "JIRA_EMAIL (or JIRA_USERNAME) is required for basic auth (Atlassian Cloud)." }
        $pair = "{0}:{1}" -f $Email, $Token
        $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pair))
        return @{
            "Authorization" = "Basic $b64"
            "Content-Type"  = "application/json"
            "Accept"        = "application/json"
        }
    }

    return @{
        "Authorization" = "Bearer $Token"
        "Content-Type"  = "application/json"
        "Accept"        = "application/json"
    }
}

$headers = New-AuthHeaders -Url $JiraUrl -Email $Email -Token $ApiToken -Mode $AuthMode

$jiraTextModule = Join-Path $repoRoot "core/modules/Aira.JiraText.psm1"
if (Test-Path $jiraTextModule) { Import-Module $jiraTextModule -Force }

function Get-JiraIssue {
    param([string]$Key)
    $url = "${JiraUrl}/rest/api/2/issue/${Key}?fields=summary,issuetype,description,status,priority,issuelinks,created,updated,project,labels,components,fixVersions,attachment"
    return (Invoke-RestMethod -Uri $url -Method Get -Headers $headers)
}

function Get-JiraComments {
    param([string]$Key)
    $url = "$JiraUrl/rest/api/2/issue/$Key/comment?maxResults=100"
    try {
        $resp = Invoke-RestMethod -Uri $url -Method Get -Headers $headers
        $comms = if ($null -ne $resp.comments) { $resp.comments } else { @() }
        return @($comms)
    } catch {
        return @()
    }
}

function Get-LinkedKeysFromIssue {
    param([object]$Issue)
    $keys = New-Object System.Collections.Generic.HashSet[string]
    $links = if ($null -ne $Issue.fields.issuelinks) { $Issue.fields.issuelinks } else { @() }
    foreach ($link in @($links)) {
        if ($link.inwardIssue -and $link.inwardIssue.key) { $keys.Add([string]$link.inwardIssue.key) | Out-Null }
        if ($link.outwardIssue -and $link.outwardIssue.key) { $keys.Add([string]$link.outwardIssue.key) | Out-Null }
    }
    return @($keys)
}

function Get-LinkedIssues {
    param(
        [string]$RootKey,
        [int]$Depth
    )

    $visited = New-Object System.Collections.Generic.HashSet[string]
    $queue = New-Object System.Collections.Generic.Queue[object]
    $issuesByKey = @{}

    $queue.Enqueue(@{ key = $RootKey; depth = 0 }) | Out-Null
    $visited.Add($RootKey) | Out-Null

    while ($queue.Count -gt 0) {
        $item = $queue.Dequeue()
        $key = $item.key
        $d = [int]$item.depth

        $issue = Get-JiraIssue -Key $key
        $issuesByKey[$key] = $issue

        if ($d -ge $Depth) { continue }

        foreach ($lk in (Get-LinkedKeysFromIssue -Issue $issue)) {
            if ($visited.Contains($lk)) { continue }
            $visited.Add($lk) | Out-Null
            $queue.Enqueue(@{ key = $lk; depth = ($d + 1) }) | Out-Null
        }
    }

    # Flatten direct links for root issue + include depth info for discovered deps.
    $root = $issuesByKey[$RootKey]
    $direct = @()
    $links = if ($null -ne $root.fields.issuelinks) { $root.fields.issuelinks } else { @() }
    foreach ($link in @($links)) {
        $direction = $null
        $linkedKey = $null
        if ($link.outwardIssue -and $link.outwardIssue.key) { $direction = "outward"; $linkedKey = $link.outwardIssue.key }
        elseif ($link.inwardIssue -and $link.inwardIssue.key) { $direction = "inward"; $linkedKey = $link.inwardIssue.key }
        if (-not $linkedKey) { continue }

        $linked = $issuesByKey[$linkedKey]
        $rel = if ($null -ne $link.type.name) { $link.type.name } elseif ($null -ne $link.type.outward) { $link.type.outward } else { $link.type.inward }
        
        $iType = if ($linked.fields.issuetype -and $linked.fields.issuetype.name) { $linked.fields.issuetype.name } else { $null }
        $iStatus = if ($linked.fields.status -and $linked.fields.status.name) { $linked.fields.status.name } else { $null }
        $iSummary = if ($linked.fields.summary) { $linked.fields.summary } else { $null }

        $direct += @{
            key = $linkedKey
            relationship = $rel
            direction = $direction
            issue_type = $iType
            status = $iStatus
            summary = $iSummary
        }
    }

    $all = @()
    foreach ($k in $issuesByKey.Keys) {
        if ($k -eq $RootKey) { continue }
        $i = $issuesByKey[$k]
        
        $iType = if ($i.fields.issuetype -and $i.fields.issuetype.name) { $i.fields.issuetype.name } else { $null }
        $iStatus = if ($i.fields.status -and $i.fields.status.name) { $i.fields.status.name } else { $null }
        $iSummary = if ($i.fields.summary) { $i.fields.summary } else { $null }

        $all += @{
            key = $k
            issue_type = $iType
            status = $iStatus
            summary = $iSummary
        }
    }

    return @{
        direct = $direct
        all = $all
        issues_by_key = @{} # omit raw by default to keep output small
    }
}

if ($TestConnection) {
    $me = Invoke-RestMethod -Uri "$JiraUrl/rest/api/2/myself" -Method Get -Headers $headers
    @{ status = "ok"; displayName = $me.displayName; accountId = $me.accountId } | ConvertTo-Json -Depth 10
    exit 0
}

if ($PSCmdlet.ParameterSetName -eq "ListProject") {
    # Minimal project listing (recent issues)
    $body = @{
        jql = "project = $ProjectKey ORDER BY updated DESC"
        maxResults = 20
        fields = @("summary", "status", "issuetype", "updated", "priority")
    } | ConvertTo-Json
    $resp = Invoke-RestMethod -Uri "$JiraUrl/rest/api/2/search" -Method Post -Headers $headers -Body $body
    $items = @($resp.issues | ForEach-Object {
        @{
            key = $_.key
            summary = $_.fields.summary
            issue_type = $_.fields.issuetype.name
            status = $_.fields.status.name
            priority = $_.fields.priority.name
            updated = $_.fields.updated
        }
    })
    @{ project = $ProjectKey; issues = $items } | ConvertTo-Json -Depth 10
    exit 0
}

# Load policy for dependency depth (if present)
$policy = $null
try {
    if (Get-Command Get-AiraEffectivePolicy -ErrorAction SilentlyContinue) {
        $policy = Get-AiraEffectivePolicy -PolicyRoot (Join-Path $repoRoot ".aira") -RepoRoot $repoRoot
    } else {
        $policy = Get-AiraPolicy -PolicyRoot (Join-Path $repoRoot ".aira")
    }
} catch {
    $policy = $null
}

$depth = if ($MaxDependencyDepth) { $MaxDependencyDepth } elseif ($policy -and $policy.context -and $policy.context.max_dependency_depth) { [int]$policy.context.max_dependency_depth } else { 2 }

$issue = Get-JiraIssue -Key $IssueKey
$descText = Convert-JiraContentToText -Value $issue.fields.description
$commentsRaw = Get-JiraComments -Key $IssueKey

$comments = @($commentsRaw | ForEach-Object {
    @{
        id = $_.id
        author = if ($_.author.displayName) { $_.author.displayName } else { $_.author.name }
        created = $_.created
        updated = $_.updated
        body = (Convert-JiraContentToText -Value $_.body)
    }
})

$links = Get-LinkedIssues -RootKey $IssueKey -Depth $depth
$ac = Extract-AcceptanceCriteria -DescriptionText $descText

$prio = if ($issue.fields.priority -and $issue.fields.priority.name) { $issue.fields.priority.name } else { $null }

$out = @{
    jira_key = $issue.key
    summary = $issue.fields.summary
    issue_type = $issue.fields.issuetype.name
    status = $issue.fields.status.name
    priority = $prio
    description = $descText
    acceptance_criteria = $ac
    comments = $comments
    linked_issues = $links
    fetched_at = (Get-Date).ToString("s")
}

$out | ConvertTo-Json -Depth 50

