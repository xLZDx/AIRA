<#
.SYNOPSIS
    Detects dangerous, hallucinated, or sensitive content in test case steps and data.

.DESCRIPTION
    Scans test case text fields (titles, step actions, step expected results, preconditions)
    for patterns that indicate:

    1. DESTRUCTIVE OPERATIONS — SQL DROP/TRUNCATE/DELETE without WHERE, shell rm -rf,
       format disk, registry deletions, etc.  These are almost never appropriate as
       literal test steps and may indicate copy-paste from production runbooks or
       AI hallucination of dangerous instructions.

    2. HALLUCINATION INDICATORS — placeholder/fictional URLs (example.com, localhost in
       production steps), "lorem ipsum", obviously fabricated data like "John Doe",
       non-existent API paths that smell auto-generated (/api/v99/, /foo/bar/baz).

    3. SENSITIVE DATA EXPOSURE — hardcoded passwords, API keys, tokens, secrets, PII
       patterns (SSN, credit-card numbers) embedded directly in test steps instead
       of using masked/parameterized references.

    4. INJECTION RISK PATTERNS — raw SQL in step text that could be interpreted as
       instructing testers to paste injection payloads without safety context, XSS
       script tags, OS command chains.

    Each finding is classified by severity:
      - Critical : Destructive operations, real credentials
      - High     : Injection patterns, PII exposure
      - Medium   : Hallucination indicators, placeholder data
      - Low      : Minor style concerns (informational)

    A single Critical or High finding FAILs the check.
    Medium findings produce a Warn.
    Low findings pass but are reported.

.PARAMETER TestCases
    The test case design object (new_cases, enhance_cases, prereq_cases).

.PARAMETER Policy
    Effective policy object.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [object]$TestCases,

    [Parameter(Mandatory = $true)]
    [object]$Policy
)

# ── Helpers ──────────────────────────────────────────────────────────────────

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

function Normalize-Categories {
    param([object]$Obj)
    $n = Get-Prop $Obj "new_cases"
    if (-not $n) { $n = Get-Prop $Obj "NEW_CASES" }
    if (-not $n) { $n = @() }

    $e = Get-Prop $Obj "enhance_cases"
    if (-not $e) { $e = Get-Prop $Obj "ENHANCE_CASES" }
    if (-not $e) { $e = @() }

    return @{ new_cases = @($n); enhance_cases = @($e) }
}

function Extract-TextFields {
    <#
    .SYNOPSIS  Returns all human-readable text from a single test case.
    #>
    param([object]$Case, [string]$Prefix)

    $texts = New-Object System.Collections.Generic.List[object]

    # Title
    $title = Get-Prop $Case "title"
    if ($title) { $texts.Add(@{ path = "$Prefix.title"; text = "$title" }) | Out-Null }

    # Preconditions
    $pre = Get-Prop $Case "preconditions"
    if ($pre) { $texts.Add(@{ path = "$Prefix.preconditions"; text = "$pre" }) | Out-Null }

    # Steps — new_cases use "steps", enhance_cases use "new_steps"
    $steps = Get-Prop $Case "steps"
    if (-not $steps) { $steps = Get-Prop $Case "new_steps" }
    if ($steps) {
        $sIdx = 0
        foreach ($s in @($steps)) {
            $sIdx++
            $act = Get-Prop $s "action"
            if (-not $act) { $act = Get-Prop $s "content" }
            if ($act) { $texts.Add(@{ path = "$Prefix.steps[$sIdx].action"; text = "$act" }) | Out-Null }

            $exp = Get-Prop $s "expected"
            if ($exp) { $texts.Add(@{ path = "$Prefix.steps[$sIdx].expected"; text = "$exp" }) | Out-Null }
        }
    }

    # Rationale (enhance_cases)
    $rat = Get-Prop $Case "rationale"
    if ($rat) { $texts.Add(@{ path = "$Prefix.rationale"; text = "$rat" }) | Out-Null }

    return $texts
}

# ── Pattern Definitions ──────────────────────────────────────────────────────

