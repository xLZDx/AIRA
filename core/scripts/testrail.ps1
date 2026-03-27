<#
.SYNOPSIS
    TestRail API operations - Bidirectional (Read + Write)

.DESCRIPTION
    Provides read operations (coverage analysis, duplicate detection) and
    write operations (create cases, update cases, enhance existing cases).

    Refinements (V2):
    - Pre-upload Validation: Check cases before upload (steps must exist).
    - Multiple References: Check for multiple references in TestRail.
    - Project Hierarchy: Support user-provided folder paths and display tree.
    - Functional Cases: New creation workflow.

.PARAMETER GetCoverage
    Analyze existing coverage for a Jira key

.PARAMETER JiraKey
    Jira issue key to search for

.PARAMETER GetCase
    Retrieve a specific test case by ID

.PARAMETER CaseId
    TestRail case ID

.PARAMETER CreateCase
    Create a new test case

.PARAMETER UpdateCase
    Update an existing test case

.PARAMETER EnhanceCase
    Add steps to an existing case (enhancement workflow)

.PARAMETER CaseJson
    JSON string or file path containing case data

.PARAMETER ProjectId
    TestRail project ID

.PARAMETER SectionId
    TestRail section ID for new cases

.PARAMETER ListProjects
    List all available projects

.PARAMETER ListRuns
    List recent runs for a project

.PARAMETER ListSections
    List sections/suites for a project

.EXAMPLE
    powershell ./core/scripts/testrail.ps1 -GetCoverage -JiraKey "MARD-719"

.EXAMPLE
    powershell ./core/scripts/testrail.ps1 -CreateCase -CaseJson "case.json" -SectionId 123

.PARAMETER CreateSection
    Create a new section in TestRail

.PARAMETER SectionName
    Name for the new section (used with -CreateSection or -BatchCreate)

.PARAMETER ParentSectionName
    Name of the parent section to create under (resolved by name)

.PARAMETER ParentId
    ID of the parent section to create under (used with -CreateSection)

.PARAMETER MaxRetries
    Maximum number of retry attempts for transient API failures (default: 3)

.PARAMETER DeleteCase
    Delete a test case by ID

.PARAMETER DeleteSection
    Delete a section and optionally all its cases

.PARAMETER DeleteCases
    When used with -DeleteSection, also deletes all cases in the section first

.EXAMPLE
    powershell ./core/scripts/testrail.ps1 -CreateSection -SectionName "AIRA-DEMO-MAV-1852" -ParentId 665098 -ProjectId 212

.EXAMPLE
    powershell ./core/scripts/testrail.ps1 -BatchCreate -CasesJson "design.json" -SectionName "AIRA-DEMO" -ParentSectionName "Functional Testing" -ProjectId 212

.EXAMPLE
    powershell ./core/scripts/testrail.ps1 -EnhanceCase -CaseId 1235 -CaseJson "enhancements.json"

.EXAMPLE
    powershell ./core/scripts/testrail.ps1 -DeleteCase -CaseId 4428776

.EXAMPLE
    powershell ./core/scripts/testrail.ps1 -DeleteSection -SectionId 679821 -ProjectId 212 -DeleteCases
#>

[CmdletBinding()]
param(
    [Parameter(ParameterSetName = 'Coverage')]
    [switch]$GetCoverage,

    [Parameter(ParameterSetName = 'Coverage', Mandatory = $true)]
    [Parameter(ParameterSetName = 'Search')]
    [string]$JiraKey,

    [Parameter(ParameterSetName = 'GetCase')]
    [switch]$GetCase,

    [Parameter(ParameterSetName = 'GetCase', Mandatory = $true)]
    [Parameter(ParameterSetName = 'UpdateCase', Mandatory = $true)]
    [Parameter(ParameterSetName = 'EnhanceCase', Mandatory = $true)]
    [int]$CaseId,

    [Parameter(ParameterSetName = 'CreateCase')]
    [switch]$CreateCase,

    [Parameter(ParameterSetName = 'UpdateCase')]
    [switch]$UpdateCase,

    [Parameter(ParameterSetName = 'EnhanceCase')]
    [switch]$EnhanceCase,
    [Parameter(ParameterSetName = 'ListProjects')]
    [switch]$ListProjects,

    [Parameter(ParameterSetName = 'ListRuns')]
    [switch]$ListRuns,

    [Parameter(ParameterSetName = 'ListSections')]
    [switch]$ListSections,

    [Parameter(ParameterSetName = 'ListRuns', Mandatory = $true)]
    [Parameter(ParameterSetName = 'ListSections', Mandatory = $true)]
    [Parameter(ParameterSetName = 'ListProjects')]
    [string]$ProjectName,
    [Parameter(ParameterSetName = 'CreateCase', Mandatory = $true)]
    [Parameter(ParameterSetName = 'UpdateCase', Mandatory = $true)]
    [Parameter(ParameterSetName = 'EnhanceCase', Mandatory = $true)]
    [string]$CaseJson,

    [Parameter(ParameterSetName = 'CreateCase', Mandatory = $true)]
    [Parameter(ParameterSetName = 'BatchCreate')]
    [int]$SectionId,

    [Parameter(ParameterSetName = 'CreateCase')]
    [Parameter(ParameterSetName = 'Coverage')]
    [Parameter(ParameterSetName = 'GetSections', Mandatory = $true)]
    [Parameter(ParameterSetName = 'BatchCreate')]
    [Parameter(ParameterSetName = 'CreateSection', Mandatory = $true)]
    [Parameter(ParameterSetName = 'DeleteSection')]
    [int]$ProjectId,

    [Parameter(ParameterSetName = 'GetSections')]
    [switch]$GetSections,

    [Parameter(ParameterSetName = 'CreateSection')]
    [switch]$CreateSection,

    [Parameter(ParameterSetName = 'CreateSection', Mandatory = $true)]
    [Parameter(ParameterSetName = 'BatchCreate')]
    [string]$SectionName,

    [Parameter(ParameterSetName = 'CreateSection')]
    [int]$ParentId = 0,

    [Parameter(ParameterSetName = 'BatchCreate')]
    [string]$ParentSectionName,

    [Parameter(ParameterSetName = 'BatchCreate')]
    [switch]$BatchCreate,

    [Parameter(ParameterSetName = 'BatchCreate', Mandatory = $true)]
    [string]$CasesJson,

    [int]$MaxRetries = 3,

    [Parameter(ParameterSetName = 'DeleteCase')]
    [switch]$DeleteCase,

    [Parameter(ParameterSetName = 'DeleteCase', Mandatory = $true)]
    [int]$DeleteCaseId,

    [Parameter(ParameterSetName = 'DeleteSection')]
    [switch]$DeleteSection,

    [Parameter(ParameterSetName = 'DeleteSection', Mandatory = $true)]
    [int]$DeleteSectionId,

    [Parameter(ParameterSetName = 'DeleteSection')]
    [switch]$DeleteCases,

    [Parameter(ParameterSetName = 'TestConnection')]
    [switch]$TestConnection,

    [string]$TestRailUrl,
    [string]$Username,
    [string]$ApiKey,
    [string]$EnvPath
)

