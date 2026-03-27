<#
.SYNOPSIS
    Prototype management script for AIRA - fetch source pages, inject requirements, publish versioned prototypes,
    and record complex multi-page scenarios.

.DESCRIPTION
    Supports seven modes:
    - InitProject:     Initialize a prototype source baseline from local HTML/CSS files when remote fetch is unavailable
    - FetchSource:     Download an existing web page (HTML + styles) as prototype base
    - AddRequirements: Inject user requirements into the prototype, marked as [PROTOTYPE]
    - Publish:         Create an immutable versioned prototype artifact package
    - ListVersions:    Show all published versions for a project
    - RecordFlow:      Create and manage multi-page scenario recordings (flows)
    - BuildFlow:       Generate a navigable SPA prototype from a recorded flow

.PARAMETER InitProject
    Initialize a project baseline in source/ from local HTML/CSS files while preserving the original app styles.

.PARAMETER FetchSource
    Fetch a web page from SourceUrl and store as prototype source.

.PARAMETER AddRequirements
    Add requirements from RequirementsFile (JSON array) to the prototype.

.PARAMETER Publish
    Publish the current prototype state as a versioned artifact.

.PARAMETER ListVersions
    List all published prototype versions for a project.

.PARAMETER RecordFlow
    Manage flow definitions: create flows, add steps, set sources, list or show flows.

.PARAMETER BuildFlow
    Build a single-file navigable SPA prototype from a recorded flow definition.

.PARAMETER SourceUrl
    URL of the page to fetch (required for FetchSource).

.PARAMETER Project
    Project slug. Auto-derived from SourceUrl when fetching; required for other modes.

.PARAMETER RequirementsFile
    Path to a JSON file containing an array of requirement objects.

.PARAMETER Requirements
    JSON string containing an array of requirement objects (alternative to RequirementsFile).

.PARAMETER Version
    Explicit version to publish (e.g., "1.2.0"). Auto-incremented if omitted.

.PARAMETER BumpType
    Version bump type when auto-incrementing: major, minor, or patch. Default: minor.

.PARAMETER Refresh
    Force re-fetch of source page even if cached.

.PARAMETER FlowAction
    Sub-action for RecordFlow: Create, AddStep, SetSource, Show, List.

.PARAMETER FlowId
    Unique slug for the flow (e.g., "login-to-dashboard").

.PARAMETER FlowName
    Human-readable name for the flow (used with Create).

.PARAMETER EntryUrl
    Starting URL for a new flow (used with Create).

.PARAMETER StepPage
    Short page label for a flow step (e.g., "login", "dashboard").

.PARAMETER StepUrl
    URL of the page at a flow step.

.PARAMETER StepActions
    JSON string containing an array of action objects for a flow step.

.PARAMETER StepDescription
    Description of what happens at this flow step.

.PARAMETER StepNumber
    1-based step number (used with SetSource).

.PARAMETER SourceHtmlFile
    Path to an HTML file to use as a step's captured source (used with SetSource).

.PARAMETER SourceCssFile
    Path to a CSS file to use as a step's captured styles (used with SetSource).
#>

