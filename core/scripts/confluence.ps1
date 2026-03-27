<#
.SYNOPSIS
    Confluence integration (read-only) for AIRA v2.

.DESCRIPTION
    Fetches page content by ID, supports safe keyword search via CQL,
    and retrieves child pages for a given parent.

.PARAMETER PageId
    Confluence page/content ID.

.PARAMETER Query
    Keyword query for Search-Pages (CQL text search).

.PARAMETER SpaceKey
    Optional space restriction for searches.

.PARAMETER GetChildren
    When set, returns child pages of the specified PageId.

.PARAMETER TestConnection
    Tests Confluence connectivity/auth (read-only) and exits.
#>

[CmdletBinding(DefaultParameterSetName = "GetPage")]
param(
    [Parameter(ParameterSetName = "GetPage", Mandatory = $true)]
    [Parameter(ParameterSetName = "GetChildren", Mandatory = $true)]
    [string]$PageId,

    [Parameter(ParameterSetName = "Search", Mandatory = $true)]
    [string]$Query,

    [Parameter(ParameterSetName = "Search")]
    [string]$SpaceKey,

    [Parameter(ParameterSetName = "GetChildren", Mandatory = $true)]
    [switch]$GetChildren,

    [Parameter(ParameterSetName = "TestConnection", Mandatory = $true)]
    [switch]$TestConnection,

    [ValidateSet("storage", "view", "both")]
    [string]$Format = "both",

    [switch]$NoBody,

    [int]$Limit = 10,

    [ValidateSet("auto", "bearer", "basic")]
    [string]$AuthMode = "auto",

    [string]$ConfluenceUrl,
    [string]$Email,
    [string]$ApiToken,
    [string]$EnvPath,
    [switch]$Refresh
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$configModule = Join-Path $repoRoot "core/modules/Aira.Config.psm1"
Import-Module $configModule -Force -WarningAction SilentlyContinue

$creds = Get-AiraCredentials -RepoRoot $repoRoot -EnvPath $EnvPath

if (-not $ConfluenceUrl) { $ConfluenceUrl = $creds.confluence.url }
if (-not $Email) { $Email = $creds.confluence.email }
if (-not $ApiToken) { $ApiToken = $creds.confluence.api_token }

if (-not $ConfluenceUrl) { throw "CONFLUENCE_URL not configured" }
if (-not $ApiToken) { throw "CONFLUENCE_API_TOKEN not configured" }

$ConfluenceUrl = $ConfluenceUrl.TrimEnd("/")

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
        if (-not $Email) { throw "CONFLUENCE_EMAIL (or CONFLUENCE_USERNAME) is required for basic auth (Atlassian Cloud)." }
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

$headers = New-AuthHeaders -Url $ConfluenceUrl -Email $Email -Token $ApiToken -Mode $AuthMode

function Get-Page {
    param([string]$Id)
    $exp = @("version", "space", "metadata.labels", "ancestors")
    if (-not $NoBody) {
        if ($Format -eq "storage" -or $Format -eq "both") { $exp += "body.storage" }
        if ($Format -eq "view" -or $Format -eq "both") { $exp += "body.view" }
    }
    $expandParam = ($exp -join ",")
    $url = "${ConfluenceUrl}/rest/api/content/${Id}?expand=${expandParam}"
    return (Invoke-RestMethod -Uri $url -Method Get -Headers $headers)
}

function Get-ChildPages {
    param([string]$ParentId, [int]$Max = 50)
    $url = "${ConfluenceUrl}/rest/api/content/${ParentId}/child/page?expand=version,space&limit=${Max}"
    return (Invoke-RestMethod -Uri $url -Method Get -Headers $headers)
}

function Search-Pages {
    param(
        [string]$Text,
        [string]$Space,
        [int]$Max = 10
    )
    $cql = if ($Space) { "space = `"$Space`" AND text ~ `"$Text`"" } else { "text ~ `"$Text`"" }
    $encoded = [System.Uri]::EscapeDataString($cql)
    $exp = "space,version"
    $url = "${ConfluenceUrl}/rest/api/content/search?cql=${encoded}&limit=${Max}&expand=${exp}"
    return (Invoke-RestMethod -Uri $url -Method Get -Headers $headers)
}

if ($TestConnection) {
    $me = Invoke-RestMethod -Uri "${ConfluenceUrl}/rest/api/user/current" -Method Get -Headers $headers
    @{ status = "ok"; displayName = $me.displayName; accountId = $me.accountId } | ConvertTo-Json -Depth 10
    exit 0
}

if ($PSCmdlet.ParameterSetName -eq "GetChildren") {
    $resp = Get-ChildPages -ParentId $PageId -Max $Limit
    $items = @($resp.results | ForEach-Object {
        @{
            id = $_.id
            title = $_.title
            space = @{
                key = $_.space.key
                name = $_.space.name
            }
            version = $_.version.number
            url = "$ConfluenceUrl$($_._links.webui)"
        }
    })
    @{ parent_id = $PageId; children = $items } | ConvertTo-Json -Depth 20
    exit 0
}

if ($PSCmdlet.ParameterSetName -eq "Search") {
    $resp = Search-Pages -Text $Query -Space $SpaceKey -Max $Limit
    $items = @($resp.results | ForEach-Object {
        @{
            id = $_.id
            title = $_.title
            space = @{
                key = $_.space.key
                name = $_.space.name
            }
            version = $_.version.number
            url = "$ConfluenceUrl$($_._links.webui)"
        }
    })
    @{ query = $Query; space_key = $SpaceKey; results = $items } | ConvertTo-Json -Depth 20
    exit 0
}

# --- Local cache check (GetPage only) ---
if (-not $Refresh) {
    $localRoot = Join-Path $repoRoot "context/local"
    if (Test-Path $localRoot) {
        $cachedDirs = @(Get-ChildItem -Path $localRoot -Directory -Recurse -Filter "* ($PageId)" -ErrorAction SilentlyContinue)
        if ($cachedDirs.Count -gt 0) {
            # Check new structure first (page.json directly in folder)
            $cachedFile = Join-Path $cachedDirs[0].FullName "page.json"
            # Fall back to legacy structure (sources/page.json)
            if (-not (Test-Path $cachedFile)) {
                $cachedFile = Join-Path $cachedDirs[0].FullName "sources/page.json"
            }
            if (Test-Path $cachedFile) {
                Write-Host "[cache-hit] Using cached page data: $cachedFile" -ForegroundColor Cyan
                Get-Content $cachedFile -Raw -Encoding UTF8
                exit 0
            }
        }
    }
}

$page = Get-Page -Id $PageId

# Build ancestors list — exclude the space home (ancestors[0]) since it's not useful content
$rawAncestors = @()
if ($null -ne $page.ancestors) {
    $rawAncestors = @($page.ancestors | ForEach-Object {
        @{ id = $_.id; title = $_.title }
    })
}
# Strip the space home (first entry) — it's always the top-level space container
if ($rawAncestors.Count -gt 1) {
    $ancestorsList = @($rawAncestors[1..($rawAncestors.Count - 1)])
} elseif ($rawAncestors.Count -eq 1) {
    # Only ancestor is the space home — page is directly under it
    $ancestorsList = @()
} else {
    $ancestorsList = @()
}

# Root page name: use the space name (e.g., "Knowledge Base - QA")
$rootPageName = $page.space.name

$out = @{
    page_id = $page.id
    title = $page.title
    space = @{
        key = $page.space.key
        name = $page.space.name
    }
    version = $page.version.number
    url = "$ConfluenceUrl$($page._links.webui)"
    labels = if ($null -ne $page.metadata.labels.results.name) { @($page.metadata.labels.results.name) } else { @() }
    ancestors = $ancestorsList
    root_page = $rootPageName
    fetched_at = (Get-Date).ToString("s")
}

if (-not $NoBody) {
    if ($Format -eq "storage" -or $Format -eq "both") { $out.body_storage = $page.body.storage.value }
    if ($Format -eq "view" -or $Format -eq "both") { $out.body_view = $page.body.view.value }
}

$json = $out | ConvertTo-Json -Depth 50

# --- Save to local cache ---
$spaceKey  = $page.space.key
$pageTitle = $page.title
$cacheDir  = Join-Path $repoRoot "context/local/$spaceKey/confluence/$pageTitle ($PageId)"
if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }
$json | Set-Content (Join-Path $cacheDir "page.json") -Encoding UTF8
Write-Host "[cache-save] Saved to: $cacheDir/page.json" -ForegroundColor Cyan

$json