# ============================================================================
# INITIALIZATION
# ============================================================================

$ErrorActionPreference = "Stop"

# Repo root resolution (this script lives at <repo>/core/scripts/)
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$resolvedEnvPath = if ($EnvPath) { $EnvPath } else { Join-Path $repoRoot ".env" }

function Read-EnvFile {
    param([string]$Path)
    $vars = @{}
    if (-not (Test-Path $Path)) { return $vars }
    foreach ($line in (Get-Content $Path)) {
        if ($line -match '^\s*#') { continue }
        if ($line -match '^\s*$') { continue }
        if ($line -match '^\s*([^=#]+?)\s*=\s*(.*)$') {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim() -replace '^["'']|["'']$'
            $vars[$key] = $value
        }
    }
    return $vars
}

$envVars = Read-EnvFile -Path $resolvedEnvPath

# Resolve credentials
if (-not $TestRailUrl) { $TestRailUrl = if ($envVars.ContainsKey('TESTRAIL_URL')) { $envVars['TESTRAIL_URL'] } else { $env:TESTRAIL_URL } }
if (-not $Username) { $Username = if ($envVars.ContainsKey('TESTRAIL_USERNAME')) { $envVars['TESTRAIL_USERNAME'] } else { $env:TESTRAIL_USERNAME } }
if (-not $ApiKey) { $ApiKey = if ($envVars.ContainsKey('TESTRAIL_API_KEY')) { $envVars['TESTRAIL_API_KEY'] } else { $env:TESTRAIL_API_KEY } }

# Validate
if (-not $TestRailUrl) { throw "TESTRAIL_URL not configured" }
if (-not $Username) { throw "TESTRAIL_USERNAME not configured" }
if (-not $ApiKey) { throw "TESTRAIL_API_KEY not configured" }

$TestRailUrl = $TestRailUrl.TrimEnd('/')

# Build auth header
$authPair = "{0}:{1}" -f $Username, $ApiKey
$authB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($authPair))
$headers = @{
    "Authorization" = "Basic $authB64"
    "Content-Type"  = "application/json"
}

function Assert-ReadinessForWrite {
    $statePath = Join-Path $repoRoot ".aira/tests/startup.state.json"
    if (-not (Test-Path $statePath)) {
        throw "Workspace readiness is not Complete. Run: powershell ./core/scripts/aira.ps1 -Doctor"
    }
    try {
        $state = Get-Content $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        $state = $null
    }
    if (-not $state -or $state.status -ne "Complete") {
        throw "Workspace readiness is not Complete. Run: powershell ./core/scripts/aira.ps1 -Doctor"
    }
}

# Derive Jira key prefix from $JiraKey when available (used for cache routing)
$script:JiraKeyPrefix = if ($JiraKey) { ($JiraKey -split '-')[0] } else { $null }

# ============================================================================
# CACHE MANAGEMENT
# ============================================================================
# Cache is split across three levels:
#
#   GLOBAL (all TestRail projects, individual cases):
#     context/local/_metadata/testrail/projects.json
#     context/local/_metadata/testrail/cases/{id}.json
#
#   PROJECT-LEVEL (runs, sections, backups — scoped under Jira prefix when available):
#     context/local/{KeyPrefix}/metadata/testrail/{ProjectName} ({Id})/
#       runs.json
#       sections/sections.json
#       backups/TC-{id}_backup_{timestamp}.json
#
#   STORY-LEVEL (coverage — per Jira key, local context only):
#     context/local/{KeyPrefix}/{JIRA-KEY}/metadata/testrail/coverage.json
#
# Directories are created on-demand (no eager empty folders).
# ============================================================================

function Resolve-ProjectDisplayName {
    <#
    .SYNOPSIS
        Resolve a TestRail project ID to its display name.
        Reads from cached projects.json first to avoid API round-trips.
    #>
    param([int]$ProjId)
    if (-not $ProjId -or $ProjId -le 0) { return $null }
    # Try cached file first (avoids circular Get-Projects call)
    $globalRoot = Join-Path $repoRoot "context/local/_metadata/testrail"
    $projCache  = Join-Path $globalRoot "projects.json"
    if (Test-Path $projCache) {
        try {
            $projects = Get-Content $projCache -Raw -Encoding UTF8 | ConvertFrom-Json
            $match = $projects | Where-Object { $_.id -eq $ProjId } | Select-Object -First 1
            if ($match) { return $match.name }
        } catch { }
    }
    # Fallback: single-project API call
    try {
        $url = "$TestRailUrl/index.php?/api/v2/get_project/$ProjId"
        $proj = Invoke-TestRailApi -Uri $url -Method Get
        if ($proj -and $proj.name) { return $proj.name }
    } catch { }
    return "Project"
}

function Get-TestRailCacheRoot {
    <#
    .SYNOPSIS
        Returns the cache root for a TestRail project.
        Global (no project)  → context/local/_metadata/testrail
        Project-specific     → context/local/{KeyPrefix}/metadata/testrail/{ProjectName} ({ProjectId})
        Fallback (no prefix) → context/local/_metadata/testrail/{ProjectName} ({ProjectId})
    #>
    param(
        [int]$ForProjectId = 0,
        [string]$ForProjectName = ""
    )
    $targetPid = if ($ForProjectId -gt 0) { $ForProjectId } else { $ProjectId }
    if ($targetPid -gt 0) {
        $name = if ($ForProjectName) { $ForProjectName } else { Resolve-ProjectDisplayName -ProjId $targetPid }
        $safeName = $name -replace '[<>:"/\\|?*]', '_'
        $folderName = "$safeName ($targetPid)"
        # Route under Jira prefix when available
        if ($script:JiraKeyPrefix) {
            return Join-Path $repoRoot "context/local/$($script:JiraKeyPrefix)/metadata/testrail/$folderName"
        }
        # Fallback to global location
        return Join-Path $repoRoot "context/local/_metadata/testrail/$folderName"
    }
    return Join-Path $repoRoot "context/local/_metadata/testrail"
}

function Get-CasesCacheDir {
    # Individual cases are always cached globally (project unknown at fetch time)
    return (Join-Path (Join-Path $repoRoot "context/local/_metadata/testrail") "cases")
}

