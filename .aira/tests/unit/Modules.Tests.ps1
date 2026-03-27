Describe "AIRA Core Modules" {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../../..")).Path
        $modulesRoot = Join-Path $repoRoot "core/modules"
        $script:modulePaths = @(
            (Join-Path $modulesRoot "Aira.Common.psm1"),
            (Join-Path $modulesRoot "Aira.Config.psm1"),
            (Join-Path $modulesRoot "Aira.Session.psm1"),
            (Join-Path $modulesRoot "Aira.Cache.psm1"),
            (Join-Path $modulesRoot "Aira.Validation.psm1"),
            (Join-Path $modulesRoot "Aira.JiraText.psm1"),
            (Join-Path $modulesRoot "Aira.Templating.psm1"),
            (Join-Path $modulesRoot "Aira.Telemetry.psm1"),
            (Join-Path $modulesRoot "Aira.Memory.psm1")
        )
    }

    It "imports all core modules without errors" {
        foreach ($p in $script:modulePaths) {
            Test-Path $p | Should -BeTrue
            { Import-Module $p -Force } | Should -Not -Throw
        }
    }
}

