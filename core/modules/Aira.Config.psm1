Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "Aira.Common.psm1") -Force -WarningAction SilentlyContinue

function ConvertTo-Hashtable {
    param($InputObject)
    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [PSCustomObject]) {
        $h = @{}
        foreach ($p in $InputObject.PSObject.Properties) {
            $h[$p.Name] = ConvertTo-Hashtable -InputObject $p.Value
        }
        return $h
    }
    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string] -and $InputObject -isnot [hashtable]) {
        $arr = @()
        foreach ($item in $InputObject) {
            $arr += ConvertTo-Hashtable -InputObject $item
        }
        return , $arr
    }
    return $InputObject
}

function Read-EnvFile {
    [CmdletBinding()]
    param([string]$Path = ".env")

    $repoRoot = Get-AiraRepoRoot
    $resolvedPath = Resolve-AiraPath -RepoRoot $repoRoot -Path $Path

    $vars = @{}
    if (-not (Test-Path $resolvedPath)) { return $vars }

    foreach ($line in (Get-Content $resolvedPath -ErrorAction Stop)) {
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

function Get-AiraCredentials {
    [CmdletBinding()]
    param(
        [string]$RepoRoot = ".",
        [string]$EnvPath
    )

    $effectiveRepoRoot = if ([System.IO.Path]::IsPathRooted($RepoRoot)) {
        $RepoRoot
    } else {
        $resolved = Resolve-AiraPath -RepoRoot (Get-AiraRepoRoot) -Path $RepoRoot
        (Resolve-Path $resolved).Path
    }

    $envFile = if ($EnvPath) { $EnvPath } else { Join-Path $effectiveRepoRoot ".env" }
    $envVars = Read-EnvFile -Path $envFile

    function Resolve-EnvValue {
        param([string]$Key)
        if ($envVars.ContainsKey($Key) -and $envVars[$Key]) { return $envVars[$Key] }
        $item = Get-Item "Env:$Key" -ErrorAction SilentlyContinue
        if ($item) { return $item.Value }
        return $null
    }

    function Resolve-EnvValueAny {
        param([string[]]$Keys)
        foreach ($k in $Keys) {
            $v = Resolve-EnvValue -Key $k
            if ($v) { return $v }
        }
        return $null
    }

    return @{
        jira = @{
            url = (Resolve-EnvValueAny @("JIRA_URL"))
            email = (Resolve-EnvValueAny @("JIRA_EMAIL", "JIRA_USERNAME"))
            api_token = (Resolve-EnvValueAny @("JIRA_API_TOKEN"))
        }
        confluence = @{
            url = (Resolve-EnvValueAny @("CONFLUENCE_URL"))
            email = (Resolve-EnvValueAny @("CONFLUENCE_EMAIL", "CONFLUENCE_USERNAME"))
            api_token = (Resolve-EnvValueAny @("CONFLUENCE_API_TOKEN"))
        }
        testrail = @{
            url = (Resolve-EnvValueAny @("TESTRAIL_URL"))
            username = (Resolve-EnvValueAny @("TESTRAIL_USERNAME"))
            api_key = (Resolve-EnvValueAny @("TESTRAIL_API_KEY"))
        }
        github = @{
            base_url = (Resolve-EnvValueAny @("GITHUB_BASE_URL"))
            token = (Resolve-EnvValueAny @("GITHUB_TOKEN"))
            owner = (Resolve-EnvValueAny @("GITHUB_OWNER"))
            repo = (Resolve-EnvValueAny @("GITHUB_REPO"))
        }
        bitbucket = @{
            base_url = (Resolve-EnvValueAny @("BITBUCKET_BASE_URL"))
            username = (Resolve-EnvValueAny @("BITBUCKET_USERNAME"))
            app_password = (Resolve-EnvValueAny @("BITBUCKET_APP_PASSWORD"))
            workspace = (Resolve-EnvValueAny @("BITBUCKET_WORKSPACE"))
            repo = (Resolve-EnvValueAny @("BITBUCKET_REPO"))
        }
    }
}

function Get-ValueByDottedPath {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Object,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $parts = $Path -split '\.'
    $current = $Object

    foreach ($part in $parts) {
        if ($null -eq $current) { return @{ Found = $false; Value = $null } }

        if ($current -is [hashtable]) {
            if (-not $current.ContainsKey($part)) { return @{ Found = $false; Value = $null } }
            $current = $current[$part]
            continue
        }

        if ($current -is [System.Collections.IDictionary]) {
            if (-not $current.Contains($part)) { return @{ Found = $false; Value = $null } }
            $current = $current[$part]
            continue
        }

        # Not navigable
        return @{ Found = $false; Value = $null }
    }

    return @{ Found = $true; Value = $current }
}

function Copy-JsonHashtable {
    param([hashtable]$Value)
    # Deep copy by round-tripping through JSON (safe for JSON-derived hashtables).
    return ($Value | ConvertTo-Json -Depth 50 | ConvertFrom-Json | ForEach-Object { ConvertTo-Hashtable $_ })
}

function Merge-Policies {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Admin,
        [Parameter(Mandatory = $true)][hashtable]$Team,
        [string[]]$Locks = @()
    )

    $merged = Copy-JsonHashtable -Value $Admin

    function Has-LockedDescendant {
        param([string]$Path)
        foreach ($l in $Locks) {
            if ($l -like "$Path.*") { return $true }
        }
        return $false
    }

    function Merge-Into {
        param(
            [hashtable]$Target,
            [hashtable]$Source,
            [string]$CurrentPath
        )

        foreach ($key in $Source.Keys) {
            $path = if ($CurrentPath) { "$CurrentPath.$key" } else { "$key" }

            # If exact path is locked, do not override
            if ($Locks -contains $path) { continue }

            $sourceVal = $Source[$key]

            # Prevent overwriting a subtree that contains locked descendants
            if (Has-LockedDescendant -Path $path) {
                $targetVal = if ($Target.ContainsKey($key)) { $Target[$key] } else { $null }

                if (($targetVal -is [hashtable]) -and ($sourceVal -is [hashtable])) {
                    Merge-Into -Target $targetVal -Source $sourceVal -CurrentPath $path
                }

                # Otherwise ignore (would wipe locked fields)
                continue
            }

            if ($Target.ContainsKey($key) -and ($Target[$key] -is [hashtable]) -and ($sourceVal -is [hashtable])) {
                Merge-Into -Target $Target[$key] -Source $sourceVal -CurrentPath $path
            } else {
                $Target[$key] = $sourceVal
            }
        }
    }

    Merge-Into -Target $merged -Source $Team -CurrentPath ""
    return $merged
}

function Test-PolicySchema {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Policy,
        [Parameter(Mandatory = $true)][hashtable]$Schema
    )

    $errors = New-Object System.Collections.Generic.List[string]

    $required = if ($null -ne $Schema.required) { @($Schema.required) } else { @() }
    foreach ($req in $required) {
        $r = Get-ValueByDottedPath -Object $Policy -Path $req
        if (-not $r.Found) {
            $errors.Add("Missing required policy field: $req") | Out-Null
        }
    }

    $types = if ($null -ne $Schema.types) { $Schema.types } else { @{} }
    foreach ($path in $types.Keys) {
        $expected = $types[$path]
        $r = Get-ValueByDottedPath -Object $Policy -Path $path
        if (-not $r.Found) { continue }

        $value = $r.Value

        function Is-Number($v) {
            return ($v -is [int]) -or ($v -is [long]) -or ($v -is [double]) -or ($v -is [decimal]) -or ($v -is [float])
        }

        function Is-ArrayOfString($v) {
            if (($v -is [array]) -or ($v -is [System.Collections.IList])) {
                foreach ($item in @($v)) {
                    if ($null -eq $item) { return $false }
                    if ($item -isnot [string]) { return $false }
                }
                return $true
            }
            return $false
        }

        $ok = $true
        switch ($expected) {
            "string" { $ok = ($value -is [string]) }
            "number" { $ok = (Is-Number $value) }
            "boolean" { $ok = ($value -is [bool]) }
            "object" { $ok = ($value -is [hashtable]) -or ($value -is [System.Collections.IDictionary]) }
            "array[string]" { $ok = (Is-ArrayOfString $value) }
            default { $ok = $true } # unknown schema type → do not block
        }

        if (-not $ok) {
            $actual = if ($null -eq $value) { "null" } else { $value.GetType().FullName }
            $errors.Add("Invalid type for '$path'. Expected '$expected', got '$actual'.") | Out-Null
        }
    }

    if ($errors.Count -gt 0) {
        throw ("Policy schema validation failed:`n- " + ($errors -join "`n- "))
    }
}

