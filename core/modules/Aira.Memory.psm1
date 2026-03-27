Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "Aira.Common.psm1") -Force

# ── Private helper: recursively convert PSCustomObject → hashtable ──
# Works on PS 5.1+ (replaces -AsHashtable which requires PS 6+).
function ConvertTo-AiraHashtable {
    param([object]$InputObject)
    if ($null -eq $InputObject) { return @{} }
    if ($InputObject -is [hashtable]) { return $InputObject }
    $ht = @{}
    foreach ($prop in $InputObject.PSObject.Properties) {
        $val = $prop.Value
        if ($val -is [System.Management.Automation.PSCustomObject]) {
            $val = ConvertTo-AiraHashtable -InputObject $val
        } elseif ($val -is [System.Object[]]) {
            $val = @($val | ForEach-Object {
                if ($_ -is [System.Management.Automation.PSCustomObject]) {
                    ConvertTo-AiraHashtable -InputObject $_
                } else { $_ }
            })
        }
        $ht[$prop.Name] = $val
    }
    return $ht
}

function Get-AiraScalarLeafMap {
    <#
    .SYNOPSIS
        Flattens nested hashtables into dotted-path => scalar leaf values.

    .NOTES
        Arrays/complex objects are ignored by default to avoid noisy diffs.
    #>
    [CmdletBinding()]
    param(
        [hashtable]$Value,
        [string]$Prefix = "",
        [hashtable]$Out
    )

    $map = if ($Out) { $Out } else { @{} }
    if (-not $Value) { return $map }

    foreach ($k in $Value.Keys) {
        $path = if ($Prefix) { "$Prefix.$k" } else { "$k" }
        $v = $Value[$k]

        if ($null -eq $v) {
            $map[$path] = $null
            continue
        }

        if ($v -is [hashtable] -or $v -is [System.Collections.IDictionary]) {
            Get-AiraScalarLeafMap -Value $v -Prefix $path -Out $map | Out-Null
            continue
        }

        if (($v -is [array]) -or ($v -is [System.Collections.IList])) {
            # Skip arrays for scalar-only diffing/promotion
            continue
        }

        if (($v -is [string]) -or ($v -is [bool]) -or ($v -is [int]) -or ($v -is [long]) -or ($v -is [double]) -or ($v -is [decimal]) -or ($v -is [float])) {
            $map[$path] = $v
            continue
        }

        # Unknown/complex leaf; ignore
    }

    return $map
}

function Get-AiraDiffs {
    <#
    .SYNOPSIS
        Produces a list of simple diffs between Before/After hashtables.
    #>
    [CmdletBinding()]
    param(
        [hashtable]$Before,
        [hashtable]$After
    )

    if (-not $Before -and -not $After) { return @() }

    $bVal = if ($Before) { $Before } else { @{} }
    $aVal = if ($After) { $After } else { @{} }
    $beforeMap = Get-AiraScalarLeafMap -Value $bVal
    $afterMap = Get-AiraScalarLeafMap -Value $aVal

    $paths = @($beforeMap.Keys + $afterMap.Keys | Select-Object -Unique)
    $diffs = @()

    foreach ($p in $paths) {
        $bFound = $beforeMap.ContainsKey($p)
        $aFound = $afterMap.ContainsKey($p)
        $b = if ($bFound) { $beforeMap[$p] } else { $null }
        $a = if ($aFound) { $afterMap[$p] } else { $null }

        if (-not $bFound -and -not $aFound) { continue }
        if ($b -eq $a) { continue }

        $diffs += @{
            path = $p
            before = $b
            after = $a
        }
    }

    return $diffs
}

function Set-HashtableValueByDottedPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Object,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value
    )

    $parts = $Path -split '\.'
    $current = $Object

    for ($i = 0; $i -lt $parts.Length; $i++) {
        $part = $parts[$i]
        $isLeaf = ($i -eq ($parts.Length - 1))

        if ($isLeaf) {
            $current[$part] = $Value
            return
        }

        if (-not $current.ContainsKey($part) -or ($current[$part] -isnot [hashtable])) {
            $current[$part] = @{}
        }

        $current = $current[$part]
    }
}