[CmdletBinding(DefaultParameterSetName = "FetchSource")]
param(
    [Parameter(ParameterSetName = "InitProject", Mandatory = $true)]
    [switch]$InitProject,

    [Parameter(ParameterSetName = "FetchSource", Mandatory = $true)]
    [switch]$FetchSource,

    [Parameter(ParameterSetName = "AddRequirements", Mandatory = $true)]
    [switch]$AddRequirements,

    [Parameter(ParameterSetName = "Publish", Mandatory = $true)]
    [switch]$Publish,

    [Parameter(ParameterSetName = "ListVersions", Mandatory = $true)]
    [switch]$ListVersions,

    [Parameter(ParameterSetName = "RecordFlow", Mandatory = $true)]
    [switch]$RecordFlow,

    [Parameter(ParameterSetName = "BuildFlow", Mandatory = $true)]
    [switch]$BuildFlow,

    [Parameter(ParameterSetName = "InitProject")]
    [Parameter(ParameterSetName = "FetchSource", Mandatory = $true)]
    [string]$SourceUrl,

    [Parameter(ParameterSetName = "InitProject")]
    [Parameter(ParameterSetName = "AddRequirements", Mandatory = $true)]
    [Parameter(ParameterSetName = "Publish", Mandatory = $true)]
    [Parameter(ParameterSetName = "ListVersions", Mandatory = $true)]
    [Parameter(ParameterSetName = "RecordFlow", Mandatory = $true)]
    [Parameter(ParameterSetName = "BuildFlow", Mandatory = $true)]
    [string]$Project,

    [Parameter(ParameterSetName = "InitProject", Mandatory = $true)]
    [Parameter(ParameterSetName = "RecordFlow")]
    [string]$SourceHtmlFile,

    [Parameter(ParameterSetName = "InitProject")]
    [Parameter(ParameterSetName = "RecordFlow")]
    [string]$SourceCssFile,

    [Parameter(ParameterSetName = "AddRequirements")]
    [string]$RequirementsFile,

    [Parameter(ParameterSetName = "AddRequirements")]
    [string]$Requirements,

    [Parameter(ParameterSetName = "Publish")]
    [string]$Version,

    [Parameter(ParameterSetName = "Publish")]
    [Parameter(ParameterSetName = "AddRequirements")]
    [ValidateSet("major", "minor", "patch")]
    [string]$BumpType = "minor",

    # --- RecordFlow parameters ---
    [Parameter(ParameterSetName = "RecordFlow", Mandatory = $true)]
    [ValidateSet("Create", "AddStep", "SetSource", "Show", "List")]
    [string]$FlowAction,

    [Parameter(ParameterSetName = "RecordFlow")]
    [Parameter(ParameterSetName = "BuildFlow", Mandatory = $true)]
    [string]$FlowId,

    [Parameter(ParameterSetName = "RecordFlow")]
    [string]$FlowName,

    [Parameter(ParameterSetName = "RecordFlow")]
    [string]$EntryUrl,

    [Parameter(ParameterSetName = "RecordFlow")]
    [string]$StepPage,

    [Parameter(ParameterSetName = "RecordFlow")]
    [string]$StepUrl,

    [Parameter(ParameterSetName = "RecordFlow")]
    [string]$StepActions,

    [Parameter(ParameterSetName = "RecordFlow")]
    [string]$StepDescription,

    [Parameter(ParameterSetName = "RecordFlow")]
    [int]$StepNumber,

    # --- BuildFlow parameters ---
    [Parameter(ParameterSetName = "BuildFlow")]
    [string]$BuildFlowRequirementsFile,

    [Parameter(ParameterSetName = "BuildFlow")]
    [string]$BuildFlowRequirements,

    [Parameter(ParameterSetName = "BuildFlow")]
    [string]$BuildFlowVersion,

    [switch]$Refresh
)

$ErrorActionPreference = "Stop"

# --- Bootstrap ---
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../../..")).Path
$commonModule = Join-Path $repoRoot "core/modules/Aira.Common.psm1"
$protoModule  = Join-Path $PSScriptRoot "../modules/Aira.Prototyping.psm1"

Import-Module $protoModule  -Force -WarningAction SilentlyContinue
Import-Module $commonModule -Force -WarningAction SilentlyContinue

# Helper: safely parse a JSON array (PS 5.1 compatible)
function ConvertFrom-JsonArray {
    param([string]$Json)
    $parsed = $Json | ConvertFrom-Json
    if ($null -eq $parsed) { return @() }
    if ($parsed -is [array]) { return @($parsed) }
    return @(,$parsed)
}

function Resolve-WorkspacePath {
    param([string]$PathValue)

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return $null
    }

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return $PathValue
    }

    return Join-Path $repoRoot $PathValue
}

