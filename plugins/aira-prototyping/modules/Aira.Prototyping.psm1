Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$_protoRepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../../..")).Path
Import-Module (Join-Path $_protoRepoRoot "core/modules/Aira.Common.psm1") -Force -WarningAction SilentlyContinue

<#
.SYNOPSIS
    Prototyping module for AIRA — manages prototype lifecycle (fetch, inject, publish).
#>

function Resolve-ProjectFromUrl {
    <#
    .SYNOPSIS
        Derives a project slug from a shared URL.
    .EXAMPLE
        Resolve-ProjectFromUrl -Url "https://example.org/dashboard"
        # Returns: "example-org"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url
    )

    $uri = [System.Uri]::new($Url)
    $host_ = $uri.Host -replace '^www\.', ''
    # Use domain without TLD as base, append first path segment if present
    $parts = $host_ -split '\.'
    $slug = if ($parts.Count -ge 2) { $parts[0..($parts.Count - 2)] -join '-' } else { $parts[0] }

    $pathSegment = ($uri.AbsolutePath.Trim('/') -split '/')[0]
    if ($pathSegment) {
        $slug = "$slug-$pathSegment"
    }

    # Sanitize: lowercase, alphanumeric + hyphens only
    $slug = ($slug -replace '[^a-zA-Z0-9\-]', '-').ToLowerInvariant()
    $slug = ($slug -replace '-{2,}', '-').Trim('-')

    if (-not $slug) { $slug = "unknown-project" }
    return $slug
}

function Get-PrototypeArtifactRoot {
    <#
    .SYNOPSIS
        Returns the artifact root path for a prototype project.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$Project
    )

    return Join-Path $RepoRoot "artifacts/prototypes/$Project"
}

function Get-PrototypeVersions {
    <#
    .SYNOPSIS
        Reads the version registry for a prototype project.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$Project
    )

    $root = Get-PrototypeArtifactRoot -RepoRoot $RepoRoot -Project $Project
    $versionsFile = Join-Path $root "versions.json"

    if (-not (Test-Path $versionsFile)) {
        return @{ project = $Project; versions = @() }
    }

    return (Get-Content $versionsFile -Raw -Encoding UTF8 | ConvertFrom-Json | ForEach-Object { Convert-PSObjectToHashtable $_ })
}

function Save-PrototypeVersions {
    <#
    .SYNOPSIS
        Writes the version registry for a prototype project.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$Project,
        [Parameter(Mandatory = $true)][hashtable]$Registry
    )

    $root = Get-PrototypeArtifactRoot -RepoRoot $RepoRoot -Project $Project
    Ensure-Dir -Path $root
    $Registry | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $root "versions.json") -Encoding UTF8
}

function Get-NextVersion {
    <#
    .SYNOPSIS
        Computes the next SemVer version based on bump type.
    .PARAMETER CurrentVersion
        Current version string (e.g., "1.0.0"). Use "0.0.0" for first version.
    .PARAMETER BumpType
        One of: major, minor, patch
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$CurrentVersion,
        [ValidateSet("major", "minor", "patch")]
        [string]$BumpType = "minor"
    )

    $parts = $CurrentVersion -split '\.'
    $major = [int]$parts[0]
    $minor = if ($parts.Count -gt 1) { [int]$parts[1] } else { 0 }
    $patch = if ($parts.Count -gt 2) { [int]$parts[2] } else { 0 }

    switch ($BumpType) {
        "major" { $major++; $minor = 0; $patch = 0 }
        "minor" { $minor++; $patch = 0 }
        "patch" { $patch++ }
    }

    return "$major.$minor.$patch"
}

function Get-ContentHash {
    <#
    .SYNOPSIS
        Computes a SHA-256 hash for a string.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Content
    )

    $sha = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Content)
    $hash = $sha.ComputeHash($bytes)
    $sha.Dispose()
    return "sha256:" + ([BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
}

function New-RequirementId {
    <#
    .SYNOPSIS
        Generates the next REQ-NNN id based on existing requirements.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][array]$ExistingRequirements = @()
    )

    $maxNum = 0
    foreach ($req in $ExistingRequirements) {
        if ($req.id -match '^REQ-(\d+)$') {
            $num = [int]$Matches[1]
            if ($num -gt $maxNum) { $maxNum = $num }
        }
    }

    $next = $maxNum + 1
    return "REQ-{0:D3}" -f $next
}

