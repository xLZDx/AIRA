BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../../..")).Path
    $checksDir = Join-Path $repoRoot "core/validation/checks"

    # Helper: build a valid, complete test-design object
    function New-ValidDesign {
        return @{
            new_cases = @(
                @{
                    title      = "Verify login with valid credentials"
                    priority   = "High"
                    type       = "Functional"
                    references = "MARD-719"
                    steps      = @(
                        @{ action = "Navigate to /login"; expected = "Login page is displayed" }
                        @{ action = "Enter valid username and password"; expected = "Credentials accepted" }
                        @{ action = "Click Submit"; expected = "Dashboard is shown" }
                    )
                }
            )
            enhance_cases = @(
                @{
                    existing_case_id   = 100
                    existing_title     = "Verify dashboard loads"
                    rationale          = "Add AUM metrics validation after MARD-719"
                    updated_references = "MARD-719"
                    new_steps          = @(
                        @{ action = "Check AUM widget"; expected = "AUM value is visible and > 0" }
                    )
                }
            )
            prereq_cases = @(
                @{
                    case_id = 200
                    title   = "User account exists"
                    usage   = "Precondition for login tests"
                }
            )
        }
    }

    # Helper: build a policy object
    function New-TestPolicy {
        return @{
            testrail = @{
                restrictions = @{
                    forbidden_priorities    = @("Blocker")
                    require_jira_reference  = $true
                    max_cases_per_batch     = 50
                }
            }
        }
    }
}

# ──────────────────────────────────────────────
# schema_compliance
# ──────────────────────────────────────────────
Describe "schema_compliance check" {
    It "passes for a fully valid design" {
        $design = New-ValidDesign
        $policy = New-TestPolicy
        $result = & (Join-Path $checksDir "schema_compliance.ps1") -TestCases $design -Policy $policy
        $result.name | Should -Be "schema_compliance"
        $result.status | Should -Be "Pass"
    }

    It "fails when new_cases.title is missing" {
        $design = New-ValidDesign
        $design.new_cases[0].title = ""
        $result = & (Join-Path $checksDir "schema_compliance.ps1") -TestCases $design -Policy (New-TestPolicy)
        $result.status | Should -Be "Fail"
        ($result.details.errors | Where-Object { $_.path -match "title" }).Count | Should -BeGreaterThan 0
    }

    It "fails when steps are empty" {
        $design = New-ValidDesign
        $design.new_cases[0].steps = @()
        $result = & (Join-Path $checksDir "schema_compliance.ps1") -TestCases $design -Policy (New-TestPolicy)
        $result.status | Should -Be "Fail"
    }

    It "fails when enhance_cases.existing_case_id is null" {
        $design = New-ValidDesign
        $design.enhance_cases[0].Remove("existing_case_id")
        $result = & (Join-Path $checksDir "schema_compliance.ps1") -TestCases $design -Policy (New-TestPolicy)
        $result.status | Should -Be "Fail"
    }

    It "fails when prereq_cases.case_id is null" {
        $design = New-ValidDesign
        $design.prereq_cases[0].Remove("case_id")
        $result = & (Join-Path $checksDir "schema_compliance.ps1") -TestCases $design -Policy (New-TestPolicy)
        $result.status | Should -Be "Fail"
    }
}

# ──────────────────────────────────────────────
# forbidden_values
# ──────────────────────────────────────────────
Describe "forbidden_values check" {
    It "passes when no forbidden priority is used" {
        $design = New-ValidDesign
        $result = & (Join-Path $checksDir "forbidden_values.ps1") -TestCases $design -Policy (New-TestPolicy)
        $result.name | Should -Be "forbidden_values"
        $result.status | Should -Be "Pass"
    }

    It "fails when a case uses a forbidden priority" {
        $design = New-ValidDesign
        $design.new_cases[0].priority = "Blocker"
        $result = & (Join-Path $checksDir "forbidden_values.ps1") -TestCases $design -Policy (New-TestPolicy)
        $result.status | Should -Be "Fail"
        $result.details.violations.Count | Should -Be 1
    }

    It "passes when forbidden list is empty" {
        $design = New-ValidDesign
        $design.new_cases[0].priority = "Blocker"
        $policy = New-TestPolicy
        $policy.testrail.restrictions.forbidden_priorities = @()
        $result = & (Join-Path $checksDir "forbidden_values.ps1") -TestCases $design -Policy $policy
        $result.status | Should -Be "Pass"
    }
}