$DestructivePatterns = @(
    @{ id = "DESTRUCT_SQL_DROP";      severity = "Critical"; regex = '\b(DROP\s+(TABLE|DATABASE|SCHEMA|INDEX|VIEW|USER))\b';         description = "SQL DROP statement" }
    @{ id = "DESTRUCT_SQL_TRUNCATE";  severity = "Critical"; regex = '\bTRUNCATE\s+TABLE\b';                                         description = "SQL TRUNCATE TABLE" }
    @{ id = "DESTRUCT_SQL_DELETE_ALL"; severity = "Critical"; regex = '\bDELETE\s+FROM\s+\w+\s*;';                                    description = "SQL DELETE without WHERE clause" }
    @{ id = "DESTRUCT_SHELL_RM_RF";   severity = "Critical"; regex = '\brm\s+-r?f\b';                                                description = "Shell rm -rf / rm -f command" }
    @{ id = "DESTRUCT_SHELL_FORMAT";  severity = "Critical"; regex = '\b(format\s+[a-zA-Z]:)|(mkfs\b)';                              description = "Disk format command" }
    @{ id = "DESTRUCT_REGISTRY_DEL";  severity = "Critical"; regex = '\b(reg\s+delete|Remove-Item\s+.*HKLM|Remove-Item\s+.*HKCU)\b'; description = "Registry deletion" }
    @{ id = "DESTRUCT_DROP_USER";     severity = "Critical"; regex = '\b(DROP\s+USER|DROP\s+ROLE)\b';                                 description = "Drop user/role" }
    @{ id = "DESTRUCT_SHUTDOWN";      severity = "High";     regex = '\b(shutdown\s+/[srf]|Stop-Computer|Restart-Computer)\b';        description = "System shutdown/restart command" }
    @{ id = "DESTRUCT_SVC_STOP";      severity = "High";     regex = '\b(net\s+stop|Stop-Service|sc\s+delete)\b';                    description = "Service stop/delete command" }
)

$HallucinationPatterns = @(
    @{ id = "HALLUC_EXAMPLE_DOMAIN";  severity = "Medium"; regex = '\b(example\.com|example\.org|example\.net)\b';                    description = "Placeholder domain (example.com)" }
    @{ id = "HALLUC_LOREM_IPSUM";     severity = "Medium"; regex = '\blorem\s+ipsum\b';                                              description = "Lorem ipsum placeholder text" }
    @{ id = "HALLUC_PLACEHOLDER_URL"; severity = "Medium"; regex = '\b(https?://(localhost|127\.0\.0\.1|0\.0\.0\.0))\b';              description = "Localhost/loopback URL in test step" }
    @{ id = "HALLUC_FAKE_API_PATH";   severity = "Medium"; regex = '/api/v\d{2,}/';                                                  description = "Suspicious high-version API path (/api/v10+/)" }
    @{ id = "HALLUC_TODO_FIXME";      severity = "Medium"; regex = '\b(TODO|FIXME|HACK|XXX|PLACEHOLDER)\b';                          description = "Unresolved TODO/FIXME marker" }
    @{ id = "HALLUC_JOHN_DOE";        severity = "Low";    regex = '\b(John\s+Doe|Jane\s+Doe|Foo\s+Bar|Test\s+User)\b';             description = "Fictional placeholder name" }
)

$SensitiveDataPatterns = @(
    @{ id = "SENSITIVE_PASSWORD";     severity = "Critical"; regex = '(?i)(password|passwd|pwd)\s*[:=]\s*\S{4,}';                     description = "Hardcoded password" }
    @{ id = "SENSITIVE_API_KEY";      severity = "Critical"; regex = '(?i)(api[_-]?key|apikey|api[_-]?secret)\s*[:=]\s*\S{8,}';      description = "Hardcoded API key/secret" }
    @{ id = "SENSITIVE_TOKEN";        severity = "Critical"; regex = '(?i)(bearer\s+[A-Za-z0-9\-_.]{20,}|token\s*[:=]\s*\S{20,})';   description = "Hardcoded bearer token / auth token" }
    @{ id = "SENSITIVE_SSN";          severity = "High";     regex = '\b\d{3}-\d{2}-\d{4}\b';                                        description = "Possible SSN pattern (###-##-####)" }
    @{ id = "SENSITIVE_CREDIT_CARD";  severity = "High";     regex = '\b(?:\d{4}[- ]?){3}\d{4}\b';                                   description = "Possible credit card number" }
    @{ id = "SENSITIVE_CONN_STRING";  severity = "Critical"; regex = '(?i)(Server|Data Source)\s*=.*?(Password|Pwd)\s*=';             description = "Connection string with credentials" }
)