function Get-AiraPolicy {
    [CmdletBinding()]
    param(
        [string]$PolicyRoot = ".aira",
        [string]$TeamName
    )

    $repoRoot = Get-AiraRepoRoot
    $policyRootPath = Resolve-AiraPath -RepoRoot $repoRoot -Path $PolicyRoot

    $schemaPath = Join-Path $policyRootPath "schema.policy.json"
    $adminPath = Join-Path $policyRootPath "admin.policy.json"
    $teamPath = Join-Path $policyRootPath "team.policy.json"

    if (-not (Test-Path $schemaPath)) { throw "Missing policy schema: $schemaPath" }
    if (-not (Test-Path $adminPath)) { throw "Missing admin policy: $adminPath" }
    if (-not (Test-Path $teamPath)) { throw "Missing team policy: $teamPath" }

    $schema = (Get-Content $schemaPath -Raw -Encoding UTF8) | ConvertFrom-Json | ForEach-Object { ConvertTo-Hashtable $_ }
    $admin = (Get-Content $adminPath -Raw -Encoding UTF8) | ConvertFrom-Json | ForEach-Object { ConvertTo-Hashtable $_ }
    $team = (Get-Content $teamPath -Raw -Encoding UTF8) | ConvertFrom-Json | ForEach-Object { ConvertTo-Hashtable $_ }

    # Merge with lock protection: admin + generic team.policy.json
    $locks = if ($null -ne $admin.locked_fields) { @($admin.locked_fields) } else { @() }
    $merged = Merge-Policies -Admin $admin -Team $team -Locks $locks

    # Discover and layer additional team policies from .aira/teams/*.policy.json
    $teamsDir = Join-Path $policyRootPath "teams"
    if (Test-Path $teamsDir) {
        $teamFiles = Get-ChildItem -Path $teamsDir -Filter "*.policy.json" -File -ErrorAction SilentlyContinue
        foreach ($tf in $teamFiles) {
            $extra = (Get-Content $tf.FullName -Raw -Encoding UTF8) | ConvertFrom-Json | ForEach-Object { ConvertTo-Hashtable $_ }
            # If a specific TeamName was requested, only apply that team's overlay
            if ($TeamName) {
                $extraName = if ($extra.team_name) { $extra.team_name } else { $tf.BaseName -replace '\.policy$', '' }
                if ($extraName -ne $TeamName) { continue }
            }
            $merged = Merge-Policies -Admin $merged -Team $extra -Locks $locks
        }
    }

    # Validate against schema
    Test-PolicySchema -Policy $merged -Schema $schema

    return $merged
}

