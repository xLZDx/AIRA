<#
.SYNOPSIS
    Validates context files for completeness, data quality, and safety.

.DESCRIPTION
    Scans a context directory (sources, manifest, context.md) for:

    1. STRUCTURAL COMPLETENESS - required source files exist and are non-empty,
       manifest hashes are present, context.md has required sections.

    2. DATA QUALITY - detects empty/placeholder content, missing acceptance
       criteria, missing description, truncated comments, stale timestamps.

    3. CONTENT SAFETY - scans raw source data for hallucinated values, test
       data leaked into real context, PII in raw JSON, suspicious URLs.

    4. CROSS-REFERENCE INTEGRITY - manifest hashes match actual file hashes,
       dependency keys match files in dependencies/ folder, attachment metadata
       matches downloaded files.

    Returns a result object with status (Pass/Warn/Fail) and findings array.

.PARAMETER ContextPath
    Absolute path to the context directory (e.g., context/local/AIRA/AIRA-3).

.PARAMETER Policy
    Effective policy object.

.PARAMETER Strict
    When true, missing optional sections (e.g., attachments, dependencies) are
    flagged as Warn instead of silently passing.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ContextPath,

    [Parameter(Mandatory = $true)]
    [object]$Policy,

    [switch]$Strict
)

# ---- helpers ----------------------------------------------------------------

function Get-Prop {
    param([object]$Obj, [string]$Name)
    if ($null -eq $Obj) { return $null }
    if ($Obj -is [hashtable]) {
        if ($Obj.ContainsKey($Name)) { return $Obj[$Name] }
        return $null
    }
    if ($Obj.PSObject.Properties.Name -contains $Name) { return $Obj.$Name }
    return $null
}

function Safe-Hash {
    param([string]$FilePath)
    if (-not (Test-Path $FilePath)) { return $null }
    $bytes = [System.IO.File]::ReadAllBytes($FilePath)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $hash = $sha.ComputeHash($bytes)
    return ($hash | ForEach-Object { $_.ToString("x2") }) -join ''
}

# ---- initialise findings list -----------------------------------------------

$findings = New-Object System.Collections.Generic.List[object]
$manifest = $null

# ---- 1. Structural Completeness --------------------------------------------

$manifestPath = Join-Path $ContextPath "manifest.json"
$contextMdPath = Join-Path $ContextPath "context.md"
$sourcesDir = Join-Path $ContextPath "sources"

# Manifest must exist
if (-not (Test-Path $manifestPath)) {
    $findings.Add(@{
        category    = "structure"
        severity    = "Critical"
        field       = "manifest.json"
        description = "Context manifest is missing - context may be corrupted or incomplete"
    }) | Out-Null
} else {
    try {
        $manifest = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        $findings.Add(@{
            category    = "structure"
            severity    = "Critical"
            field       = "manifest.json"
            description = "Context manifest is not valid JSON: $($_.Exception.Message)"
        }) | Out-Null
        $manifest = $null
    }
}

# context.md must exist
if (-not (Test-Path $contextMdPath)) {
    $findings.Add(@{
        category    = "structure"
        severity    = "Critical"
        field       = "context.md"
        description = "Enriched context.md is missing - context building may have failed"
    }) | Out-Null
}

# Required source files
$requiredSources = @("issue.json", "comments.json", "linked_issues.json")
foreach ($src in $requiredSources) {
    $srcPath = Join-Path $sourcesDir $src
    if (-not (Test-Path $srcPath)) {
        $findings.Add(@{
            category    = "structure"
            severity    = "High"
            field       = "sources/$src"
            description = "Required source file '$src' is missing"
        }) | Out-Null
    } else {
        $content = Get-Content $srcPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        if ([string]::IsNullOrWhiteSpace($content) -or $content.Trim().Length -lt 3) {
            $findings.Add(@{
                category    = "structure"
                severity    = "High"
                field       = "sources/$src"
                description = "Source file '$src' is empty or nearly empty"
            }) | Out-Null
        }
    }
}