# ──────────────────────────────────────────────
# step_completeness
# ──────────────────────────────────────────────
Describe "step_completeness check" {
    It "passes when all steps have action + expected" {
        $result = & (Join-Path $checksDir "step_completeness.ps1") -TestCases (New-ValidDesign) -Policy (New-TestPolicy)
        $result.name | Should -Be "step_completeness"
        $result.status | Should -Be "Pass"
    }

    It "fails when a step is missing expected" {
        $design = New-ValidDesign
        $design.new_cases[0].steps += @{ action = "Click save"; expected = $null }
        $result = & (Join-Path $checksDir "step_completeness.ps1") -TestCases $design -Policy (New-TestPolicy)
        $result.status | Should -Be "Fail"
        $result.details.issue_count | Should -BeGreaterThan 0
    }

    It "fails when an enhance step is missing action" {
        $design = New-ValidDesign
        $design.enhance_cases[0].new_steps += @{ action = ""; expected = "something" }
        $result = & (Join-Path $checksDir "step_completeness.ps1") -TestCases $design -Policy (New-TestPolicy)
        $result.status | Should -Be "Fail"
    }
}

# ──────────────────────────────────────────────
# reference_integrity
# ──────────────────────────────────────────────
Describe "reference_integrity check" {
    It "passes when all references contain valid Jira keys" {
        $result = & (Join-Path $checksDir "reference_integrity.ps1") -TestCases (New-ValidDesign) -Policy (New-TestPolicy)
        $result.name | Should -Be "reference_integrity"
        $result.status | Should -Be "Pass"
    }

    It "fails when new_case reference has no Jira key and policy requires it" {
        $design = New-ValidDesign
        $design.new_cases[0].references = "no jira key here"
        $result = & (Join-Path $checksDir "reference_integrity.ps1") -TestCases $design -Policy (New-TestPolicy)
        $result.status | Should -Be "Fail"
    }

    It "passes with missing Jira keys when policy does not require them" {
        $design = New-ValidDesign
        $design.new_cases[0].references = "no jira key"
        $policy = New-TestPolicy
        $policy.testrail.restrictions.require_jira_reference = $false
        $result = & (Join-Path $checksDir "reference_integrity.ps1") -TestCases $design -Policy $policy
        $result.status | Should -Be "Pass"
    }
}

# ──────────────────────────────────────────────
# duplicate_detection
# ──────────────────────────────────────────────
Describe "duplicate_detection check" {
    It "warns when no coverage data is available" {
        $design = New-ValidDesign
        $result = & (Join-Path $checksDir "duplicate_detection.ps1") -TestCases $design -Policy (New-TestPolicy)
        $result.name | Should -Be "duplicate_detection"
        $result.status | Should -Be "Warn"
    }

    It "passes when new titles do not match existing" {
        $design = New-ValidDesign
        $design["existing_coverage"] = @{
            direct_cases = @(
                @{ id = 300; title = "Verify logout" }
            )
        }
        $result = & (Join-Path $checksDir "duplicate_detection.ps1") -TestCases $design -Policy (New-TestPolicy)
        $result.status | Should -Be "Pass"
    }

    It "fails when new title matches an existing case" {
        $design = New-ValidDesign
        $design["existing_coverage"] = @{
            direct_cases = @(
                @{ id = 300; title = "Verify login with valid credentials" }
            )
        }
        $result = & (Join-Path $checksDir "duplicate_detection.ps1") -TestCases $design -Policy (New-TestPolicy)
        $result.status | Should -Be "Fail"
        $result.details.duplicate_count | Should -Be 1
    }

    It "detects case-insensitive duplicates" {
        $design = New-ValidDesign
        $design["existing_coverage"] = @{
            direct_cases = @(
                @{ id = 300; title = "VERIFY LOGIN WITH VALID CREDENTIALS" }
            )
        }
        $result = & (Join-Path $checksDir "duplicate_detection.ps1") -TestCases $design -Policy (New-TestPolicy)
        $result.status | Should -Be "Fail"
    }
}