function ConvertTo-PrototypeHtml {
    <#
    .SYNOPSIS
        Injects prototype requirement annotations into source HTML.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SourceHtml,
        [Parameter(Mandatory = $true)][array]$Requirements,
        [Parameter(Mandatory = $true)][string]$Version
    )

    $reqBlocks = @()
    foreach ($req in $Requirements) {
        $id = $req.id
        $title = [System.Net.WebUtility]::HtmlEncode($req.title)
        $desc = [System.Net.WebUtility]::HtmlEncode($req.description)
        $priority = [System.Net.WebUtility]::HtmlEncode($req.priority)
        $date = if ($req.added_in -eq $Version) { (Get-Date).ToString("yyyy-MM-dd") } else { $req.date_added }

        $block = @"

<!-- [PROTOTYPE:$id] v$Version | Priority: $priority | Added: $date -->
<div class="aira-prototype-requirement" data-req-id="$id" data-version="$Version">
  <h4>$id`: $title</h4>
  <p>$desc</p>
  <span class="aira-meta">Priority: $priority | Status: prototype</span>
</div>
<!-- [/PROTOTYPE:$id] -->
"@
        $reqBlocks += $block
    }

    $reqSection = @"

<!-- [AIRA-PROTOTYPE-REQUIREMENTS] v$Version -->
<style>
.aira-prototype-requirements { padding: 20px; margin: 20px 0; border: 2px dashed #f0ad4e; background: #fefbed; }
.aira-prototype-requirements h3 { color: #8a6d3b; }
.aira-prototype-requirement { padding: 10px; margin: 10px 0; border-left: 4px solid #f0ad4e; background: #fff; }
.aira-prototype-requirement h4 { margin: 0 0 5px 0; color: #333; }
.aira-meta { font-size: 0.85em; color: #999; }
</style>
<div class="aira-prototype-requirements" id="aira-requirements">
  <h3>Prototype Requirements (v$Version)</h3>
$($reqBlocks -join "`n")
</div>
<!-- [/AIRA-PROTOTYPE-REQUIREMENTS] -->
"@

    # Insert before </body> if present, otherwise append
    if ($SourceHtml -match '(?i)</body>') {
        return $SourceHtml -replace '(?i)</body>', "$reqSection`n</body>"
    } else {
        return $SourceHtml + $reqSection
    }
}

function New-PrototypeChangelog {
    <#
    .SYNOPSIS
        Generates a CHANGELOG.md entry for a prototype version.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Project,
        [Parameter(Mandatory = $true)][string]$Version,
        [string]$PreviousVersion,
        [array]$Added = @(),
        [array]$Modified = @(),
        [array]$Removed = @()
    )

    $date = (Get-Date).ToString("yyyy-MM-dd")
    $lines = @("# Changelog - $Project", "", "## [$Version] - $date", "")

    if ($Added.Count -gt 0) {
        $lines += "### Added"
        foreach ($r in $Added) { $lines += "- **$($r.id)**: $($r.title) (Priority: $($r.priority))" }
        $lines += ""
    }
    if ($Modified.Count -gt 0) {
        $lines += "### Modified"
        foreach ($r in $Modified) { $lines += "- **$($r.id)**: $($r.title)" }
        $lines += ""
    }
    if ($Removed.Count -gt 0) {
        $lines += "### Removed"
        foreach ($r in $Removed) { $lines += "- **$($r.id)**: $($r.title)" }
        $lines += ""
    }

    if ($PreviousVersion) {
        $lines += "---", "Previous version: v$PreviousVersion"
    }

    return ($lines -join "`n")
}

# ============================================================
# Flow / Scenario Recording
# ============================================================

function Get-FlowsDirectory {
    <#
    .SYNOPSIS
        Returns the flows directory path for a prototype project.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$Project
    )

    $root = Get-PrototypeArtifactRoot -RepoRoot $RepoRoot -Project $Project
    return Join-Path $root "flows"
}