function Get-CoveragePath {
    <#
    .SYNOPSIS
        Returns the per-story coverage cache path.
        context/local/{KeyPrefix}/{JIRA-KEY}/metadata/testrail/coverage.json
    #>
    param([string]$ForJiraKey)
    $prefix = ($ForJiraKey -split '-')[0]
    return Join-Path $repoRoot "context/local/$prefix/$ForJiraKey/metadata/testrail/coverage.json"
}

function Get-SectionsCacheDir {
    param([int]$ForProjectId = 0)
    return (Join-Path (Get-TestRailCacheRoot -ForProjectId $ForProjectId) "sections")
}

function Get-BackupsCacheDir {
    param([int]$ForProjectId = 0)
    return (Join-Path (Get-TestRailCacheRoot -ForProjectId $ForProjectId) "backups")
}

function Get-CachedJson {
    param([string]$Path, [int]$MaxAgeMinutes)
    if (Test-Path $Path) {
        $cacheAge = (Get-Date) - (Get-Item $Path).LastWriteTime
        if ($cacheAge.TotalMinutes -lt $MaxAgeMinutes) {
            return Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        }
    }
    return $null
}

function Set-CachedJson {
    param([string]$Path, [object]$Data)
    $parentDir = Split-Path $Path -Parent
    if (-not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }
    $Data | ConvertTo-Json -Depth 10 | Out-File $Path -Encoding UTF8
}

function Get-CachedCase {
    param([int]$Id, [int]$MaxAgeMinutes = 60)
    # Individual cases cached globally (project unknown at fetch time)
    $cachePath = Join-Path (Get-CasesCacheDir) "$Id.json"
    return (Get-CachedJson -Path $cachePath -MaxAgeMinutes $MaxAgeMinutes)
}

function Set-CachedCase {
    param([int]$Id, [object]$Data)
    $cachePath = Join-Path (Get-CasesCacheDir) "$Id.json"
    Set-CachedJson -Path $cachePath -Data $Data
}

function Get-CachedCoverage {
    param([string]$JiraKey, [int]$ForProjectId = 0, [int]$MaxAgeMinutes = 30)
    $cachePath = Get-CoveragePath -ForJiraKey $JiraKey
    return (Get-CachedJson -Path $cachePath -MaxAgeMinutes $MaxAgeMinutes)
}

function Set-CachedCoverage {
    param([string]$JiraKey, [int]$ForProjectId = 0, [object]$Data)
    # Only persist when there is actual coverage — avoid creating empty metadata folders
    $hasCoverage = $false
    if ($Data -and $Data.summary) {
        $hasCoverage = [bool]$Data.summary.has_coverage
    }
    if (-not $hasCoverage) { return }
    $cachePath = Get-CoveragePath -ForJiraKey $JiraKey
    Set-CachedJson -Path $cachePath -Data $Data
}

# ============================================================================
# RETRY WRAPPER
# ============================================================================

function Invoke-TestRailApi {
    <#
    .SYNOPSIS
        Invoke a TestRail API call with automatic retries and enhanced error reporting.
    #>
    param(
        [string]$Uri,
        [string]$Method = 'Get',
        [byte[]]$Body = $null,
        [int]$Retries = $script:MaxRetries
    )

    $attempt = 0
    while ($true) {
        $attempt++
        try {
            if ($Body) {
                return Invoke-RestMethod -Uri $Uri -Method $Method -Headers $headers -Body $Body
            } else {
                return Invoke-RestMethod -Uri $Uri -Method $Method -Headers $headers
            }
        } catch {
            $status = $null
            if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }

            # Extract detailed error message from TestRail response body
            $detail = ''
            try {
                if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
                    $detail = $_.ErrorDetails.Message
                } elseif ($_.Exception.Response) {
                    $stream = $_.Exception.Response.GetResponseStream()
                    $reader = New-Object System.IO.StreamReader($stream)
                    $detail = $reader.ReadToEnd()
                }
            } catch { }

            # Retryable: 429 (rate limit) or 5xx server errors
            $retryable = ($status -eq 429) -or ($status -ge 500 -and $status -lt 600)

            if ($retryable -and $attempt -lt $Retries) {
                $wait = [math]::Pow(2, $attempt)   # exponential backoff: 2, 4, 8 …
                Write-Host "  Retry $attempt/$Retries after ${wait}s (HTTP $status)" -ForegroundColor Yellow
                Start-Sleep -Seconds $wait
                continue
            }

            # Non-retryable or retries exhausted — throw with detail
            $msg = $_.Exception.Message
            if ($detail) { $msg = "$msg | Detail: $detail" }
            throw $msg
        }
    }
}

# ============================================================================
# READ OPERATIONS
# ============================================================================

function Get-TestRailCase {
    param([int]$Id)

    # Check cache first
    $cached = Get-CachedCase -Id $Id
    if ($cached) { return $cached }

    # Fetch from API
    $url = "$TestRailUrl/index.php?/api/v2/get_case/$Id"
    $response = Invoke-TestRailApi -Uri $url -Method Get

    # Cache result
    Set-CachedCase -Id $Id -Data $response

    return $response
}