function Get-AiraEffectivePolicy {
    <#
    .SYNOPSIS
        Returns effective policy = policy merge + user preferences overlay.

    .DESCRIPTION
        Loads admin/team policy (with lock enforcement), validates it against schema,
        then applies `.aira/memory/user_preferences.json` as an overlay while still
        respecting locked fields.
    #>
    [CmdletBinding()]
    param(
        [string]$PolicyRoot = ".aira",
        [string]$RepoRoot = (Get-AiraRepoRoot)
    )

    $policy = Get-AiraPolicy -PolicyRoot $PolicyRoot

    $memoryModule = Join-Path $RepoRoot "core/modules/Aira.Memory.psm1"
    if (-not (Test-Path $memoryModule)) { return $policy }

    try {
        Import-Module $memoryModule -Force -ErrorAction Stop | Out-Null
    } catch {
        return $policy
    }

    if (-not (Get-Command Get-AiraUserPreferences -ErrorAction SilentlyContinue)) { return $policy }
    if (-not (Get-Command Apply-AiraUserPreferences -ErrorAction SilentlyContinue)) { return $policy }

    $prefs = Get-AiraUserPreferences -RepoRoot $RepoRoot
    if (-not $prefs -or $prefs.Count -eq 0) { return $policy }

    $locks = if ($null -ne $policy.locked_fields) { @($policy.locked_fields) } else { @() }
    $effective = $null
    try {
        $effective = Apply-AiraUserPreferences -Policy $policy -Preferences $prefs -LockedFields $locks

        # Re-validate after overlay (skip preferences on validation failure).
        $policyRootPath = Resolve-AiraPath -RepoRoot $RepoRoot -Path $PolicyRoot
        $schemaPath = Join-Path $policyRootPath "schema.policy.json"
        if (Test-Path $schemaPath) {
            $schema = (Get-Content $schemaPath -Raw -Encoding UTF8) | ConvertFrom-Json -AsHashtable
            Test-PolicySchema -Policy $effective -Schema $schema
        }
        return $effective
    } catch {
        Write-Warning "User preferences were ignored due to invalid policy overlay: $($_.Exception.Message)"
        return $policy
    }
}