# ============================================================
# MODE: InitProject
# ============================================================
if ($PSCmdlet.ParameterSetName -eq "InitProject") {
    $artifactRoot = Get-PrototypeArtifactRoot -RepoRoot $repoRoot -Project $Project
    $sourceDir = Join-Path $artifactRoot "source"

    $htmlPath = Resolve-WorkspacePath -PathValue $SourceHtmlFile
    if (-not $htmlPath -or -not (Test-Path $htmlPath)) {
        throw "InitProject requires -SourceHtmlFile pointing to an existing baseline HTML file."
    }

    $cssPath = Resolve-WorkspacePath -PathValue $SourceCssFile
    if ($SourceCssFile -and -not (Test-Path $cssPath)) {
        throw "InitProject received -SourceCssFile but the file was not found: $cssPath"
    }

    $htmlContent = Get-Content $htmlPath -Raw -Encoding UTF8
    $cssContent = if ($cssPath) { Get-Content $cssPath -Raw -Encoding UTF8 } else { "" }

    Ensure-Dir -Path $sourceDir
    $htmlContent | Set-Content (Join-Path $sourceDir "index.html") -Encoding UTF8
    $cssContent | Set-Content (Join-Path $sourceDir "styles.css") -Encoding UTF8

    $metadata = @{
        project                  = $Project
        source_url               = if ($SourceUrl) { $SourceUrl } else { $null }
        initialized_at           = (Get-Date).ToString("s")
        initialization_mode      = "local-seed"
        preserve_original_styles = $true
        content_hash             = Get-ContentHash -Content ($htmlContent + "`n/*styles*/`n" + $cssContent)
        files                    = @{
            html   = "artifacts/prototypes/$Project/source/index.html"
            styles = "artifacts/prototypes/$Project/source/styles.css"
        }
    }
    $metadata | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $sourceDir "metadata.json") -Encoding UTF8

    @{
        status                   = "ok"
        project                  = $Project
        initialized              = $true
        preserve_original_styles = $true
        source_path              = "artifacts/prototypes/$Project/source/"
        files                    = $metadata.files
    } | ConvertTo-Json -Depth 10
    exit 0
}

# ============================================================
# MODE: FetchSource
# ============================================================
if ($PSCmdlet.ParameterSetName -eq "FetchSource") {
    # Validate URL format
    try {
        $null = [System.Uri]::new($SourceUrl)
    } catch {
        throw "Invalid URL: $SourceUrl"
    }

    $projectSlug = Resolve-ProjectFromUrl -Url $SourceUrl
    $artifactRoot = Get-PrototypeArtifactRoot -RepoRoot $repoRoot -Project $projectSlug
    $sourceDir = Join-Path $artifactRoot "source"

    # Check cache
    if (-not $Refresh -and (Test-Path (Join-Path $sourceDir "index.html"))) {
        Write-Host "[cache-hit] Source already fetched for project '$projectSlug'. Use -Refresh to re-fetch." -ForegroundColor Cyan
        $metadata = @{}
        $metaFile = Join-Path $sourceDir "metadata.json"
        if (Test-Path $metaFile) {
            $metadata = Get-Content $metaFile -Raw -Encoding UTF8 | ConvertFrom-Json
        }
        @{
            status     = "ok"
            project    = $projectSlug
            source_url = $SourceUrl
            cached     = $true
            fetched_at = if ($metadata.fetched_at) { $metadata.fetched_at } else { "unknown" }
            files      = @{
                html   = "artifacts/prototypes/$projectSlug/source/index.html"
                styles = "artifacts/prototypes/$projectSlug/source/styles.css"
            }
        } | ConvertTo-Json -Depth 10
        exit 0
    }

    # Fetch page content
    Write-Host "[fetch] Downloading page from: $SourceUrl" -ForegroundColor Yellow
    try {
        $response = Invoke-WebRequest -Uri $SourceUrl -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
        $htmlContent = $response.Content
    } catch {
        throw "Failed to fetch page: $($_.Exception.Message)"
    }

    # Extract inline styles and linked stylesheet references
    $styles = ""

    # Extract <style> blocks
    $styleMatches = [regex]::Matches($htmlContent, '(?si)<style[^>]*>(.*?)</style>')
    foreach ($m in $styleMatches) {
        $styles += $m.Groups[1].Value + "`n"
    }

    # Extract linked CSS (href values from <link rel="stylesheet">)
    $linkMatches = [regex]::Matches($htmlContent, '(?i)<link[^>]+rel=["\u0027]stylesheet["\u0027][^>]+href=["\u0027]([^"\u0027]+)["\u0027]')
    foreach ($m in $linkMatches) {
        $cssUrl = $m.Groups[1].Value
        # Resolve relative URLs
        if ($cssUrl -notmatch '^https?://') {
            $baseUri = [System.Uri]::new($SourceUrl)
            $cssUrl = [System.Uri]::new($baseUri, $cssUrl).AbsoluteUri
        }
        try {
            $cssResp = Invoke-WebRequest -Uri $cssUrl -UseBasicParsing -TimeoutSec 15 -ErrorAction SilentlyContinue
            if ($cssResp) { $styles += "/* Source: $cssUrl */`n" + $cssResp.Content + "`n" }
        } catch {
            Write-Host "[warn] Could not fetch stylesheet: $cssUrl" -ForegroundColor DarkYellow
        }
    }

    # Save to source directory
    Ensure-Dir -Path $sourceDir
    $htmlContent | Set-Content (Join-Path $sourceDir "index.html") -Encoding UTF8
    $styles | Set-Content (Join-Path $sourceDir "styles.css") -Encoding UTF8

    $contentHash = Get-ContentHash -Content $htmlContent
    $metadata = @{
        source_url  = $SourceUrl
        project     = $projectSlug
        fetched_at  = (Get-Date).ToString("s")
        content_hash = $contentHash
        html_length = $htmlContent.Length
        styles_length = $styles.Length
    }
    $metadata | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $sourceDir "metadata.json") -Encoding UTF8

    Write-Host "[ok] Source saved to: artifacts/prototypes/$projectSlug/source/" -ForegroundColor Green

    @{
        status     = "ok"
        project    = $projectSlug
        source_url = $SourceUrl
        fetched_at = $metadata.fetched_at
        content_hash = $contentHash
        files      = @{
            html   = "artifacts/prototypes/$projectSlug/source/index.html"
            styles = "artifacts/prototypes/$projectSlug/source/styles.css"
        }
    } | ConvertTo-Json -Depth 10
    exit 0
}

