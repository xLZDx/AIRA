Describe "Integration - Confluence" {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../../..")).Path
        $script:confScript = Join-Path $repoRoot "core/scripts/confluence.ps1"

        $configModule = Join-Path $repoRoot "core/modules/Aira.Config.psm1"
        Import-Module $configModule -Force
        try {
            $script:policy = Get-AiraPolicy -PolicyRoot (Join-Path $repoRoot ".aira")
        } catch {
            $script:policy = $null
        }
        try { $script:creds = Get-AiraCredentials -RepoRoot $repoRoot } catch { $script:creds = $null }
    }

    It "can authenticate to Confluence when enabled by policy (read-only)" {
        # Use Windows PowerShell
        $psCmd = "powershell"

        $enabled = $true
        if ($script:policy -and $script:policy.context -and ($script:policy.context.PSObject.Properties.Name -contains "include_confluence")) {
            $enabled = [bool]$script:policy.context.include_confluence
        }

        if (-not $enabled) {
            Set-ItResult -Skipped -Because "Confluence integration disabled by policy."
        }

        $url   = if ($script:creds) { $script:creds.confluence.url } else { "" }
        $email = if ($script:creds) { $script:creds.confluence.email } else { "" }
        $token = if ($script:creds) { $script:creds.confluence.api_token } else { "" }
        if (-not $url -or (-not $email -and -not $token)) {
            Set-ItResult -Skipped -Because "CONFLUENCE_URL / CONFLUENCE_EMAIL / CONFLUENCE_API_TOKEN not configured."
        }

        Test-Path $script:confScript | Should -BeTrue

        $out = & $psCmd -NoProfile -File $script:confScript -TestConnection 2>&1
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