# ──────────────────────────────────────────────
# prerequisite_exists
# ──────────────────────────────────────────────
Describe "prerequisite_exists check" {
    It "passes when prereq case_ids are valid integers without coverage lookup" {
        $design = New-ValidDesign
        $result = & (Join-Path $checksDir "prerequisite_exists.ps1") -TestCases $design -Policy (New-TestPolicy)
        $result.name | Should -Be "prerequisite_exists"
        $result.status | Should -Be "Pass"
    }

    It "warns when prereq case_id is not found in coverage" {
        $design = New-ValidDesign
        $design["existing_coverage"] = @{
            direct_cases = @(
                @{ id = 300; title = "Some other case" }
            )
        }
        $result = & (Join-Path $checksDir "prerequisite_exists.ps1") -TestCases $design -Policy (New-TestPolicy)
        $result.status | Should -Be "Warn"
        $result.details.issue_count | Should -BeGreaterThan 0
    }

    It "passes when prereq case_id exists in coverage" {
        $design = New-ValidDesign
        $design["existing_coverage"] = @{
            direct_cases = @(
                @{ id = 200; title = "User account exists" }
            )
        }
        $result = & (Join-Path $checksDir "prerequisite_exists.ps1") -TestCases $design -Policy (New-TestPolicy)
        $result.status | Should -Be "Pass"
    }

    It "warns on duplicate prereq case_ids" {
        $design = New-ValidDesign
        $design.prereq_cases += @{
            case_id = 200
            title   = "Duplicate entry"
            usage   = "Duplicate"
        }
        $result = & (Join-Path $checksDir "prerequisite_exists.ps1") -TestCases $design -Policy (New-TestPolicy)
        $result.status | Should -Be "Warn"
    }
}