# ============================================================
# MODE: AddRequirements
# ============================================================
if ($PSCmdlet.ParameterSetName -eq "AddRequirements") {
    $artifactRoot = Get-PrototypeArtifactRoot -RepoRoot $repoRoot -Project $Project
    $sourceDir = Join-Path $artifactRoot "source"

    if (-not (Test-Path (Join-Path $sourceDir "index.html"))) {
        throw "No source page found for project '$Project'. Run -FetchSource first."
    }

    # Load requirements from file or string
    $reqList = @()
    if ($RequirementsFile) {
        $reqPath = if ([System.IO.Path]::IsPathRooted($RequirementsFile)) {
            $RequirementsFile
        } else {
            Join-Path $repoRoot $RequirementsFile
        }
        if (-not (Test-Path $reqPath)) { throw "Requirements file not found: $reqPath" }
        $reqList = ConvertFrom-JsonArray -Json (Get-Content $reqPath -Raw -Encoding UTF8)
    } elseif ($Requirements) {
        $reqList = ConvertFrom-JsonArray -Json $Requirements
    } else {
        throw "Provide either -RequirementsFile or -Requirements (JSON string)."
    }

    if ($reqList.Count -eq 0) { throw "No requirements provided." }

    # Load existing requirements from the latest version (if any)
    $registry = Get-PrototypeVersions -RepoRoot $repoRoot -Project $Project
    $existingReqs = @()
    $currentVersion = "0.0.0"

    if ($registry.versions -and $registry.versions.Count -gt 0) {
        $latest = $registry.versions | Sort-Object { [version]$_.version } | Select-Object -Last 1
        $currentVersion = $latest.version
        $latestReqFile = Join-Path $artifactRoot "v$currentVersion/requirements.json"
        if (Test-Path $latestReqFile) {
            $existingReqs = ConvertFrom-JsonArray -Json (Get-Content $latestReqFile -Raw -Encoding UTF8)
        }
    }

    # Assign IDs and merge
    $allExisting = @($existingReqs)
    $newVersion = if ($Version) { $Version } else { Get-NextVersion -CurrentVersion $currentVersion -BumpType $BumpType }
    $addedReqs = @()

    foreach ($raw in $reqList) {
        $combined = @($allExisting) + @($addedReqs)
        $reqId = New-RequirementId -ExistingRequirements $combined
        $reqObj = @{
            id          = $reqId
            title       = if ($raw.title) { "$($raw.title)" } else { "Untitled Requirement" }
            description = if ($raw.description) { "$($raw.description)" } else { "" }
            priority    = if ($raw.priority) { "$($raw.priority)" } else { "Medium" }
            status      = "prototype"
            source      = if ($raw.source) { "$($raw.source)" } else { "User requirement" }
            added_in    = $newVersion
            modified_in = $null
            date_added  = (Get-Date).ToString("yyyy-MM-dd")
        }
        $addedReqs += $reqObj
    }

    $allReqs = @($existingReqs) + @($addedReqs)

    # Build prototype HTML
    $sourceHtml = Get-Content (Join-Path $sourceDir "index.html") -Raw -Encoding UTF8
    $prototypeHtml = ConvertTo-PrototypeHtml -SourceHtml $sourceHtml -Requirements $allReqs -Version $newVersion

    # Save working copy (not yet published)
    $workDir = Join-Path $artifactRoot "working"
    Ensure-Dir -Path $workDir
    $prototypeHtml | Set-Content (Join-Path $workDir "prototype.html") -Encoding UTF8
    $allReqs | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $workDir "requirements.json") -Encoding UTF8
    @{ pending_version = $newVersion; project = $Project } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $workDir "state.json") -Encoding UTF8

    Write-Host "[ok] Added $($addedReqs.Count) requirements to project '$Project'. Pending version: v$newVersion" -ForegroundColor Green
    Write-Host "[info] Run -Publish -Project '$Project' to publish v$newVersion" -ForegroundColor Cyan

    @{
        status              = "ok"
        project             = $Project
        requirements_added  = $addedReqs.Count
        total_requirements  = $allReqs.Count
        current_version     = $currentVersion
        pending_version     = $newVersion
        working_path        = "artifacts/prototypes/$Project/working/"
        added_ids           = @($addedReqs | ForEach-Object { $_.id })
    } | ConvertTo-Json -Depth 10
    exit 0
}