function Add-AiraCorrection {
    <#
    .SYNOPSIS
        Append a user correction/override event to `.aira/memory/corrections.jsonl`.

    .DESCRIPTION
        Corrections represent explicit user overrides (rename a case, change priority, etc).
        This is append-only JSONL.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Kind,

        [string]$JiraKey,

        [hashtable]$Before,
        [hashtable]$After,
        [string]$Rationale,

        [string]$RepoRoot
    )

    $root = if ($RepoRoot) { $RepoRoot } else { Get-AiraRepoRoot }
    $memDir = Join-Path $root ".aira/memory"
    Ensure-Dir $memDir

    $path = Join-Path $memDir "corrections.jsonl"
    $diffs = @()
    try {
        $diffs = Get-AiraDiffs -Before $Before -After $After
    } catch {
        $diffs = @()
    }
    $evt = @{
        timestamp = (Get-Date).ToString("s")
        jira_key = $JiraKey
        kind = $Kind
        before = $Before
        after = $After
        diffs = $diffs
        rationale = $Rationale
    }

    ($evt | ConvertTo-Json -Depth 20 -Compress) + "`n" | Out-File -FilePath $path -Encoding UTF8 -Append
    return $true
}

function Get-AiraUserPreferences {
    [CmdletBinding()]
    param([string]$RepoRoot)

    $root = if ($RepoRoot) { $RepoRoot } else { Get-AiraRepoRoot }
    $path = Join-Path $root ".aira/memory/user_preferences.json"
    if (-not (Test-Path $path)) { return @{} }
    try {
        return (ConvertTo-AiraHashtable -InputObject (Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json))
    } catch {
        return @{}
    }
}

function Set-AiraUserPreferences {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Preferences,

        [string]$RepoRoot
    )

    $root = if ($RepoRoot) { $RepoRoot } else { Get-AiraRepoRoot }
    $memDir = Join-Path $root ".aira/memory"
    Ensure-Dir $memDir

    $path = Join-Path $memDir "user_preferences.json"
    $Preferences | ConvertTo-Json -Depth 50 | Out-File -FilePath $path -Encoding UTF8
    return $true
}

function Merge-HashtableWithLocks {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Base,
        [Parameter(Mandatory = $true)][hashtable]$Overlay,
        [string[]]$Locks = @()
    )

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

            if ($Locks -contains $path) { continue }

            $sourceVal = $Source[$key]

            if (Has-LockedDescendant -Path $path) {
                $targetVal = if ($Target.ContainsKey($key)) { $Target[$key] } else { $null }
                if (($targetVal -is [hashtable]) -and ($sourceVal -is [hashtable])) {
                    Merge-Into -Target $targetVal -Source $sourceVal -CurrentPath $path
                }
                continue
            }

            if ($Target.ContainsKey($key) -and ($Target[$key] -is [hashtable]) -and ($sourceVal -is [hashtable])) {
                Merge-Into -Target $Target[$key] -Source $sourceVal -CurrentPath $path
            } else {
                $Target[$key] = $sourceVal
            }
        }
    }

    # Deep copy base via JSON roundtrip
    $merged = (ConvertTo-AiraHashtable -InputObject ($Base | ConvertTo-Json -Depth 50 | ConvertFrom-Json))
    Merge-Into -Target $merged -Source $Overlay -CurrentPath ""
    return $merged
}

function Apply-AiraUserPreferences {
    <#
    .SYNOPSIS
        Applies user preferences to a policy-like hashtable while respecting locked fields.

    .DESCRIPTION
        Preferences are treated like an overlay. Locked fields are not overridden.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Policy,

        [Parameter(Mandatory = $true)]
        [hashtable]$Preferences,

        [string[]]$LockedFields
    )

    $locks = if ($LockedFields) { $LockedFields } elseif ($Policy.locked_fields) { @($Policy.locked_fields) } else { @() }
    return (Merge-HashtableWithLocks -Base $Policy -Overlay $Preferences -Locks $locks)
}

