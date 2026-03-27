Describe "Integration - GitHub" {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../../..")).Path
        $configModule = Join-Path $repoRoot "core/modules/Aira.Config.psm1"
        Import-Module $configModule -Force
        $script:creds = Get-AiraCredentials -RepoRoot $repoRoot
    }

    It "can authenticate to GitHub when token configured (read-only)" {
        $token = $script:creds.github.token
        if (-not $token) {
            Set-ItResult -Skipped -Because "GITHUB_TOKEN not configured."
        }

        $base = $script:creds.github.base_url
        if (-not $base) { $base = "https://github.com" }
        $base = $base.TrimEnd("/")

        $apiBase = if ($base -eq "https://github.com") { "https://api.github.com" } else { "$base/api/v3" }
        $url = "$apiBase/user"

        $headers = @{
            "Authorization" = "Bearer $token"
            "Accept" = "application/vnd.github+json"
            "User-Agent" = "AIRA-v2-readiness"
        }

        try {
            $me = Invoke-RestMethod -Uri $url -Method Get -Headers $headers
            $login = if ($null -ne $me.login) { $me.login } else { "" }
            $login | Should -Not -BeNullOrEmpty
        } catch {
            throw "GitHub connectivity/auth failed. Check GITHUB_BASE_URL and GITHUB_TOKEN. Error: $($_.Exception.Message)"
        }
    }
}

