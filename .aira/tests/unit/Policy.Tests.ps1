Describe "AIRA Policy System" {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../../..")).Path
        $configModule = Join-Path $repoRoot "core/modules/Aira.Config.psm1"
        Import-Module $configModule -Force
    }

    It "loads effective policy (schema + admin + team merged)" {
        { $script:policy = Get-AiraPolicy -PolicyRoot (Join-Path $repoRoot ".aira") } | Should -Not -Throw
        $script:policy | Should -Not -BeNullOrEmpty
        $script:policy.testrail.restrictions.max_cases_per_batch | Should -BeGreaterThan 0
        # Critical is NOT forbidden — all Jira priority levels are valid for test cases
        ($script:policy.testrail.restrictions.forbidden_priorities -contains "Critical") | Should -BeFalse
    }

    It "loads effective policy with optional user preferences overlay" {
        $script:ep = $null
        { $script:ep = Get-AiraEffectivePolicy -PolicyRoot (Join-Path $repoRoot ".aira") -RepoRoot $repoRoot } | Should -Not -Throw
        $script:ep | Should -Not -BeNullOrEmpty
        $script:ep.testrail.restrictions.max_cases_per_batch | Should -BeGreaterThan 0
    }
}

