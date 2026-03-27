Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "Aira.Common.psm1") -Force

# NOTE: Aira.Config (Get-AiraPolicy) is NOT imported here to avoid clobbering
# the caller's scope in PowerShell 5.1.  The calling script MUST import
# Aira.Config AFTER importing Aira.Validation.  The $Policy default-parameter
# expression (Get-AiraPolicy) relies on the function being visible in the
# caller's session.
$repoRoot = Get-AiraRepoRoot

function Invoke-AiraValidation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$TestCases,

        [object]$Policy = (Get-AiraPolicy)
    )

    $results = @{
        timestamp = (Get-Date).ToString("s")
        overall = "Pass"
        checks = @()
    }

    $val = if ($Policy.validation.enabled_checks) { $Policy.validation.enabled_checks } else { @() }
    $enabledChecks = @($val)

    $checkFiles = Get-ChildItem -Path @(
        (Join-Path $repoRoot "core/validation/checks"),
        (Join-Path $repoRoot "plugins/*/validation/checks")
    ) -Filter "*.ps1" -File -ErrorAction SilentlyContinue

    foreach ($checkFile in $checkFiles) {
        $checkName = $checkFile.BaseName

        if ($enabledChecks -notcontains $checkName) { continue }

        try {
            $checkResult = & $checkFile.FullName -TestCases $TestCases -Policy $Policy

            # Normalize
            if ($checkResult -isnot [hashtable]) {
                $checkResult = @{
                    name = $checkName
                    status = "Pass"
                    details = $checkResult
                }
            } else {
                if (-not $checkResult.ContainsKey("name")) { $checkResult.name = $checkName }
                if (-not $checkResult.ContainsKey("status")) { $checkResult.status = "Pass" }
            }

            $results.checks += $checkResult

            if ($checkResult.status -eq "Fail") {
                $results.overall = "Fail"
            } elseif ($checkResult.status -eq "Warn" -and $results.overall -ne "Fail") {
                $results.overall = "Warn"
            }
        } catch {
            $results.checks += @{
                name = $checkName
                status = "Fail"
                details = @{
                    error = $_.Exception.Message
                }
            }
            $results.overall = "Fail"
        }
    }

    return $results
}