function Resolve-AiraResourcePath {
    <#
    .SYNOPSIS
        Resolves a resource path using override precedence.

    .DESCRIPTION
        For prompts/templates/rules, resolve in this order:
        1) overrides/ (highest)
        2) enabled plugins/
        3) core/ (baseline)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("prompts", "templates", "rules")]
        [string]$Kind,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [string]$RepoRoot = (Get-AiraRepoRoot)
    )

    $overridesCandidate = Join-Path $RepoRoot (Join-Path "overrides/$Kind" $Name)
    if (Test-Path $overridesCandidate) { return $overridesCandidate }

    $pluginsRoot = Join-Path $RepoRoot "plugins"
    if (Test-Path $pluginsRoot) {
        $pluginDirs = Get-ChildItem -Path $pluginsRoot -Directory -ErrorAction SilentlyContinue

        $plugins = @()
        foreach ($d in $pluginDirs) {
            $manifestPath = Join-Path $d.FullName "manifest.json"
            $enabled = $true
            $loadOrder = 1000
            if (Test-Path $manifestPath) {
                try {
                    $m = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
                    if ($m.PSObject.Properties.Name -contains "enabled") {
                        $enabled = [bool]$m.enabled
                    }
                    if ($m.PSObject.Properties.Name -contains "load_order") {
                        $loadOrder = [int]$m.load_order
                    }
                } catch {
                    # Invalid manifest should not crash resolution; treat as enabled with default order.
                    $enabled = $true
                    $loadOrder = 1000
                }
            }
            $plugins += [PSCustomObject]@{
                Path = $d.FullName
                Name = $d.Name
                Enabled = $enabled
                LoadOrder = $loadOrder
            }
        }

        foreach ($p in ($plugins | Where-Object { $_.Enabled } | Sort-Object LoadOrder, Name)) {
            $candidate = Join-Path $p.Path (Join-Path $Kind $Name)
            if (Test-Path $candidate) { return $candidate }
        }
    }

    $coreCandidate = Join-Path $RepoRoot (Join-Path "core/$Kind" $Name)
    if (Test-Path $coreCandidate) { return $coreCandidate }

    return $null
}

Export-ModuleMember -Function Get-AiraPolicy, Get-AiraEffectivePolicy, Read-EnvFile, Get-AiraCredentials, Resolve-AiraResourcePath