function New-PrototypeFlow {
    <#
    .SYNOPSIS
        Creates a new flow definition for multi-page scenario recording.
    .PARAMETER FlowId
        Unique slug for the flow (e.g., "login-to-dashboard").
    .PARAMETER FlowName
        Human-readable name for the scenario.
    .PARAMETER EntryUrl
        The starting URL of the flow.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$Project,
        [Parameter(Mandatory = $true)][string]$FlowId,
        [Parameter(Mandatory = $true)][string]$FlowName,
        [Parameter(Mandatory = $true)][string]$EntryUrl
    )

    $flow = @{
        flow_id    = $FlowId
        name       = $FlowName
        project    = $Project
        entry_url  = $EntryUrl
        steps      = @()
        created_at = (Get-Date).ToString("s")
        updated_at = (Get-Date).ToString("s")
    }
    return $flow
}

function Add-PrototypeFlowStep {
    <#
    .SYNOPSIS
        Adds a step to a flow definition.
    .PARAMETER Flow
        The flow hashtable to add the step to.
    .PARAMETER Page
        A short label for this page/state (e.g., "login", "dashboard").
    .PARAMETER Url
        The URL of this page (can be the same as a previous step if it is a state change).
    .PARAMETER Actions
        Array of action hashtables. Each action has: type (navigate|click|type|select|snapshot|wait|scroll|assert), plus
        optional keys: selector, value, label, timeout_ms.
    .PARAMETER Description
        Optional description of what happens at this step.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Flow,
        [Parameter(Mandatory = $true)][string]$Page,
        [Parameter(Mandatory = $true)][string]$Url,
        [array]$Actions = @(),
        [string]$Description = ""
    )

    $stepNumber = $Flow.steps.Count + 1
    $step = @{
        step        = $stepNumber
        page        = $Page
        url         = $Url
        description = $Description
        actions     = @($Actions)
        has_source  = $false
    }
    $Flow.steps = @($Flow.steps) + @($step)
    $Flow.updated_at = (Get-Date).ToString("s")
    return $Flow
}

function Get-PrototypeFlow {
    <#
    .SYNOPSIS
        Loads a flow definition from disk.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$Project,
        [Parameter(Mandatory = $true)][string]$FlowId
    )

    $flowsDir = Get-FlowsDirectory -RepoRoot $RepoRoot -Project $Project
    $flowFile = Join-Path $flowsDir "$FlowId.json"

    if (-not (Test-Path $flowFile)) {
        throw "Flow '$FlowId' not found for project '$Project'."
    }

    return (Get-Content $flowFile -Raw -Encoding UTF8 | ConvertFrom-Json | ForEach-Object { Convert-PSObjectToHashtable $_ })
}

function Save-PrototypeFlow {
    <#
    .SYNOPSIS
        Saves a flow definition to disk.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$Project,
        [Parameter(Mandatory = $true)][hashtable]$Flow
    )

    $flowsDir = Get-FlowsDirectory -RepoRoot $RepoRoot -Project $Project
    Ensure-Dir -Path $flowsDir
    $flowFile = Join-Path $flowsDir "$($Flow.flow_id).json"
    $Flow | ConvertTo-Json -Depth 20 | Set-Content $flowFile -Encoding UTF8
}

function Get-PrototypeFlows {
    <#
    .SYNOPSIS
        Lists all flow definitions for a project.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$Project
    )

    $flowsDir = Get-FlowsDirectory -RepoRoot $RepoRoot -Project $Project
    if (-not (Test-Path $flowsDir)) { return @() }

    $flows = @()
    foreach ($file in (Get-ChildItem $flowsDir -Filter "*.json" -File)) {
        $flow = Get-Content $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json | ForEach-Object { Convert-PSObjectToHashtable $_ }
        $flows += @{
            flow_id    = $flow.flow_id
            name       = $flow.name
            steps      = if ($flow.steps) { $flow.steps.Count } else { 0 }
            entry_url  = $flow.entry_url
            created_at = $flow.created_at
            updated_at = $flow.updated_at
        }
    }
    return $flows
}