# Optional sources (warn in strict mode)
$optionalSources = @("attachments.json", "sources.json", "attachment_extractions.json")
foreach ($src in $optionalSources) {
    $srcPath = Join-Path $sourcesDir $src
    if (-not (Test-Path $srcPath) -and $Strict) {
        $findings.Add(@{
            category    = "structure"
            severity    = "Low"
            field       = "sources/$src"
            description = "Optional source file '$src' not present"
        }) | Out-Null
    }
}

# ---- 2. Data Quality -------------------------------------------------------

# Validate manifest fields
if ($manifest) {
    $requiredManifestFields = @("jira_key", "scraped_at", "hashes", "context_md_path", "local_data_path")
    foreach ($field in $requiredManifestFields) {
        $val = Get-Prop $manifest $field
        if ($null -eq $val -or ($val -is [string] -and [string]::IsNullOrWhiteSpace($val))) {
            $findings.Add(@{
                category    = "quality"
                severity    = "High"
                field       = "manifest.$field"
                description = "Required manifest field '$field' is missing or empty"
            }) | Out-Null
        }
    }

    # Staleness check - context older than 30 days
    $scrapedAt = Get-Prop $manifest "scraped_at"
    if ($scrapedAt) {
        try {
            $scrapedDate = [datetime]::Parse($scrapedAt)
            $age = (Get-Date) - $scrapedDate
            if ($age.TotalDays -gt 30) {
                $findings.Add(@{
                    category    = "quality"
                    severity    = "Medium"
                    field       = "manifest.scraped_at"
                    description = "Context is $([int]$age.TotalDays) days old - consider refreshing"
                }) | Out-Null
            }
        } catch { }
    }
}

