BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../../..")).Path
    $checksDir = Join-Path $repoRoot "core/validation/checks"

    $commonModule     = Join-Path $repoRoot "core/modules/Aira.Common.psm1"
    $validationModule = Join-Path $repoRoot "core/modules/Aira.Validation.psm1"
    $configModule     = Join-Path $repoRoot "core/modules/Aira.Config.psm1"

    Import-Module $commonModule     -Force -WarningAction SilentlyContinue
    Import-Module $validationModule -Force -WarningAction SilentlyContinue
    Import-Module $configModule     -Force -WarningAction SilentlyContinue

    # Policy object for tests
    function New-TestPolicy {
        return @{
            testrail = @{
                restrictions = @{
                    forbidden_priorities   = @("Blocker")
                    require_jira_reference = $true
                    max_cases_per_batch    = 50
                }
            }
            validation = @{
                enabled_checks = @("context_integrity")
            }
        }
    }

    # Create a minimal but valid context directory in temp
    function New-CleanContext {
        param([string]$Root)

        $srcDir = Join-Path $Root "sources"
        New-Item -ItemType Directory -Path $srcDir -Force | Out-Null

        # issue.json
        $issue = @{
            key    = "TEST-1"
            fields = @{
                summary     = "Test story for validation"
                description = "As a user I want validation so that context is reliable."
                issuetype   = @{ name = "Story" }
                status      = @{ name = "In Progress" }
                priority    = @{ name = "High" }
                created     = "2025-01-01T10:00:00"
                updated     = "2025-01-01T12:00:00"
            }
        }
        $issueJson = $issue | ConvertTo-Json -Depth 10
        $issuePath = Join-Path $srcDir "issue.json"
        $issueJson | Out-File -FilePath $issuePath -Encoding UTF8

        # comments.json
        $comments = @(@{ id = 1; body = "First comment"; author = "tester"; created = "2025-01-01" })
        $commentsJson = $comments | ConvertTo-Json -Depth 10
        $commentsPath = Join-Path $srcDir "comments.json"
        $commentsJson | Out-File -FilePath $commentsPath -Encoding UTF8

        # linked_issues.json
        $linked = @(@{ key = "TEST-2"; type = "blocks"; direction = "outward"; summary = "Dependency" })
        $linkedJson = $linked | ConvertTo-Json -Depth 10
        $linkedPath = Join-Path $srcDir "linked_issues.json"
        $linkedJson | Out-File -FilePath $linkedPath -Encoding UTF8

        # context.md
        $contextMd = @"
# TEST-1: Test story for validation

## Issue
| Field | Value |
|-------|-------|
| Key | TEST-1 |
| Type | Story |
| Status | In Progress |

## Description
As a user I want validation so that context is reliable.

## Acceptance Criteria
- Context must pass integrity checks
- All source files must be present

## Direct Dependencies
| Key | Type | Summary |
|-----|------|---------|
| TEST-2 | blocks | Dependency |

## References & Links
- Jira: https://example.atlassian.net/browse/TEST-1
"@
        $contextMdPath = Join-Path $Root "context.md"
        $contextMd | Out-File -FilePath $contextMdPath -Encoding UTF8

        # Compute hashes
        function Local-Hash([string]$Path) {
            $bytes = [System.IO.File]::ReadAllBytes($Path)
            $sha = [System.Security.Cryptography.SHA256]::Create()
            $hash = $sha.ComputeHash($bytes)
            return ($hash | ForEach-Object { $_.ToString("x2") }) -join ''
        }

        # manifest.json
        $manifest = @{
            jira_key       = "TEST-1"
            context_status = "raw"
            scraped_at     = (Get-Date).ToString("s")
            last_updated   = (Get-Date).ToString("s")
            dependency_depth = 0
            dependency_keys  = @()
            confluence_page_ids = @()
            attachment_extractions = @()
            context_md_path = "context/local/TEST/TEST-1/context.md"
            local_data_path = "context/local/TEST/TEST-1"
            hashes = @{
                issue         = Local-Hash $issuePath
                comments      = Local-Hash $commentsPath
                linked_issues = Local-Hash $linkedPath
                context_md    = Local-Hash $contextMdPath
            }
            diffs = @()
        }
        $manifestPath = Join-Path $Root "manifest.json"
        $manifest | ConvertTo-Json -Depth 10 | Out-File -FilePath $manifestPath -Encoding UTF8

        return $Root
    }

    # Global temp directory for all tests
    $script:tempBase = Join-Path ([System.IO.Path]::GetTempPath()) "aira_ctx_test_$([guid]::NewGuid().ToString('N').Substring(0,8))"
    New-Item -ItemType Directory -Path $script:tempBase -Force | Out-Null
}