function Set-FlowStepSource {
    <#
    .SYNOPSIS
        Associates captured HTML/CSS source with a flow step and saves it to disk.
    .PARAMETER StepNumber
        1-based step number.
    .PARAMETER HtmlContent
        The HTML content for this step's page state.
    .PARAMETER CssContent
        The CSS content for this step's page state.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$Project,
        [Parameter(Mandatory = $true)][hashtable]$Flow,
        [Parameter(Mandatory = $true)][int]$StepNumber,
        [Parameter(Mandatory = $true)][string]$HtmlContent,
        [string]$CssContent = ""
    )

    if ($StepNumber -lt 1 -or $StepNumber -gt $Flow.steps.Count) {
        throw "Step number $StepNumber is out of range (1..$($Flow.steps.Count))."
    }

    $flowsDir = Get-FlowsDirectory -RepoRoot $RepoRoot -Project $Project
    $stepDir = Join-Path $flowsDir "$($Flow.flow_id)/step-$StepNumber"
    Ensure-Dir -Path $stepDir

    $HtmlContent | Set-Content (Join-Path $stepDir "source.html") -Encoding UTF8
    $CssContent | Set-Content (Join-Path $stepDir "styles.css") -Encoding UTF8

    # Mark step as having source
    $idx = $StepNumber - 1
    if ($Flow.steps[$idx] -is [hashtable]) {
        $Flow.steps[$idx].has_source = $true
    } else {
        $Flow.steps[$idx] | Add-Member -NotePropertyName has_source -NotePropertyValue $true -Force
    }
    $Flow.updated_at = (Get-Date).ToString("s")

    Save-PrototypeFlow -RepoRoot $RepoRoot -Project $Project -Flow $Flow
    return $Flow
}