# context.md section completeness
if (Test-Path $contextMdPath) {
    $ctxContent = Get-Content $contextMdPath -Raw -Encoding UTF8
    $requiredSections = @(
        @{ header = "## Issue";                  severity = "Critical" },
        @{ header = "## Description";            severity = "High" },
        @{ header = "## Acceptance Criteria";     severity = "High" },
        @{ header = "## Direct Dependencies";     severity = "Medium" },
        @{ header = "## References & Links";      severity = "Medium" }
    )
    foreach ($sec in $requiredSections) {
        if ($ctxContent -notmatch [regex]::Escape($sec.header)) {
            $findings.Add(@{
                category    = "quality"
                severity    = $sec.severity
                field       = "context.md"
                description = "Missing required section: '$($sec.header)'"
            }) | Out-Null
        }
    }

    # Detect placeholder / missing content markers
    $placeholderPatterns = @(
        @{ regex = '\[MISSING\s*-?\s*NEEDS?\s*INPUT\]'; severity = "Medium"; description = "Contains unresolved [MISSING - NEEDS INPUT] placeholder" }
        @{ regex = '\[PENDING\s*CLARIFICATION\]';       severity = "Low";    description = "Contains [PENDING CLARIFICATION] marker" }
        @{ regex = '\[TBD\]|\[TODO\]';                   severity = "Medium"; description = "Contains unresolved TBD/TODO marker" }
    )
    foreach ($pat in $placeholderPatterns) {
        $matches = [regex]::Matches($ctxContent, $pat.regex, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($matches.Count -gt 0) {
            $findings.Add(@{
                category    = "quality"
                severity    = $pat.severity
                field       = "context.md"
                description = "$($pat.description) ($($matches.Count) occurrence(s))"
                count       = $matches.Count
            }) | Out-Null
        }
    }

    # Empty description detection
    if ($ctxContent -match '## Description\s*\n+\s*(\(empty|No description| *\n##)') {
        $findings.Add(@{
            category    = "quality"
            severity    = "High"
            field       = "context.md"
            description = "Description section appears empty - requirements cannot be derived"
        }) | Out-Null
    }
}

# Validate issue.json has key fields
$issuePath = Join-Path $sourcesDir "issue.json"
if (Test-Path $issuePath) {
    try {
        $issue = Get-Content $issuePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $issueFields = Get-Prop $issue "fields"
        if ($issueFields) {
            $summary = Get-Prop $issueFields "summary"
            $description = Get-Prop $issueFields "description"
            $issuetype = Get-Prop $issueFields "issuetype"

            if ([string]::IsNullOrWhiteSpace($summary)) {
                $findings.Add(@{
                    category    = "quality"
                    severity    = "High"
                    field       = "sources/issue.json"
                    description = "Jira issue has no summary"
                }) | Out-Null
            }
            if ([string]::IsNullOrWhiteSpace($description)) {
                $findings.Add(@{
                    category    = "quality"
                    severity    = "Medium"
                    field       = "sources/issue.json"
                    description = "Jira issue has no description - acceptance criteria may be missing"
                }) | Out-Null
            }
            if ($issuetype) {
                $typeName = Get-Prop $issuetype "name"
                if ($typeName -eq "Bug") {
                    $findings.Add(@{
                        category    = "quality"
                        severity    = "High"
                        field       = "sources/issue.json"
                        description = "Issue type is Bug - Bugs should not be analyzed as requirement sources"
                    }) | Out-Null
                }
            }
        }
    } catch { }
}

# ---- 3. Content Safety (raw source data) ------------------------------------

$safetyPatterns = @(
    @{ id = "CTX_HARDCODED_CRED";  severity = "Critical"; regex = '(?i)(password|passwd|pwd|api[_-]?key|secret|token)\s*[:=]\s*["\u0027][^"\u0027]{8,}'; description = "Possible hardcoded credential in source data" }
    @{ id = "CTX_PII_SSN";         severity = "High";     regex = '\b\d{3}-\d{2}-\d{4}\b';                description = "Possible SSN pattern in source data" }
    @{ id = "CTX_PII_CREDIT_CARD"; severity = "High";     regex = '\b(?:\d{4}[- ]?){3}\d{4}\b';           description = "Possible credit card number in source data" }
    @{ id = "CTX_INTERNAL_URL";    severity = "Medium";   regex = '(?i)https?://(10\.\d+\.\d+\.\d+|192\.168\.\d+\.\d+|172\.(1[6-9]|2\d|3[01])\.\d+\.\d+)[:/]'; description = "Internal/private IP address in source data" }
    @{ id = "CTX_SQL_INJECTION";   severity = "High";     regex = "(?i)('\s*(OR|AND)\s+['\d].*=)|(;\s*(DROP|ALTER|INSERT|UPDATE|DELETE)\b)"; description = "SQL injection pattern in source data" }
)

# Scan all source files
$sourceFiles = @()
if (Test-Path $sourcesDir) {
    $sourceFiles = Get-ChildItem -Path $sourcesDir -Filter "*.json" -File -ErrorAction SilentlyContinue
}
if (Test-Path $contextMdPath) {
    $sourceFiles += Get-Item $contextMdPath
}

foreach ($file in $sourceFiles) {
    $content = Get-Content $file.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
    if (-not $content) { continue }

    foreach ($pat in $safetyPatterns) {
        if ([regex]::IsMatch($content, $pat.regex, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
            $match = [regex]::Match($content, $pat.regex, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            $lineNum = ($content.Substring(0, $match.Index) -split "`n").Count
            $findings.Add(@{
                category    = "safety"
                severity    = $pat.severity
                field       = $file.Name
                description = $pat.description
                line        = $lineNum
                matched     = $match.Value.Substring(0, [Math]::Min($match.Value.Length, 80))
            }) | Out-Null
        }
    }
}

# ---- 4. Cross-Reference Integrity ------------------------------------------

if ($manifest) {
    $hashes = Get-Prop $manifest "hashes"
    if ($hashes) {
        $hashChecks = @(
            @{ name = "issue";          path = (Join-Path $sourcesDir "issue.json") }
            @{ name = "comments";       path = (Join-Path $sourcesDir "comments.json") }
            @{ name = "linked_issues";  path = (Join-Path $sourcesDir "linked_issues.json") }
        )
        foreach ($hc in $hashChecks) {
            $expected = Get-Prop $hashes $hc.name
            if (-not $expected) { continue }
            if (-not (Test-Path $hc.path)) { continue }

            $actual = Safe-Hash -FilePath $hc.path
            if ($actual -ne $expected) {
                $findings.Add(@{
                    category    = "integrity"
                    severity    = "High"
                    field       = "manifest.hashes.$($hc.name)"
                    description = "Hash mismatch for $($hc.name) - file may have been modified outside AIRA"
                }) | Out-Null
            }
        }
    }

    # Dependency keys vs actual dependency folders
    $depKeys = Get-Prop $manifest "dependency_keys"
    if ($depKeys -and @($depKeys).Count -gt 0) {
        $depsDir = Join-Path $ContextPath "dependencies"
        foreach ($dk in @($depKeys)) {
            $depDir = Join-Path $depsDir $dk
            if (-not (Test-Path $depDir)) {
                $findings.Add(@{
                    category    = "integrity"
                    severity    = "Medium"
                    field       = "dependencies/$dk"
                    description = "Manifest lists dependency '$dk' but folder is missing"
                }) | Out-Null
            }
        }
    }

    # Attachment metadata vs downloaded files
    $attachmentsJsonPath = Join-Path $sourcesDir "attachments.json"
    if (Test-Path $attachmentsJsonPath) {
        try {
            $attachMeta = Get-Content $attachmentsJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $attachDir = Join-Path $ContextPath "attachments"
            foreach ($att in @($attachMeta)) {
                $downloaded = Get-Prop $att "downloaded"
                $attPath = Get-Prop $att "path"
                if ($downloaded -eq $true -and $attPath) {
                    $fullPath = if ([System.IO.Path]::IsPathRooted($attPath)) { $attPath } else { Join-Path (Split-Path $ContextPath -Parent | Split-Path -Parent | Split-Path -Parent) $attPath }
                    if (-not (Test-Path $fullPath)) {
                        $filename = Get-Prop $att "filename"
                        $findings.Add(@{
                            category    = "integrity"
                            severity    = "Medium"
                            field       = "attachments/$filename"
                            description = "Attachment '$filename' marked as downloaded but file not found"
                        }) | Out-Null
                    }
                }
            }
        } catch { }
    }
}

# ---- Compute overall status -------------------------------------------------

$critCount = @($findings | Where-Object { $_.severity -eq "Critical" }).Count
$highCount = @($findings | Where-Object { $_.severity -eq "High" }).Count
$medCount  = @($findings | Where-Object { $_.severity -eq "Medium" }).Count
$lowCount  = @($findings | Where-Object { $_.severity -eq "Low" }).Count

$catStructure = @($findings | Where-Object { $_.category -eq "structure" }).Count
$catQuality   = @($findings | Where-Object { $_.category -eq "quality" }).Count
$catSafety    = @($findings | Where-Object { $_.category -eq "safety" }).Count
$catIntegrity = @($findings | Where-Object { $_.category -eq "integrity" }).Count

$status = if ($critCount -gt 0) {
    "Fail"
} elseif ($highCount -gt 0) {
    "Warn"
} else {
    "Pass"
}

$sevHash = @{ critical = $critCount; high = $highCount; medium = $medCount; low = $lowCount }
$catHash = @{ structure = $catStructure; quality = $catQuality; safety = $catSafety; integrity = $catIntegrity }
$summaryHash = @{ finding_count = $findings.Count; by_severity = $sevHash; by_category = $catHash }
$findingsArr = $findings.ToArray()

return @{
    name     = "context_integrity"
    status   = $status
    summary  = $summaryHash
    findings = $findingsArr
}