# ============================================================
# MODE: Publish
# ============================================================
if ($PSCmdlet.ParameterSetName -eq "Publish") {
    $artifactRoot = Get-PrototypeArtifactRoot -RepoRoot $repoRoot -Project $Project
    $workDir = Join-Path $artifactRoot "working"

    if (-not (Test-Path (Join-Path $workDir "prototype.html"))) {
        throw "No working prototype found for project '$Project'. Run -AddRequirements or -BuildFlow first."
    }

    # Read working state
    $stateFile = Join-Path $workDir "state.json"
    $state = @{ pending_version = "1.0.0" }
    if (Test-Path $stateFile) {
        $state = Get-Content $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json | ForEach-Object { Convert-PSObjectToHashtable $_ }
    }

    $publishVersion = if ($Version) { $Version } else { $state.pending_version }
    $versionDir = Join-Path $artifactRoot "v$publishVersion"

    if (Test-Path $versionDir) {
        throw "Version v$publishVersion already exists for project '$Project'. Versions are immutable - use a different version number."
    }

    # Create version directory
    Ensure-Dir -Path $versionDir

    # Copy working files to version directory
    $protoHtml = Get-Content (Join-Path $workDir "prototype.html") -Raw -Encoding UTF8
    $protoHtml | Set-Content (Join-Path $versionDir "prototype.html") -Encoding UTF8

    $reqsContent = Get-Content (Join-Path $workDir "requirements.json") -Raw -Encoding UTF8
    $reqsContent | Set-Content (Join-Path $versionDir "requirements.json") -Encoding UTF8

    $reqs = ConvertFrom-JsonArray -Json $reqsContent

    # Determine previous version for changelog
    $registry = Get-PrototypeVersions -RepoRoot $repoRoot -Project $Project
    $prevVersion = $null
    $prevReqs = @()
    if ($registry.versions -and $registry.versions.Count -gt 0) {
        $sorted = $registry.versions | Sort-Object { [version]$_.version }
        $prevVersion = ($sorted | Select-Object -Last 1).version
        $prevReqFile = Join-Path $artifactRoot "v$prevVersion/requirements.json"
        if (Test-Path $prevReqFile) {
            $prevReqs = ConvertFrom-JsonArray -Json (Get-Content $prevReqFile -Raw -Encoding UTF8)
        }
    }

    # Compute added/modified/removed
    $prevIds = @($prevReqs | ForEach-Object { $_.id })
    $currIds = @($reqs | ForEach-Object { $_.id })
    $added    = @($reqs | Where-Object { $_.id -notin $prevIds })
    $removed  = @($prevReqs | Where-Object { $_.id -notin $currIds })
    $modified = @($reqs | Where-Object { $_.id -in $prevIds -and $_.modified_in -eq $publishVersion })

    # Generate changelog
    $changelog = New-PrototypeChangelog -Project $Project -Version $publishVersion `
        -PreviousVersion $prevVersion -Added $added -Modified $modified -Removed $removed
    $changelog | Set-Content (Join-Path $versionDir "CHANGELOG.md") -Encoding UTF8

    # Generate manifest
    $contentHash = Get-ContentHash -Content $protoHtml
    $manifest = @{
        project               = $Project
        version               = $publishVersion
        previous_version      = $prevVersion
        published_at          = (Get-Date).ToString("s")
        source_url            = $null
        prototype_type        = if ($state.type) { $state.type } else { "single-page" }
        preserves_original_styles = $true
        requirements_count    = $reqs.Count
        requirements_added    = $added.Count
        requirements_modified = $modified.Count
        requirements_removed  = $removed.Count
        content_hash          = $contentHash
        files                 = @("prototype.html", "requirements.json", "CHANGELOG.md", "manifest.json")
    }

    # Read source URL from source metadata if available
    $srcMeta = Join-Path $artifactRoot "source/metadata.json"
    if (Test-Path $srcMeta) {
        $meta = Get-Content $srcMeta -Raw -Encoding UTF8 | ConvertFrom-Json
        $manifest.source_url = $meta.source_url
    }

    $manifest | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $versionDir "manifest.json") -Encoding UTF8

    # Update version registry
    $versionEntry = @{
        version      = $publishVersion
        published_at = $manifest.published_at
        requirements = $reqs.Count
        content_hash = $contentHash
    }
    if (-not $registry.versions) { $registry.versions = @() }
    $registry.versions = @($registry.versions) + @($versionEntry)
    $registry.project = $Project
    Save-PrototypeVersions -RepoRoot $repoRoot -Project $Project -Registry $registry

    # Update latest/ directory
    $latestDir = Join-Path $artifactRoot "latest"
    if (Test-Path $latestDir) { Remove-Item $latestDir -Recurse -Force }
    Ensure-Dir -Path $latestDir
    Copy-Item -Path (Join-Path $versionDir "*") -Destination $latestDir -Recurse -Force

    # Clean working directory
    if (Test-Path $workDir) { Remove-Item $workDir -Recurse -Force }

    Write-Host "[ok] Published prototype v$publishVersion for project '$Project'" -ForegroundColor Green

    @{
        status    = "ok"
        project   = $Project
        version   = $publishVersion
        published_at = $manifest.published_at
        artifacts = @{
            prototype    = "artifacts/prototypes/$Project/v$publishVersion/prototype.html"
            requirements = "artifacts/prototypes/$Project/v$publishVersion/requirements.json"
            changelog    = "artifacts/prototypes/$Project/v$publishVersion/CHANGELOG.md"
            manifest     = "artifacts/prototypes/$Project/v$publishVersion/manifest.json"
        }
    } | ConvertTo-Json -Depth 10
    exit 0
}

# ============================================================
# MODE: ListVersions
# ============================================================
if ($PSCmdlet.ParameterSetName -eq "ListVersions") {
    $registry = Get-PrototypeVersions -RepoRoot $repoRoot -Project $Project

    if (-not $registry.versions -or $registry.versions.Count -eq 0) {
        Write-Host "[info] No published versions found for project '$Project'." -ForegroundColor Cyan
        @{ status = "ok"; project = $Project; versions = @() } | ConvertTo-Json -Depth 10
        exit 0
    }

    Write-Host "[ok] Found $($registry.versions.Count) version(s) for project '$Project'" -ForegroundColor Green
    $registry | ConvertTo-Json -Depth 20
    exit 0
}

# ============================================================
# MODE: RecordFlow
# ============================================================
if ($PSCmdlet.ParameterSetName -eq "RecordFlow") {

    switch ($FlowAction) {

        "Create" {
            if (-not $FlowId)   { throw "RecordFlow -Create requires -FlowId." }
            if (-not $FlowName) { throw "RecordFlow -Create requires -FlowName." }
            if (-not $EntryUrl) { throw "RecordFlow -Create requires -EntryUrl." }

            # Check if flow already exists
            $flowsDir = Get-FlowsDirectory -RepoRoot $repoRoot -Project $Project
            $flowFile = Join-Path $flowsDir "$FlowId.json"
            if (Test-Path $flowFile) {
                throw "Flow '$FlowId' already exists for project '$Project'. Choose a different FlowId."
            }

            $flow = New-PrototypeFlow -RepoRoot $repoRoot -Project $Project `
                -FlowId $FlowId -FlowName $FlowName -EntryUrl $EntryUrl
            Save-PrototypeFlow -RepoRoot $repoRoot -Project $Project -Flow $flow

            Write-Host "[ok] Created flow '$FlowId' for project '$Project'" -ForegroundColor Green

            @{
                status   = "ok"
                action   = "create"
                project  = $Project
                flow_id  = $FlowId
                name     = $FlowName
                entry_url = $EntryUrl
                steps    = 0
                path     = "artifacts/prototypes/$Project/flows/$FlowId.json"
            } | ConvertTo-Json -Depth 10
            exit 0
        }

        "AddStep" {
            if (-not $FlowId)   { throw "RecordFlow -AddStep requires -FlowId." }
            if (-not $StepPage) { throw "RecordFlow -AddStep requires -StepPage." }
            if (-not $StepUrl)  { throw "RecordFlow -AddStep requires -StepUrl." }

            $flow = Get-PrototypeFlow -RepoRoot $repoRoot -Project $Project -FlowId $FlowId

            $actions = @()
            if ($StepActions) {
                $actions = ConvertFrom-JsonArray -Json $StepActions
            }

            $descText = if ($StepDescription) { $StepDescription } else { "" }

            $flow = Add-PrototypeFlowStep -Flow $flow -Page $StepPage -Url $StepUrl `
                -Actions $actions -Description $descText
            Save-PrototypeFlow -RepoRoot $repoRoot -Project $Project -Flow $flow

            $newStep = $flow.steps[$flow.steps.Count - 1]
            Write-Host "[ok] Added step $($newStep.step) '$StepPage' to flow '$FlowId'" -ForegroundColor Green

            @{
                status      = "ok"
                action      = "add_step"
                project     = $Project
                flow_id     = $FlowId
                step_number = $newStep.step
                page        = $StepPage
                url         = $StepUrl
                actions     = $actions.Count
                total_steps = $flow.steps.Count
            } | ConvertTo-Json -Depth 10
            exit 0
        }

        "SetSource" {
            if (-not $FlowId)     { throw "RecordFlow -SetSource requires -FlowId." }
            if (-not $StepNumber) { throw "RecordFlow -SetSource requires -StepNumber." }

            $flow = Get-PrototypeFlow -RepoRoot $repoRoot -Project $Project -FlowId $FlowId

            # Load HTML content
            $htmlContent = ""
            if ($SourceHtmlFile) {
                $htmlPath = if ([System.IO.Path]::IsPathRooted($SourceHtmlFile)) { $SourceHtmlFile } else { Join-Path $repoRoot $SourceHtmlFile }
                if (-not (Test-Path $htmlPath)) { throw "Source HTML file not found: $htmlPath" }
                $htmlContent = Get-Content $htmlPath -Raw -Encoding UTF8
            } else {
                throw "RecordFlow -SetSource requires -SourceHtmlFile."
            }

            # Load CSS content (optional)
            $cssContent = ""
            if ($SourceCssFile) {
                $cssPath = if ([System.IO.Path]::IsPathRooted($SourceCssFile)) { $SourceCssFile } else { Join-Path $repoRoot $SourceCssFile }
                if (Test-Path $cssPath) {
                    $cssContent = Get-Content $cssPath -Raw -Encoding UTF8
                }
            }

            $flow = Set-FlowStepSource -RepoRoot $repoRoot -Project $Project -Flow $flow `
                -StepNumber $StepNumber -HtmlContent $htmlContent -CssContent $cssContent

            Write-Host "[ok] Set source for step $StepNumber of flow '$FlowId'" -ForegroundColor Green

            @{
                status        = "ok"
                action        = "set_source"
                project       = $Project
                flow_id       = $FlowId
                step_number   = $StepNumber
                html_length   = $htmlContent.Length
                css_length    = $cssContent.Length
                source_path   = "artifacts/prototypes/$Project/flows/$FlowId/step-$StepNumber/"
            } | ConvertTo-Json -Depth 10
            exit 0
        }

        "Show" {
            if (-not $FlowId) { throw "RecordFlow -Show requires -FlowId." }

            $flow = Get-PrototypeFlow -RepoRoot $repoRoot -Project $Project -FlowId $FlowId

            Write-Host "[ok] Flow '$FlowId' for project '$Project'" -ForegroundColor Green
            $flow | ConvertTo-Json -Depth 20
            exit 0
        }

        "List" {
            $flows = Get-PrototypeFlows -RepoRoot $repoRoot -Project $Project

            if ($flows.Count -eq 0) {
                Write-Host "[info] No flows found for project '$Project'." -ForegroundColor Cyan
                @{ status = "ok"; project = $Project; flows = @() } | ConvertTo-Json -Depth 10
                exit 0
            }

            Write-Host "[ok] Found $($flows.Count) flow(s) for project '$Project'" -ForegroundColor Green
            @{ status = "ok"; project = $Project; flows = $flows } | ConvertTo-Json -Depth 20
            exit 0
        }

        default { throw "Unknown FlowAction: $FlowAction" }
    }
}

