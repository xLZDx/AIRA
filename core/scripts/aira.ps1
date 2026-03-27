<#
.SYNOPSIS
    AIRA v2 CLI entry point (init + doctor/readiness + context + pipeline).

.DESCRIPTION
    -InitWorkspace: ensures required folders/files exist (non-destructive).
    -InstallDependencies: installs required PowerShell modules (Pester 5, ImportExcel).
    -Doctor: runs startup readiness tests (.aira/tests/) and maintains startup.state.json.
    -BuildContext: builds/refreshes context under `context/{scope}/{KeyPrefix}/{KEY}/`.
    -RunPipeline: creates a versioned output package under `outputs/<Project>/runs/<KEY>_<timestamp>/`.
#>


param(
    [switch]$InitWorkspace,
    [switch]$InstallDependencies,
    [switch]$Doctor,
    [switch]$Force,
    [switch]$BuildContext,
    [switch]$RunPipeline,
    [switch]$ArchiveContext,
    [switch]$ListContext,
    [switch]$Rescan,
    [string]$JiraKey,
    [switch]$Refresh,
    [string]$EnvPath,
    [int]$ProjectId,
    [int]$MaxDependencyDepth,
    [string[]]$ConfluencePageIds,
    [switch]$SkipConfluence,
    [switch]$WithCoverage,
    [switch]$DownloadAttachments,
    [int]$MaxAttachmentMB = 25,
    [ValidateSet('Auto','Local','Shared')]
    [string]$Scope = 'Auto',
    [string]$Project,
    [string]$DesignJson,
    [string]$SpecPath,
    [switch]$SkipValidation,
    [switch]$SkipExcel
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path

function Ensure-Dir([string]$p) {
    if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
}

function Ensure-File([string]$path, [string]$content) {
    if (-not (Test-Path $path)) {
        $dir = Split-Path -Parent $path
        if ($dir -and -not (Test-Path $dir)) { Ensure-Dir $dir }
        $content | Out-File -FilePath $path -Encoding UTF8
    }
}

function Resolve-RepoPath([string]$p) {
    if ([System.IO.Path]::IsPathRooted($p)) { return $p }
    return (Join-Path $repoRoot $p)
}

function Read-JsonHashtable([string]$path) {
    if (-not (Test-Path $path)) { return $null }
    return (Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

# Repair Windows-1252 → UTF-8 double-encoded text (mojibake).
# Jira Server sometimes stores description text with double encoding, producing
# sequences like "â€"" instead of "—". Detect and fix by round-tripping through
# Windows-1252 byte interpretation back to UTF-8.
function Repair-Mojibake([string]$Text) {
    if (-not $Text) { return $Text }
    # Quick check: the sequence â€ (U+00E2 followed by U+20AC) is a strong
    # indicator of Win-1252 double-encoding and almost never appears naturally.
    if ($Text.IndexOf([char]0x00E2) -lt 0) { return $Text }
    $marker = [string]::new([char]0x00E2, 1) + [string]::new([char]0x20AC, 1)
    if (-not $Text.Contains($marker)) { return $Text }
    try {
        $win1252 = [System.Text.Encoding]::GetEncoding(1252)
        $utf8 = [System.Text.Encoding]::UTF8
        $bytes = $win1252.GetBytes($Text)
        $fixed = $utf8.GetString($bytes)
        # If the result contains replacement chars, the fix was wrong — return original
        if ($fixed.Contains([string]::new([char]0xFFFD, 1))) { return $Text }
        return $fixed
    } catch {}
    return $Text
}

function Write-Json([string]$path, [object]$obj) {
    $dir = Split-Path -Parent $path
    if ($dir) { Ensure-Dir $dir }
    $obj | ConvertTo-Json -Depth 50 | Out-File -FilePath $path -Encoding UTF8
}

function Write-Text([string]$path, [string]$content) {
    $dir = Split-Path -Parent $path
    if ($dir) { Ensure-Dir $dir }
    $content | Out-File -FilePath $path -Encoding UTF8
}

# PS 5.1 UTF-8 fix: Invoke-RestMethod misreads multi-byte chars when server
# omits charset=utf-8 in Content-Type. This wrapper reads raw bytes as UTF-8.
function Invoke-Utf8RestMethod {
    param(
        [string]$Uri,
        [string]$Method = 'Get',
        [hashtable]$Headers,
        $Body,
        [string]$ErrorAction
    )
    $params = @{ Uri = $Uri; Method = $Method; Headers = $Headers; UseBasicParsing = $true }
    if ($Body) { $params.Body = $Body }
    if ($ErrorAction) { $params.ErrorAction = $ErrorAction }
    $resp = Invoke-WebRequest @params
    # Read raw bytes from the response stream and decode as UTF-8
    $stream = $resp.RawContentStream
    $stream.Position = 0
    $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
    $utf8Text = $reader.ReadToEnd()
    $reader.Dispose()
    return ($utf8Text | ConvertFrom-Json)
}

function Get-ContextRoot {
    param(
        [string]$Scope = "Auto",
        [string]$Subdir,
        [switch]$ForWrite
    )
    
    # Scope: 'Shared', 'Local', 'Auto'
    # Write behavior: New items ALWAYS go to 'Local' unless 'Shared' is explicitly requested.
    # Read behavior (Auto, ForWrite=$false): Check Shared first, then Local.

    $shared = Join-Path $repoRoot "context/shared"
    $local = Join-Path $repoRoot "context/local"
    $legacy = Join-Path $repoRoot "context" # Backwards compat for root context items

    if ($Subdir) {
        $shared = Join-Path $shared $Subdir
        $local = Join-Path $local $Subdir
        $legacy = Join-Path $legacy $Subdir
    }

    if ($Scope -eq "Shared") { return $shared }
    if ($Scope -eq "Local") { return $local }

    # Auto mode:
    # For WRITES: always default to Local (user must explicitly say Shared)
    if ($ForWrite) { return $local }

    # For READS: Check Shared first, then Local, then Legacy.
    if (Test-Path $shared) { return $shared }
    
    # Check if legacy path exists (excluding the shared/local folders themselves)
    if (Test-Path $legacy) {
         if ($legacy -ne (Join-Path $repoRoot "context")) { return $legacy }
    }

    return $local
}

# Resolve a human-readable project name for context folder structure.
# Priority: 1) team.policy.json -> jira.project.description (ONLY if key prefix matches project)
#           2) Jira API issue -> project.name
#           3) Fallback: Jira key prefix (e.g. "PLAT")
function Resolve-ProjectName {
    param(
        [hashtable]$Policy,
        $Issue,            # Jira issue object (optional, from API)
        [string]$JiraKey   # e.g. "PLAT-1488"
    )

    $keyPrefix = if ($JiraKey) { ($JiraKey -split "-")[0] } else { "" }

    # 1. Team policy: jira.project.description — but ONLY if key prefix belongs to this project
    if ($Policy -and $Policy.jira -and $Policy.jira.project -and $Policy.jira.project.description) {
        $desc = $Policy.jira.project.description
        if ($desc -and $desc.Trim() -ne "" -and $desc.Trim() -ne "Default") {
            # Check if key prefix matches jira_project_code or any scrum_teams value
            $policyCode = if ($Policy.jira.project.jira_project_code) { $Policy.jira.project.jira_project_code } else { "" }
            $scrumCodes = @()
            if ($Policy.jira.project.scrum_teams) {
                $st = $Policy.jira.project.scrum_teams
                if ($st -is [hashtable]) {
                    $scrumCodes = @($st.Values)
                } elseif ($st.PSObject -and $st.PSObject.Properties) {
                    $scrumCodes = @($st.PSObject.Properties | ForEach-Object { $_.Value })
                }
            }
            $allCodes = @($policyCode) + $scrumCodes | Where-Object { $_ -and $_.Trim() -ne "" }
            if ($allCodes -contains $keyPrefix) {
                return $desc.Trim()
            }
            # Key prefix doesn't match this team policy's project — fall through
        }
    }

    # 2. Jira issue: fields.project.name
    if ($Issue -and $Issue.fields -and $Issue.fields.project -and $Issue.fields.project.name) {
        $pName = $Issue.fields.project.name
        if ($pName -and $pName.Trim() -ne "") { return $pName.Trim() }
    }

    # 3. Fallback: key prefix
    if ($JiraKey) { return $keyPrefix }

    return "Unknown"
}

# Extract the Jira key prefix (e.g. "PLAT" from "PLAT-1488")
function Get-JiraKeyPrefix([string]$Key) {
    return ($Key -split "-")[0]
}

# Build the sub-path for context storage: {KeyPrefix}/{JIRA-KEY}
function Get-ContextSubPath {
    param(
        [string]$JiraKey
    )
    $prefix = Get-JiraKeyPrefix -Key $JiraKey
    return "$prefix/$JiraKey"
}


function Get-FileSha256([string]$path) {
    if (-not (Test-Path $path)) { return $null }
    return ((Get-FileHash -Path $path -Algorithm SHA256).Hash.ToLowerInvariant())
}

function Get-ScriptFingerprint {
    $searchRoots = @(
        (Join-Path $repoRoot "core"),
        (Join-Path $repoRoot ".aira/tests")
    )
    $entries = [System.Collections.Generic.List[string]]::new()
    foreach ($root in $searchRoots) {
        if (-not (Test-Path $root)) { continue }
        Get-ChildItem -Path $root -Recurse -File |
            Where-Object { $_.Extension -in @('.ps1', '.psm1') } |
            Sort-Object FullName |
            ForEach-Object {
                $h = Get-FileSha256 -path $_.FullName
                $entries.Add("$($_.FullName):$h")
            }
    }
    if ($entries.Count -eq 0) { return "empty" }
    $combined = $entries -join "|"
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($combined)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $hashBytes = $sha.ComputeHash($bytes)
    return ([System.BitConverter]::ToString($hashBytes) -replace '-', '').ToLowerInvariant()
}

function Get-Timestamp([string]$format = "yyyyMMdd_HHmmss") {
    return (Get-Date -Format $format)
}

function Get-EnvFingerprint {
    $configModule = Join-Path $repoRoot "core/modules/Aira.Config.psm1"
    Import-Module $configModule -Force
    $c = Get-AiraCredentials -RepoRoot $repoRoot -EnvPath $EnvPath
    return @{
        jira_url = $c.jira.url
        confluence_url = $c.confluence.url
        testrail_url = $c.testrail.url
        github_base_url = $c.github.base_url
        bitbucket_base_url = $c.bitbucket.base_url
        user = if ($c.jira.email) { $c.jira.email } elseif ($c.confluence.email) { $c.confluence.email } else { $c.testrail.username }
    }
}

function Get-StartupState {
    $statePath = Join-Path $repoRoot ".aira/tests/startup.state.json"
    if (-not (Test-Path $statePath)) { return $null }
    try {
        return (Get-Content $statePath -Raw -Encoding UTF8 | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Assert-ReadinessComplete {
    $state = Get-StartupState
    if (-not $state -or $state.status -ne "Complete") {
        throw "Workspace readiness is not Complete. Run: powershell ./core/scripts/aira.ps1 -Doctor"
    }
}

function Get-EffectivePolicy {
    $configModule = Join-Path $repoRoot "core/modules/Aira.Config.psm1"
    Import-Module $configModule -Force
    if (Get-Command Get-AiraEffectivePolicy -ErrorAction SilentlyContinue) {
        return (Get-AiraEffectivePolicy -PolicyRoot (Join-Path $repoRoot ".aira") -RepoRoot $repoRoot)
    }
    return (Get-AiraPolicy -PolicyRoot (Join-Path $repoRoot ".aira"))
}

function Get-ContextManifestPath {
    param([string]$Root)
    # If explicit root provided (e.g. context/local), use that.
    # Otherwise default to legacy root for backward compatibility if needed, 
    # but practically we should be passing a root now.
    
    if (-not $Root) { return (Join-Path $repoRoot "context/manifest.json") }
    return (Join-Path $Root "manifest.json")
}

function Read-ContextManifest {
    param([string]$Path)
    
    if (-not $Path) {
        # Aggregate mode: read both manifests
        $lName = Join-Path (Join-Path $repoRoot "context/local") "manifest.json"
        $sName = Join-Path (Join-Path $repoRoot "context/shared") "manifest.json"
        
        $local = Read-ContextManifest -Path $lName
        $shared = Read-ContextManifest -Path $sName
        
        return @{
            active = @($local.active + $shared.active)
            archived = @($local.archived + $shared.archived)
        }
    }

    if (-not (Test-Path $Path)) {
        return @{ active = @(); archived = @() }
    }
    try {
        return (Read-JsonHashtable -path $Path)
    } catch {
        return @{ active = @(); archived = @() }
    }
}

function Write-ContextManifest($manifest, [string]$Path) {
    if (-not $Path) { $Path = Get-ContextManifestPath }
    Write-Json -path $Path -obj $manifest
}

function Get-ManifestForArtifact {
    param([string]$ArtifactPath)
    # Determine the context root (local/shared) based on the artifact path
    
    # Check "shared" path pattern
    $sharedRoot = (Join-Path $repoRoot "context/shared").Replace('\','/')
    if ($ArtifactPath.Replace('\','/').StartsWith($sharedRoot)) {
        return (Join-Path $sharedRoot "manifest.json")
    }

    # Check "local" path pattern
    $localRoot = (Join-Path $repoRoot "context/local").Replace('\','/')
    if ($ArtifactPath.Replace('\','/').StartsWith($localRoot)) {
        return (Join-Path $localRoot "manifest.json")
    }

    # Fallback to legacy root
    return (Join-Path $repoRoot "context/manifest.json")
}

function Upsert-ActiveContextEntry {
    param(
        [string]$Kind,
        [string]$Key,
        [string]$Path
    )
    
    # Resolve full path to find correct manifest
    $fullPath = Resolve-RepoPath -p $Path
    $manifestPath = Get-ManifestForArtifact -ArtifactPath $fullPath
    $manifest = Read-ContextManifest -Path $manifestPath
    
    $entry = @{
        kind = $Kind
        key = $Key
        path = $Path
        addedAt = (Get-Date).ToString("s")
    }
    
    # Remove existing entry for same key/kind
    $manifest.active = @($manifest.active | Where-Object { $_.kind -ne $Kind -or $_.key -ne $Key })
    $manifest.active += $entry
    
    Write-ContextManifest -manifest $manifest -Path $manifestPath
}

function Archive-ContextEntry {
    param(
        [string]$Kind,
        [string]$Key,
        [string]$ArchivedPath
    )
    
    $fullPath = Resolve-RepoPath -p $ArchivedPath
    $manifestPath = Get-ManifestForArtifact -ArtifactPath $fullPath
    $manifest = Read-ContextManifest -Path $manifestPath
    
    $manifest.active = @($manifest.active | Where-Object { $_.kind -ne $Kind -or $_.key -ne $Key })
    $manifest.archived += @{
        kind = $Kind
        key = $Key
        path = $ArchivedPath
        archivedAt = (Get-Date).ToString("s")
    }
    Write-ContextManifest -manifest $manifest -Path $manifestPath
}

$jiraTextModule = Join-Path $repoRoot "core/modules/Aira.JiraText.psm1"
if (Test-Path $jiraTextModule) { Import-Module $jiraTextModule -Force }

function Get-JiraHeadersAndUrl {
    $configModule = Join-Path $repoRoot "core/modules/Aira.Config.psm1"
    Import-Module $configModule -Force
    $creds = Get-AiraCredentials -RepoRoot $repoRoot -EnvPath $EnvPath
    $jiraUrl = $creds.jira.url
    $email = $creds.jira.email
    $token = $creds.jira.api_token
    if (-not $jiraUrl) { throw "JIRA_URL not configured" }
    if (-not $token) { throw "JIRA_API_TOKEN not configured" }

    $jiraUrl = $jiraUrl.TrimEnd("/")
    $mode = if ($jiraUrl -match "atlassian\\.net") { "basic" } else { "bearer" }

    if ($mode -eq "basic") {
        if (-not $email) { throw "JIRA_EMAIL (or JIRA_USERNAME) is required for Atlassian Cloud basic auth." }
        $pair = "{0}:{1}" -f $email, $token
        $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pair))
        return @{
            url = $jiraUrl
            headers = @{
                "Authorization" = "Basic $b64"
                "Content-Type"  = "application/json"
                "Accept"        = "application/json"
            }
        }
    }

    return @{
        url = $jiraUrl
        headers = @{
            "Authorization" = "Bearer $token"
            "Content-Type"  = "application/json"
            "Accept"        = "application/json"
        }
    }
}

function Invoke-JiraGet {
    param([string]$Path)
    $auth = Get-JiraHeadersAndUrl
    $url = "$($auth.url)$Path"
    return (Invoke-Utf8RestMethod -Uri $url -Method Get -Headers $auth.headers)
}

function Get-JiraIssueRaw {
    param([string]$Key)
    return (Invoke-JiraGet -Path "/rest/api/2/issue/${Key}?fields=summary,issuetype,description,status,priority,issuelinks,created,updated,attachment,project,labels,components,fixVersions")
}

function Get-JiraCommentsRaw {
    param([string]$Key)
    try {
        $resp = Invoke-JiraGet -Path "/rest/api/2/issue/$Key/comment?maxResults=100"
        return $resp
    } catch {
        return @{ comments = @() }
    }
}

function Get-LinkedKeysFromIssue {
    param([object]$Issue)
    $keys = New-Object System.Collections.Generic.HashSet[string]
    $links = if ($Issue.fields.issuelinks) { $Issue.fields.issuelinks } else { @() }
    foreach ($link in @($links)) {
        if ($link.inwardIssue -and $link.inwardIssue.key) { [void]$keys.Add([string]$link.inwardIssue.key) }
        if ($link.outwardIssue -and $link.outwardIssue.key) { [void]$keys.Add([string]$link.outwardIssue.key) }
    }
    return @($keys)
}

function Get-DependencyGraph {
    param([string]$RootKey, [int]$Depth)
    $visited = New-Object System.Collections.Generic.HashSet[string]
    $queue = New-Object System.Collections.Generic.Queue[object]
    $issuesByKey = @{}

    $queue.Enqueue(@{ key = $RootKey; depth = 0 }) | Out-Null
    [void]$visited.Add($RootKey)

    while ($queue.Count -gt 0) {
        $item = $queue.Dequeue()
        $key = $item.key
        $d = [int]$item.depth

        if (-not $issuesByKey.ContainsKey($key)) {
            $issuesByKey[$key] = Get-JiraIssueRaw -Key $key
        }

        if ($d -ge $Depth) { continue }
        foreach ($lk in (Get-LinkedKeysFromIssue -Issue $issuesByKey[$key])) {
            if ($visited.Contains($lk)) { continue }
            [void]$visited.Add($lk)
            $queue.Enqueue(@{ key = $lk; depth = ($d + 1) }) | Out-Null
        }
    }

    # Direct links metadata (root only)
    $root = $issuesByKey[$RootKey]
    $direct = @()
    $rLinks = if ($root.fields.issuelinks) { $root.fields.issuelinks } else { @() }
    foreach ($link in @($rLinks)) {
        $direction = $null
        $linkedKey = $null
        if ($link.outwardIssue -and $link.outwardIssue.key) { $direction = "outward"; $linkedKey = $link.outwardIssue.key }
        elseif ($link.inwardIssue -and $link.inwardIssue.key) { $direction = "inward"; $linkedKey = $link.inwardIssue.key }
        if (-not $linkedKey) { continue }

        $linked = $issuesByKey[$linkedKey]
        $direct += @{
            key = $linkedKey
            relationship = if ($link.type.name) { $link.type.name } elseif ($link.type.outward) { $link.type.outward } else { $link.type.inward }
            direction = $direction
            issue_type = if ($linked.fields.issuetype.name) { $linked.fields.issuetype.name } else { $null }
            status = if ($linked.fields.status.name) { $linked.fields.status.name } else { $null }
            summary = if ($linked.fields.summary) { $linked.fields.summary } else { $null }
        }
    }

    $all = @()
    foreach ($k in $issuesByKey.Keys) {
        if ($k -eq $RootKey) { continue }
        $i = $issuesByKey[$k]
        $kt = if ($i.fields.issuetype.name) { $i.fields.issuetype.name } else { $null }
        $ks = if ($i.fields.status.name) { $i.fields.status.name } else { $null }
        $ksum = if ($i.fields.summary) { $i.fields.summary } else { $null }
        $all += @{
            key = $k
            issue_type = $kt
            status = $ks
            summary = $ksum
        }
    }

    $rl = if ($root.fields.issuelinks) { $root.fields.issuelinks } else { @() }
    
    return @{
        root_key = $RootKey
        depth = $Depth
        fetched_at = (Get-Date).ToString("s")
        direct = $direct
        all = $all
        raw_root_issuelinks = @($rl)
    }
}

function Assert-AllowedRequirementSource {
    param([object]$Issue, [object]$Policy)
    if (-not $Policy) { $Policy = Get-EffectivePolicy }

    $allowed = @("feature", "story")
    if ($Policy.jira.allowed_types) {
        $allowed = @($Policy.jira.allowed_types | ForEach-Object { "$_".ToLowerInvariant() })
    }

    $tn = if ($Issue.fields.issuetype.name) { $Issue.fields.issuetype.name } else { "" }
    $t = $tn.ToString()
    $lower = $t.ToLowerInvariant()
    
    # Always block bugs/epics unless explicitly allowed (safety net)
    if ($lower -eq "bug" -and $allowed -notcontains "bug") { throw "Issue '$($Issue.key)' is a Bug. Bugs are not analyzed as requirement sources." }
    if ($lower -eq "epic" -and $allowed -notcontains "epic") { throw "Issue '$($Issue.key)' is an Epic. Provide a Feature or Story instead." }
    
    if ($allowed -notcontains $lower) {
        $msg = $allowed -join ", "
        throw "Issue '$($Issue.key)' type '$t' is not allowed. Allowed types: $msg."
    }
}

function Invoke-TestRailCoverage {
    param([string]$Key, [int]$ProjectId)
    $scriptPath = Join-Path $repoRoot "core/scripts/testrail.ps1"
    if (-not (Test-Path $scriptPath)) { throw "TestRail script not found: $scriptPath" }

    $params = @{
        GetCoverage = $true
        JiraKey = $Key
    }
    if ($ProjectId) { $params["ProjectId"] = $ProjectId }
    if ($EnvPath) { $params["EnvPath"] = $EnvPath }

    $json = & $scriptPath @params
    return ($json | ConvertFrom-Json)
}

function Invoke-ConfluenceFetch {
    param([string]$PageId)
    $scriptPath = Join-Path $repoRoot "core/scripts/confluence.ps1"
    if (-not (Test-Path $scriptPath)) { throw "Confluence script not found: $scriptPath" }

    $params = @{
        PageId = $PageId
        Format = "both"
    }
    if ($EnvPath) { $params["EnvPath"] = $EnvPath }
    $json = & $scriptPath @params
    return ($json | ConvertFrom-Json)
}

function Build-JiraContext {
    param(
        [string]$Key,
        [switch]$DoRefresh,
        [int]$DepDepthOverride,
        [int]$TestRailProjectIdOverride,
        [string[]]$ConfluenceIdsOverride,
        [switch]$NoConfluence,
        [switch]$IncludeTestRail,
        [switch]$DownloadAttachments,
        [int]$MaxAttachmentMB = 25,
        [string]$ContextScope = "Auto"
    )

    Assert-ReadinessComplete
    $policy = Get-EffectivePolicy
    $depDepth = if ($DepDepthOverride) { $DepDepthOverride } elseif ($policy.context -and $policy.context.max_dependency_depth) { [int]$policy.context.max_dependency_depth } else { 2 }

    # Resolve effective scope: if caller passed Auto, check policy for a default_scope override
    if ($ContextScope -eq 'Auto' -and $policy.context -and $policy.context.default_scope) {
        $ContextScope = $policy.context.default_scope
    }

    $includeConfluence = if ($NoConfluence) { $false } elseif ($policy.context -is [hashtable] -and $policy.context.ContainsKey('include_confluence')) { [bool]$policy.context.include_confluence } elseif ($policy.context -and $policy.context.PSObject -and $policy.context.PSObject.Properties.Name -contains 'include_confluence') { [bool]$policy.context.include_confluence } else { $true }

    # Build context sub-path: {KeyPrefix}/{JIRA-KEY}
    $contextSubPath = Get-ContextSubPath -JiraKey $Key

    # Context scope resolution:
    # SHARED: context/shared/{KeyPrefix}/{JIRA-KEY}/context.md (consolidated, team-visible)
    # LOCAL:  context/local/{KeyPrefix}/{JIRA-KEY}/ (raw sources, diffs, attachments, deps)
    $localBase = Join-Path $repoRoot "context/local"
    $sharedBase = Join-Path $repoRoot "context/shared"

    # Primary data directory (local by default, shared only if explicitly requested)
    $jiraDir = if ($ContextScope -eq "Shared") { Join-Path $sharedBase $contextSubPath } else { Join-Path $localBase $contextSubPath }
    # Shared context.md location — ALWAYS shared regardless of scope (team-visible summary)
    $sharedJiraDir = Join-Path $sharedBase $contextSubPath

    # Backwards compat: also check legacy flat path context/local/jira/<KEY> for existing context
    $legacyLocalDir = Join-Path $localBase "jira/$Key"
    $legacySharedDir = Join-Path $sharedBase "jira/$Key"

    # Also check if context already exists in either scope (for reuse)
    # Try new structure first, then legacy
    $existingDir = $null
    if (Test-Path (Join-Path $jiraDir "manifest.json")) {
        $existingDir = $jiraDir
    } elseif (Test-Path (Join-Path $sharedJiraDir "manifest.json")) {
        $existingDir = $sharedJiraDir
    } elseif (Test-Path (Join-Path $legacyLocalDir "manifest.json")) {
        $existingDir = $legacyLocalDir
    } elseif (Test-Path (Join-Path $legacySharedDir "manifest.json")) {
        $existingDir = $legacySharedDir
    }

    if ($existingDir -and $existingDir -ne $jiraDir -and (-not $DoRefresh)) {
        # Context exists in another scope; reuse it without re-fetching
        $relPath = $existingDir.Substring($repoRoot.Length + 1).Replace('\', '/')
        Upsert-ActiveContextEntry -Kind "jira" -Key $Key -Path $relPath
        return @{
            jira_key = $Key
            reused = $true
            context_dir = $existingDir
            manifest_path = (Join-Path $existingDir "manifest.json")
        }
    }

    $diffsDir = Join-Path $jiraDir "diffs"
    $depsDir = Join-Path $jiraDir "dependencies"
    $attachDir = Join-Path $jiraDir "attachments"
    $sourcesDir = Join-Path $jiraDir "sources"

    # Only create jiraDir and sourcesDir eagerly (always needed for issue/comments/linked JSON).
    # diffs, dependencies, attachments are created on-demand when content is written.
    Ensure-Dir $jiraDir
    Ensure-Dir $sourcesDir

    $manifestPath = Join-Path $jiraDir "manifest.json"
    $oldManifest = if (Test-Path $manifestPath) { Read-JsonHashtable -path $manifestPath } else { $null }

    if ((-not $DoRefresh) -and $oldManifest) {
        $relPath = $jiraDir.Substring($repoRoot.Length + 1).Replace('\', '/')
        Upsert-ActiveContextEntry -Kind "jira" -Key $Key -Path $relPath
        return @{
            jira_key = $Key
            reused = $true
            context_dir = $jiraDir
            manifest_path = $manifestPath
        }
    }

    $issue = Get-JiraIssueRaw -Key $Key
    Assert-AllowedRequirementSource -Issue $issue -Policy $policy

    $comments = Get-JiraCommentsRaw -Key $Key
    $graph = Get-DependencyGraph -RootKey $Key -Depth $depDepth

    $issuePath = Join-Path $sourcesDir "issue.json"
    $commentsPath = Join-Path $sourcesDir "comments.json"
    $linkedPath = Join-Path $sourcesDir "linked_issues.json"

    Write-Json -path $issuePath -obj $issue
    Write-Json -path $commentsPath -obj $comments
    Write-Json -path $linkedPath -obj $graph

    # Attachments (metadata + optional download)
    $att = if ($issue.fields.attachment) { $issue.fields.attachment } else { @() }
    $attachments = @($att)
    $attachmentsMeta = @()
    $attachmentsPath = Join-Path $sourcesDir "attachments.json"

    function Sanitize-FileName([string]$Name) {
        if (-not $Name) { return "attachment" }
        $san = $Name
        foreach ($c in [System.IO.Path]::GetInvalidFileNameChars()) {
            $san = $san.Replace($c, '_')
        }
        $san = $san.Replace('/', '_').Replace('\', '_')
        return $san
    }

    $auth = $null
    if ($DownloadAttachments -and $attachments.Count -gt 0) {
        try { $auth = Get-JiraHeadersAndUrl } catch { $auth = $null }
    }

    foreach ($a in $attachments) {
        $id = "$($a.id)"
        $filename = Sanitize-FileName -Name "$($a.filename)"
        $sz = if ($a.size) { $a.size } else { 0 }
        $size = [int64]$sz

        $meta = @{
            id = $id
            filename = "$($a.filename)"
            size = $size
            mimeType = "$($a.mimeType)"
            created = "$($a.created)"
            author = "$($a.author.displayName)"
            content_url = "$($a.content)"
            downloaded = $false
            path = $null
            sha256 = $null
            skipped_reason = $null
        }

        if ($DownloadAttachments) {
            if (-not $auth) {
                $meta.skipped_reason = "Auth headers not available"
            } elseif (-not $a.content) {
                $meta.skipped_reason = "No content URL"
            } elseif ($size -gt ([int64]$MaxAttachmentMB * 1MB)) {
                $meta.skipped_reason = "Exceeds MaxAttachmentMB ($MaxAttachmentMB MB)"
            } else {
                $destName = if ($id) { "${id}_$filename" } else { $filename }
                $destAbs = Join-Path $attachDir $destName
                $destRel = "context/jira/$Key/attachments/$destName"
                try {
                    Ensure-Dir $attachDir
                    if (Test-Path $destAbs) { Remove-Item $destAbs -Force }
                    Invoke-WebRequest -Uri $a.content -Method Get -Headers $auth.headers -OutFile $destAbs -ErrorAction Stop | Out-Null
                    $meta.downloaded = $true
                    $meta.path = $destRel
                    $meta.sha256 = Get-FileSha256 -path $destAbs
                } catch {
                    $meta.skipped_reason = $_.Exception.Message
                }
            }
        }

        $attachmentsMeta += $meta
    }

    Write-Json -path $attachmentsPath -obj @{
        jira_key = $Key
        downloaded_at = (Get-Date).ToString("s")
        download_enabled = [bool]$DownloadAttachments
        max_attachment_mb = $MaxAttachmentMB
        attachments = $attachmentsMeta
    }

    # Dependency capture (store per dependency key)
    foreach ($d in @($graph.all)) {
        $depKey = $d.key
        $depFolder = Join-Path $depsDir $depKey
        $depSourcesFolder = Join-Path $depFolder "sources"
        Ensure-Dir $depFolder
        Ensure-Dir $depSourcesFolder

        $depIssue = Get-JiraIssueRaw -Key $depKey
        $depComments = Get-JiraCommentsRaw -Key $depKey
        $depGraph = Get-DependencyGraph -RootKey $depKey -Depth 1

        Write-Json -path (Join-Path $depSourcesFolder "issue.json") -obj $depIssue
        Write-Json -path (Join-Path $depSourcesFolder "comments.json") -obj $depComments
        Write-Json -path (Join-Path $depSourcesFolder "linked_issues.json") -obj $depGraph

        $depDescText = Repair-Mojibake (Convert-JiraContentToText -Value $depIssue.fields.description)
        $depAc = Extract-AcceptanceCriteria -DescriptionText $depDescText

        # Build enriched dependency context with status, description, comments, links
        $depStatus = if ($depIssue.fields.status.name) { $depIssue.fields.status.name } else { "Unknown" }
        $depPriority = if ($depIssue.fields.priority.name) { $depIssue.fields.priority.name } else { "Unknown" }
        $depCreated = if ($depIssue.fields.created) { ($depIssue.fields.created -split 'T')[0] } else { "Unknown" }
        $depUpdated = if ($depIssue.fields.updated) { ($depIssue.fields.updated -split 'T')[0] } else { "Unknown" }

        $depDescSection = if ($depDescText -and $depDescText.Trim()) { Convert-JiraWikiToMarkdown -Text $depDescText.Trim() } else { "[MISSING - NEEDS INPUT]" }

        $depCommentsSection = @()
        $depCommentsList = if ($depComments.comments) { @($depComments.comments) } else { @() }
        if ($depCommentsList.Count -gt 0) {
            $depCIdx = 0
            foreach ($dcm in $depCommentsList) {
                $depCIdx++
                $dcAuthor = if ($dcm.author -and $dcm.author.displayName) { $dcm.author.displayName } else { "Unknown" }
                $dcCreated = if ($dcm.created) { ($dcm.created -split 'T')[0] } else { "?" }
                $dcBody = Convert-JiraContentToText -Value $dcm.body
                if ($dcBody.Length -gt 300) { $dcBody = $dcBody.Substring(0, 297) + "..." }
                $depCommentsSection += "**#$depCIdx** *$dcAuthor* ($dcCreated): $dcBody"
            }
        } else {
            $depCommentsSection += "(no comments)"
        }

        # Extract attachment count for dependency
        $depAttachments = if ($depIssue.fields.attachment) { @($depIssue.fields.attachment) } else { @() }

        $depContext = @"
## Issue
- **Key:** $depKey
- **Summary:** $($depIssue.fields.summary)
- **Type:** $($depIssue.fields.issuetype.name)
- **Status:** $depStatus
- **Priority:** $depPriority
- **Created:** $depCreated
- **Last Updated:** $depUpdated

## Description
$depDescSection

## Acceptance Criteria
$(if ($depAc.Count -gt 0) { ($depAc | ForEach-Object { "- $_" }) -join "`n" } else { "- [MISSING - NEEDS INPUT]" })

## Comments ($($depCommentsList.Count) total)
$(($depCommentsSection) -join "`n")

## Attachments
- $($depAttachments.Count) file(s)$(if ($depAttachments.Count -gt 0) { ": " + (($depAttachments | ForEach-Object { $_.filename }) -join ", ") } else { "" })
"@
        Write-Text -path (Join-Path $depFolder "context.md") -content $depContext.Trim() 
    }

    # Confluence discovery/fetch (optional)
    $descText = Repair-Mojibake (Convert-JiraContentToText -Value $issue.fields.description)
    $commentText = @($comments.comments | ForEach-Object { Repair-Mojibake (Convert-JiraContentToText -Value $_.body) }) -join "`n"

    $foundConfluence = @()
    if ($includeConfluence) {
        $foundConfluence += (Extract-ConfluencePageIds -Text $descText)
        $foundConfluence += (Extract-ConfluencePageIds -Text $commentText)
    }

    # Also check Jira remote links for Confluence page references
    try {
        $jiraAuth = Get-JiraHeadersAndUrl
        $rlUri = "$($jiraAuth.url)/rest/api/2/issue/$Key/remotelink"
        $remoteLinks = Invoke-Utf8RestMethod -Uri $rlUri -Method Get -Headers $jiraAuth.headers -ErrorAction SilentlyContinue
        if ($remoteLinks) {
            foreach ($rl in @($remoteLinks)) {
                $rlUrl = if ($rl.object -and $rl.object.url) { $rl.object.url } else { "" }
                $rlPageIds = Extract-ConfluencePageIds -Text $rlUrl
                if ($rlPageIds.Count -gt 0) { $foundConfluence += $rlPageIds }
            }
        }
    } catch { <# ignore remote link fetch failures #> }

    if ($ConfluenceIdsOverride) { $foundConfluence += @($ConfluenceIdsOverride) }
    $foundConfluence = @($foundConfluence | Where-Object { $_ } | Select-Object -Unique)

    $confluenceRefs = @()
    if ($includeConfluence -and -not $NoConfluence -and $foundConfluence.Count -gt 0) {
        $confPrefix = Get-JiraKeyPrefix -Key $Key
        foreach ($pageId in $foundConfluence) {
            $page = Invoke-ConfluenceFetch -PageId $pageId
            $confDirName = "$($page.title) ($pageId)"
            $confDir = Join-Path $repoRoot "context/local/$confPrefix/confluence/$confDirName"
            Ensure-Dir $confDir
            
            Write-Json -path (Join-Path $confDir "page.json") -obj $page
            $summaryMd = @"
## Confluence Page
- Page ID: $pageId
- Title: $($page.title)
- Space: $($page.space.key)
- URL: $($page.url)
"@
            Write-Text -path (Join-Path $confDir "context.md") -content $summaryMd.Trim()
            
            $pageRel = (Join-Path $confDir "page.json").Substring($repoRoot.Length + 1).Replace('\', '/')
            $confluenceRefs += @{
                page_id = $pageId
                title = $page.title
                url = $page.url
                path = $pageRel
            }
        }
    }

    # TestRail coverage
    $coverage = $null
    $effectiveProjectId = $TestRailProjectIdOverride
    if (-not $effectiveProjectId) {
        $prefix = ($Key -split "-")[0]
        $mapId = $null
        
        if ($policy.testrail.project_id_map) { 
             # Check exact match
             $mapId = $policy.testrail.project_id_map[$prefix]
             
             # Check wildcard
             if (-not $mapId -and $policy.testrail.project_id_map.ContainsKey("*")) {
                 $mapId = $policy.testrail.project_id_map["*"]
             }
        }

        $effectiveProjectId = if ($mapId) { $mapId } elseif ($policy.testrail.default_project_id) { $policy.testrail.default_project_id } else { $null }
    }

    if ($IncludeTestRail) {
        $coverage = Invoke-TestRailCoverage -Key $Key -ProjectId $effectiveProjectId
    }

    $dCases = if ($coverage.direct_cases) { $coverage.direct_cases } else { @() }
    $directCases = @($dCases)
    
    $rCases = if ($coverage.related_cases) { $coverage.related_cases } else { @() }
    $relatedCases = @($rCases)

    # Sources.json - all relative paths point to sources/ subfolder
    $jiraUrlBase = (Get-EnvFingerprint).jira_url
    
    $issueRel = (Join-Path $sourcesDir "issue.json").Substring($repoRoot.Length + 1).Replace('\', '/')
    $commentsRel = (Join-Path $sourcesDir "comments.json").Substring($repoRoot.Length + 1).Replace('\', '/')
    $linkedRel = (Join-Path $sourcesDir "linked_issues.json").Substring($repoRoot.Length + 1).Replace('\', '/')
    $attRel = (Join-Path $sourcesDir "attachments.json").Substring($repoRoot.Length + 1).Replace('\', '/')
    $attDirRel = (Join-Path $jiraDir "attachments/").Substring($repoRoot.Length + 1).Replace('\', '/')

    $sources = @{
        jira = @{
            key = $Key
            url = if ($jiraUrlBase) { "$jiraUrlBase/browse/$Key" } else { $null }
            issue_path = $issueRel
            comments_path = $commentsRel
            linked_issues_path = $linkedRel
            attachments_path = $attRel
            attachments_dir = $attDirRel
        }
        testrail = if ($coverage) {
            $covPath = Join-Path (Get-ContextRoot -Scope "Auto" -Subdir "testrail") "$($coverage.project_id)/coverage/$Key.json"
            $covRel = $covPath.Substring($repoRoot.Length + 1).Replace('\', '/')
            @{
                project_id = $coverage.project_id
                coverage_path = $covRel
                direct_case_ids = @($directCases | ForEach-Object { $_.id })
                related_case_ids = @($relatedCases | ForEach-Object { $_.id })
            }
        } else { $null }
        confluence_pages = @($confluenceRefs)
    }
    $sourcesPath = Join-Path $sourcesDir "sources.json"
    Write-Json -path $sourcesPath -obj $sources

    # Context.md (enriched outline with description, comments, links, key details)
    $bugConcerns = @($graph.all | Where-Object { 
        $t = if ($_.issue_type) { "$($_.issue_type)" } else { "" }
        $t.ToLowerInvariant() -eq "bug" 
    })

    $depsTable = @()
    foreach ($d in @($graph.direct)) {
        $depStatus = if ($d.status) { $d.status } else { "Unknown" }
        $depSummary = if ($d.summary) { $d.summary } else { "[MISSING]" }
        $depsTable += "| $($d.key) | $($d.relationship) ($($d.direction)) | $depStatus | $depSummary | ``dependencies/$($d.key)/context.md`` |"
    }
    if ($depsTable.Count -eq 0) {
        $depsTable = @("| [None] | - | - | - | - |")
    }

    $coverageLines = if ($coverage) {
        "- ProjectId: $($coverage.project_id)`n" +
        "- Direct cases: $($directCases.Count)`n" +
        "- Related cases: $($relatedCases.Count)`n" +
        "- Gaps to address: [MISSING - NEEDS INPUT]"
    } else {
        "- Status: Not Checked (use -WithCoverage to include)`n" +
        "- Direct cases: -`n" +
        "- Related cases: -"
    }

    $referencesLines = @()
    $jiraLink = $sources.jira.url
    if ($jiraLink) { $referencesLines += "- Jira: [$Key]($jiraLink)" } else { $referencesLines += "- Jira: [MISSING - NEEDS INPUT]" }
    if ($confluenceRefs.Count -gt 0) {
        $referencesLines += "- Confluence:"
        foreach ($c in $confluenceRefs) { $referencesLines += "  - [$($c.title)]($($c.url))" }
    } else {
        $referencesLines += "- Confluence: (none found)"
    }

    if ($attachmentsMeta.Count -gt 0) {
        $downloadedCount = @($attachmentsMeta | Where-Object { $_.downloaded }).Count
        $referencesLines += "- Attachments: $($attachmentsMeta.Count) file(s) (downloaded: $downloadedCount)"
        foreach ($am in $attachmentsMeta) {
            $dlStatus = if ($am.downloaded) { "downloaded" } else { "not downloaded" }
            $referencesLines += "  - ``$($am.filename)`` ($($am.mimeType), $dlStatus)"
        }
    } else {
        $referencesLines += "- Attachments: (none)"
    }

    # Extract inline links from description
    $descLinks = @()
    if ($descText) {
        $linkMatches = [regex]::Matches($descText, 'https?://[^\s\|\]\)]+')
        foreach ($lm in $linkMatches) { $descLinks += $lm.Value }
    }
    if ($descLinks.Count -gt 0) {
        $referencesLines += "- Links found in description:"
        foreach ($dl in ($descLinks | Select-Object -Unique)) { $referencesLines += "  - $dl" }
    }

    # Build description summary section — convert Jira wiki markup to Markdown
    $descSection = if ($descText -and $descText.Trim()) {
        Convert-JiraWikiToMarkdown -Text $descText.Trim()
    } else {
        "[MISSING - NEEDS INPUT]"
    }

    # Extract attachment contents → save to sources/attachment_extractions.json for AI analysis
    $attachmentExtractions = @()
    $readableExtensions = @('.txt', '.csv', '.md', '.json', '.xml', '.yml', '.yaml', '.log', '.ini', '.cfg', '.conf', '.properties', '.env', '.sh', '.ps1', '.bat', '.sql', '.html', '.css', '.js', '.ts', '.py', '.java', '.rb', '.go', '.rs')
    $svgExtensions = @('.svg')
    $excelExtensions = @('.xlsx', '.xls')
    $pdfExtensions = @('.pdf')
    $imageExtensions = @('.png', '.jpg', '.jpeg', '.gif', '.bmp', '.webp', '.tiff')
    $maxExtractBytes = 8000
    foreach ($am in $attachmentsMeta) {
        if (-not $am.downloaded -or -not $am.path) { continue }
        $ext = [System.IO.Path]::GetExtension($am.filename).ToLowerInvariant()
        $destName = if ($am.id) { "$($am.id)_$(Sanitize-FileName -Name $am.filename)" } else { Sanitize-FileName -Name $am.filename }
        $absPath = Join-Path $attachDir $destName
        if (-not (Test-Path $absPath)) { continue }
        $fileSize = (Get-Item $absPath).Length
        $fSizeKB = [math]::Round($fileSize/1KB, 1)

        $extraction = @{
            filename    = $am.filename
            mimeType    = $am.mimeType
            sizeKB      = $fSizeKB
            localPath   = $am.path
            type        = "unknown"
            method      = "metadata_only"
            raw_content = $null
            notes       = ""
        }

        if ($ext -in $readableExtensions) {
            $extraction.type = "text"
            try {
                $raw = [System.IO.File]::ReadAllText($absPath, [System.Text.Encoding]::UTF8)
                if ($raw.Length -gt $maxExtractBytes) { $raw = $raw.Substring(0, $maxExtractBytes) + "`n... [truncated at $maxExtractBytes chars]" }
                $extraction.raw_content = $raw
                $extraction.method = "utf8_text_read"
            } catch {
                $extraction.notes = "Read error: $($_.Exception.Message)"
            }
        } elseif ($ext -in $svgExtensions) {
            $extraction.type = "svg"
            try {
                $svgRaw = [System.IO.File]::ReadAllText($absPath, [System.Text.Encoding]::UTF8)
                $textElements = @([regex]::Matches($svgRaw, '<text[^>]*>([^<]+)</text>') | ForEach-Object { $_.Groups[1].Value.Trim() } | Where-Object { $_ })
                $titleMatch = [regex]::Match($svgRaw, '<title>([^<]+)</title>')
                $descMatch = [regex]::Match($svgRaw, '<desc>([^<]+)</desc>')
                $svgContent = ""
                if ($titleMatch.Success) { $svgContent += "Title: $($titleMatch.Groups[1].Value)`n" }
                if ($descMatch.Success) { $svgContent += "Description: $($descMatch.Groups[1].Value)`n" }
                if ($textElements.Count -gt 0) { $svgContent += "Labels/Annotations:`n" + ($textElements -join "`n") }
                $extraction.raw_content = $svgContent.Trim()
                $extraction.method = "svg_text_elements"
                $extraction.notes = "$($textElements.Count) text elements extracted"
            } catch {
                $extraction.notes = "SVG parse error: $($_.Exception.Message)"
            }
        } elseif ($ext -in $excelExtensions) {
            $extraction.type = "excel"
            try {
                $excelModule = Get-Module -ListAvailable -Name ImportExcel | Select-Object -First 1
                if ($excelModule) {
                    Import-Module ImportExcel -ErrorAction SilentlyContinue
                    $sheets = Get-ExcelSheetInfo -Path $absPath
                    $excelContent = "Sheets: $($sheets.Count)`n"
                    foreach ($sheet in $sheets) {
                        $data = Import-Excel -Path $absPath -WorksheetName $sheet.Name -ErrorAction SilentlyContinue
                        if ($data -and $data.Count -gt 0) {
                            $colHeaders = @($data[0].PSObject.Properties.Name)
                            $excelContent += "Sheet '$($sheet.Name)': $($data.Count) rows, columns: $($colHeaders -join ', ')`n"
                            $preview = $data | Select-Object -First 15 | Format-Table -AutoSize | Out-String
                            if ($preview.Length -gt $maxExtractBytes) { $preview = $preview.Substring(0, $maxExtractBytes) + "`n[truncated]" }
                            $excelContent += $preview.Trim() + "`n"
                        }
                    }
                    $extraction.raw_content = $excelContent.Trim()
                    $extraction.method = "importexcel"
                } else {
                    $extraction.notes = "ImportExcel module not available"
                }
            } catch {
                $extraction.notes = "Excel read error: $($_.Exception.Message)"
            }
        } elseif ($ext -in $pdfExtensions) {
            $extraction.type = "pdf"
            try {
                $pdfBytes = [System.IO.File]::ReadAllBytes($absPath)
                $latin1Text = [System.Text.Encoding]::GetEncoding(28591).GetString($pdfBytes)
                $textParts = @([regex]::Matches($latin1Text, '\(([^\)]{3,})\)') | ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -match '[a-zA-Z]{2,}' -and $_ -notmatch '^\s*[\d\.]+\s*$' })
                if ($textParts.Count -gt 0) {
                    $pdfText = $textParts -join "`n"
                    if ($pdfText.Length -gt $maxExtractBytes) { $pdfText = $pdfText.Substring(0, $maxExtractBytes) + "`n[truncated]" }
                    $extraction.raw_content = $pdfText
                    $extraction.method = "pdf_text_scan"
                    $extraction.notes = "$($textParts.Count) text segments extracted"
                } else {
                    $extraction.notes = "No extractable text found - may need OCR"
                }
            } catch {
                $extraction.notes = "PDF read error: $($_.Exception.Message)"
            }
        } elseif ($ext -in $imageExtensions) {
            $extraction.type = "image"
            $extraction.notes = "Image file - requires visual analysis by AI agent"
        } else {
            $extraction.notes = "Binary file - content not extractable"
        }

        $attachmentExtractions += $extraction
    }

    # Save extraction data for AI agent to analyze
    if ($attachmentExtractions.Count -gt 0) {
        $extractionsPath = Join-Path $sourcesDir "attachment_extractions.json"
        Write-Json -path $extractionsPath -obj $attachmentExtractions
    }

    # Build a minimal attachment section for context.md (AI will replace with summaries)
    $attachContentSection = @()
    if ($attachmentExtractions.Count -gt 0) {
        $attachContentSection += "<!-- ATTACHMENT_ANALYSIS_PLACEHOLDER -->"
        $attachContentSection += "*Extracted data from $($attachmentExtractions.Count) attachment(s) saved to ``sources/attachment_extractions.json`` for AI analysis.*"
        $attachContentSection += "*The AI agent will analyze and summarize each file below during the analysis phase.*"
        $attachContentSection += ""
        foreach ($ae in $attachmentExtractions) {
            $typeLabel = switch ($ae.type) { "text" { "Text" }; "svg" { "SVG Diagram" }; "excel" { "Excel Workbook" }; "pdf" { "PDF Document" }; "image" { "Image" }; default { "File" } }
            $attachContentSection += "- **$($ae.filename)** ($typeLabel, $($ae.sizeKB) KB) - extraction: $($ae.method)"
        }
    } else {
        $attachContentSection += "(no attachments to analyze)"
    }

    # Build comments summary section
    $commentsSection = @()
    $commentsList = if ($comments.comments) { @($comments.comments) } else { @() }
    if ($commentsList.Count -gt 0) {
        $commentIdx = 0
        foreach ($cm in $commentsList) {
            $commentIdx++
            $author = if ($cm.author -and $cm.author.displayName) { $cm.author.displayName } else { "Unknown" }
            $created = if ($cm.created) { ($cm.created -split 'T')[0] } else { "Unknown date" }
            $body = Repair-Mojibake (Convert-JiraContentToText -Value $cm.body)
            # Truncate very long comments for the summary
            if ($body.Length -gt 500) { $body = $body.Substring(0, 497) + "..." }
            $commentsSection += "**Comment #$commentIdx** by *$author* ($created):"
            $commentsSection += "> $($body -replace "`n", "`n> ")"
            $commentsSection += ""
        }
    } else {
        $commentsSection += "(no comments)"
    }

    # Build key details section
    $issueStatus = if ($issue.fields.status.name) { $issue.fields.status.name } else { "Unknown" }
    $issuePriority = if ($issue.fields.priority.name) { $issue.fields.priority.name } else { "Unknown" }
    $issueCreated = if ($issue.fields.created) { ($issue.fields.created -split 'T')[0] } else { "Unknown" }
    $issueUpdated = if ($issue.fields.updated) { ($issue.fields.updated -split 'T')[0] } else { "Unknown" }

    # Build all linked issues section (not just direct deps)
    $allLinkedSection = @()
    foreach ($lnk in @($graph.all)) {
        $lnkStatus = if ($lnk.status) { $lnk.status } else { "Unknown" }
        $lnkType = if ($lnk.issue_type) { $lnk.issue_type } else { "Unknown" }
        $allLinkedSection += "| $($lnk.key) | $lnkType | $lnkStatus | $($lnk.summary) |"
    }

    $contextMd = @"
## Issue
- **Key:** $Key
- **Summary:** $($issue.fields.summary)
- **Type:** $($issue.fields.issuetype.name)
- **Status:** $issueStatus
- **Priority:** $issuePriority
- **Created:** $issueCreated
- **Last Updated:** $issueUpdated

## Description
$descSection

## Acceptance Criteria
$(if (($ac = Extract-AcceptanceCriteria -DescriptionText $descText) -and $ac.Count -gt 0) { ($ac | ForEach-Object { "- $_" }) -join "`n" } else { "- [MISSING - NEEDS INPUT]" })

## Comments ($($commentsList.Count) total)
$(($commentsSection) -join "`n")

## Direct Dependencies
| Key | Relationship | Status | Summary | Context Link |
|-----|-------------|--------|---------|-------------|
$(($depsTable) -join "`n")

## All Linked Issues ($($graph.all.Count) total)
| Key | Type | Status | Summary |
|-----|------|--------|---------|
$(if ($allLinkedSection.Count -gt 0) { ($allLinkedSection) -join "`n" } else { "| (none) | - | - | - |" })

## Existing Coverage (TestRail)
$coverageLines

## References & Links
$(($referencesLines) -join "`n")

## Attachment Extractions
$(if ($attachContentSection.Count -gt 0) { ($attachContentSection) -join "`n" } else { "(no attachments)" })

## Concerns / Known Bugs (NOT analyzed as requirements)
$(if ($bugConcerns.Count -gt 0) { ($bugConcerns | ForEach-Object { "- $($_.key): $($_.summary)" }) -join "`n" } else { "- (none detected)" })
"@

    # Write context.md to shared location (team-visible summary)
    Ensure-Dir $sharedJiraDir
    $contextPath = Join-Path $sharedJiraDir "context.md"
    Write-Text -path $contextPath -content $contextMd.Trim()

    # Also write a copy in local dir for completeness
    if ($sharedJiraDir -ne $jiraDir) {
        $localContextPath = Join-Path $jiraDir "context.md"
        Write-Text -path $localContextPath -content $contextMd.Trim()
    }

    # Jira context manifest
    $newManifest = @{
        jira_key = $Key
        context_status = "raw"
        scraped_at = (Get-Date).ToString("s")
        last_updated = (Get-Date).ToString("s")
        dependency_depth = $depDepth
        dependency_keys = @($graph.all | ForEach-Object { $_.key })
        confluence_page_ids = @($foundConfluence)
        attachment_extractions = @($attachmentExtractions | ForEach-Object { @{ filename = $_.filename; type = $_.type; method = $_.method } })
        context_md_path = $contextPath.Substring($repoRoot.Length + 1).Replace('\', '/')
        local_data_path = $jiraDir.Substring($repoRoot.Length + 1).Replace('\', '/')
        hashes = @{
            issue = Get-FileSha256 -path $issuePath
            comments = Get-FileSha256 -path $commentsPath
            linked_issues = Get-FileSha256 -path $linkedPath
            attachments = Get-FileSha256 -path $attachmentsPath
            sources = Get-FileSha256 -path $sourcesPath
            context_md = Get-FileSha256 -path $contextPath
        }
        testrail = if ($coverage) {
            @{
                project_id = $coverage.project_id
                direct_count = $directCases.Count
                related_count = $relatedCases.Count
            }
        } else { $null }
        diffs = @()
    }

    # Diff entry (if refresh and previous existed)
    if ($oldManifest) {
        $changes = @()
        
        $oldIss = if ($oldManifest.hashes.issue) { $oldManifest.hashes.issue } else { "" }
        $newIss = if ($newManifest.hashes.issue) { $newManifest.hashes.issue } else { "" }
        if ($oldIss -ne $newIss) { $changes += "- issue.json changed" }
        
        $oldComm = if ($oldManifest.hashes.comments) { $oldManifest.hashes.comments } else { "" }
        $newComm = if ($newManifest.hashes.comments) { $newManifest.hashes.comments } else { "" }
        if ($oldComm -ne $newComm) { $changes += "- comments.json changed" }

        $oldLink = if ($oldManifest.hashes.linked_issues) { $oldManifest.hashes.linked_issues } else { "" }
        $newLink = if ($newManifest.hashes.linked_issues) { $newManifest.hashes.linked_issues } else { "" }
        if ($oldLink -ne $newLink) { $changes += "- linked_issues.json changed" }

        $oldDeps = if ($oldManifest.dependency_keys) { @($oldManifest.dependency_keys) } else { @() }
        $newDeps = if ($newManifest.dependency_keys) { @($newManifest.dependency_keys) } else { @() }
        $added = @($newDeps | Where-Object { $_ -notin $oldDeps })
        $removed = @($oldDeps | Where-Object { $_ -notin $newDeps })
        if ($added.Count -gt 0) { $changes += "- dependencies added: $($added -join ', ')" }
        if ($removed.Count -gt 0) { $changes += "- dependencies removed: $($removed -join ', ')" }

        $diffStamp = Get-Timestamp
        $diffRel = "context/jira/$Key/diffs/$diffStamp.md"
        $diffPath = Join-Path $diffsDir "$diffStamp.md"
        $diffMd = @"
## Context Refresh Diff ($diffStamp)

$(if ($changes.Count -gt 0) { ($changes -join "`n") } else { "No detectable changes (hashes unchanged)." })
"@
        Write-Text -path $diffPath -content $diffMd.Trim()
        $newManifest.diffs = @(@{ timestamp = $diffStamp; path = $diffRel }) + $(if ($oldManifest.diffs) { @($oldManifest.diffs) } else { @() })
    }

    Write-Json -path $manifestPath -obj $newManifest
    $jiraDirRel = $jiraDir.Substring($repoRoot.Length + 1).Replace('\', '/')
    Upsert-ActiveContextEntry -Kind "jira" -Key $Key -Path $jiraDirRel

    return @{
        jira_key = $Key
        reused = $false
        context_dir = $jiraDir
        manifest_path = $manifestPath
        context_md_path = $contextPath
        sources_path = $sourcesPath
    }
}

if ($InitWorkspace) {
    # Directories (per REQS-V2-UPDATE.MD)
    foreach ($d in @(
        ".github",
        ".github/agents",
        ".github/instructions",
        "core/prompts",
        "core/skills",
        "core/scripts",
        "core/modules",
        "core/templates",
        "core/validation/checks",
        "overrides/prompts",
        "overrides/templates",
        "overrides/rules",
        "plugins",
        ".aira/tests/unit",
        ".aira/tests/integration",
        ".aira/tests/results",
        ".aira/sessions",
        ".aira/memory",
        "context/local",
        "context/shared",
        "outputs",
        "requirements",
        "scratch"
    )) {
        Ensure-Dir (Join-Path $repoRoot $d)
    }

    # Non-destructive: do not overwrite existing files.
    Ensure-File (Join-Path $repoRoot ".env.example") "# Copy to .env and fill in credentials.`n"
    Ensure-File (Join-Path $repoRoot "context/manifest.json") (@{ active = @(); archived = @() } | ConvertTo-Json -Depth 5)
    Ensure-File (Join-Path $repoRoot "context/local/manifest.json") (@{ active = @(); archived = @() } | ConvertTo-Json -Depth 5)
    Ensure-File (Join-Path $repoRoot "context/shared/manifest.json") (@{ active = @(); archived = @() } | ConvertTo-Json -Depth 5)

    @{ status = "ok"; message = "Workspace initialized"; repo_root = $repoRoot } | ConvertTo-Json -Depth 10
    exit 0
}

if ($InstallDependencies) {
    # Install required PowerShell modules for AIRA.
    # - Pester 5.7+ (test framework; Windows ships Pester 3.4 which is incompatible)
    # - ImportExcel  (Excel export without Office dependency)
    Write-Host "Checking AIRA dependencies..." -ForegroundColor Cyan

    $deps = @(
        @{ Name = "Pester";      MinVersion = "5.7.0"; Scope = "CurrentUser" }
        @{ Name = "ImportExcel"; MinVersion = $null;    Scope = "CurrentUser" }
    )

    $installed = @()
    $skipped   = @()

    foreach ($dep in $deps) {
        $mod = Get-Module -ListAvailable -Name $dep.Name | Sort-Object Version -Descending | Select-Object -First 1
        $needsInstall = $false

        if (-not $mod) {
            $needsInstall = $true
        } elseif ($dep.MinVersion) {
            if ($mod.Version -lt [version]$dep.MinVersion) { $needsInstall = $true }
        }

        if ($needsInstall) {
            Write-Host "  Installing $($dep.Name)..." -ForegroundColor Yellow
            try {
                $installParams = @{ Name = $dep.Name; Scope = $dep.Scope; Force = $true; SkipPublisherCheck = $true; AllowClobber = $true }
                if ($dep.MinVersion) { $installParams.MinimumVersion = $dep.MinVersion }
                Install-Module @installParams
                $installed += $dep.Name
                Write-Host "    $($dep.Name) installed." -ForegroundColor Green
            } catch {
                Write-Host "    FAILED to install $($dep.Name): $($_.Exception.Message)" -ForegroundColor Red
            }
        } else {
            $skipped += "$($dep.Name) v$($mod.Version)"
            Write-Host "  $($dep.Name) v$($mod.Version) already installed." -ForegroundColor Green
        }
    }

    @{ status = "ok"; installed = $installed; already_present = $skipped } | ConvertTo-Json -Depth 5
    exit 0
}

if ($Doctor) {
    $statePath = Join-Path $repoRoot ".aira/tests/startup.state.json"
    $resultsDir = Join-Path $repoRoot ".aira/tests/results"
    Ensure-Dir $resultsDir

    $fingerprint = $null
    try { $fingerprint = Get-EnvFingerprint } catch { $fingerprint = @{} }

    $scriptHash = $null
    try { $scriptHash = Get-ScriptFingerprint } catch { $scriptHash = "" }

    $shouldRun = $Force
    if (-not $shouldRun) {
        if (-not (Test-Path $statePath)) { $shouldRun = $true }
        else {
            try {
                $state = Get-Content $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($state.status -ne "Complete") { $shouldRun = $true }
                else {
                    $old = $state.env_fingerprint
                    $oldJira = if ($old.jira_url) { $old.jira_url } else { "" }
                    $newJira = if ($fingerprint.jira_url) { $fingerprint.jira_url } else { "" }
                    
                    $oldConf = if ($old.confluence_url) { $old.confluence_url } else { "" }
                    $newConf = if ($fingerprint.confluence_url) { $fingerprint.confluence_url } else { "" }

                    $oldTr = if ($old.testrail_url) { $old.testrail_url } else { "" }
                    $newTr = if ($fingerprint.testrail_url) { $fingerprint.testrail_url } else { "" }

                    $oldUser = if ($old.user) { $old.user } else { "" }
                    $newUser = if ($fingerprint.user) { $fingerprint.user } else { "" }

                    if ($oldJira -ne $newJira) { $shouldRun = $true }
                    elseif ($oldConf -ne $newConf) { $shouldRun = $true }
                    elseif ($oldTr -ne $newTr) { $shouldRun = $true }
                    elseif ($oldUser -ne $newUser) { $shouldRun = $true }
                    else {
                        $oldSH = if ($state.PSObject.Properties.Name -contains 'script_hash') { [string]$state.script_hash } else { "" }
                        $newSH = if ($scriptHash) { $scriptHash } else { "" }
                        if ($oldSH -ne $newSH) { $shouldRun = $true }
                    }
                }
            } catch {
                $shouldRun = $true
            }
        }
    }

    if (-not $shouldRun) {
        @{ status = "Complete"; message = "Readiness already complete"; startup_state = $statePath } | ConvertTo-Json -Depth 10
        exit 0
    }

    # Force Pester 5+ (skip builtin 3.x if present)
    $pesterModules = Get-Module -ListAvailable -Name Pester | Sort-Object Version -Descending
    $pester5 = $pesterModules | Where-Object { $_.Version.Major -ge 5 } | Select-Object -First 1
    if (-not $pester5) {
        $failState = @{
            status = "Failed"
            completed_at = (Get-Date).ToString("s")
            env_fingerprint = $fingerprint
            last_run = @{ overall = "Fail"; unit = "Fail"; integration = "Fail" }
            error = "Pester 5+ module not installed. Found: $($pesterModules | ForEach-Object { $_.Version }) "
        }
        $failState | ConvertTo-Json -Depth 10 | Out-File -FilePath $statePath -Encoding UTF8
        throw "Pester 5+ is required for readiness tests. Install with: Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck"
    }

    Import-Module $pester5.Path -Force -ErrorAction Stop

    $unitPath = Join-Path $repoRoot ".aira/tests/unit"
    $intPath = Join-Path $repoRoot ".aira/tests/integration"

    $runStamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $unitOutFile = Join-Path $resultsDir "unit_$runStamp.xml"
    $intOutFile = Join-Path $resultsDir "integration_$runStamp.xml"
    $logFile = Join-Path $resultsDir "test_result.log"

    # Pester 5 configuration — Verbosity set to Minimal.
    # All console output (including warnings) is redirected to the log file
    # to prevent VS Code terminal crashes from large output volumes.
    $unitConfig = New-PesterConfiguration
    $unitConfig.Run.Path = $unitPath
    $unitConfig.Run.PassThru = $true
    $unitConfig.TestResult.Enabled = $true
    $unitConfig.TestResult.OutputPath = $unitOutFile
    $unitConfig.TestResult.OutputFormat = "NUnitXml"
    $unitConfig.Output.Verbosity = "Minimal"

    $intConfig = New-PesterConfiguration
    $intConfig.Run.Path = $intPath
    $intConfig.Run.PassThru = $true
    $intConfig.TestResult.Enabled = $true
    $intConfig.TestResult.OutputPath = $intOutFile
    $intConfig.TestResult.OutputFormat = "NUnitXml"
    $intConfig.Output.Verbosity = "Minimal"

    # Initialize log file with timestamp header
    $logTs = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    "=============================================" | Out-File -FilePath $logFile -Encoding UTF8
    "  AIRA Doctor - Test Run Log" | Out-File -FilePath $logFile -Encoding UTF8 -Append
    "  Started: $logTs" | Out-File -FilePath $logFile -Encoding UTF8 -Append
    "=============================================" | Out-File -FilePath $logFile -Encoding UTF8 -Append
    "" | Out-File -FilePath $logFile -Encoding UTF8 -Append

    # Run unit tests in subprocess — Pester output goes to a temp file via *>>,
    # then post-processed (collapse double-blank-lines) and appended to the main log.
    # This preserves Pester's native formatting (test name + timing on one line).
    # JSON summary goes to a separate file for reliable result parsing.
    Write-Host "Running unit tests (log: .aira/tests/results/test_result.log)..." -ForegroundColor Cyan
    $unitJsonFile = Join-Path $resultsDir "unit_result.json"
    $unitTmpFile = Join-Path $resultsDir "unit_pester.tmp"
    "" | Out-File -FilePath $logFile -Encoding UTF8 -Append
    "=== Unit Tests === [$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')]" | Out-File -FilePath $logFile -Encoding UTF8 -Append
    "---" | Out-File -FilePath $logFile -Encoding UTF8 -Append
    if (Test-Path $unitTmpFile) { Remove-Item $unitTmpFile -Force }
    powershell -NoProfile -Command "
        `$env:NO_COLOR = '1'
        Import-Module Pester -RequiredVersion 5.7.1 -Force -WarningAction SilentlyContinue
        `$c = New-PesterConfiguration
        `$c.Run.Path = '$unitPath'
        `$c.Run.PassThru = `$true
        `$c.TestResult.Enabled = `$true
        `$c.TestResult.OutputPath = '$unitOutFile'
        `$c.TestResult.OutputFormat = 'NUnitXml'
        `$c.Output.Verbosity = 'Detailed'
        & { `$script:r = Invoke-Pester -Configuration `$c } *>> '$unitTmpFile'
        @{ PassedCount = `$script:r.PassedCount; FailedCount = `$script:r.FailedCount; SkippedCount = `$script:r.SkippedCount } | ConvertTo-Json | Out-File '$unitJsonFile' -Encoding UTF8
    "
    # Post-process: strip ANSI escape codes and collapse consecutive blank lines
    $ansiRegex = [char]0x1b + '\[[0-9;]*m'
    if (Test-Path $unitTmpFile) {
        $prevBlank = $false
        foreach ($line in (Get-Content $unitTmpFile -Encoding UTF8)) {
            $clean = $line -replace $ansiRegex, ''
            $isBlank = [string]::IsNullOrWhiteSpace($clean)
            if ($isBlank -and $prevBlank) { continue }
            $prevBlank = $isBlank
            $clean | Out-File -FilePath $logFile -Encoding UTF8 -Append
        }
        Remove-Item $unitTmpFile -Force -ErrorAction SilentlyContinue
    }
    "---" | Out-File -FilePath $logFile -Encoding UTF8 -Append
    "Unit tests completed [$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')]" | Out-File -FilePath $logFile -Encoding UTF8 -Append
    $unit = if (Test-Path $unitJsonFile) {
        try { Get-Content $unitJsonFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch { [pscustomobject]@{ PassedCount = 0; FailedCount = 999; SkippedCount = 0 } }
    } else { [pscustomobject]@{ PassedCount = 0; FailedCount = 999; SkippedCount = 0 } }
    Write-Host "  Unit: P=$($unit.PassedCount) F=$($unit.FailedCount) S=$($unit.SkippedCount)" -ForegroundColor $(if ($unit.FailedCount -gt 0) { 'Red' } else { 'Green' })

    # Run integration tests — same subprocess + post-process approach
    Write-Host "Running integration tests..." -ForegroundColor Cyan
    $intJsonFile = Join-Path $resultsDir "integration_result.json"
    $intTmpFile = Join-Path $resultsDir "integration_pester.tmp"
    "" | Out-File -FilePath $logFile -Encoding UTF8 -Append
    "=== Integration Tests === [$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')]" | Out-File -FilePath $logFile -Encoding UTF8 -Append
    "---" | Out-File -FilePath $logFile -Encoding UTF8 -Append
    if (Test-Path $intTmpFile) { Remove-Item $intTmpFile -Force }
    powershell -NoProfile -Command "
        `$env:NO_COLOR = '1'
        Import-Module Pester -RequiredVersion 5.7.1 -Force -WarningAction SilentlyContinue
        `$c = New-PesterConfiguration
        `$c.Run.Path = '$intPath'
        `$c.Run.PassThru = `$true
        `$c.TestResult.Enabled = `$true
        `$c.TestResult.OutputPath = '$intOutFile'
        `$c.TestResult.OutputFormat = 'NUnitXml'
        `$c.Output.Verbosity = 'Detailed'
        & { `$script:r = Invoke-Pester -Configuration `$c } *>> '$intTmpFile'
        @{ PassedCount = `$script:r.PassedCount; FailedCount = `$script:r.FailedCount; SkippedCount = `$script:r.SkippedCount } | ConvertTo-Json | Out-File '$intJsonFile' -Encoding UTF8
    "
    $ansiRegex = [char]0x1b + '\[[0-9;]*m'
    if (Test-Path $intTmpFile) {
        $prevBlank = $false
        foreach ($line in (Get-Content $intTmpFile -Encoding UTF8)) {
            $clean = $line -replace $ansiRegex, ''
            $isBlank = [string]::IsNullOrWhiteSpace($clean)
            if ($isBlank -and $prevBlank) { continue }
            $prevBlank = $isBlank
            $clean | Out-File -FilePath $logFile -Encoding UTF8 -Append
        }
        Remove-Item $intTmpFile -Force -ErrorAction SilentlyContinue
    }
    "---" | Out-File -FilePath $logFile -Encoding UTF8 -Append
    "Integration tests completed [$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')]" | Out-File -FilePath $logFile -Encoding UTF8 -Append
    $integration = if (Test-Path $intJsonFile) {
        try { Get-Content $intJsonFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch { [pscustomobject]@{ PassedCount = 0; FailedCount = 999; SkippedCount = 0 } }
    } else { [pscustomobject]@{ PassedCount = 0; FailedCount = 999; SkippedCount = 0 } }
    Write-Host "  Integration: P=$($integration.PassedCount) F=$($integration.FailedCount) S=$($integration.SkippedCount)" -ForegroundColor $(if ($integration.FailedCount -gt 0) { 'Red' } else { 'Green' })

    # ── Package Safety Audit ──
    $validationModule = Join-Path $repoRoot "core/modules/Aira.Validation.psm1"
    if (Test-Path $validationModule) { Import-Module $validationModule -Force -WarningAction SilentlyContinue }
    Write-Host "Running package safety audit..." -ForegroundColor Cyan
    $pkgSafetyStatus = "Pass"
    $pkgSafetyResult = $null
    try {
        $pkgSafetyResult = Invoke-AiraPackageSafetyAudit -RepoRoot $repoRoot
        $pkgSafetyStatus = $pkgSafetyResult.status
        $critCount = $pkgSafetyResult.summary.by_severity.critical
        $highCount = $pkgSafetyResult.summary.by_severity.high
        $medCount  = $pkgSafetyResult.summary.by_severity.medium
        $lowCount  = $pkgSafetyResult.summary.by_severity.low
        $color = if ($pkgSafetyStatus -eq "Fail") { "Red" } elseif ($pkgSafetyStatus -eq "Warn") { "Yellow" } else { "Green" }
        Write-Host "  Package Safety: $pkgSafetyStatus (Critical=$critCount High=$highCount Medium=$medCount Low=$lowCount)" -ForegroundColor $color
        if ($critCount -gt 0 -or $highCount -gt 0) {
            foreach ($f in $pkgSafetyResult.findings) {
                if ($f.severity -eq "Critical" -or $f.severity -eq "High") {
                    $line = if ($f.line) { ":$($f.line)" } else { "" }
                    Write-Host "    [$($f.severity)] $($f.path)$line - $($f.description)" -ForegroundColor $(if ($f.severity -eq "Critical") { "Red" } else { "Yellow" })
                }
            }
        }
        # Save audit results to file
        $pkgSafetyFile = Join-Path $resultsDir "package_safety.json"
        $pkgSafetyResult | ConvertTo-Json -Depth 50 | Out-File -FilePath $pkgSafetyFile -Encoding UTF8
        "" | Out-File -FilePath $logFile -Encoding UTF8 -Append
        "=== Package Safety Audit === [$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')]" | Out-File -FilePath $logFile -Encoding UTF8 -Append
        "Status: $pkgSafetyStatus | Findings: $($pkgSafetyResult.summary.finding_count) (C=$critCount H=$highCount M=$medCount L=$lowCount)" | Out-File -FilePath $logFile -Encoding UTF8 -Append
        foreach ($f in $pkgSafetyResult.findings) {
            $line = if ($f.line) { ":$($f.line)" } else { "" }
            "  [$($f.severity)] $($f.path)$line - $($f.description)" | Out-File -FilePath $logFile -Encoding UTF8 -Append
        }
    } catch {
        $pkgSafetyStatus = "Fail"
        Write-Host "  Package Safety: FAILED - $($_.Exception.Message)" -ForegroundColor Red
        "=== Package Safety Audit === FAILED" | Out-File -FilePath $logFile -Encoding UTF8 -Append
        "$($_.Exception.Message)" | Out-File -FilePath $logFile -Encoding UTF8 -Append
    }

    $unitStatus = if ($unit.FailedCount -gt 0) { "Fail" } else { "Pass" }
    $intStatus = if ($integration.FailedCount -gt 0) { "Fail" } else { "Pass" }
    # Package safety Critical = Fail the overall doctor run
    $pkgFailed = ($pkgSafetyStatus -eq "Fail")
    $overall = if ($unitStatus -eq "Pass" -and $intStatus -eq "Pass" -and -not $pkgFailed) { "Pass" } else { "Fail" }

    $status = if ($overall -eq "Pass") { "Complete" } else { "Failed" }

    $startupState = @{
        status = $status
        completed_at = (Get-Date).ToString("s")
        env_fingerprint = $fingerprint
        script_hash = $scriptHash
        last_run = @{
            overall = $overall
            unit = $unitStatus
            integration = $intStatus
            package_safety = $pkgSafetyStatus
        }
    }

    $startupState | ConvertTo-Json -Depth 10 | Out-File -FilePath $statePath -Encoding UTF8

    # Save last-run summary for troubleshooting
    $lastRun = @{
        timestamp = (Get-Date).ToString("s")
        status = $startupState.status
        unit = @{
            passed = $unit.PassedCount
            failed = $unit.FailedCount
            skipped = $unit.SkippedCount
            report = $unitOutFile
        }
        integration = @{
            passed = $integration.PassedCount
            failed = $integration.FailedCount
            skipped = $integration.SkippedCount
            report = $intOutFile
        }
        package_safety = @{
            status   = $pkgSafetyStatus
            findings = if ($pkgSafetyResult) { $pkgSafetyResult.summary.finding_count } else { 0 }
            report   = (Join-Path $resultsDir "package_safety.json")
        }
        log_file = $logFile
    }
    Write-Json -path (Join-Path $resultsDir "last_doctor.json") -obj $lastRun
    Write-Host "`nResults: $status | Log: .aira/tests/results/test_result.log" -ForegroundColor $(if ($status -eq 'Complete') { 'Green' } else { 'Red' })

    try {
        $telemetryModule = Join-Path $repoRoot "core/modules/Aira.Telemetry.psm1"
        if (Test-Path $telemetryModule) {
            Import-Module $telemetryModule -Force -ErrorAction SilentlyContinue | Out-Null
            if (Get-Command Write-AiraTelemetryEvent -ErrorAction SilentlyContinue) {
                Write-AiraTelemetryEvent -Action "doctor" -Outcome $startupState.status -Data @{
                    unit = $unitStatus
                    integration = $intStatus
                } -RepoRoot $repoRoot | Out-Null
            }
        }
    } catch { }

    $startupState | ConvertTo-Json -Depth 10
    exit 0
}

if ($ListContext) {
    $manifest = Read-ContextManifest
    $manifest | ConvertTo-Json -Depth 10
    exit 0
}

if ($ArchiveContext) {
    # Resolve path for the Jira key: {KeyPrefix}/{JiraKey}\n    $subPath = Get-ContextSubPath -JiraKey $JiraKey

    $localBase = Join-Path $repoRoot "context/local"
    $sharedBase = Join-Path $repoRoot "context/shared"
    $lDir = Join-Path $localBase $subPath
    $sDir = Join-Path $sharedBase $subPath

    # Also check legacy flat paths for backwards compat
    $legacyL = Join-Path $localBase "jira/$JiraKey"
    $legacyS = Join-Path $sharedBase "jira/$JiraKey"

    $activeDir = if (Test-Path $lDir) { $lDir } elseif (Test-Path $sDir) { $sDir } elseif (Test-Path $legacyL) { $legacyL } elseif (Test-Path $legacyS) { $legacyS } else { $null }

    if (-not $activeDir) { throw "Active Jira context not found for $JiraKey (checked local/shared)" }

    $archiveRoot = Join-Path $repoRoot "context/archive"
    Ensure-Dir $archiveRoot
    $stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
    $archivedDir = Join-Path $archiveRoot ("{0}__{1}" -f $JiraKey, $stamp)
    Move-Item -Path $activeDir -Destination $archivedDir -Force

    # Also remove the shared context.md if it was separate from the archived dir
    if ($activeDir -ne $sDir -and (Test-Path $sDir)) { Remove-Item $sDir -Recurse -Force }

    Archive-ContextEntry -Kind "jira" -Key $JiraKey -ArchivedPath ("context/archive/{0}__{1}" -f $JiraKey, $stamp)
    @{ status = "ok"; archived_to = $archivedDir } | ConvertTo-Json -Depth 10
    exit 0
}

if ($Rescan) {
    # Rescan all active context entries: re-fetch from sources, compare hashes, write diffs
    Assert-ReadinessComplete
    Write-Host "Rescanning all active context entries..." -ForegroundColor Cyan

    $manifest = Read-ContextManifest
    $rescanResults = @()

    foreach ($entry in @($manifest.active)) {
        if ($entry.kind -ne "jira") { continue }
        $key = $entry.key
        $absDir = Resolve-RepoPath -p $entry.path
        $entryManifestPath = Join-Path $absDir "manifest.json"

        if (-not (Test-Path $entryManifestPath)) {
            $rescanResults += @{ key = $key; status = "skipped"; reason = "No manifest.json found" }
            continue
        }

        Write-Host "  Rescanning $key..." -ForegroundColor White
        $oldManifest = Read-JsonHashtable -path $entryManifestPath
        $oldScrapedAt = if ($oldManifest.scraped_at) { $oldManifest.scraped_at } else { $null }

        try {
            # Re-fetch with refresh forced to compare
            $doDownload = if ($DownloadAttachments) { $true } else { $true }
            $result = Build-JiraContext -Key $key -DoRefresh -DepDepthOverride $MaxDependencyDepth -TestRailProjectIdOverride $ProjectId -NoConfluence:$SkipConfluence -IncludeTestRail:$WithCoverage -DownloadAttachments:$doDownload -MaxAttachmentMB $MaxAttachmentMB -ContextScope $Scope

            $newManifestPath = Join-Path $result.context_dir "manifest.json"
            $newManifest = Read-JsonHashtable -path $newManifestPath

            # Compare hashes to detect changes
            $changes = @()
            $oldH = if ($oldManifest.hashes) { $oldManifest.hashes } else { @{} }
            $newH = if ($newManifest.hashes) { $newManifest.hashes } else { @{} }

            foreach ($field in @("issue", "comments", "linked_issues", "attachments")) {
                $oldVal = if ($oldH.$field) { "$($oldH.$field)" } else { "" }
                $newVal = if ($newH.$field) { "$($newH.$field)" } else { "" }
                if ($oldVal -ne $newVal) { $changes += $field }
            }

            $rescanResults += @{
                key = $key
                status = if ($changes.Count -gt 0) { "updated" } else { "unchanged" }
                previous_scan = $oldScrapedAt
                current_scan = $newManifest.scraped_at
                changed_sources = $changes
            }

            if ($changes.Count -gt 0) {
                Write-Host "    Changes detected in: $($changes -join ', ')" -ForegroundColor Yellow
            } else {
                Write-Host "    No changes detected" -ForegroundColor Green
            }
        } catch {
            $rescanResults += @{ key = $key; status = "error"; reason = $_.Exception.Message }
            Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    Write-Host "`nRescan complete: $($rescanResults.Count) context(s) checked." -ForegroundColor Cyan
    @{ status = "ok"; results = $rescanResults } | ConvertTo-Json -Depth 20
    exit 0
}

if ($BuildContext) {
    # Using $WithCoverage to opt-in to TestRail; attachments always downloaded by default
    $doDownload = if ($DownloadAttachments) { $true } else { $true }  # Default: always download
    $result = Build-JiraContext -Key $JiraKey -DoRefresh:$Refresh -DepDepthOverride $MaxDependencyDepth -TestRailProjectIdOverride $ProjectId -ConfluenceIdsOverride $ConfluencePageIds -NoConfluence:$SkipConfluence -IncludeTestRail:$WithCoverage -DownloadAttachments:$doDownload -MaxAttachmentMB $MaxAttachmentMB -ContextScope $Scope

    # Session: create/update session for this context build
    try {
        $sessionModule = Join-Path $repoRoot "core/modules/Aira.Session.psm1"
        Import-Module $sessionModule -Force
        $existingSession = $null
        try { $existingSession = Get-AiraSession -JiraKey $JiraKey -SessionRoot ".aira/sessions" } catch { }
        if (-not $existingSession) {
            $existingSession = New-AiraSession -JiraKey $JiraKey -SessionRoot ".aira/sessions"
        }
        $contextMdPath = if ($result.context_md_path) { $result.context_md_path } elseif ($result.context_dir) { Join-Path $result.context_dir "context.md" } else { $null }
        if ($contextMdPath -and (Test-Path $contextMdPath)) {
            $contextMdRel = $contextMdPath.Substring($repoRoot.Length + 1).Replace('\', '/')
            Update-Checkpoint -SessionId $existingSession.id -Name context -State "CONTEXT_READY" -Path $contextMdRel | Out-Null
        }
        $result["session_id"] = $existingSession.id
    } catch {
        Write-Host "Warning: Session creation failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    try {
        $telemetryModule = Join-Path $repoRoot "core/modules/Aira.Telemetry.psm1"
        if (Test-Path $telemetryModule) {
            Import-Module $telemetryModule -Force -ErrorAction SilentlyContinue | Out-Null
            if (Get-Command Write-AiraTelemetryEvent -ErrorAction SilentlyContinue) {
                Write-AiraTelemetryEvent -Action "build_context" -JiraKey $JiraKey -Outcome "ok" -Data @{ refresh = [bool]$Refresh } -RepoRoot $repoRoot | Out-Null
            }
        }
    } catch { }
    $result | ConvertTo-Json -Depth 20
    exit 0
}

if ($RunPipeline) {
    Assert-ReadinessComplete

    $envFingerprint = $null
    try { $envFingerprint = Get-EnvFingerprint } catch { $envFingerprint = @{} }

    $effectiveProject = if ($Project) { $Project } else { ($JiraKey -split "-")[0] }
    $runStamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $runRelDir = "outputs/$effectiveProject/runs/$JiraKey`_$runStamp"
    $runDir = Join-Path $repoRoot $runRelDir
    Ensure-Dir $runDir

    # Context build/refresh (writes under context/jira/<KEY>/)
    # Changed NoTestRail to IncludeTestRail to respect opt-in policy
    $pipelineDownload = if ($DownloadAttachments) { $true } else { $true }  # Default: always download
    $contextResult = Build-JiraContext -Key $JiraKey -DoRefresh:$Refresh -DepDepthOverride $MaxDependencyDepth -TestRailProjectIdOverride $ProjectId -ConfluenceIdsOverride $ConfluencePageIds -NoConfluence:$SkipConfluence -IncludeTestRail:$WithCoverage -DownloadAttachments:$pipelineDownload -MaxAttachmentMB $MaxAttachmentMB -ContextScope $Scope
    $jiraDir = $contextResult.context_dir

    # Session: create a new session for this run
    $sessionModule = Join-Path $repoRoot "core/modules/Aira.Session.psm1"
    Import-Module $sessionModule -Force
    $session = New-AiraSession -JiraKey $JiraKey -SessionRoot ".aira/sessions"

    # Update context checkpoint (path + hash)
    $contextMdRel = (Join-Path $jiraDir "context.md").Substring($repoRoot.Length + 1).Replace('\', '/')
    $contextMdAbs = Join-Path $repoRoot $contextMdRel
    if (Test-Path $contextMdAbs) {
        $session = Update-Checkpoint -SessionId $session.id -Name context -State "CONTEXT_READY" -Path $contextMdRel
    }

    # Spec: copy provided spec or render from template
    $specOutRel = "$runRelDir/spec.md"
    $specOutAbs = Join-Path $repoRoot $specOutRel
    if ($SpecPath) {
        $src = Resolve-RepoPath $SpecPath
        Copy-Item -Path $src -Destination $specOutAbs -Force
    } else {
        $configModule = Join-Path $repoRoot "core/modules/Aira.Config.psm1"
        $templatingModule = Join-Path $repoRoot "core/modules/Aira.Templating.psm1"
        Import-Module $configModule -Force
        Import-Module $templatingModule -Force

        $issuePath = Join-Path $jiraDir "sources/issue.json"
        # Fallback to legacy path for backward compat
        if (-not (Test-Path $issuePath)) { $issuePath = Join-Path $jiraDir "issue.json" }
        $issue = if (Test-Path $issuePath) { Get-Content $issuePath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }

        $title = if ($issue) { $issue.fields.summary } else { "[MISSING - NEEDS INPUT]" }
        $jiraPriority = if ($issue -and $issue.fields.priority) { $issue.fields.priority.name } else { $null }
        $priority = "Medium"
        if ($jiraPriority) {
            $p = $jiraPriority.ToLowerInvariant()
            if ($p -match "critical|blocker|highest|high") { $priority = "High" }
            elseif ($p -match "lowest|low|minor") { $priority = "Low" }
        }

        $descText = if ($issue) { Repair-Mojibake (Convert-JiraContentToText -Value $issue.fields.description) } else { "" }
        $ac = Extract-AcceptanceCriteria -DescriptionText $descText

        $acRows = @()
        if ($ac.Count -gt 0) {
            $i = 1
            foreach ($item in $ac) {
                $id = ("AC-{0:00}" -f $i)
                $acRows += ('| {0} | {1} | [MISSING] | [MISSING] | [MISSING] |' -f $id, $item)
                $i++
            }
        } else {
            $acRows += '| AC-01 | [MISSING - NEEDS INPUT] | [MISSING] | [MISSING] | [MISSING] |'
        }

        $acHeader = '| ID | Title/Scenario | Pre-conditions | Test Steps | Expected Result |'
        $acSep    = '|----|----------------|----------------|------------|-----------------|'
        $acSection = @($acHeader, $acSep) + $acRows -join "`n"

        $templatePath = Resolve-AiraResourcePath -Kind templates -Name "spec_template.md" -RepoRoot $repoRoot
        $template = if ($templatePath) { Get-Content $templatePath -Raw -Encoding UTF8 } else { "" }

        if (-not $template) {
            # Fallback to a minimal spec if template is missing
            $template = '### 1. Document Summary' + "`n" +
                '*   **Title:** {{TITLE}}' + "`n" +
                '*   **ID:** {{REQ_ID}}' + "`n" +
                '*   **Status:** {{STATUS}}' + "`n" +
                '*   **Priority:** {{PRIORITY}}' + "`n" +
                '' + "`n" +
                '### 6. Acceptance Criteria' + "`n" +
                '{{AC_SECTION}}' + "`n" +
                '' + "`n" +
                '### 8. References & Attachments' + "`n" +
                '{{REFERENCES}}'
        }

        $rendered = Render-AiraTemplate -Template $template -Data @{
            TITLE = $title
            REQ_ID = '[MISSING - NEEDS INPUT]'
            STATUS = "Draft"
            PRIORITY = $priority
            DATE = (Get-Date -Format "yyyy-MM-dd")
            AUTHOR = '[MISSING - NEEDS INPUT]'
            BUSINESS_CONTEXT = '[MISSING - NEEDS INPUT]'
            CURRENT_BEHAVIOR = '[MISSING - NEEDS INPUT]'
            TARGET_AUDIENCE = '[MISSING - NEEDS INPUT]'
            USER_STORY = 'As a [Role], I want to [Action], so that [Benefit]. [MISSING - NEEDS INPUT]'
            USER_STORY_DETAILS = '[MISSING - NEEDS INPUT]'
            UI_UX_SCOPE = '[CONDITIONAL - PENDING CLARIFICATION]'
            VISUAL_REFERENCE = '[MISSING - NEEDS INPUT]'
            API_SCOPE = 'Pending definition of endpoints and payloads. [CONDITIONAL - PENDING CLARIFICATION]'
            BACKEND_SCOPE = '[CONDITIONAL - PENDING CLARIFICATION]'
            DB_SCOPE = 'Pending schema definition. [CONDITIONAL - PENDING CLARIFICATION]'
            AC_SECTION = $acSection.Trim()
            NFRS = ""
            REFERENCES = "* Context: 'context/jira/$JiraKey/context.md'"
            JIRA_KEY = $JiraKey
        }

        Write-Text -path $specOutAbs -content $rendered.Trim()
    }

    # Optionally run validation + excel export if a design JSON is provided
    $designOutRel = $null
    $validationOutRel = "$runRelDir/validation.json"
    $validationOutAbs = Join-Path $repoRoot $validationOutRel
    $excelOutRel = "$runRelDir/testrail.xlsx"
    $excelOutAbs = Join-Path $repoRoot $excelOutRel

    $validationResult = $null
    $excelResult = $null

    if ($DesignJson) {
        $designSrc = Resolve-RepoPath $DesignJson
        $designOutRel = "$runRelDir/design.json"
        $designOutAbs = Join-Path $repoRoot $designOutRel
        Copy-Item -Path $designSrc -Destination $designOutAbs -Force

        if (-not $SkipValidation) {
            $validateScript = Join-Path $repoRoot "core/scripts/validate.ps1"
            $validationJson = & $validateScript -TestCasesJson $designOutAbs -OutputPath $validationOutAbs -PolicyRoot ".aira"
            $validationResult = $validationJson | ConvertFrom-Json
        }

        if (-not $SkipExcel) {
            try {
                $excelScript = Join-Path $repoRoot "core/scripts/excel.ps1"
                $excelJson = & $excelScript -InputJson $designOutAbs -OutputPath $excelOutAbs
                $excelResult = $excelJson | ConvertFrom-Json
            } catch {
                $excelResult = @{ status = "skipped"; error = $_.Exception.Message }
            }
        }
    } else {
        if (-not $SkipValidation) {
            Write-Json -path $validationOutAbs -obj @{ timestamp = (Get-Date).ToString("s"); overall = "Warn"; checks = @(); details = "No design.json provided; validation skipped." }
        }
    }

    # Run manifest (hashes + pointers)
    $ctxManRel = (Join-Path $jiraDir "manifest.json").Substring($repoRoot.Length + 1).Replace('\', '/')
    $manifest = @{
        jira_key = $JiraKey
        project = $effectiveProject
        run_timestamp = $runStamp
        session_id = $session.id
        env_fingerprint = $envFingerprint
        inputs = @{
            context = @{
                result = $contextResult
                context_md = $contextMdRel
                context_hash = Get-FileSha256 -path $contextMdAbs
                context_manifest = $ctxManRel
            }
        }
        outputs = @{
            summary_md = "$runRelDir/summary.md"
            report_html = "$runRelDir/report.html"
            spec_md = $specOutRel
            design_json = $designOutRel
            validation_json = if (Test-Path $validationOutAbs) { $validationOutRel } else { $null }
            excel_xlsx = if (Test-Path $excelOutAbs) { $excelOutRel } else { $null }
        }
        hashes = @{
            spec_md = Get-FileSha256 -path $specOutAbs
            design_json = if ($designOutRel) { Get-FileSha256 -path (Join-Path $repoRoot $designOutRel) } else { $null }
            validation_json = if (Test-Path $validationOutAbs) { Get-FileSha256 -path $validationOutAbs } else { $null }
            excel_xlsx = if (Test-Path $excelOutAbs) { Get-FileSha256 -path $excelOutAbs } else { $null }
        }
    }
    Write-Json -path (Join-Path $runDir "manifest.json") -obj $manifest

    # Summary.md
    $summaryLines = @()
    $summaryLines += "## AIRA Run Summary"
    $summaryLines += ""
    $summaryLines += "- Jira: **$JiraKey**"
    $summaryLines += "- Project: **$effectiveProject**"
    $summaryLines += "- Run: **$runStamp**"
    $summaryLines += "- Session: '$($session.id)'"
    $summaryLines += ""
    $summaryLines += "### Artifacts"
    $summaryLines += "- Spec: '$specOutRel'"
    if ($designOutRel) { $summaryLines += "- Design: '$designOutRel'" } else { $summaryLines += "- Design: (not provided)" }
    if (Test-Path $validationOutAbs) { $summaryLines += "- Validation: '$validationOutRel'" }
    if (Test-Path $excelOutAbs) { $summaryLines += "- Excel: '$excelOutRel'" }
    $htmlReportRel = "$runRelDir/report.html"
    $htmlReportAbs = Join-Path $runDir "report.html"
    $summaryLines += "- Context: 'context/jira/$JiraKey/context.md'"
    $summaryLines += ""
    $summaryLines += "### HTML Report"
    $summaryLines += "*(generated after all artifacts - see below)*"
    $summaryLines += ""
    if ($validationResult) {
        $summaryLines += "### Validation"
        $summaryLines += "- Overall: **$($validationResult.overall)**"
    }
    if ($excelResult -and $excelResult.status) {
        $summaryLines += "### Excel"
        $summaryLines += "- Status: **$($excelResult.status)**"
    }
    # Write summary before HTML (report path appended after generation)
    Write-Text -path (Join-Path $runDir "summary.md") -content (($summaryLines -join "`n").Trim())

    # HTML report (email_report.html template)
    try {
        $htmlTemplatePath = Resolve-AiraResourcePath -Kind templates -Name "email_report.html" -RepoRoot $repoRoot
        if ($htmlTemplatePath -and (Test-Path $htmlTemplatePath)) {
            $htmlTemplate = Get-Content $htmlTemplatePath -Raw -Encoding UTF8

            # Build validation table rows
            $valTableHtml = ""
            if ($validationResult -and $validationResult.checks) {
                $rows = @()
                foreach ($chk in @($validationResult.checks)) {
                    $badge = switch ($chk.status) { "Pass" { "pass" } "Warn" { "warn" } default { "fail" } }
                    $rows += "<tr><td>$($chk.name)</td><td><span class=`"badge $badge`">$($chk.status)</span></td><td>$($chk.message)</td></tr>"
                }
                $valTableHtml = "<table><tr><th>Check</th><th>Status</th><th>Details</th></tr>" + ($rows -join "") + "</table>"
            } else {
                $valTableHtml = "<p><em>No validation checks ran (no design.json provided).</em></p>"
            }

            $valOverall = if ($validationResult) { "$($validationResult.overall)" } else { "N/A" }
            $valBadge = switch ($valOverall) { "Pass" { "pass" } "Warn" { "warn" } "Fail" { "fail" } default { "warn" } }

            $designData = $null
            if ($DesignJson -and (Test-Path $designOutAbs)) {
                try { $designData = Get-Content $designOutAbs -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $designData = $null }
            }

            $htmlRendered = Render-AiraTemplate -Template $htmlTemplate -Data @{
                JIRA_KEY         = $JiraKey
                SUMMARY          = $title
                PROJECT_NAME     = $effectiveProject
                SESSION_ID       = $session.id
                RUN_TIMESTAMP    = $runStamp
                VALIDATION_OVERALL     = $valOverall
                VALIDATION_BADGE_CLASS = $valBadge
                VALIDATION_TABLE       = $valTableHtml
                COUNT_NEW        = if ($designData -and $designData.new_cases) { "$($designData.new_cases.Count)" } else { "0" }
                COUNT_ENHANCE    = if ($designData -and $designData.enhance_cases) { "$($designData.enhance_cases.Count)" } else { "0" }
                COUNT_PREREQ     = if ($designData -and $designData.prereq_cases) { "$($designData.prereq_cases.Count)" } else { "0" }
                SPEC_PATH        = $specOutRel
                EXCEL_PATH       = if (Test-Path $excelOutAbs) { $excelOutRel } else { "(not generated)" }
                VALIDATION_PATH  = if (Test-Path $validationOutAbs) { $validationOutRel } else { "(not generated)" }
                CONTEXT_PATH     = "context/jira/$JiraKey/context.md"
            }

            $htmlOutAbs = Join-Path $runDir "report.html"
            Write-Text -path $htmlOutAbs -content $htmlRendered

            # Append report path back into summary.md
            $summaryAppend = "`n`n- HTML Report: ``$htmlReportRel``"
            Add-Content -Path (Join-Path $runDir "summary.md") -Value $summaryAppend -Encoding UTF8
        }
    } catch {
        # Non-fatal: HTML report is optional
    }

    try {
        $telemetryModule = Join-Path $repoRoot "core/modules/Aira.Telemetry.psm1"
        if (Test-Path $telemetryModule) {
            Import-Module $telemetryModule -Force -ErrorAction SilentlyContinue | Out-Null
            if (Get-Command Write-AiraTelemetryEvent -ErrorAction SilentlyContinue) {
                Write-AiraTelemetryEvent -Action "run_pipeline" -JiraKey $JiraKey -Outcome "ok" -Data @{
                    project = $effectiveProject
                    run_rel = $runRelDir
                    has_design = [bool]$DesignJson
                    validation = if ($validationResult) { $validationResult.overall } else { $null }
                    excel_status = if ($excelResult) { $excelResult.status } else { $null }
                } -RepoRoot $repoRoot | Out-Null
            }
        }
    } catch { }

    @{ status = "ok"; run_dir = $runDir; run_rel = $runRelDir; session_id = $session.id } | ConvertTo-Json -Depth 10
    exit 0
}

Write-Host "Usage:" -ForegroundColor Cyan
Write-Host "  powershell ./core/scripts/aira.ps1 -InitWorkspace" -ForegroundColor Gray
Write-Host "  powershell ./core/scripts/aira.ps1 -Doctor [-Force]" -ForegroundColor Gray
Write-Host "  powershell ./core/scripts/aira.ps1 -BuildContext -JiraKey <KEY> [-Refresh] [-Scope Local|Shared|Auto] [-DownloadAttachments] [-MaxAttachmentMB <int>]" -ForegroundColor Gray
Write-Host "  powershell ./core/scripts/aira.ps1 -RunPipeline -JiraKey <KEY> [-Project <Name>] [-Scope Local|Shared|Auto] [-DesignJson <path>] [-SpecPath <path>] [-DownloadAttachments] [-MaxAttachmentMB <int>]" -ForegroundColor Gray
Write-Host "  powershell ./core/scripts/aira.ps1 -ListContext" -ForegroundColor Gray
Write-Host "  powershell ./core/scripts/aira.ps1 -ArchiveContext -JiraKey <KEY>" -ForegroundColor Gray
exit 1



