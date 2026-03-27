Describe "Integration - Bitbucket" {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../../..")).Path
        $configModule = Join-Path $repoRoot "core/modules/Aira.Config.psm1"
        Import-Module $configModule -Force
        $script:creds = Get-AiraCredentials -RepoRoot $repoRoot
    }

    It "can authenticate to Bitbucket Cloud when app password configured (read-only)" {
        $user = $script:creds.bitbucket.username
        $appPw = $script:creds.bitbucket.app_password
        if (-not $user -or -not $appPw) {
            Set-ItResult -Skipped -Because "BITBUCKET_USERNAME / BITBUCKET_APP_PASSWORD not configured."
        }

        $base = $script:creds.bitbucket.base_url
        if (-not $base) { $base = "https://bitbucket.org" }
        $base = $base.TrimEnd("/")

        if ($base -ne "https://bitbucket.org") {
            Set-ItResult -Skipped -Because "Bitbucket Server/Data Center API readiness test not implemented (base_url != https://bitbucket.org)."
        }

        $pair = "{0}:{1}" -f $user, $appPw
        $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pair))
        $headers = @{
            "Authorization" = "Basic $b64"
            "Accept" = "application/json"
            "User-Agent" = "AIRA-v2-readiness"
        }

        $url = "https://api.bitbucket.org/2.0/user"
        try {
            $me = Invoke-RestMethod -Uri $url -Method Get -Headers $headers
            $name = if ($null -ne $me.username) { $me.username } elseif ($null -ne $me.display_name) { $me.display_name } else { "" }
            $name | Should -Not -BeNullOrEmpty
        } catch {
            throw "Bitbucket connectivity/auth failed. Check BITBUCKET_USERNAME and BITBUCKET_APP_PASSWORD. Error: $($_.Exception.Message)"
        }
    }
}