# ============================================================
# MODE: BuildFlow
# ============================================================
if ($PSCmdlet.ParameterSetName -eq "BuildFlow") {
    $flow = Get-PrototypeFlow -RepoRoot $repoRoot -Project $Project -FlowId $FlowId
    $artifactRoot = Get-PrototypeArtifactRoot -RepoRoot $repoRoot -Project $Project
    $flowsDir = Get-FlowsDirectory -RepoRoot $repoRoot -Project $Project

    # Load requirements (optional)
    $reqs = @()
    if ($BuildFlowRequirementsFile) {
        $rPath = if ([System.IO.Path]::IsPathRooted($BuildFlowRequirementsFile)) { $BuildFlowRequirementsFile } else { Join-Path $repoRoot $BuildFlowRequirementsFile }
        if (Test-Path $rPath) {
            $reqs = ConvertFrom-JsonArray -Json (Get-Content $rPath -Raw -Encoding UTF8)
        }
    } elseif ($BuildFlowRequirements) {
        $reqs = ConvertFrom-JsonArray -Json $BuildFlowRequirements
    } else {
        # Check working directory or latest version for existing requirements
        $workReqFile = Join-Path $artifactRoot "working/requirements.json"
        $latestReqFile = Join-Path $artifactRoot "latest/requirements.json"
        if (Test-Path $workReqFile) {
            $reqs = ConvertFrom-JsonArray -Json (Get-Content $workReqFile -Raw -Encoding UTF8)
        } elseif (Test-Path $latestReqFile) {
            $reqs = ConvertFrom-JsonArray -Json (Get-Content $latestReqFile -Raw -Encoding UTF8)
        }
    }

    # Determine version
    $ver = "0.1.0"
    if ($BuildFlowVersion) {
        $ver = $BuildFlowVersion
    } else {
        $registry = Get-PrototypeVersions -RepoRoot $repoRoot -Project $Project
        if ($registry.versions -and $registry.versions.Count -gt 0) {
            $latest = $registry.versions | Sort-Object { [version]$_.version } | Select-Object -Last 1
            $ver = Get-NextVersion -CurrentVersion $latest.version -BumpType "minor"
        }
    }

    # Check steps have sources
    $stepsWithSource = @($flow.steps | Where-Object {
        $hs = if ($_ -is [hashtable]) { $_.has_source } else { $_.has_source }
        $hs -eq $true
    })
    if ($stepsWithSource.Count -eq 0) {
        Write-Host "[warn] No steps have captured sources. The SPA will show placeholders." -ForegroundColor DarkYellow
    }

    # Generate SPA
    $sourceDir = Join-Path $artifactRoot "source"
    $spa = ConvertTo-FlowPrototypeHtml -Flow $flow -Requirements $reqs -Version $ver -FlowsDir $flowsDir -ProjectSourceDir $sourceDir

    # Save to working directory
    $workDir = Join-Path $artifactRoot "working"
    Ensure-Dir -Path $workDir
    $spa | Set-Content (Join-Path $workDir "prototype.html") -Encoding UTF8
    $reqsJson = if ($reqs.Count -eq 0) { "[]" } else { $reqs | ConvertTo-Json -Depth 20 }
    $reqsJson | Set-Content (Join-Path $workDir "requirements.json") -Encoding UTF8
    @{
        pending_version = $ver
        project         = $Project
        flow_id         = $FlowId
        type            = "flow"
    } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $workDir "state.json") -Encoding UTF8

    Write-Host "[ok] Built flow prototype for '$FlowId' (v$ver). Use -Publish to finalize." -ForegroundColor Green

    @{
        status          = "ok"
        project         = $Project
        flow_id         = $FlowId
        version         = $ver
        steps           = $flow.steps.Count
        steps_with_src  = $stepsWithSource.Count
        requirements    = $reqs.Count
        working_path    = "artifacts/prototypes/$Project/working/prototype.html"
    } | ConvertTo-Json -Depth 10
    exit 0
}