function ConvertTo-FlowPrototypeHtml {
    <#
    .SYNOPSIS
        Generates a multi-page SPA from a recorded flow, combining step sources + requirements
        into a single navigable prototype with proper style isolation via iframes.
    .PARAMETER Flow
        The flow definition hashtable.
    .PARAMETER Requirements
        Array of requirement objects to inject.
    .PARAMETER Version
        The prototype version string.
    .PARAMETER FlowsDir
        Base directory where flow step sources are stored.
    .PARAMETER ProjectSourceDir
        Path to the project source/ directory for loading base app styles.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Flow,
        [array]$Requirements = @(),
        [Parameter(Mandatory = $true)][string]$Version,
        [Parameter(Mandatory = $true)][string]$FlowsDir,
        [string]$ProjectSourceDir = ""
    )

    $flowStepDir = Join-Path $FlowsDir $Flow.flow_id
    $steps = @($Flow.steps)
    # Ensure Requirements is always a real array (PS 5.1 strict mode safety)
    if ($null -eq $Requirements) { $Requirements = @() }

    # Load base app styles from project source (fetched original page styles)
    $baseAppStyles = ""
    if ($ProjectSourceDir) {
        $baseStylesFile = Join-Path $ProjectSourceDir "styles.css"
        if (Test-Path $baseStylesFile) {
            $baseAppStyles = Get-Content $baseStylesFile -Raw -Encoding UTF8
        }
        # Also extract inline styles from the original source index.html
        $baseIndexFile = Join-Path $ProjectSourceDir "index.html"
        if (Test-Path $baseIndexFile) {
            $baseHtml = Get-Content $baseIndexFile -Raw -Encoding UTF8
            $baseStyleMatches = [regex]::Matches($baseHtml, '(?si)<style[^>]*>(.*?)</style>')
            foreach ($m in $baseStyleMatches) {
                $baseAppStyles += "`n" + $m.Groups[1].Value
            }
        }
    }

    # Build per-step data: extract body + styles from each source
    $pageSections = @()
    $navItems = @()

    for ($i = 0; $i -lt $steps.Count; $i++) {
        $step = $steps[$i]
        $sNum = $i + 1
        $pageId = "page-$($step.page -replace '[^a-zA-Z0-9]', '-')-$sNum"
        $stepSourceDir = Join-Path $flowStepDir "step-$sNum"
        $display = if ($i -eq 0) { "block" } else { "none" }

        # Build the full page HTML that will go inside the iframe srcdoc
        $stepFullHtml = ""
        $rawHtml = ""
        $stepStyles = ""

        if (Test-Path (Join-Path $stepSourceDir "source.html")) {
            $rawHtml = Get-Content (Join-Path $stepSourceDir "source.html") -Raw -Encoding UTF8

            # If it's a full HTML document, use it as-is but inject base styles
            if ($rawHtml -match '(?i)<html') {
                # Extract existing <style> blocks from the source
                $sourceStyleMatches = [regex]::Matches($rawHtml, '(?si)<style[^>]*>(.*?)</style>')
                foreach ($m in $sourceStyleMatches) {
                    $stepStyles += $m.Groups[1].Value + "`n"
                }

                # Extract body content
                $bodyContent = $rawHtml
                if ($rawHtml -match '(?si)<body[^>]*>(.*)</body>') {
                    $bodyContent = $Matches[1]
                }

                # Build complete isolated page with base app styles + step's own styles
                $stepFullHtml = @"
<!DOCTYPE html>
<html><head><meta charset="UTF-8"><style>
$baseAppStyles
$stepStyles
</style></head><body>$bodyContent</body></html>
"@
            } else {
                # Fragment -- wrap with base styles
                $stepFullHtml = @"
<!DOCTYPE html>
<html><head><meta charset="UTF-8"><style>
$baseAppStyles
</style></head><body>$rawHtml</body></html>
"@
            }
        }

        # Also load separate styles.css if provided
        if (Test-Path (Join-Path $stepSourceDir "styles.css")) {
            $extraCss = Get-Content (Join-Path $stepSourceDir "styles.css") -Raw -Encoding UTF8
            if ($extraCss.Trim()) {
                # Inject into the iframe HTML
                $stepFullHtml = $stepFullHtml -replace '(?i)</style>\s*</head>', "$extraCss`n</style></head>"
            }
        }

        if (-not $stepFullHtml) {
            $stepFullHtml = "<!DOCTYPE html><html><head><meta charset=`"UTF-8`"><style>$baseAppStyles</style></head><body><p style=`"padding:20px;color:#999;`">No source captured for this step.</p></body></html>"
        }

        # Escape the HTML for srcdoc attribute (double-quote and ampersand escaping)
        $srcdoc = $stepFullHtml -replace '&', '&amp;' -replace '"', '&quot;'

        $descHtml = ""
        if ($step.description) {
            $safeDesc = [System.Net.WebUtility]::HtmlEncode($step.description)
            $descHtml = "<p class=`"aira-step-desc`">$safeDesc</p>"
        }

        $actionSummary = ""
        $stepActions = @($step.actions)
        if ($stepActions.Count -gt 0) {
            $actionLines = @()
            foreach ($a in $stepActions) {
                $aType = if ($a -is [hashtable]) { $a.type } else { $a.type }
                $aLabel = if ($a -is [hashtable]) { $a.label } else { $a.label }
                $aSel = if ($a -is [hashtable]) { $a.selector } else { $a.selector }
                $desc_ = $aType
                if ($aLabel) { $desc_ = "$aType - $([System.Net.WebUtility]::HtmlEncode($aLabel))" }
                elseif ($aSel) { $desc_ = "$aType on $([System.Net.WebUtility]::HtmlEncode($aSel))" }
                $actionLines += "<li>$desc_</li>"
            }
            $actionSummary = "<details class=`"aira-actions`"><summary>Actions ($($stepActions.Count))</summary><ol>$($actionLines -join '')</ol></details>"
        }

        $safePage = [System.Net.WebUtility]::HtmlEncode($step.page)
        $safeUrl = [System.Net.WebUtility]::HtmlEncode($step.url)

        $pageSections += @"
<section id="$pageId" class="aira-flow-page" style="display:$display" data-step="$sNum">
  <div class="aira-step-header">
    <span class="aira-step-badge">Step $sNum</span>
    <strong>$safePage</strong>
    <span class="aira-step-url">$safeUrl</span>
  </div>
  $descHtml
  $actionSummary
  <iframe class="aira-step-frame" srcdoc="$srcdoc" sandbox="allow-same-origin" frameborder="0"></iframe>
</section>
"@

        $activeClass = if ($i -eq 0) { " active" } else { "" }
        $navItems += "<button class=`"aira-nav-btn$activeClass`" onclick=`"navigateTo('$pageId', $sNum)`">$sNum. $safePage</button>"
    }

    # Build requirements section
    $reqHtml = ""
    if ($Requirements.Count -gt 0) {
        $reqBlocks = @()
        foreach ($req in $Requirements) {
            $rid = [System.Net.WebUtility]::HtmlEncode($req.id)
            $rtitle = [System.Net.WebUtility]::HtmlEncode($req.title)
            $rdesc = [System.Net.WebUtility]::HtmlEncode($req.description)
            $rpri = [System.Net.WebUtility]::HtmlEncode($req.priority)
            $reqBlocks += @"
<div class="aira-prototype-requirement" data-req-id="$rid">
  <h4>$rid`: $rtitle</h4>
  <p>$rdesc</p>
  <span class="aira-meta">Priority: $rpri | Status: prototype</span>
</div>
"@
        }
        $reqHtml = @"
<div class="aira-prototype-requirements" id="aira-requirements">
  <h3>Prototype Requirements (v$Version)</h3>
  $($reqBlocks -join "`n  ")
</div>
"@
    }

    $safeFlowName = [System.Net.WebUtility]::HtmlEncode($Flow.name)
    $safeFlowId = [System.Net.WebUtility]::HtmlEncode($Flow.flow_id)

    # Assemble the full SPA -- AIRA chrome is the outer shell, app content in iframes
    $spa = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Prototype: $safeFlowName (v$Version)</title>
<style>
/* AIRA Flow Chrome -- does NOT leak into step content (isolated in iframes) */
* { box-sizing: border-box; margin: 0; padding: 0; }
html, body { height: 100%; }
body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f5f5f5; display: flex; flex-direction: column; }
.aira-flow-toolbar { position: sticky; top: 0; z-index: 9999; background: #2c3e50; color: #fff; padding: 8px 16px; display: flex; align-items: center; gap: 12px; flex-wrap: wrap; flex-shrink: 0; }
.aira-flow-toolbar .aira-flow-title { font-weight: 700; font-size: 1.05em; margin-right: auto; }
.aira-flow-toolbar .aira-flow-version { background: #27ae60; padding: 2px 8px; border-radius: 3px; font-size: 0.85em; }
.aira-flow-nav { display: flex; gap: 4px; flex-wrap: wrap; }
.aira-nav-btn { background: #34495e; color: #ecf0f1; border: 1px solid #4a6278; padding: 5px 12px; border-radius: 3px; cursor: pointer; font-size: 0.85em; transition: background 0.15s; }
.aira-nav-btn:hover { background: #4a6278; }
.aira-nav-btn.active { background: #2980b9; border-color: #3498db; font-weight: 600; }
.aira-flow-page { flex: 1; display: none; flex-direction: column; }
.aira-flow-page.aira-active { display: flex; }
.aira-step-header { background: #ecf0f1; padding: 8px 16px; display: flex; align-items: center; gap: 10px; border-bottom: 1px solid #bdc3c7; flex-shrink: 0; }
.aira-step-badge { background: #2980b9; color: #fff; padding: 2px 8px; border-radius: 3px; font-size: 0.8em; font-weight: 700; }
.aira-step-url { color: #7f8c8d; font-size: 0.85em; margin-left: auto; }
.aira-step-desc { padding: 6px 16px; margin: 0; background: #fef9e7; border-bottom: 1px solid #f0e6b4; font-size: 0.9em; color: #7d6608; flex-shrink: 0; }
.aira-actions { padding: 6px 16px; background: #fafafa; border-bottom: 1px solid #eee; font-size: 0.85em; flex-shrink: 0; }
.aira-actions summary { cursor: pointer; color: #2980b9; font-weight: 600; }
.aira-actions ol { margin: 6px 0; padding-left: 20px; }
.aira-actions li { margin: 2px 0; }
.aira-step-frame { flex: 1; width: 100%; border: none; min-height: 400px; }
.aira-flow-footer { background: #2c3e50; color: #95a5a6; text-align: center; padding: 10px; font-size: 0.8em; flex-shrink: 0; }
/* Prototype requirements */
.aira-prototype-requirements { padding: 20px 16px; margin: 0; border-top: 2px dashed #f0ad4e; background: #fefbed; flex-shrink: 0; }
.aira-prototype-requirements h3 { color: #8a6d3b; margin-top: 0; }
.aira-prototype-requirement { padding: 10px; margin: 10px 0; border-left: 4px solid #f0ad4e; background: #fff; }
.aira-prototype-requirement h4 { margin: 0 0 5px 0; color: #333; }
.aira-meta { font-size: 0.85em; color: #999; }
</style>
</head>
<body>

<!-- AIRA Flow Prototype Toolbar -->
<div class="aira-flow-toolbar">
  <span class="aira-flow-title">$safeFlowName</span>
  <span class="aira-flow-version">v$Version</span>
  <span style="color:#95a5a6;font-size:0.8em;">Flow: $safeFlowId | $($steps.Count) steps</span>
  <div class="aira-flow-nav">
    $($navItems -join "`n    ")
  </div>
</div>

<!-- Flow Pages (each step renders in an isolated iframe) -->
$($pageSections -join "`n`n")

<!-- Requirements -->
$reqHtml

<!-- Footer -->
<div class="aira-flow-footer">
  AIRA Prototype - $safeFlowName v$Version - $($steps.Count) steps, $($Requirements.Count) requirements - Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm')
</div>

<script>
var currentStep = 1;
var totalSteps = $($steps.Count);
function navigateTo(pageId, stepNum) {
  document.querySelectorAll('.aira-flow-page').forEach(function(el) { el.classList.remove('aira-active'); el.style.display = ''; });
  var target = document.getElementById(pageId);
  if (target) { target.classList.add('aira-active'); target.style.display = 'flex'; }
  currentStep = stepNum;
  document.querySelectorAll('.aira-nav-btn').forEach(function(btn, i) {
    btn.classList.toggle('active', i === stepNum - 1);
  });
  // Auto-resize iframe to content height
  var frame = target ? target.querySelector('.aira-step-frame') : null;
  if (frame) { resizeFrame(frame); }
}
function resizeFrame(frame) {
  try {
    var doc = frame.contentDocument || frame.contentWindow.document;
    if (doc && doc.body) { frame.style.height = Math.max(400, doc.body.scrollHeight + 20) + 'px'; }
  } catch(e) {}
}
// Resize all iframes once loaded
document.querySelectorAll('.aira-step-frame').forEach(function(frame) {
  frame.addEventListener('load', function() { resizeFrame(this); });
});
// Initialize first page
document.addEventListener('DOMContentLoaded', function() {
  var first = document.querySelector('.aira-flow-page');
  if (first) { first.classList.add('aira-active'); first.style.display = 'flex'; }
});
document.addEventListener('keydown', function(e) {
  if (e.key === 'ArrowRight' && currentStep < totalSteps) {
    var btns = document.querySelectorAll('.aira-nav-btn');
    if (btns[currentStep]) btns[currentStep].click();
  } else if (e.key === 'ArrowLeft' && currentStep > 1) {
    var btns = document.querySelectorAll('.aira-nav-btn');
    if (btns[currentStep - 2]) btns[currentStep - 2].click();
  }
});
</script>
</body>
</html>
"@

    return $spa
}

Export-ModuleMember -Function Resolve-ProjectFromUrl, Get-PrototypeArtifactRoot, `
    Get-PrototypeVersions, Save-PrototypeVersions, Get-NextVersion, Get-ContentHash, `
    New-RequirementId, ConvertTo-PrototypeHtml, New-PrototypeChangelog, `
    Get-FlowsDirectory, New-PrototypeFlow, Add-PrototypeFlowStep, `
    Get-PrototypeFlow, Save-PrototypeFlow, Get-PrototypeFlows, `
    Set-FlowStepSource, ConvertTo-FlowPrototypeHtml
