Describe "Integration - TestRail" {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../../..")).Path
        $script:trScript = Join-Path $repoRoot "core/scripts/testrail.ps1"
        $configModule = Join-Path $repoRoot "core/modules/Aira.Config.psm1"
        Import-Module $configModule -Force
        try { $script:creds = Get-AiraCredentials -RepoRoot $repoRoot } catch { $script:creds = $null }
    }

    It "can authenticate to TestRail (read-only)" {
        $url      = if ($script:creds) { $script:creds.testrail.url } else { "" }
        $username = if ($script:creds) { $script:creds.testrail.username } else { "" }
        $apiKey   = if ($script:creds) { $script:creds.testrail.api_key } else { "" }
        if (-not $url -or (-not $username -and -not $apiKey)) {
            Set-ItResult -Skipped -Because "TESTRAIL_URL / TESTRAIL_USERNAME / TESTRAIL_API_KEY not configured."
        }

        # Use Windows PowerShell
        $psCmd = "powershell"

        Test-Path $script:trScript | Should -BeTrue

        $out = & $psCmd -NoProfile -File $script:trScript -TestConnection 2>&1
        $code = $LASTEXITCODE

        $code | Should -Be 0
    }
}