# ──────────────────────────────────────────────
# content_safety
# ──────────────────────────────────────────────
Describe "content_safety check" {

    # ── Clean / safe designs PASS ──

    It "passes for a fully safe design" {
        $result = & (Join-Path $checksDir "content_safety.ps1") -TestCases (New-ValidDesign) -Policy (New-TestPolicy)
        $result.name | Should -Be "content_safety"
        $result.status | Should -Be "Pass"
        $result.details.finding_count | Should -Be 0
    }

    # ── Destructive operations ──

    It "fails on DROP TABLE in a step action" {
        $design = New-ValidDesign
        $design.new_cases[0].steps += @{
            action   = "Run: DROP TABLE users;"
            expected = "Table is removed"
        }
        $result = & (Join-Path $checksDir "content_safety.ps1") -TestCases $design -Policy (New-TestPolicy)
        $result.status | Should -Be "Fail"
        ($result.details.findings | Where-Object { $_.pattern_id -eq "DESTRUCT_SQL_DROP" }).Count |
            Should -BeGreaterThan 0
    }

    It "fails on DROP DATABASE in title" {
        $design = New-ValidDesign
        $design.new_cases[0].title = "Verify DROP DATABASE cleanup runs"
        $result = & (Join-Path $checksDir "content_safety.ps1") -TestCases $design -Policy (New-TestPolicy)
        $result.status | Should -Be "Fail"
        ($result.details.findings | Where-Object { $_.pattern_id -eq "DESTRUCT_SQL_DROP" }).Count |
            Should -BeGreaterThan 0
    }

    It "fails on TRUNCATE TABLE" {
        $design = New-ValidDesign
        $design.new_cases[0].steps[0].action = "Execute TRUNCATE TABLE audit_log"
        $result = & (Join-Path $checksDir "content_safety.ps1") -TestCases $design -Policy (New-TestPolicy)
        $result.status | Should -Be "Fail"
        ($result.details.findings | Where-Object { $_.pattern_id -eq "DESTRUCT_SQL_TRUNCATE" }).Count |
            Should -BeGreaterThan 0
    }

    It "fails on DELETE FROM without WHERE" {
        $design = New-ValidDesign
        $design.new_cases[0].steps[0].action = "Run DELETE FROM orders;"
        $result = & (Join-Path $checksDir "content_safety.ps1") -TestCases $design -Policy (New-TestPolicy)
        $result.status | Should -Be "Fail"
        ($result.details.findings | Where-Object { $_.pattern_id -eq "DESTRUCT_SQL_DELETE_ALL" }).Count |
            Should -BeGreaterThan 0
    }

    It "fails on rm -rf" {
        $design = New-ValidDesign
        $design.new_cases[0].steps[0].action = "Clean up: rm -rf /var/data"
        $result = & (Join-Path $checksDir "content_safety.ps1") -TestCases $design -Policy (New-TestPolicy)
        $result.status | Should -Be "Fail"
        ($result.details.findings | Where-Object { $_.pattern_id -eq "DESTRUCT_SHELL_RM_RF" }).Count |
            Should -BeGreaterThan 0
    }

    It "detects destructive ops in enhance_cases" {
        $design = New-ValidDesign
        $design.enhance_cases[0].new_steps[0].action = "DROP TABLE temp_data"
        $result = & (Join-Path $checksDir "content_safety.ps1") -TestCases $design -Policy (New-TestPolicy)
        $result.status | Should -Be "Fail"
        ($result.details.findings | Where-Object { $_.path -match "enhance_cases" }).Count |
            Should -BeGreaterThan 0
    }

    # ── Hallucination indicators ──

    It "warns on example.com URL" {
        $design = New-ValidDesign
        $design.new_cases[0].steps[0].action = "Navigate to https://example.com/login"
        $result = & (Join-Path $checksDir "content_safety.ps1") -TestCases $design -Policy (New-TestPolicy)
        $result.status | Should -Be "Warn"
        ($result.details.findings | Where-Object { $_.pattern_id -eq "HALLUC_EXAMPLE_DOMAIN" }).Count |
            Should -BeGreaterThan 0
    }

    It "warns on lorem ipsum text" {
        $design = New-ValidDesign
        $design.new_cases[0].steps[0].expected = "Lorem ipsum dolor sit amet displayed"
        $result = & (Join-Path $checksDir "content_safety.ps1") -TestCases $design -Policy (New-TestPolicy)
        $result.status | Should -Be "Warn"
        ($result.details.findings | Where-Object { $_.pattern_id -eq "HALLUC_LOREM_IPSUM" }).Count |
            Should -BeGreaterThan 0
    }

    It "warns on TODO/FIXME markers" {
        $design = New-ValidDesign
        $design.new_cases[0].steps[0].expected = "TODO: fill in expected result"
        $result = & (Join-Path $checksDir "content_safety.ps1") -TestCases $design -Policy (New-TestPolicy)
        $result.status | Should -Be "Warn"
        ($result.details.findings | Where-Object { $_.pattern_id -eq "HALLUC_TODO_FIXME" }).Count |
            Should -BeGreaterThan 0
    }

    It "warns on localhost URL in step" {
        $design = New-ValidDesign
        $design.new_cases[0].steps[0].action = "Call http://localhost:3000/api/users"
        $result = & (Join-Path $checksDir "content_safety.ps1") -TestCases $design -Policy (New-TestPolicy)
        $result.status | Should -Be "Warn"
        ($result.details.findings | Where-Object { $_.pattern_id -eq "HALLUC_PLACEHOLDER_URL" }).Count |
            Should -BeGreaterThan 0
    }

    # ── Sensitive data exposure ──

    It "fails on hardcoded password" {
        $design = New-ValidDesign
        $design.new_cases[0].steps[0].action = "Enter password: SuperSecret123!"
        $result = & (Join-Path $checksDir "content_safety.ps1") -TestCases $design -Policy (New-TestPolicy)
        $result.status | Should -Be "Fail"
        ($result.details.findings | Where-Object { $_.pattern_id -eq "SENSITIVE_PASSWORD" }).Count |
            Should -BeGreaterThan 0
    }

    It "fails on hardcoded API key" {
        $design = New-ValidDesign
        $design.new_cases[0].steps[0].action = "Set header api_key=sk_live_abcdef1234567890"
        $result = & (Join-Path $checksDir "content_safety.ps1") -TestCases $design -Policy (New-TestPolicy)
        $result.status | Should -Be "Fail"
        ($result.details.findings | Where-Object { $_.pattern_id -eq "SENSITIVE_API_KEY" }).Count |
            Should -BeGreaterThan 0
    }

    It "fails on SSN pattern" {
        $design = New-ValidDesign
        $design.new_cases[0].steps[0].action = "Enter SSN 123-45-6789 in the form"
        $result = & (Join-Path $checksDir "content_safety.ps1") -TestCases $design -Policy (New-TestPolicy)
        $result.status | Should -Be "Fail"
        ($result.details.findings | Where-Object { $_.pattern_id -eq "SENSITIVE_SSN" }).Count |
            Should -BeGreaterThan 0
    }

    It "fails on connection string with credentials" {
        $design = New-ValidDesign
        $design.new_cases[0].steps[0].action = "Use connection: Server=prod-db;Database=main;Password=hunter2"
        $result = & (Join-Path $checksDir "content_safety.ps1") -TestCases $design -Policy (New-TestPolicy)
        $result.status | Should -Be "Fail"
        ($result.details.findings | Where-Object { $_.pattern_id -eq "SENSITIVE_CONN_STRING" }).Count |
            Should -BeGreaterThan 0
    }

    # ── Injection risk patterns ──

    It "fails on SQL injection pattern" {
        $design = New-ValidDesign
        $design.new_cases[0].steps[0].action = "Enter username: ' OR 1=1 --"
        $result = & (Join-Path $checksDir "content_safety.ps1") -TestCases $design -Policy (New-TestPolicy)
        $result.status | Should -Be "Fail"
        ($result.details.findings | Where-Object { $_.pattern_id -eq "INJECT_SQL" }).Count |
            Should -BeGreaterThan 0
    }

    It "fails on XSS script tags" {
        $design = New-ValidDesign
        $design.new_cases[0].steps[0].action = "Enter <script>alert('xss')</script> in name field"
        $result = & (Join-Path $checksDir "content_safety.ps1") -TestCases $design -Policy (New-TestPolicy)
        $result.status | Should -Be "Fail"
        ($result.details.findings | Where-Object { $_.pattern_id -eq "INJECT_XSS_SCRIPT" }).Count |
            Should -BeGreaterThan 0
    }

    # ── Severity aggregation ──

    It "reports correct severity counts" {
        $design = New-ValidDesign
        # Critical: DROP TABLE
        $design.new_cases[0].steps[0].action = "Run DROP TABLE users"
        # Medium: example.com
        $design.new_cases[0].steps[1].action = "Navigate to https://example.com/setup"
        $result = & (Join-Path $checksDir "content_safety.ps1") -TestCases $design -Policy (New-TestPolicy)
        $result.status | Should -Be "Fail"
        $result.details.by_severity.critical | Should -BeGreaterThan 0
        $result.details.by_severity.medium | Should -BeGreaterThan 0
    }

    It "returns Low findings as Pass" {
        $design = New-ValidDesign
        $design.new_cases[0].steps[0].action = "Log in as John Doe"
        $result = & (Join-Path $checksDir "content_safety.ps1") -TestCases $design -Policy (New-TestPolicy)
        $result.status | Should -Be "Pass"
        $result.details.by_severity.low | Should -BeGreaterThan 0
    }
}