function Invoke-AiraPackageSafetyAudit {
    <#
    .SYNOPSIS
        Audits plugins, modules, and scripts for unsafe patterns before they run.

    .DESCRIPTION
        Scans the workspace for package-level safety concerns:
        1. Plugin manifest validation - structure, unknown fields, missing signatures
        2. Script content scanning - destructive commands, credential harvesting,
           data exfiltration, obfuscated/encoded payloads, network calls
        3. Module integrity - verifies modules follow AIRA conventions
        4. Dependency hygiene - flags unverified or suspicious Install-Module calls

        Each finding is classified by severity:
          Critical - obfuscated payloads, credential harvesting, data exfiltration
          High     - destructive OS/DB commands, unverified remote downloads
          Medium   - missing manifest fields, unsigned scripts, suspicious patterns
          Low      - style/convention warnings

        Returns a result object with overall status (Pass/Warn/Fail) and findings.

    .PARAMETER RepoRoot
        Root of the AIRA repository. Defaults to Get-AiraRepoRoot.

    .PARAMETER ScanPaths
        Additional paths to scan (beyond the default plugins/ and core/ dirs).
    #>
    [CmdletBinding()]
    param(
        [string]$RepoRoot = (Get-AiraRepoRoot),

        [string[]]$ScanPaths = @()
    )

    $findings = New-Object System.Collections.Generic.List[object]

    # ── Manifest schema expectations ──
    $requiredManifestFields = @("name", "version", "description", "enabled")
    $knownManifestFields    = @("name", "version", "description", "enabled", "load_order",
                                 "entry_script", "capabilities", "author", "license", "homepage")

    # ── Dangerous content patterns ──
    $scriptPatterns = @(
        # Destructive OS commands
        @{ id = "PKG_DESTRUCT_RM";        severity = "High";     regex = '\b(Remove-Item|rm)\b.*-Recurse.*-Force';          description = "Recursive force-delete (Remove-Item -Recurse -Force)" }
        @{ id = "PKG_DESTRUCT_FORMAT";    severity = "Critical"; regex = '\b(Format-Volume|format\s+[a-zA-Z]:)\b';          description = "Disk format command" }
        @{ id = "PKG_DESTRUCT_REG_DEL";   severity = "Critical"; regex = '\b(Remove-ItemProperty|reg\s+delete)\b.*HK';     description = "Registry deletion" }
        @{ id = "PKG_DESTRUCT_SVC";       severity = "High";     regex = '\b(Stop-Service|sc\s+delete)\b';                  description = "Service stop/delete" }
        # SQL destructive
        @{ id = "PKG_SQL_DROP";           severity = "Critical"; regex = '\b(DROP\s+(TABLE|DATABASE|SCHEMA))\b';             description = "SQL DROP statement in script" }
        @{ id = "PKG_SQL_TRUNCATE";       severity = "Critical"; regex = '\bTRUNCATE\s+TABLE\b';                             description = "SQL TRUNCATE TABLE in script" }
        # Credential harvesting / exfiltration
        @{ id = "PKG_CRED_HARVEST";       severity = "Critical"; regex = '(?i)(Get-Credential|ConvertFrom-SecureString)\b.*\b(Invoke-(Web|Rest)Request|curl|wget|System\.Net)\b';  description = "Credential harvesting + network send" }
        @{ id = "PKG_NET_EXFIL";          severity = "High";     regex = '(?i)\b(Invoke-(WebRequest|RestMethod)|curl|wget|Start-BitsTransfer)\b.*\b(POST|Upload|Body)\b';           description = "Potential data exfiltration via HTTP POST" }
        @{ id = "PKG_HARDCODED_CRED";     severity = "Critical"; regex = '(?i)(password|api[_-]?key|secret|token)\s*=\s*["\u0027][^"\u0027]{8,}["\u0027]';                           description = "Hardcoded credential in script" }
        # Obfuscation / encoded payloads
        @{ id = "PKG_ENCODED_CMD";        severity = "Critical"; regex = '(?i)-[Ee]ncoded[Cc]ommand\s';                      description = "PowerShell -EncodedCommand (obfuscated payload)" }
        @{ id = "PKG_BASE64_DECODE";      severity = "High";     regex = '(?i)\[System\.Convert\]::FromBase64String';        description = "Base64 decode (potential hidden payload)" }
        @{ id = "PKG_INVOKE_EXPRESSION";  severity = "High";     regex = '(?i)\b(Invoke-Expression|iex)\b';                  description = "Invoke-Expression (arbitrary code execution)" }
        @{ id = "PKG_DOWNLOADSTRING";     severity = "High";     regex = '(?i)(DownloadString|DownloadFile|WebClient)';       description = "Remote download via .NET WebClient" }
        # Unverified module installs
        @{ id = "PKG_INSTALL_NOVERIFY";   severity = "Medium";   regex = '(?i)Install-Module\b.*-SkipPublisherCheck';        description = "Install-Module with -SkipPublisherCheck" }
        @{ id = "PKG_INSTALL_UNTRUSTED";  severity = "Medium";   regex = '(?i)Install-Module\b(?!.*-Scope\s+CurrentUser)';   description = "Install-Module without -Scope CurrentUser" }
        @{ id = "PKG_FORCE_INSTALL";      severity = "Low";      regex = '(?i)Install-Module\b.*-Force\b.*-AllowClobber';    description = "Install-Module -Force -AllowClobber" }
        # Startup persistence
        @{ id = "PKG_SCHTASK";           severity = "High";     regex = '(?i)\b(schtasks|Register-ScheduledTask|New-ScheduledTask)\b';   description = "Scheduled task creation" }
        @{ id = "PKG_STARTUP_REG";       severity = "High";     regex = '(?i)(HKCU|HKLM).*\\Run\b';                         description = "Startup registry key modification" }
    )

    # ── Trusted / known core scripts (skip script-content scans for core infra) ──
    $trustedCorePaths = @(
        (Join-Path $RepoRoot "core/scripts/aira.ps1"),
        (Join-Path $RepoRoot "core/scripts/validate.ps1"),
        (Join-Path $RepoRoot "core/scripts/excel.ps1"),
        (Join-Path $RepoRoot "core/scripts/jira.ps1"),
        (Join-Path $RepoRoot "core/scripts/testrail.ps1"),
        (Join-Path $RepoRoot "core/scripts/confluence.ps1"),
        (Join-Path $RepoRoot "core/scripts/session.ps1"),
        (Join-Path $RepoRoot "core/scripts/memory.ps1")
    )
    # Also trust all core modules — they are part of the AIRA framework
    $coreModulesDir = Join-Path $RepoRoot "core/modules"
    if (Test-Path $coreModulesDir) {
        Get-ChildItem -Path $coreModulesDir -Filter "*.psm1" -File -ErrorAction SilentlyContinue |
            ForEach-Object { $trustedCorePaths += $_.FullName }
    }
    $trustedCoreSet = @{}
    foreach ($tp in $trustedCorePaths) {
        $resolved = if (Test-Path $tp) { (Resolve-Path $tp).Path } else { $tp }
        $trustedCoreSet[$resolved] = $true
    }

    # ── 1. Audit plugin manifests ──
    $pluginsRoot = Join-Path $RepoRoot "plugins"
    if (Test-Path $pluginsRoot) {
        $pluginDirs = Get-ChildItem -Path $pluginsRoot -Directory -ErrorAction SilentlyContinue
        foreach ($dir in $pluginDirs) {
            $manifestPath = Join-Path $dir.FullName "manifest.json"
            $relPath = $manifestPath.Replace($RepoRoot, "").TrimStart("\", "/")

            if (-not (Test-Path $manifestPath)) {
                $findings.Add(@{
                    path        = $relPath
                    pattern_id  = "PKG_MANIFEST_MISSING"
                    severity    = "High"
                    description = "Plugin directory '$($dir.Name)' has no manifest.json"
                }) | Out-Null
                continue
            }

            try {
                $manifest = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
            } catch {
                $findings.Add(@{
                    path        = $relPath
                    pattern_id  = "PKG_MANIFEST_INVALID"
                    severity    = "High"
                    description = "manifest.json is not valid JSON: $($_.Exception.Message)"
                }) | Out-Null
                continue
            }

            # Check required fields
            foreach ($field in $requiredManifestFields) {
                $hasField = $manifest.PSObject.Properties.Name -contains $field
                if (-not $hasField) {
                    $findings.Add(@{
                        path        = $relPath
                        pattern_id  = "PKG_MANIFEST_FIELD_MISSING"
                        severity    = "Medium"
                        description = "Missing required manifest field: '$field'"
                        matched     = $field
                    }) | Out-Null
                }
            }

            # Warn on unknown fields
            foreach ($prop in $manifest.PSObject.Properties.Name) {
                if ($knownManifestFields -notcontains $prop) {
                    $findings.Add(@{
                        path        = $relPath
                        pattern_id  = "PKG_MANIFEST_UNKNOWN_FIELD"
                        severity    = "Low"
                        description = "Unknown manifest field: '$prop' - could indicate untrusted plugin structure"
                        matched     = $prop
                    }) | Out-Null
                }
            }

            # Validate entry_script points to an existing file
            if ($manifest.PSObject.Properties.Name -contains "entry_script") {
                $entryPath = Join-Path $RepoRoot $manifest.entry_script
                if (-not (Test-Path $entryPath)) {
                    $findings.Add(@{
                        path        = $relPath
                        pattern_id  = "PKG_MANIFEST_ENTRY_MISSING"
                        severity    = "High"
                        description = "entry_script '$($manifest.entry_script)' does not exist"
                        matched     = $manifest.entry_script
                    }) | Out-Null
                }
            }
        }
    }

    # ── 2. Scan script files for dangerous patterns ──
    $scanDirs = @(
        (Join-Path $RepoRoot "plugins")
    ) + $ScanPaths
    # Also scan core scripts and modules
    $scanDirs += (Join-Path $RepoRoot "core/scripts")
    $scanDirs += (Join-Path $RepoRoot "core/modules")

    foreach ($scanDir in $scanDirs) {
        if (-not (Test-Path $scanDir)) { continue }
        $scriptFiles = Get-ChildItem -Path $scanDir -Include "*.ps1","*.psm1" -Recurse -File -ErrorAction SilentlyContinue

        foreach ($file in $scriptFiles) {
            $content = Get-Content $file.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
            if (-not $content) { continue }

            $relFilePath = $file.FullName.Replace($RepoRoot, "").TrimStart("\", "/")
            $isTrustedCore = $trustedCoreSet.ContainsKey($file.FullName)

            foreach ($pat in $scriptPatterns) {
                # Skip all dangerous-pattern scans for trusted core files (framework code)
                if ($isTrustedCore) { continue }

                if ([regex]::IsMatch($content, $pat.regex, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
                    $matchObj = [regex]::Match($content, $pat.regex, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                    # Find line number
                    $lineNum = ($content.Substring(0, $matchObj.Index) -split "`n").Count

                    $findings.Add(@{
                        path        = $relFilePath
                        pattern_id  = $pat.id
                        severity    = $pat.severity
                        description = $pat.description
                        matched     = $matchObj.Value.Substring(0, [Math]::Min($matchObj.Value.Length, 120))
                        line        = $lineNum
                    }) | Out-Null
                }
            }

            # Check for Authenticode signature on plugin scripts
            $isPlugin = $relFilePath -match '^plugins[/\\]'
            if ($isPlugin -and $file.Extension -eq ".ps1") {
                try {
                    $sig = Get-AuthenticodeSignature -FilePath $file.FullName -ErrorAction SilentlyContinue
                    if (-not $sig -or $sig.Status -ne "Valid") {
                        $findings.Add(@{
                            path        = $relFilePath
                            pattern_id  = "PKG_UNSIGNED_SCRIPT"
                            severity    = "Medium"
                            description = "Plugin script is not digitally signed (status: $($sig.Status))"
                            matched     = "$($sig.Status)"
                        }) | Out-Null
                    }
                } catch {
                    # Skip signature check if unavailable
                }
            }
        }
    }

    # ── 3. Determine overall status ──
    $critCount = @($findings | Where-Object { $_.severity -eq "Critical" }).Count
    $highCount = @($findings | Where-Object { $_.severity -eq "High" }).Count
    $medCount  = @($findings | Where-Object { $_.severity -eq "Medium" }).Count
    $lowCount  = @($findings | Where-Object { $_.severity -eq "Low" }).Count

    $status = if ($critCount -gt 0) {
        "Fail"
    } elseif ($highCount -gt 0) {
        "Warn"
    } else {
        "Pass"
    }

    return @{
        name      = "package_safety"
        timestamp = (Get-Date).ToString("s")
        status    = $status
        summary   = @{
            plugins_scanned  = @(Get-ChildItem -Path (Join-Path $RepoRoot "plugins") -Directory -ErrorAction SilentlyContinue).Count
            files_scanned    = @(Get-ChildItem -Path $scanDirs -Include "*.ps1","*.psm1" -Recurse -File -ErrorAction SilentlyContinue).Count
            finding_count    = $findings.Count
            by_severity      = @{
                critical = $critCount
                high     = $highCount
                medium   = $medCount
                low      = $lowCount
            }
        }
        findings  = $findings
    }
}

function Invoke-AiraContextValidation {
    <#
    .SYNOPSIS
        Validates context files for completeness, data quality, safety, and integrity.

    .DESCRIPTION
        Runs the context_integrity check against a context directory. This is the
        validation gate that determines whether raw context is safe to promote to
        processed status.

    .PARAMETER ContextPath
        Absolute path to the context directory (must contain manifest.json + sources/).

    .PARAMETER Policy
        Effective policy object. Defaults to Get-AiraPolicy if available.

    .PARAMETER Strict
        When true, missing optional files are flagged.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ContextPath,

        [object]$Policy = (Get-AiraPolicy),

        [switch]$Strict
    )

    $checkFile = Join-Path $repoRoot "core/validation/checks/context_integrity.ps1"
    if (-not (Test-Path $checkFile)) {
        throw "Context integrity check not found at: $checkFile"
    }

    $params = @{
        ContextPath = $ContextPath
        Policy      = $Policy
    }
    if ($Strict) { $params.Strict = $true }

    $result = & $checkFile @params
    return $result
}

function Invoke-AiraContextPromote {
    <#
    .SYNOPSIS
        Promotes context from raw to processed after validation passes.

    .DESCRIPTION
        1. Runs Invoke-AiraContextValidation on the context directory.
        2. If validation passes (no Critical findings), updates the manifest
           with context_status = "processed" and records the validation result.
        3. If validation fails with Critical findings, the context stays "raw"
           and the validation result is returned for the user to review.

        The processed context represents user-validated, curated data that
        downstream agents (Analysis, Design) can trust.

    .PARAMETER ContextPath
        Absolute path to the context directory.

    .PARAMETER Policy
        Effective policy object.

    .PARAMETER Force
        Force promotion even with High findings (Critical still blocks).

    .PARAMETER UserApproved
        Indicates the user has explicitly reviewed and approved the raw context.
        Bypasses Warn-level blocks but Critical findings still prevent promotion.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ContextPath,

        [object]$Policy = (Get-AiraPolicy),

        [switch]$Force,

        [switch]$UserApproved
    )

    # Run validation
    $validation = Invoke-AiraContextValidation -ContextPath $ContextPath -Policy $Policy

    $manifestPath = Join-Path $ContextPath "manifest.json"
    if (-not (Test-Path $manifestPath)) {
        return @{
            promoted   = $false
            reason     = "Manifest not found - cannot promote"
            validation = $validation
        }
    }

    $manifest = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json

    $critCount = $validation.summary.by_severity.critical

    # Critical findings always block promotion
    if ($critCount -gt 0) {
        # Update manifest to record failed validation
        $manifest | Add-Member -NotePropertyName "context_status" -NotePropertyValue "raw" -Force
        $manifest | Add-Member -NotePropertyName "last_validation" -NotePropertyValue @{
            timestamp = (Get-Date).ToString("s")
            status    = $validation.status
            promoted  = $false
            findings  = $validation.summary.finding_count
        } -Force
        $manifest | ConvertTo-Json -Depth 10 | Out-File -FilePath $manifestPath -Encoding UTF8

        return @{
            promoted   = $false
            reason     = "Critical findings ($critCount) prevent promotion - user must fix issues"
            validation = $validation
        }
    }

    $highCount = $validation.summary.by_severity.high
    # High findings block unless Force or UserApproved
    if ($highCount -gt 0 -and -not $Force -and -not $UserApproved) {
        $manifest | Add-Member -NotePropertyName "context_status" -NotePropertyValue "raw" -Force
        $manifest | Add-Member -NotePropertyName "last_validation" -NotePropertyValue @{
            timestamp = (Get-Date).ToString("s")
            status    = $validation.status
            promoted  = $false
            findings  = $validation.summary.finding_count
        } -Force
        $manifest | ConvertTo-Json -Depth 10 | Out-File -FilePath $manifestPath -Encoding UTF8

        return @{
            promoted   = $false
            reason     = "High findings ($highCount) require user approval (-UserApproved) or -Force to promote"
            validation = $validation
        }
    }

    # Promote: update manifest
    $manifest | Add-Member -NotePropertyName "context_status" -NotePropertyValue "processed" -Force
    $manifest | Add-Member -NotePropertyName "last_validation" -NotePropertyValue @{
        timestamp = (Get-Date).ToString("s")
        status    = $validation.status
        promoted  = $true
        findings  = $validation.summary.finding_count
        user_approved = [bool]$UserApproved
    } -Force
    $manifest | Add-Member -NotePropertyName "processed_at" -NotePropertyValue (Get-Date).ToString("s") -Force

    $manifest | ConvertTo-Json -Depth 10 | Out-File -FilePath $manifestPath -Encoding UTF8

    return @{
        promoted   = $true
        reason     = "Context promoted to processed"
        validation = $validation
    }
}

Export-ModuleMember -Function Invoke-AiraValidation, Invoke-AiraPackageSafetyAudit, Invoke-AiraContextValidation, Invoke-AiraContextPromote