$InjectionPatterns = @(
    @{ id = "INJECT_SQL";            severity = "High";    regex = "(?i)('\s*(OR|AND)\s+['\d].*=)|(--.*)|(;\s*(DROP|ALTER|INSERT|UPDATE|DELETE)\b)"; description = "SQL injection pattern" }
    @{ id = "INJECT_XSS_SCRIPT";    severity = "High";    regex = '<script\b[^>]*>|javascript\s*:';                                  description = "XSS script tag or javascript: URI" }
    @{ id = "INJECT_CMD_CHAIN";     severity = "High";    regex = '(\|\||\&\&)\s*(rm|del|format|shutdown|curl|wget)\b';              description = "Command injection chain" }
    @{ id = "INJECT_TEMPLATE";      severity = "Medium";  regex = '\{\{.*\}\}|\$\{.*\}';                                            description = "Template injection / unsanitized interpolation" }
)

# ── Scanning Engine ──────────────────────────────────────────────────────────

$AllPatterns = @()
$AllPatterns += $DestructivePatterns
$AllPatterns += $HallucinationPatterns
$AllPatterns += $SensitiveDataPatterns
$AllPatterns += $InjectionPatterns

$findings = New-Object System.Collections.Generic.List[object]

$cats = Normalize-Categories -Obj $TestCases

# Scan new_cases
$i = 0
foreach ($c in @($cats.new_cases)) {
    $i++
    $textFields = Extract-TextFields -Case $c -Prefix "new_cases[$i]"
    foreach ($tf in $textFields) {
        foreach ($pat in $AllPatterns) {
            if ([regex]::IsMatch($tf.text, $pat.regex, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
                $matchObj = [regex]::Match($tf.text, $pat.regex, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                $findings.Add(@{
                    path        = $tf.path
                    pattern_id  = $pat.id
                    severity    = $pat.severity
                    description = $pat.description
                    matched     = $matchObj.Value
                }) | Out-Null
            }
        }
    }
}

# Scan enhance_cases
$i = 0
foreach ($c in @($cats.enhance_cases)) {
    $i++
    $textFields = Extract-TextFields -Case $c -Prefix "enhance_cases[$i]"
    foreach ($tf in $textFields) {
        foreach ($pat in $AllPatterns) {
            if ([regex]::IsMatch($tf.text, $pat.regex, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
                $matchObj = [regex]::Match($tf.text, $pat.regex, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                $findings.Add(@{
                    path        = $tf.path
                    pattern_id  = $pat.id
                    severity    = $pat.severity
                    description = $pat.description
                    matched     = $matchObj.Value
                }) | Out-Null
            }
        }
    }
}

# ── Determine overall status ─────────────────────────────────────────────────

$critCount = @($findings | Where-Object { $_.severity -eq "Critical" }).Count
$highCount = @($findings | Where-Object { $_.severity -eq "High" }).Count
$medCount  = @($findings | Where-Object { $_.severity -eq "Medium" }).Count
$lowCount  = @($findings | Where-Object { $_.severity -eq "Low" }).Count

$status = if ($critCount -gt 0 -or $highCount -gt 0) {
    "Fail"
} elseif ($medCount -gt 0) {
    "Warn"
} else {
    "Pass"
}

return @{
    name    = "content_safety"
    status  = $status
    details = @{
        finding_count = $findings.Count
        by_severity   = @{
            critical = $critCount
            high     = $highCount
            medium   = $medCount
            low      = $lowCount
        }
        findings      = $findings
    }
}
