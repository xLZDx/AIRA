Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "Aira.Common.psm1") -Force

function Get-ContentHashSha256 {
    param([Parameter(Mandatory = $true)][string]$Content)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Content)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hashBytes = $sha.ComputeHash($bytes)
        return ([BitConverter]::ToString($hashBytes) -replace '-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Load-AiraSessionFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path $Path)) { throw "Session file not found: $Path" }
    $obj = Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    return (Convert-PSObjectToHashtable $obj)
}

function Save-AiraSessionFile {
    param(
        [Parameter(Mandatory = $true)]$Session,
        [Parameter(Mandatory = $true)][string]$Path
    )
    $Session.updated_at = (Get-Date).ToString("s")
    $Session | ConvertTo-Json -Depth 50 | Out-File -FilePath $Path -Encoding UTF8
}

function New-AiraSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$JiraKey,
        [string]$SessionRoot = ".aira/sessions"
    )

    $repoRoot = Get-AiraRepoRoot
    $sessionRootPath = Resolve-AiraPath -RepoRoot $repoRoot -Path $SessionRoot
    Ensure-Dir -Path $sessionRootPath

    $id = "session_$(Get-Date -Format 'yyyyMMdd_HHmmss')_$($JiraKey -replace '-','')"

    $session = @{
        id = $id
        jira_key = $JiraKey
        created_at = (Get-Date).ToString("s")
        updated_at = (Get-Date).ToString("s")
        state = "INITIALIZING"
        checkpoints = @{
            context = $null
            analysis = $null
            design = $null
            validation = $null
        }
        metadata = @{}
    }

    $path = Join-Path $sessionRootPath "$id.json"
    $session | ConvertTo-Json -Depth 50 | Out-File $path -Encoding UTF8

    return $session
}

function Get-AiraSession {
    [CmdletBinding(DefaultParameterSetName = "ById")]
    param(
        [Parameter(ParameterSetName = "ById", Mandatory = $true)]
        [string]$SessionId,

        [Parameter(ParameterSetName = "ByPath", Mandatory = $true)]
        [string]$Path,

        [Parameter(ParameterSetName = "ByJiraKey", Mandatory = $true)]
        [string]$JiraKey,

        [string]$SessionRoot = ".aira/sessions"
    )

    $repoRoot = Get-AiraRepoRoot
    $sessionRootPath = Resolve-AiraPath -RepoRoot $repoRoot -Path $SessionRoot

    if ($PSCmdlet.ParameterSetName -eq "ByPath") {
        $resolved = Resolve-AiraPath -RepoRoot $repoRoot -Path $Path
        return (Load-AiraSessionFile -Path $resolved)
    }

    if ($PSCmdlet.ParameterSetName -eq "ByJiraKey") {
        if (-not (Test-Path $sessionRootPath)) { throw "Session root not found: $sessionRootPath" }
        $candidates = Get-ChildItem -Path $sessionRootPath -Filter "*.json" -File -ErrorAction SilentlyContinue
        $matches = @()
        foreach ($f in $candidates) {
            try {
                $s = Load-AiraSessionFile -Path $f.FullName
                $key = if ($s.jira_key) { $s.jira_key } else { "" }
                if ($key -eq $JiraKey) {
                    $matches += @{ file = $f; session = $s }
                }
            } catch {
                continue
            }
        }
        if ($matches.Count -eq 0) { throw "No session found for Jira key: $JiraKey" }
        $latest = $matches | Sort-Object { $_.file.LastWriteTime } -Descending | Select-Object -First 1
        return $latest.session
    }

    $path = Join-Path $sessionRootPath "$SessionId.json"
    return (Load-AiraSessionFile -Path $path)
}

function Get-AiraCheckpoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Session,
        [Parameter(Mandatory = $true)]
        [ValidateSet("context", "analysis", "design", "validation")]
        [string]$Name
    )

    if (-not $Session.ContainsKey("checkpoints")) { return $null }
    $cp = $Session["checkpoints"]
    if ($cp -is [hashtable]) { return $cp[$Name] }
    return $null
}

function Update-Checkpoint {
    [CmdletBinding(DefaultParameterSetName = "ById")]
    param(
        [Parameter(ParameterSetName = "ById", Mandatory = $true)]
        [string]$SessionId,

        [Parameter(ParameterSetName = "ByPath", Mandatory = $true)]
        [string]$SessionPath,

        [Parameter(ParameterSetName = "ByObject", Mandatory = $true)]
        [hashtable]$Session,

        [Parameter(Mandatory = $true)]
        [ValidateSet("context", "analysis", "design", "validation")]
        [string]$Name,

        [string]$State,

        # Optional: artifact path to hash + store
        [string]$Path,

        # Optional: inline checkpoint data (object/hashtable)
        [object]$Data,

        [string]$SessionRoot = ".aira/sessions"
    )

    $repoRoot = Get-AiraRepoRoot
    $sessionRootPath = Resolve-AiraPath -RepoRoot $repoRoot -Path $SessionRoot

    $effectiveSession = $null
    $effectiveSessionPath = $null

    switch ($PSCmdlet.ParameterSetName) {
        "ById" {
            $effectiveSessionPath = Join-Path $sessionRootPath "$SessionId.json"
            $effectiveSession = Load-AiraSessionFile -Path $effectiveSessionPath
            break
        }
        "ByPath" {
            $effectiveSessionPath = Resolve-AiraPath -RepoRoot $repoRoot -Path $SessionPath
            $effectiveSession = Load-AiraSessionFile -Path $effectiveSessionPath
            break
        }
        "ByObject" {
            $effectiveSession = $Session
            $effectiveSessionPath = Join-Path $sessionRootPath "$($Session.id).json"
            break
        }
    }

    if (-not $effectiveSession.ContainsKey("checkpoints") -or -not ($effectiveSession.checkpoints -is [hashtable])) {
        $effectiveSession["checkpoints"] = @{
            context = $null
            analysis = $null
            design = $null
            validation = $null
        }
    }

    $checkpoint = @{
        timestamp = (Get-Date).ToString("s")
    }

    if ($Path) {
        $resolvedArtifactPath = Resolve-AiraPath -RepoRoot $repoRoot -Path $Path
        if (Test-Path $resolvedArtifactPath) {
            $checkpoint.hash = (Get-FileHash -Path $resolvedArtifactPath -Algorithm SHA256).Hash.ToLowerInvariant()
        } else {
            $checkpoint.hash = $null
        }
        $checkpoint.path = $Path
    }

    if ($null -ne $Data) {
        $json = ($Data | ConvertTo-Json -Depth 50)
        if (-not $checkpoint.hash) {
            $checkpoint.hash = (Get-ContentHashSha256 -Content $json)
        }
        $checkpoint.data = $Data
    }

    $effectiveSession.checkpoints[$Name] = $checkpoint
    if ($State) { $effectiveSession.state = $State }

    Ensure-Dir -Path $sessionRootPath
    Save-AiraSessionFile -Session $effectiveSession -Path $effectiveSessionPath

    return $effectiveSession
}

Export-ModuleMember -Function New-AiraSession, Get-AiraSession, Get-AiraCheckpoint, Update-Checkpoint