function Promote-AiraPreferencesFromCorrections {
    <#
    .SYNOPSIS
        Promotes repeated correction diffs into `.aira/memory/user_preferences.json`.

    .DESCRIPTION
        Looks at the last N correction events and, when the same dotted-path is
        repeatedly changed to the same value, writes that value into
        `user_preferences.json`. Only a safe allowlist of prefixes is promoted.
    #>
    [CmdletBinding()]
    param(
        [int]$Window = 50,
        [int]$Threshold = 3,
        [string[]]$AllowedPrefixes = @("context.", "preferences.", "testrail.defaults."),
        [switch]$DryRun,
        [string]$RepoRoot
    )

    if ($Window -lt 1) { throw "Window must be >= 1" }
    if ($Threshold -lt 2) { throw "Threshold must be >= 2" }

    $root = if ($RepoRoot) { $RepoRoot } else { Get-AiraRepoRoot }
    $path = Join-Path $root ".aira/memory/corrections.jsonl"
    if (-not (Test-Path $path)) {
        return @{
            status = "ok"
            promoted = @()
            message = "No corrections file found."
        }
    }

    $lines = Get-Content $path -ErrorAction Stop
    if (-not $lines -or $lines.Count -eq 0) {
        return @{
            status = "ok"
            promoted = @()
            message = "No corrections found."
        }
    }

    $tail = if ($lines.Count -gt $Window) { $lines[($lines.Count - $Window)..($lines.Count - 1)] } else { $lines }

    # counts[path][valueKey] = count
    $counts = @{}

    foreach ($line in $tail) {
        if (-not $line) { continue }
        $evt = $null
        try { $evt = (ConvertTo-AiraHashtable -InputObject ($line | ConvertFrom-Json)) } catch { $evt = $null }
        if (-not $evt) { continue }

        $diffs = if ($evt.diffs) { $evt.diffs } else { @() }
        if ($diffs.Count -eq 0) {
            try { $diffs = Get-AiraDiffs -Before $evt.before -After $evt.after } catch { $diffs = @() }
        }

        foreach ($d in $diffs) {
            $p = "$($d.path)"
            if (-not $p) { continue }

            $allowed = $false
            foreach ($prefix in $AllowedPrefixes) {
                if ($p -like "$prefix*") { $allowed = $true; break }
            }
            if (-not $allowed) { continue }

            $a = $d.after
            if ($null -eq $a) { continue }
            if ($a -isnot [string] -and $a -isnot [bool] -and $a -isnot [int] -and $a -isnot [long] -and $a -isnot [double] -and $a -isnot [decimal] -and $a -isnot [float]) {
                continue
            }

            $valueKey = ($a | ConvertTo-Json -Compress)
            if (-not $counts.ContainsKey($p)) { $counts[$p] = @{} }
            if (-not $counts[$p].ContainsKey($valueKey)) { $counts[$p][$valueKey] = 0 }
            $counts[$p][$valueKey] = [int]$counts[$p][$valueKey] + 1
        }
    }

    $prefs = Get-AiraUserPreferences -RepoRoot $root
    if (-not $prefs) { $prefs = @{} }

    $promoted = @()
    foreach ($p in $counts.Keys) {
        $valueTable = $counts[$p]
        if (-not $valueTable) { continue }

        $top = $valueTable.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1
        if (-not $top) { continue }
        if ([int]$top.Value -lt $Threshold) { continue }

        $val = $null
        try { $val = ($top.Key | ConvertFrom-Json) } catch { $val = $null }
        if ($null -eq $val) { continue }

        $promoted += @{
            path = $p
            value = $val
            count = [int]$top.Value
        }

        if (-not $DryRun) {
            Set-HashtableValueByDottedPath -Object $prefs -Path $p -Value $val
        }
    }

    if (-not $DryRun -and $promoted.Count -gt 0) {
        Set-AiraUserPreferences -Preferences $prefs -RepoRoot $root | Out-Null
    }

    return @{
        status = "ok"
        dry_run = [bool]$DryRun
        promoted = $promoted
        window = $Window
        threshold = $Threshold
        allowed_prefixes = $AllowedPrefixes
    }
}