function Find-CasesByReference {
    param(
        [string]$JiraKey,
        [int]$ProjectId
    )

    $url = "$TestRailUrl/index.php?/api/v2/get_cases/$ProjectId"
    $params = @{ refs = $JiraKey }
    $queryString = ($params.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "&"
    $fullUrl = "$url&$queryString"

    try {
        $response = Invoke-TestRailApi -Uri $fullUrl -Method Get
        $cases = if ($null -ne $response.cases) { $response.cases } else { $response }
        return $cases
    } catch {
        if ($_ -match '400') { return @() }
        throw
    }
}

function Find-RelatedCases {
    param(
        [string]$JiraKey,
        [int]$ProjectId,
        [int]$Limit = 100
    )

    $prefix = ($JiraKey -split '-')[0]
    $url = "$TestRailUrl/index.php?/api/v2/get_cases/$ProjectId&limit=$Limit"

    try {
        $response = Invoke-TestRailApi -Uri $url -Method Get
        $allCases = if ($null -ne $response.cases) { $response.cases } else { $response }

        # Filter for cases with refs from same project prefix (supports multiple refs)
        $related = $allCases | Where-Object {
            if ($_.refs) {
                $refs = $_.refs -split ',' | ForEach-Object { $_.Trim() }
                $refs | Where-Object { $_ -like "$prefix-*" }
            }
        }

        return $related
    } catch {
        return @()
    }
}

function Find-RunsByReference {
    <#
    .SYNOPSIS
        Search for TestRail runs whose refs field contains the given Jira key.
    #>
    param(
        [string]$JiraKey,
        [int]$ProjId,
        [int]$Limit = 250
    )
    $url = "$TestRailUrl/index.php?/api/v2/get_runs/$ProjId&limit=$Limit"
    try {
        $response = Invoke-TestRailApi -Uri $url -Method Get
        $runs = if ($null -ne $response.runs) { $response.runs } else { @($response) }
        $matching = @($runs | Where-Object {
            if ($_.refs) {
                $refs = $_.refs -split ',' | ForEach-Object { $_.Trim() }
                $refs -contains $JiraKey
            }
        })
        return $matching
    } catch {
        return @()
    }
}

function Find-CoverageGlobal {
    <#
    .SYNOPSIS
        Search ALL active TestRail projects for cases and runs referencing a Jira key.
        Used when no ProjectId is specified.
    #>
    param([string]$JiraKey)

    Write-Host "Searching for $JiraKey across all TestRail projects..." -ForegroundColor Cyan
    $projects = Get-Projects
    $activeProjects = @($projects | Where-Object { -not $_.is_completed })

    $allCases = @()
    $allRuns = @()
    $projectsWithCoverage = @()

    foreach ($proj in $activeProjects) {
        $projId   = $proj.id
        $projName = $proj.name

        # Search cases by ref
        try {
            $cases = Find-CasesByReference -JiraKey $JiraKey -ProjectId $projId
            if ($cases -and @($cases).Count -gt 0) {
                foreach ($c in @($cases)) {
                    $c | Add-Member -NotePropertyName "_project_id"   -NotePropertyValue $projId   -Force
                    $c | Add-Member -NotePropertyName "_project_name" -NotePropertyValue $projName -Force
                }
                $allCases += @($cases)
            }
        } catch { }

        # Search runs by ref
        try {
            $runs = Find-RunsByReference -JiraKey $JiraKey -ProjId $projId
            if ($runs -and @($runs).Count -gt 0) {
                foreach ($r in @($runs)) {
                    $r | Add-Member -NotePropertyName "_project_id"   -NotePropertyValue $projId   -Force
                    $r | Add-Member -NotePropertyName "_project_name" -NotePropertyValue $projName -Force
                }
                $allRuns += @($runs)
            }
        } catch { }

        $caseCount = if ($cases) { @($cases).Count } else { 0 }
        $runCount  = if ($runs)  { @($runs).Count }  else { 0 }
        if ($caseCount -gt 0 -or $runCount -gt 0) {
            $projectsWithCoverage += @{ id = $projId; name = $projName; cases = $caseCount; runs = $runCount }
        }
    }

    Write-Host "  Searched $($activeProjects.Count) active projects" -ForegroundColor Gray
    $totalHits = $allCases.Count + $allRuns.Count
    Write-Host "  Found $($allCases.Count) cases and $($allRuns.Count) runs" -ForegroundColor $(if ($totalHits -gt 0) { "Green" } else { "Yellow" })

    return @{
        cases    = $allCases
        runs     = $allRuns
        projects_with_coverage = $projectsWithCoverage
        total_projects_searched = $activeProjects.Count
    }
}

function Get-CoverageAnalysis {
    <#
    .SYNOPSIS
        Analyze TestRail coverage for a Jira key.
        When ProjectId is provided, searches that project only.
        When ProjectId is 0/missing, searches ALL active projects (cases + runs).
    #>
    param(
        [string]$JiraKey,
        [int]$ProjectId = 0
    )

    # Check cache
    $cached = Get-CachedCoverage -JiraKey $JiraKey -ForProjectId $ProjectId
    if ($cached) { return $cached }

    Write-Host "Analyzing TestRail coverage for $JiraKey..." -ForegroundColor Cyan

    $directCases  = @()
    $matchedRuns  = @()
    $uniqueRelated = @()
    $searchScope  = "project"
    $projectsWithCoverage = @()

    if ($ProjectId -gt 0) {
        # ---- Project-specific search ----
        $directCases  = Find-CasesByReference -JiraKey $JiraKey -ProjectId $ProjectId
        $relatedCases = Find-RelatedCases     -JiraKey $JiraKey -ProjectId $ProjectId
        $directIds    = @($directCases | ForEach-Object { $_.id })
        $uniqueRelated = @($relatedCases | Where-Object { $_.id -notin $directIds })
        $matchedRuns  = Find-RunsByReference -JiraKey $JiraKey -ProjId $ProjectId
    } else {
        # ---- Cross-project global search ----
        $searchScope = "global"
        $global      = Find-CoverageGlobal -JiraKey $JiraKey
        $directCases = $global.cases
        $matchedRuns = $global.runs
        $projectsWithCoverage = $global.projects_with_coverage
    }

    $coverage = @{
        jira_key      = $JiraKey
        project_id    = $ProjectId
        search_scope  = $searchScope
        analyzed_at   = (Get-Date).ToString("s")
        direct_cases  = @($directCases | ForEach-Object {
            $c = @{
                id          = $_.id
                title       = $_.title
                priority_id = $_.priority_id
                refs        = $_.refs
                updated_on  = $_.updated_on
                section_id  = $_.section_id
            }
            if ($_._project_id)   { $c._project_id   = $_._project_id }
            if ($_._project_name) { $c._project_name  = $_._project_name }
            $c
        })
        matched_runs  = @($matchedRuns | ForEach-Object {
            $r = @{
                id             = $_.id
                name           = $_.name
                refs           = $_.refs
                is_completed   = $_.is_completed
                passed_count   = $_.passed_count
                failed_count   = $_.failed_count
                untested_count = $_.untested_count
                retest_count   = $_.retest_count
                milestone_id   = $_.milestone_id
                url            = $_.url
            }
            if ($_._project_id)   { $r._project_id   = $_._project_id }
            if ($_._project_name) { $r._project_name  = $_._project_name }
            $r
        })
        related_cases = @($uniqueRelated | ForEach-Object {
            @{
                id            = $_.id
                title         = $_.title
                refs          = $_.refs
                potential_use = "Prerequisite or Related"
            }
        })
        projects_with_coverage = $projectsWithCoverage
        summary = @{
            direct_count  = ($directCases  | Measure-Object).Count
            runs_count    = ($matchedRuns  | Measure-Object).Count
            related_count = ($uniqueRelated | Measure-Object).Count
            has_coverage  = (($directCases | Measure-Object).Count -gt 0) -or (($matchedRuns | Measure-Object).Count -gt 0)
        }
    }

    # Cache result
    Set-CachedCoverage -JiraKey $JiraKey -ForProjectId $ProjectId -Data $coverage

    return $coverage
}

# ============================================================================
# WRITE OPERATIONS
# ============================================================================

function Assert-CaseStepsPresent {
    param([hashtable]$CaseData)
    if (-not $CaseData.steps -or @($CaseData.steps).Count -eq 0) {
        throw "Pre-upload validation failed: steps must exist for case '$($CaseData.title)'."
    }
    foreach ($s in @($CaseData.steps)) {
        $action = if ($null -ne $s.action) { $s.action } else { $s.content }
        if (-not $action) { throw "Pre-upload validation failed: each step must include 'action' (or 'content')." }
        if (-not $s.expected) { throw "Pre-upload validation failed: each step must include 'expected'." }
    }
}

function New-TestRailCase {
    param(
        [int]$SectionId,
        [hashtable]$CaseData
    )

    Assert-CaseStepsPresent -CaseData $CaseData

    # Validate against policy
    $policy = Get-PolicyConfig
    $forbiddenPriorities = if ($policy.testrail.restrictions.forbidden_priorities) { $policy.testrail.restrictions.forbidden_priorities } else { @() }

    if ($CaseData.priority_id -and $forbiddenPriorities -contains (Get-PriorityName $CaseData.priority_id)) {
        throw "Priority '$($CaseData.priority_id)' is forbidden by policy"
    }

    $url = "$TestRailUrl/index.php?/api/v2/add_case/$SectionId"

    $body = @{
        title = $CaseData.title
        priority_id = if ($CaseData.priority_id) { $CaseData.priority_id } else { 2 }
        type_id = if ($CaseData.type_id) { $CaseData.type_id } else { 2 }
        refs = $CaseData.refs
        custom_preconds = $CaseData.preconditions
    }

    if ($CaseData.steps) {
        $body.custom_steps_separated = @($CaseData.steps | ForEach-Object {
            @{
                content = $_.action
                expected = $_.expected
            }
        })
    }

    $jsonBody = $body | ConvertTo-Json -Depth 10
    $utf8Bytes = [System.Text.Encoding]::UTF8.GetBytes($jsonBody)
    $response = Invoke-TestRailApi -Uri $url -Method Post -Body $utf8Bytes

    Write-Host "Created case: $($response.id) - $($response.title)" -ForegroundColor Green

    # Invalidate coverage cache for the Jira key if possible (best-effort)
    if ($CaseData.refs) {
        $refs = ($CaseData.refs -split ',' | ForEach-Object { $_.Trim() }) | Where-Object { $_ }
        foreach ($r in $refs) {
            $p = Get-CoveragePath -ForJiraKey $r
            if (Test-Path $p) { Remove-Item $p -Force }
        }
    }

    return $response
}

function Update-TestRailCase {
    param(
        [int]$CaseId,
        [hashtable]$Updates
    )

    $url = "$TestRailUrl/index.php?/api/v2/update_case/$CaseId"
    $body = @{}

    if ($Updates.title) { $body.title = $Updates.title }
    if ($Updates.priority_id) { $body.priority_id = $Updates.priority_id }
    if ($Updates.refs) { $body.refs = $Updates.refs }
    if ($Updates.preconditions) { $body.custom_preconds = $Updates.preconditions }

    if ($Updates.steps) {
        $body.custom_steps_separated = @($Updates.steps | ForEach-Object {
            @{
                content = if ($null -ne $_.action) { $_.action } else { $_.content }
                expected = $_.expected
            }
        })
    }

    $jsonBody = $body | ConvertTo-Json -Depth 10
    $utf8Bytes = [System.Text.Encoding]::UTF8.GetBytes($jsonBody)
    $response = Invoke-TestRailApi -Uri $url -Method Post -Body $utf8Bytes

    Write-Host "Updated case: $($response.id) - $($response.title)" -ForegroundColor Yellow

    # Invalidate cache (global case cache)
    $cachePath = Join-Path (Get-CasesCacheDir) "$CaseId.json"
    if (Test-Path $cachePath) { Remove-Item $cachePath -Force }

    return $response
}

function Add-StepsToCase {
    param(
        [int]$CaseId,
        [array]$NewSteps,
        [string]$AdditionalRef
    )

    if (-not $NewSteps -or $NewSteps.Count -eq 0) {
        throw "Enhancement workflow requires at least one new step."
    }

    # Fetch current case
    $currentCase = Get-TestRailCase -Id $CaseId
    if (-not $currentCase) { throw "Case $CaseId not found" }

    # Backup before update (stored under project-specific backups dir)
    $backupDir = Get-BackupsCacheDir
    if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
    $stamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $backupPath = Join-Path $backupDir "TC-$CaseId_backup_$stamp.json"
    $currentCase | ConvertTo-Json -Depth 10 | Out-File $backupPath -Encoding UTF8

    # Get existing steps
    $existingSteps = if ($null -ne $currentCase.custom_steps_separated) { $currentCase.custom_steps_separated } else { @() }

    # Merge steps
    $mergedSteps = @($existingSteps) + @($NewSteps | ForEach-Object {
        @{
            content  = if ($null -ne $_.action) { $_.action } else { $_.content }
            expected = $_.expected
        }
    })

    # Update refs
    $existingRefs = if ($null -ne $currentCase.refs) { $currentCase.refs } else { "" }
    $newRefs = if ($AdditionalRef) {
        if ($existingRefs) { "$existingRefs,$AdditionalRef" } else { $AdditionalRef }
    } else {
        $existingRefs
    }

    # Update case
    $updates = @{
        steps = $mergedSteps
        refs  = $newRefs
    }

    $result = Update-TestRailCase -CaseId $CaseId -Updates $updates
    Write-Host "Enhanced case $CaseId with $($NewSteps.Count) new steps" -ForegroundColor Green

    return $result
}

function New-TestRailCasesBatch {
    param(
        [int]$SectionId,
        [array]$Cases
    )

    $results = @{
        created = @()
        errors  = @()
    }

    foreach ($case in $Cases) {
        try {
            $caseData = @{
                title         = $case.title
                priority_id   = Get-PriorityId $case.priority
                type_id       = Get-TypeId $case.type
                refs          = $case.references
                preconditions = $case.preconditions
                steps         = $case.steps
            }

            $created = New-TestRailCase -SectionId $SectionId -CaseData $caseData
            $results.created += $created
        } catch {
            $results.errors += @{
                case  = $case.title
                error = $_.Exception.Message
            }
        }
    }

    return $results
}

# ============================================================================
# HELPERS
# ============================================================================

function Get-PriorityId {
    param([string]$Name)
    $n = if ($Name) { $Name } else { "" }
    switch ($n.ToLower()) {
        "critical" { return 1 }  # Critical (4) not available in this TestRail instance; map to High (1)
        "high"     { return 1 }
        "medium"   { return 2 }
        "low"      { return 3 }
        default    { return 2 }
    }
}

function Get-PriorityName {
    param([int]$Id)
    switch ($Id) {
        4       { return "Critical" }
        1       { return "High" }
        2       { return "Medium" }
        3       { return "Low" }
        default { return "Medium" }
    }
}

function Get-TypeId {
    param([string]$Name)
    $n = if ($Name) { $Name } else { "" }
    switch ($n.ToLower()) {
        "backend"     { return 10 }
        "data"        { return 9 }
        "exploratory" { return 12 }
        "functional"  { return 2 }
        "other"       { return 6 }
        "performance" { return 3 }
        "regression"  { return 4 }
        "smoke"       { return 7 }
        "uat"         { return 8 }
        "ui"          { return 13 }
        default       { return 2 }
    }
}

function Get-TypeName {
    param([int]$Id)
    switch ($Id) {
        10      { return "Backend" }
        9       { return "Data" }
        12      { return "Exploratory" }
        2       { return "Functional" }
        6       { return "Other" }
        3       { return "Performance" }
        4       { return "Regression" }
        7       { return "Smoke" }
        8       { return "UAT" }
        13      { return "UI" }
        default { return "Functional" }
    }
}

function Get-PolicyConfig {
    # Prefer merged policy via core/modules/Aira.Config.psm1 when available.
    try {
        $configModule = Join-Path $repoRoot "core/modules/Aira.Config.psm1"
        if (Test-Path $configModule) { Import-Module $configModule -Force -ErrorAction SilentlyContinue | Out-Null }
        if (Get-Command Get-AiraEffectivePolicy -ErrorAction SilentlyContinue) {
            return (Get-AiraEffectivePolicy -PolicyRoot (Join-Path $repoRoot ".aira") -RepoRoot $repoRoot)
        }
        if (Get-Command Get-AiraPolicy -ErrorAction SilentlyContinue) {
            return (Get-AiraPolicy -PolicyRoot (Join-Path $repoRoot ".aira"))
        }
    } catch {
        # fall through
    }

    $policyPath = Join-Path $repoRoot ".aira/team.policy.json"
    if (Test-Path $policyPath) {
        return (Get-Content $policyPath -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable)
    }
    return @{
        testrail = @{
            restrictions = @{
                forbidden_priorities = @()
                max_cases_per_batch  = 50
            }
        }
    }
}

function Get-Projects {
    param([int]$MaxAgeMinutes = 60)
    
    # Projects list always cached globally
    $cachePath = Join-Path (Get-TestRailCacheRoot -ForProjectId 0) "projects.json"
    $cached = Get-CachedJson -Path $cachePath -MaxAgeMinutes $MaxAgeMinutes
    if ($cached) { return $cached }

    $url = "$TestRailUrl/index.php?/api/v2/get_projects"
    $response = Invoke-TestRailApi -Uri $url -Method Get
    
    $projects = if ($null -ne $response.projects) { $response.projects } else { $response }
    Set-CachedJson -Path $cachePath -Data $projects
    
    return $projects
}

function Get-Runs {
    param([int]$ProjectId, [int]$Limit = 10, [int]$MaxAgeMinutes = 15)

    $cacheRoot = Get-TestRailCacheRoot -ForProjectId $ProjectId
    $cachePath = Join-Path $cacheRoot "runs.json"
    $cached = Get-CachedJson -Path $cachePath -MaxAgeMinutes $MaxAgeMinutes
    if ($cached) { return $cached }

    $url = "$TestRailUrl/index.php?/api/v2/get_runs/$ProjectId&limit=$Limit"
    $response = Invoke-TestRailApi -Uri $url -Method Get
    
    $runs = if ($null -ne $response.runs) { $response.runs } else { $response }
    Set-CachedJson -Path $cachePath -Data $runs
    
    return $runs
}

function Get-Sections {
    param([int]$ProjectId, [int]$MaxAgeMinutes = 60)

    # Cache per project (explicit ForProjectId avoids script-scope leakage)
    $cachePath = Join-Path (Get-SectionsCacheDir -ForProjectId $ProjectId) "sections.json"
    $cached = Get-CachedJson -Path $cachePath -MaxAgeMinutes $MaxAgeMinutes
    if ($cached) {
        $c = if ($null -ne $cached.sections) { $cached.sections } else { $cached }
        return $c
    }

    $url = "$TestRailUrl/index.php?/api/v2/get_sections/$ProjectId"
    $response = Invoke-TestRailApi -Uri $url -Method Get
    Set-CachedJson -Path $cachePath -Data $response
    $sect = if ($null -ne $response.sections) { $response.sections } else { $response }
    return $sect
}

function Get-OrCreateSection {
    param(
        [int]$ProjectId,
        [string]$SectionName,
        [int]$ParentId = 0
    )

    $sections = Get-Sections -ProjectId $ProjectId
    $existing = if ($ParentId -gt 0) {
        $sections | Where-Object { $_.name -eq $SectionName -and $_.parent_id -eq $ParentId }
    } else {
        $sections | Where-Object { $_.name -eq $SectionName -and (-not $_.parent_id) }
    }
    if ($existing) {
        $found = @($existing)
        return $found[0].id
    }

    # Create new section
    $url = "$TestRailUrl/index.php?/api/v2/add_section/$ProjectId"
    $body = @{ name = $SectionName }
    if ($ParentId -gt 0) { $body.parent_id = $ParentId }
    $jsonBody = $body | ConvertTo-Json
    $utf8Bytes = [System.Text.Encoding]::UTF8.GetBytes($jsonBody)
    $response = Invoke-TestRailApi -Uri $url -Method Post -Body $utf8Bytes

    Write-Host "Created section: $($response.name) (id=$($response.id), parent=$ParentId)" -ForegroundColor Green

    # Invalidate sections cache
    $cachePath = Join-Path (Get-SectionsCacheDir -ForProjectId $ProjectId) "sections.json"
    if (Test-Path $cachePath) { Remove-Item $cachePath -Force }

    return $response.id
}

function Remove-TestRailCase {
    param([int]$CaseId)
    Assert-ReadinessForWrite
    $url = "$TestRailUrl/index.php?/api/v2/delete_case/$CaseId"
    Invoke-TestRailApi -Uri $url -Method Post | Out-Null
    Write-Host "Deleted case C$CaseId" -ForegroundColor Yellow
}

function Remove-TestRailSection {
    param(
        [int]$SectionId,
        [int]$ProjectId,
        [switch]$IncludeCases
    )
    Assert-ReadinessForWrite

    if ($IncludeCases -and $ProjectId -gt 0) {
        # Fetch and delete all cases in the section first
        $suiteId = $null
        try {
            $sections = Get-Sections -ProjectId $ProjectId
            $section = $sections | Where-Object { $_.id -eq $SectionId } | Select-Object -First 1
            if ($section -and $section.suite_id) { $suiteId = $section.suite_id }
        } catch { }

        $casesUrl = "$TestRailUrl/index.php?/api/v2/get_cases/$ProjectId"
        $casesUrl += "&section_id=$SectionId"
        if ($suiteId) { $casesUrl += "&suite_id=$suiteId" }
        try {
            $resp = Invoke-TestRailApi -Uri $casesUrl -Method Get
            $cases = if ($resp.cases) { $resp.cases } else { @($resp) }
            Write-Host "Found $($cases.Count) case`(s`) in section $SectionId" -ForegroundColor Cyan
            foreach ($c in $cases) {
                Remove-TestRailCase -CaseId $c.id
            }
        } catch {
            Write-Host "Warning: Could not fetch cases for section $SectionId - $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    $url = "$TestRailUrl/index.php?/api/v2/delete_section/$SectionId"
    Invoke-TestRailApi -Uri $url -Method Post | Out-Null
    Write-Host "Deleted section $SectionId" -ForegroundColor Yellow

    # Invalidate sections cache
    $projCache = Join-Path (Get-SectionsCacheDir -ForProjectId $ProjectId) "sections.json"
    if (Test-Path $projCache) { Remove-Item $projCache -Force }
}

# ============================================================================
# COMMAND ROUTING
# ============================================================================

if ($TestConnection) {
    Write-Host "Testing TestRail connection..." -ForegroundColor Cyan
    Write-Host "URL: $TestRailUrl" -ForegroundColor Gray

    try {
        $url = "$TestRailUrl/index.php?/api/v2/get_projects"
        $response = Invoke-TestRailApi -Uri $url -Method Get
        Write-Host "Connection successful!" -ForegroundColor Green
        $count = if ($null -ne $response.projects) { $response.projects.Count } else { $response.Count }
        Write-Host "Projects found: $count" -ForegroundColor Green
        exit 0
    } catch {
        Write-Host "Connection failed: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

if ($GetCoverage) {
    if (-not $ProjectId) {
        # Try to infer from policy
        $policy = Get-PolicyConfig
        $prefix = ($JiraKey -split '-')[0]
        $ProjectId = $policy.testrail.project_id_map[$prefix]
        # If still no ProjectId, fall through to global cross-project search (ProjectId stays 0)
    }

    $coverage = Get-CoverageAnalysis -JiraKey $JiraKey -ProjectId $ProjectId

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Coverage Analysis: $JiraKey (scope: $($coverage.search_scope))" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    if ($coverage.search_scope -eq "global" -and $coverage.projects_with_coverage.Count -gt 0) {
        Write-Host "Projects with coverage:" -ForegroundColor Yellow
        $coverage.projects_with_coverage | ForEach-Object {
            Write-Host "  - $($_.name) (id=$($_.id)): $($_.cases) cases, $($_.runs) runs" -ForegroundColor White
        }
        Write-Host ""
    }

    Write-Host "Direct Coverage `($($coverage.summary.direct_count) cases`):" -ForegroundColor Yellow
    if ($coverage.direct_cases.Count -gt 0) {
        $coverage.direct_cases | ForEach-Object {
            $proj = if ($_._project_name) { " [$($_._project_name)]" } else { "" }
            Write-Host "  - TC-$($_.id): $($_.title)$proj" -ForegroundColor White
        }
    } else {
        Write-Host "  (No direct case coverage found)" -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host "Matched Runs `($($coverage.summary.runs_count) runs`):" -ForegroundColor Yellow
    if ($coverage.matched_runs.Count -gt 0) {
        $coverage.matched_runs | ForEach-Object {
            $proj = if ($_._project_name) { " [$($_._project_name)]" } else { "" }
            $status = "P:$($_.passed_count) F:$($_.failed_count) U:$($_.untested_count)"
            Write-Host "  - R$($_.id): $($_.name)$proj ($status)" -ForegroundColor White
        }
    } else {
        Write-Host "  (No matching runs found)" -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host "Related Cases `($($coverage.summary.related_count) cases`):" -ForegroundColor Yellow
    if ($coverage.related_cases.Count -gt 0) {
        $coverage.related_cases | Select-Object -First 10 | ForEach-Object { Write-Host "  - TC-$($_.id): $($_.title)" -ForegroundColor Gray }
        if ($coverage.related_cases.Count -gt 10) {
            Write-Host "  ... and $($coverage.related_cases.Count - 10) more" -ForegroundColor Gray
        }
    } else {
        Write-Host "  (No related cases found)" -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "JSON Output" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    $coverage | ConvertTo-Json -Depth 10
    exit 0
}

if ($GetCase) {
    $case = Get-TestRailCase -Id $CaseId

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Test Case: TC-$CaseId" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Title: $($case.title)" -ForegroundColor Yellow
    Write-Host "Priority: $(Get-PriorityName $case.priority_id)" -ForegroundColor White
    Write-Host "References: $($case.refs)" -ForegroundColor White
    Write-Host "Section: $($case.section_id)" -ForegroundColor White
    Write-Host ""

    if ($case.custom_steps_separated) {
        Write-Host "Steps:" -ForegroundColor Yellow
        $stepNum = 1
        foreach ($step in $case.custom_steps_separated) {
            Write-Host "  $stepNum. $($step.content)" -ForegroundColor White
            Write-Host "     Expected: $($step.expected)" -ForegroundColor Gray
            $stepNum++
        }
    }

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "JSON Output" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    $case | ConvertTo-Json -Depth 10
    exit 0
}

if ($CreateCase) {
    Assert-ReadinessForWrite

    $caseData = if (Test-Path $CaseJson) {
        Get-Content $CaseJson -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
    } else {
        $CaseJson | ConvertFrom-Json -AsHashtable
    }

    $result = New-TestRailCase -SectionId $SectionId -CaseData $caseData
    $result | ConvertTo-Json -Depth 10
    exit 0
}

if ($UpdateCase) {
    Assert-ReadinessForWrite

    $updates = if (Test-Path $CaseJson) {
        Get-Content $CaseJson -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
    } else {
        $CaseJson | ConvertFrom-Json -AsHashtable
    }

    $result = Update-TestRailCase -CaseId $CaseId -Updates $updates
    $result | ConvertTo-Json -Depth 10
    exit 0
}

if ($EnhanceCase) {
    Assert-ReadinessForWrite

    $enhancement = if (Test-Path $CaseJson) {
        Get-Content $CaseJson -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
    } else {
        $CaseJson | ConvertFrom-Json -AsHashtable
    }

    $result = Add-StepsToCase -CaseId $CaseId -NewSteps $enhancement.new_steps -AdditionalRef $enhancement.additional_ref
    $result | ConvertTo-Json -Depth 10
    exit 0
}

if ($CreateSection) {
    Assert-ReadinessForWrite
    if (-not $ProjectId) { throw "ProjectId required for -CreateSection" }

    $newSectionId = Get-OrCreateSection -ProjectId $ProjectId -SectionName $SectionName -ParentId $ParentId

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Section Ready" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Name:      $SectionName" -ForegroundColor White
    Write-Host "ID:        $newSectionId" -ForegroundColor Green
    Write-Host "Parent ID: $ParentId" -ForegroundColor White
    Write-Host "Project:   $ProjectId" -ForegroundColor White

    @{ section_id = $newSectionId; section_name = $SectionName; parent_id = $ParentId; project_id = $ProjectId } | ConvertTo-Json -Depth 5
    exit 0
}

if ($BatchCreate) {
    Assert-ReadinessForWrite

    $cases = if (Test-Path $CasesJson) {
        Get-Content $CasesJson -Raw -Encoding UTF8 | ConvertFrom-Json
    } else {
        $CasesJson | ConvertFrom-Json
    }

    # Guard: abort early if neither SectionId nor SectionName is provided
    if ($SectionId -eq 0 -and -not $SectionName) {
        throw "Aborting batch upload: you must provide either -SectionId or -SectionName. Neither was supplied."
    }

    # Resolve SectionId: if -SectionName is provided, auto-create the section
    if ($SectionId -eq 0 -and $SectionName) {
        if (-not $ProjectId) { throw "ProjectId required when using -SectionName for batch create" }

        $parentId = 0
        if ($ParentSectionName) {
            $sections = Get-Sections -ProjectId $ProjectId
            $parentMatch = $sections | Where-Object { $_.name -eq $ParentSectionName } | Select-Object -First 1
            if (-not $parentMatch) {
                throw "Parent section '$ParentSectionName' not found in project $ProjectId"
            }
            $parentId = $parentMatch.id
        }

        $SectionId = Get-OrCreateSection -ProjectId $ProjectId -SectionName $SectionName -ParentId $parentId
        if ($SectionId -eq 0) { throw "Failed to create or resolve section '$SectionName'" }
        Write-Host "Using section: $SectionName (id=$SectionId)" -ForegroundColor Cyan
    }

    if ($SectionId -eq 0) { throw "SectionId could not be resolved. Provide -SectionId or -SectionName." }

    # Support both { new_cases: [...] } and flat array [...]
    $caseList = if ($cases -is [array]) {
        $cases
    } elseif ($cases.new_cases) {
        @($cases.new_cases)
    } else {
        @($cases)
    }

    $result = New-TestRailCasesBatch -SectionId $SectionId -Cases $caseList

    Write-Host "" 
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Batch Create Results" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Section: $SectionId" -ForegroundColor Cyan
    Write-Host "Created: $($result.created.Count)" -ForegroundColor Green
    Write-Host "Errors: $($result.errors.Count)" -ForegroundColor $(if ($result.errors.Count -gt 0) { "Red" } else { "Green" })

    $result | ConvertTo-Json -Depth 10
    exit 0
}


if ($ListProjects) {
    Write-Host "Fetching projects..." -ForegroundColor Cyan
    $projects = Get-Projects

    if ($ProjectName) {
        $projects = $projects | Where-Object { $_.name -like "*$ProjectName*" }
    }

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Projects Found: $($projects.Count)" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    
    $projects | Format-Table -Property id, name, suite_mode, is_completed -AutoSize | Out-String | Write-Host -ForegroundColor White
    
    $projects | ConvertTo-Json -Depth 5
    exit 0
}

function Resolve-ProjectId {
    param([string]$Name)
    $all = Get-Projects
    $match = $all | Where-Object { $_.name -eq $Name }
    if (-not $match) {
        # Try partial match if exact fails
        $match = $all | Where-Object { $_.name -like "*$Name*" }
    }
    
    if (-not $match) { throw "Project '$Name' not found." }
    if ($match.Count -gt 1) { 
        $names = $match.name -join ", "
        throw "Ambiguous project name '$Name'. Matches: $names" 
    }
    
    return $match.id
}

if ($ListRuns) {
    if (-not $ProjectId -and -not $ProjectName) { throw "ProjectId or ProjectName required" }
    
    if (-not $ProjectId) {
         $ProjectId = Resolve-ProjectId -Name $ProjectName
    }

    Write-Host "Fetching runs for Project ID: $ProjectId..." -ForegroundColor Cyan
    $runs = Get-Runs -ProjectId $ProjectId

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Recent Runs" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    
    $runs | Select-Object -First 20 | Format-Table -Property id, name, is_completed, passed_count, failed_count -AutoSize | Out-String | Write-Host -ForegroundColor White

    $runs | ConvertTo-Json -Depth 5
    exit 0
}

if ($ListSections) {
    if (-not $ProjectId -and -not $ProjectName) { throw "ProjectId or ProjectName required" }
    
    if (-not $ProjectId) {
         $ProjectId = Resolve-ProjectId -Name $ProjectName
    }

    $sections = Get-Sections -ProjectId $ProjectId

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Project Sections (ID: $ProjectId)" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    # Build tree view
    $lookup = @{}
    $sections | ForEach-Object { $lookup[$_.id] = $_ }
    $roots = $sections | Where-Object { -not $_.parent_id }

    function Show-Tree {
        param($Nodes, $Indent = 0)
        foreach ($node in $Nodes) {
            $prefix = " " * $Indent
            Write-Host "$prefix- [$($node.id)] $($node.name)" -ForegroundColor White
            
            $children = $sections | Where-Object { $_.parent_id -eq $node.id }
            if ($children) {
                Show-Tree -Nodes $children -Indent ($Indent + 2)
            }
        }
    }

    Show-Tree -Nodes $roots

    $sections | ConvertTo-Json -Depth 5
    exit 0
}

if ($GetSections) {
    if (-not $ProjectId) { throw "ProjectId required" }

    $sections = Get-Sections -ProjectId $ProjectId

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Project Sections" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    $sections | ForEach-Object { Write-Host "  $($_.id): $($_.name)" -ForegroundColor White }
    Write-Host ""
    $sections | ConvertTo-Json -Depth 5
    exit 0
}

if ($DeleteCase) {
    Assert-ReadinessForWrite
    Remove-TestRailCase -CaseId $DeleteCaseId
    @{ status = "deleted"; case_id = $DeleteCaseId } | ConvertTo-Json
    exit 0
}

if ($DeleteSection) {
    Assert-ReadinessForWrite
    $delParams = @{ SectionId = $DeleteSectionId }
    if ($ProjectId -gt 0) { $delParams.ProjectId = $ProjectId }
    if ($DeleteCases) { $delParams.IncludeCases = $true }
    Remove-TestRailSection @delParams
    @{ status = "deleted"; section_id = $DeleteSectionId; cases_deleted = [bool]$DeleteCases } | ConvertTo-Json
    exit 0
}

Write-Host "No operation specified. Use -GetCoverage, -GetCase, -CreateCase, -UpdateCase, -EnhanceCase, -BatchCreate, -CreateSection, -GetSections, -DeleteCase, -DeleteSection, or -TestConnection" -ForegroundColor Yellow
exit 1