AfterAll {
    if (Test-Path $script:tempBase) {
        Remove-Item -Path $script:tempBase -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ============================================================================
# context_integrity.ps1 -- direct check execution
# ============================================================================
Describe "context_integrity check" {

    It "passes for a fully valid context directory" {
        $ctxDir = Join-Path $script:tempBase "clean_1"
        New-Item -ItemType Directory -Path $ctxDir -Force | Out-Null
        New-CleanContext -Root $ctxDir

        $policy = New-TestPolicy
        $result = & (Join-Path $checksDir "context_integrity.ps1") -ContextPath $ctxDir -Policy $policy
        $result.name   | Should -Be "context_integrity"
        $result.status | Should -Be "Pass"
        $result.summary.finding_count | Should -Be 0
    }

    It "returns Critical when manifest.json is missing" {
        $ctxDir = Join-Path $script:tempBase "no_manifest"
        New-Item -ItemType Directory -Path $ctxDir -Force | Out-Null
        New-CleanContext -Root $ctxDir
        Remove-Item (Join-Path $ctxDir "manifest.json") -Force

        $policy = New-TestPolicy
        $result = & (Join-Path $checksDir "context_integrity.ps1") -ContextPath $ctxDir -Policy $policy
        $result.status | Should -Be "Fail"
        $crit = @($result.findings | Where-Object { $_.severity -eq "Critical" -and $_.field -eq "manifest.json" })
        $crit.Count | Should -BeGreaterThan 0
    }

    It "returns Critical when context.md is missing" {
        $ctxDir = Join-Path $script:tempBase "no_contextmd"
        New-Item -ItemType Directory -Path $ctxDir -Force | Out-Null
        New-CleanContext -Root $ctxDir
        Remove-Item (Join-Path $ctxDir "context.md") -Force

        $policy = New-TestPolicy
        $result = & (Join-Path $checksDir "context_integrity.ps1") -ContextPath $ctxDir -Policy $policy
        $result.status | Should -Be "Fail"
        $crit = @($result.findings | Where-Object { $_.severity -eq "Critical" -and $_.field -eq "context.md" })
        $crit.Count | Should -BeGreaterThan 0
    }

    It "returns High when a required source file is missing" {
        $ctxDir = Join-Path $script:tempBase "no_issue"
        New-Item -ItemType Directory -Path $ctxDir -Force | Out-Null
        New-CleanContext -Root $ctxDir
        Remove-Item (Join-Path $ctxDir "sources/issue.json") -Force

        $policy = New-TestPolicy
        $result = & (Join-Path $checksDir "context_integrity.ps1") -ContextPath $ctxDir -Policy $policy
        $high = @($result.findings | Where-Object { $_.severity -eq "High" -and $_.field -eq "sources/issue.json" })
        $high.Count | Should -BeGreaterThan 0
    }

    It "returns High when a source file is empty" {
        $ctxDir = Join-Path $script:tempBase "empty_src"
        New-Item -ItemType Directory -Path $ctxDir -Force | Out-Null
        New-CleanContext -Root $ctxDir
        "" | Out-File -FilePath (Join-Path $ctxDir "sources/comments.json") -Encoding UTF8

        $policy = New-TestPolicy
        $result = & (Join-Path $checksDir "context_integrity.ps1") -ContextPath $ctxDir -Policy $policy
        $high = @($result.findings | Where-Object { $_.severity -eq "High" -and $_.field -eq "sources/comments.json" })
        $high.Count | Should -BeGreaterThan 0
    }

    It "flags stale context older than 30 days" {
        $ctxDir = Join-Path $script:tempBase "stale_ctx"
        New-Item -ItemType Directory -Path $ctxDir -Force | Out-Null
        New-CleanContext -Root $ctxDir

        # Patch manifest with old scraped_at
        $mPath = Join-Path $ctxDir "manifest.json"
        $m = Get-Content $mPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $m.scraped_at = (Get-Date).AddDays(-45).ToString("s")
        $m | ConvertTo-Json -Depth 10 | Out-File -FilePath $mPath -Encoding UTF8

        $policy = New-TestPolicy
        $result = & (Join-Path $checksDir "context_integrity.ps1") -ContextPath $ctxDir -Policy $policy
        $stale = @($result.findings | Where-Object { $_.category -eq "quality" -and $_.description -match "days old" })
        $stale.Count | Should -BeGreaterThan 0
    }

    It "flags missing context.md sections" {
        $ctxDir = Join-Path $script:tempBase "missing_sec"
        New-Item -ItemType Directory -Path $ctxDir -Force | Out-Null
        New-CleanContext -Root $ctxDir

        # Replace context.md with minimal content missing sections
        $ctxMdPath = Join-Path $ctxDir "context.md"
        "# TEST-1`n`n## Issue`n| Key | TEST-1 |`n" | Out-File -FilePath $ctxMdPath -Encoding UTF8

        # Re-hash so integrity check passes
        $bytes = [System.IO.File]::ReadAllBytes($ctxMdPath)
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $hash = ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join ''
        $mPath = Join-Path $ctxDir "manifest.json"
        $m = Get-Content $mPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $m.hashes.context_md = $hash
        $m | ConvertTo-Json -Depth 10 | Out-File -FilePath $mPath -Encoding UTF8

        $policy = New-TestPolicy
        $result = & (Join-Path $checksDir "context_integrity.ps1") -ContextPath $ctxDir -Policy $policy
        $missing = @($result.findings | Where-Object { $_.description -match "Missing required section" })
        $missing.Count | Should -BeGreaterOrEqual 3
    }

    It "flags TBD/TODO placeholders in context.md" {
        $ctxDir = Join-Path $script:tempBase "placeholder_ctx"
        New-Item -ItemType Directory -Path $ctxDir -Force | Out-Null
        New-CleanContext -Root $ctxDir

        # Inject placeholders
        $ctxMdPath = Join-Path $ctxDir "context.md"
        $content = Get-Content $ctxMdPath -Raw -Encoding UTF8
        $content = $content + "`n`nSome note [TBD] and another [TODO] item.`n"
        $content | Out-File -FilePath $ctxMdPath -Encoding UTF8

        # Re-hash
        $bytes = [System.IO.File]::ReadAllBytes($ctxMdPath)
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $hash = ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join ''
        $mPath = Join-Path $ctxDir "manifest.json"
        $m = Get-Content $mPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $m.hashes.context_md = $hash
        $m | ConvertTo-Json -Depth 10 | Out-File -FilePath $mPath -Encoding UTF8

        $policy = New-TestPolicy
        $result = & (Join-Path $checksDir "context_integrity.ps1") -ContextPath $ctxDir -Policy $policy
        $placeholders = @($result.findings | Where-Object { $_.description -match "TBD|TODO" })
        $placeholders.Count | Should -BeGreaterThan 0
    }

    It "detects PII (SSN pattern) in source data" {
        $ctxDir = Join-Path $script:tempBase "pii_ssn"
        New-Item -ItemType Directory -Path $ctxDir -Force | Out-Null
        New-CleanContext -Root $ctxDir

        # Inject SSN into comments
        $commPath = Join-Path $ctxDir "sources/comments.json"
        $comments = @(@{ id = 1; body = "SSN is 123-45-6789 for test"; author = "leak"; created = "2025-01-01" })
        $comments | ConvertTo-Json -Depth 5 | Out-File -FilePath $commPath -Encoding UTF8

        # Re-hash
        $bytes = [System.IO.File]::ReadAllBytes($commPath)
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $hash = ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join ''
        $mPath = Join-Path $ctxDir "manifest.json"
        $m = Get-Content $mPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $m.hashes.comments = $hash
        $m | ConvertTo-Json -Depth 10 | Out-File -FilePath $mPath -Encoding UTF8

        $policy = New-TestPolicy
        $result = & (Join-Path $checksDir "context_integrity.ps1") -ContextPath $ctxDir -Policy $policy
        $pii = @($result.findings | Where-Object { $_.category -eq "safety" -and $_.description -match "SSN" })
        $pii.Count | Should -BeGreaterThan 0
    }

    It "detects hardcoded credentials in source data" {
        $ctxDir = Join-Path $script:tempBase "creds_ctx"
        New-Item -ItemType Directory -Path $ctxDir -Force | Out-Null
        New-CleanContext -Root $ctxDir

        # Write JSON directly to preserve actual single-quote characters in the file.
        # ConvertTo-Json escapes ' as \u0027 which the raw-file regex cannot match.
        $issuePath = Join-Path $ctxDir "sources/issue.json"
        $rawJson = "{""key"":""TEST-1"",""fields"":{""summary"":""Test story"",""description"":""Connect using password = 'SuperSecret123Abc' to the DB."",""issuetype"":{""name"":""Story""},""status"":{""name"":""In Progress""},""priority"":{""name"":""High""}}}"
        $rawJson | Out-File -FilePath $issuePath -Encoding UTF8

        # Re-hash
        $bytes = [System.IO.File]::ReadAllBytes($issuePath)
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $hash = ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join ''
        $mPath = Join-Path $ctxDir "manifest.json"
        $m = Get-Content $mPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $m.hashes.issue = $hash
        $m | ConvertTo-Json -Depth 10 | Out-File -FilePath $mPath -Encoding UTF8

        $policy = New-TestPolicy
        $result = & (Join-Path $checksDir "context_integrity.ps1") -ContextPath $ctxDir -Policy $policy
        $cred = @($result.findings | Where-Object { $_.category -eq "safety" -and $_.description -match "credential" })
        $cred.Count | Should -BeGreaterThan 0
        $cred[0].severity | Should -Be "Critical"
    }

    It "detects hash mismatch (integrity failure)" {
        $ctxDir = Join-Path $script:tempBase "hash_mismatch"
        New-Item -ItemType Directory -Path $ctxDir -Force | Out-Null
        New-CleanContext -Root $ctxDir

        # Modify issue.json after manifest was created (hash now wrong)
        $issuePath = Join-Path $ctxDir "sources/issue.json"
        $issue = @{ key = "TEST-1"; fields = @{ summary = "Modified!"; description = "Changed."; issuetype = @{ name = "Story" } } }
        $issue | ConvertTo-Json -Depth 10 | Out-File -FilePath $issuePath -Encoding UTF8

        $policy = New-TestPolicy
        $result = & (Join-Path $checksDir "context_integrity.ps1") -ContextPath $ctxDir -Policy $policy
        $integrity = @($result.findings | Where-Object { $_.category -eq "integrity" -and $_.description -match "Hash mismatch" })
        $integrity.Count | Should -BeGreaterThan 0
        $integrity[0].severity | Should -Be "High"
    }

    It "flags Bug issue type as not a valid requirement source" {
        $ctxDir = Join-Path $script:tempBase "bug_type"
        New-Item -ItemType Directory -Path $ctxDir -Force | Out-Null
        New-CleanContext -Root $ctxDir

        $issuePath = Join-Path $ctxDir "sources/issue.json"
        $issue = @{
            key    = "BUG-1"
            fields = @{
                summary     = "Something is broken"
                description = "Steps to reproduce the bug."
                issuetype   = @{ name = "Bug" }
                status      = @{ name = "Open" }
                priority    = @{ name = "High" }
            }
        }
        $issue | ConvertTo-Json -Depth 10 | Out-File -FilePath $issuePath -Encoding UTF8

        # Re-hash
        $bytes = [System.IO.File]::ReadAllBytes($issuePath)
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $hash = ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join ''
        $mPath = Join-Path $ctxDir "manifest.json"
        $m = Get-Content $mPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $m.hashes.issue = $hash
        $m | ConvertTo-Json -Depth 10 | Out-File -FilePath $mPath -Encoding UTF8

        $policy = New-TestPolicy
        $result = & (Join-Path $checksDir "context_integrity.ps1") -ContextPath $ctxDir -Policy $policy
        $bug = @($result.findings | Where-Object { $_.description -match "Bug" })
        $bug.Count | Should -BeGreaterThan 0
    }

    It "flags missing dependency folder for declared dependency" {
        $ctxDir = Join-Path $script:tempBase "missing_dep"
        New-Item -ItemType Directory -Path $ctxDir -Force | Out-Null
        New-CleanContext -Root $ctxDir

        # Add dependency key without creating the folder
        $mPath = Join-Path $ctxDir "manifest.json"
        $m = Get-Content $mPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $m.dependency_keys = @("DEP-99")
        $m | ConvertTo-Json -Depth 10 | Out-File -FilePath $mPath -Encoding UTF8

        $policy = New-TestPolicy
        $result = & (Join-Path $checksDir "context_integrity.ps1") -ContextPath $ctxDir -Policy $policy
        $dep = @($result.findings | Where-Object { $_.category -eq "integrity" -and $_.description -match "DEP-99" })
        $dep.Count | Should -BeGreaterThan 0
    }

    It "returns correct by_category breakdown in summary" {
        $ctxDir = Join-Path $script:tempBase "category_check"
        New-Item -ItemType Directory -Path $ctxDir -Force | Out-Null
        New-CleanContext -Root $ctxDir

        $policy = New-TestPolicy
        $result = & (Join-Path $checksDir "context_integrity.ps1") -ContextPath $ctxDir -Policy $policy
        $result.summary.by_category.structure | Should -BeOfType [int]
        $result.summary.by_category.quality   | Should -BeOfType [int]
        $result.summary.by_category.safety    | Should -BeOfType [int]
        $result.summary.by_category.integrity | Should -BeOfType [int]
    }
}

# ============================================================================
# Invoke-AiraContextValidation -- module wrapper
# ============================================================================
Describe "Invoke-AiraContextValidation" {

    It "returns context_integrity result for valid context" {
        $ctxDir = Join-Path $script:tempBase "mod_valid"
        New-Item -ItemType Directory -Path $ctxDir -Force | Out-Null
        New-CleanContext -Root $ctxDir

        $policy = New-TestPolicy
        $result = Invoke-AiraContextValidation -ContextPath $ctxDir -Policy $policy
        $result.name   | Should -Be "context_integrity"
        $result.status | Should -Be "Pass"
    }

    It "detects issues through the module wrapper" {
        $ctxDir = Join-Path $script:tempBase "mod_broken"
        New-Item -ItemType Directory -Path $ctxDir -Force | Out-Null
        New-CleanContext -Root $ctxDir
        Remove-Item (Join-Path $ctxDir "manifest.json") -Force

        $policy = New-TestPolicy
        $result = Invoke-AiraContextValidation -ContextPath $ctxDir -Policy $policy
        $result.status | Should -Be "Fail"
    }
}

# ============================================================================
# Invoke-AiraContextPromote -- lifecycle promotion
# ============================================================================
Describe "Invoke-AiraContextPromote" {

    It "promotes clean context to processed status" {
        $ctxDir = Join-Path $script:tempBase "promo_clean"
        New-Item -ItemType Directory -Path $ctxDir -Force | Out-Null
        New-CleanContext -Root $ctxDir

        $policy = New-TestPolicy
        $result = Invoke-AiraContextPromote -ContextPath $ctxDir -Policy $policy
        $result.promoted | Should -Be $true
        $result.reason   | Should -Match "promoted"

        # Verify manifest was updated
        $m = Get-Content (Join-Path $ctxDir "manifest.json") -Raw -Encoding UTF8 | ConvertFrom-Json
        $m.context_status | Should -Be "processed"
        $m.processed_at   | Should -Not -BeNullOrEmpty
        $m.last_validation.promoted | Should -Be $true
    }

    It "blocks promotion when Critical findings exist" {
        $ctxDir = Join-Path $script:tempBase "promo_crit"
        New-Item -ItemType Directory -Path $ctxDir -Force | Out-Null
        New-CleanContext -Root $ctxDir
        # Remove context.md to trigger Critical finding
        Remove-Item (Join-Path $ctxDir "context.md") -Force

        $policy = New-TestPolicy
        $result = Invoke-AiraContextPromote -ContextPath $ctxDir -Policy $policy
        $result.promoted | Should -Be $false
        $result.reason   | Should -Match "Critical"

        # Manifest remains raw
        $m = Get-Content (Join-Path $ctxDir "manifest.json") -Raw -Encoding UTF8 | ConvertFrom-Json
        $m.context_status | Should -Be "raw"
    }

    It "blocks promotion on High findings without UserApproved" {
        $ctxDir = Join-Path $script:tempBase "promo_high"
        New-Item -ItemType Directory -Path $ctxDir -Force | Out-Null
        New-CleanContext -Root $ctxDir
        # Remove a required source to trigger High finding
        Remove-Item (Join-Path $ctxDir "sources/issue.json") -Force

        $policy = New-TestPolicy
        $result = Invoke-AiraContextPromote -ContextPath $ctxDir -Policy $policy
        $result.promoted | Should -Be $false
        $result.reason   | Should -Match "High|approval"
    }

    It "allows promotion with High findings when UserApproved" {
        $ctxDir = Join-Path $script:tempBase "promo_approved"
        New-Item -ItemType Directory -Path $ctxDir -Force | Out-Null
        New-CleanContext -Root $ctxDir
        # Remove a required source to trigger High finding (not Critical)
        Remove-Item (Join-Path $ctxDir "sources/issue.json") -Force

        $policy = New-TestPolicy
        $result = Invoke-AiraContextPromote -ContextPath $ctxDir -Policy $policy -UserApproved
        $result.promoted | Should -Be $true

        $m = Get-Content (Join-Path $ctxDir "manifest.json") -Raw -Encoding UTF8 | ConvertFrom-Json
        $m.context_status | Should -Be "processed"
        $m.last_validation.user_approved | Should -Be $true
    }

    It "returns promoted=false when manifest is missing" {
        $ctxDir = Join-Path $script:tempBase "promo_nomanifest"
        New-Item -ItemType Directory -Path $ctxDir -Force | Out-Null
        New-CleanContext -Root $ctxDir
        Remove-Item (Join-Path $ctxDir "manifest.json") -Force

        $policy = New-TestPolicy
        $result = Invoke-AiraContextPromote -ContextPath $ctxDir -Policy $policy
        $result.promoted | Should -Be $false
        $result.reason   | Should -Match "Manifest not found|Critical"
    }
}