function Find-AiraSimilarCorrections {
    <#
    .SYNOPSIS
        Searches existing corrections for entries similar to a new correction by kind and dotted-path overlap.

    .DESCRIPTION
        Returns matching correction events from corrections.jsonl where the `kind`
        matches and at least one diff path overlaps with the new Before/After diffs.
        This allows the AI agent to detect when a user is making corrections in the
        same area and decide whether to enhance existing preferences.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Kind,

        [hashtable]$Before,
        [hashtable]$After,

        [int]$Window = 100,

        [string]$RepoRoot
    )

    $root = if ($RepoRoot) { $RepoRoot } else { Get-AiraRepoRoot }
    $path = Join-Path $root ".aira/memory/corrections.jsonl"
    if (-not (Test-Path $path)) { return @() }

    $lines = Get-Content $path -ErrorAction Stop
    if (-not $lines -or $lines.Count -eq 0) { return @() }

    # Compute diff paths for the new correction
    $newDiffs = @()
    try { $newDiffs = Get-AiraDiffs -Before $Before -After $After } catch { $newDiffs = @() }
    $newPaths = @($newDiffs | ForEach-Object { $_.path })
    if ($newPaths.Count -eq 0) { return @() }

    $tail = if ($lines.Count -gt $Window) { $lines[($lines.Count - $Window)..($lines.Count - 1)] } else { $lines }

    $matches = @()
    foreach ($line in $tail) {
        if (-not $line) { continue }
        $evt = $null
        try { $evt = (ConvertTo-AiraHashtable -InputObject ($line | ConvertFrom-Json)) } catch { continue }
        if (-not $evt -or $evt.kind -ne $Kind) { continue }

        $evtDiffs = if ($evt.diffs) { $evt.diffs } else { @() }
        if ($evtDiffs.Count -eq 0) {
            try { $evtDiffs = Get-AiraDiffs -Before $evt.before -After $evt.after } catch { $evtDiffs = @() }
        }

        $evtPaths = @($evtDiffs | ForEach-Object { $_.path })
        $overlap = @($newPaths | Where-Object { $evtPaths -contains $_ })
        if ($overlap.Count -gt 0) {
            $matches += @{
                event          = $evt
                overlap_paths  = $overlap
            }
        }
    }

    return $matches
}

function Add-AiraCorrectionWithEnhance {
    <#
    .SYNOPSIS
        Logs a correction AND auto-promotes to preferences when a pattern is detected.

    .DESCRIPTION
        Combines Add-AiraCorrection with an immediate check for repeated similar
        corrections. If the same kind+path combination has been corrected >=Threshold
        times to the same value, it is auto-promoted to user_preferences.json without
        waiting for a manual Promote-AiraPreferencesFromCorrections call.

        This ensures the AI agent can call a single function that both records the
        correction and enhances preferences in one step.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Kind,

        [string]$JiraKey,

        [hashtable]$Before,
        [hashtable]$After,
        [string]$Rationale,

        [int]$AutoPromoteThreshold = 3,
        [int]$Window = 50,

        [string]$RepoRoot
    )

    $root = if ($RepoRoot) { $RepoRoot } else { Get-AiraRepoRoot }

    # 1. Log the correction
    Add-AiraCorrection -Kind $Kind -JiraKey $JiraKey -Before $Before -After $After -Rationale $Rationale -RepoRoot $root | Out-Null

    # 2. Immediately run promotion check
    $result = Promote-AiraPreferencesFromCorrections -RepoRoot $root -Window $Window -Threshold $AutoPromoteThreshold
    $promoted = if ($result.promoted) { $result.promoted } else { @() }

    return @{
        correction_logged = $true
        auto_promoted     = $promoted
    }
}

