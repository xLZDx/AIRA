Describe "Integration - Jira" {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../../..")).Path
        $script:jiraScript = Join-Path $repoRoot "core/scripts/jira.ps1"
        $configModule = Join-Path $repoRoot "core/modules/Aira.Config.psm1"
        Import-Module $configModule -Force
        try { $script:creds = Get-AiraCredentials -RepoRoot $repoRoot } catch { $script:creds = $null }
    }

    It "can authenticate to Jira (read-only)" {
        $url   = if ($script:creds) { $script:creds.jira.url } else { "" }
        $email = if ($script:creds) { $script:creds.jira.email } else { "" }
        $token = if ($script:creds) { $script:creds.jira.api_token } else { "" }
        if (-not $url -or (-not $email -and -not $token)) {
            Set-ItResult -Skipped -Because "JIRA_URL / JIRA_EMAIL / JIRA_API_TOKEN not configured."
        }

        # Use Windows PowerShell
        $psCmd = "powershell"

        Test-Path $script:jiraScript | Should -BeTrue

        $out = & $psCmd -NoProfile -File $script:jiraScript -TestConnection 2>&1
        $code = $LASTEXITCODE

        $code | Should -Be 0

        $jsonStrRaw = $out | Out-String
        $jsonStartIndex = $jsonStrRaw.IndexOf("{")
        if ($jsonStartIndex -ge 0) {
            $json = $jsonStrRaw.Substring($jsonStartIndex).Trim()
            $result = $json | ConvertFrom-Json
            $result.status | Should -Be "ok"
        } else {
             throw "No JSON output found. Output: $jsonStrRaw"
        }
    }
}