function Add-AiraUserNote {
    <#
    .SYNOPSIS
        Append user-provided knowledge to `.aira/memory/notes.jsonl`.

    .DESCRIPTION
        Users can explicitly ask AIRA to remember definitions, structural
        preferences, requirement summaries, naming conventions, or any free-form
        knowledge. Each note has a category, topic, and content body.

        Categories help organise retrieval:
          - "preference"   — explicit user preference (e.g., "always use BDD format")
          - "definition"   — domain term or acronym definition
          - "structure"    — output structure / template preference
          - "requirement"  — summary requirement or acceptance criteria pattern
          - "convention"   — naming / formatting convention
          - "general"      — anything else

        Notes are append-only JSONL.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("preference", "definition", "structure", "requirement", "convention", "general")]
        [string]$Category,

        [Parameter(Mandatory = $true)]
        [string]$Topic,

        [Parameter(Mandatory = $true)]
        [string]$Content,

        [string]$JiraKey,
        [string[]]$Tags = @(),

        [string]$RepoRoot
    )

    $root = if ($RepoRoot) { $RepoRoot } else { Get-AiraRepoRoot }
    $memDir = Join-Path $root ".aira/memory"
    Ensure-Dir $memDir

    $path = Join-Path $memDir "notes.jsonl"
    $evt = @{
        timestamp = (Get-Date).ToString("s")
        category  = $Category
        topic     = $Topic
        content   = $Content
        jira_key  = $JiraKey
        tags      = $Tags
    }

    ($evt | ConvertTo-Json -Depth 20 -Compress) + "`n" | Out-File -FilePath $path -Encoding UTF8 -Append
    return $evt
}

function Get-AiraUserNotes {
    <#
    .SYNOPSIS
        Retrieves stored user notes from `.aira/memory/notes.jsonl`.

    .DESCRIPTION
        Returns all notes, optionally filtered by Category and/or Topic substring.
    #>
    [CmdletBinding()]
    param(
        [string]$Category,
        [string]$TopicFilter,
        [int]$Last = 0,
        [string]$RepoRoot
    )

    $root = if ($RepoRoot) { $RepoRoot } else { Get-AiraRepoRoot }
    $path = Join-Path $root ".aira/memory/notes.jsonl"
    if (-not (Test-Path $path)) { return @() }

    $lines = Get-Content $path -ErrorAction Stop
    if (-not $lines -or $lines.Count -eq 0) { return @() }

    $notes = @()
    foreach ($line in $lines) {
        if (-not $line) { continue }
        $note = $null
        try { $note = (ConvertTo-AiraHashtable -InputObject ($line | ConvertFrom-Json)) } catch { continue }
        if (-not $note) { continue }

        if ($Category -and $note.category -ne $Category) { continue }
        if ($TopicFilter -and $note.topic -notlike "*$TopicFilter*") { continue }

        $notes += $note
    }

    if ($Last -gt 0 -and $notes.Count -gt $Last) {
        $notes = $notes[($notes.Count - $Last)..($notes.Count - 1)]
    }

    return $notes
}

function Add-AiraDirectPreference {
    <#
    .SYNOPSIS
        Immediately writes an explicit user preference to user_preferences.json.

    .DESCRIPTION
        Unlike the correction→promote flow (which waits for repeated patterns),
        this function is for when the user explicitly says "remember that I prefer X"
        or "add to my preferences". It merges the new preference into the existing
        user_preferences.json without requiring a threshold of corrections.

        Also logs a correction event for audit trail.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Preference,

        [string]$Rationale,
        [string]$JiraKey,
        [string]$RepoRoot
    )

    $root = if ($RepoRoot) { $RepoRoot } else { Get-AiraRepoRoot }

    # 1. Load existing preferences and merge
    $existing = Get-AiraUserPreferences -RepoRoot $root
    if (-not $existing) { $existing = @{} }
    $merged = Merge-HashtableWithLocks -Base $existing -Overlay $Preference -Locks @()
    Set-AiraUserPreferences -Preferences $merged -RepoRoot $root | Out-Null

    # 2. Log a correction for audit trail
    Add-AiraCorrection -Kind "explicit_preference" -JiraKey $JiraKey -Before $existing -After $merged -Rationale $Rationale -RepoRoot $root | Out-Null

    return @{
        status   = "ok"
        merged   = $true
        rationale = $Rationale
    }
}

Export-ModuleMember -Function Get-AiraScalarLeafMap, Get-AiraDiffs, Set-HashtableValueByDottedPath, Add-AiraCorrection, Add-AiraCorrectionWithEnhance, Find-AiraSimilarCorrections, Get-AiraUserPreferences, Set-AiraUserPreferences, Apply-AiraUserPreferences, Promote-AiraPreferencesFromCorrections, Add-AiraUserNote, Get-AiraUserNotes, Add-AiraDirectPreference

