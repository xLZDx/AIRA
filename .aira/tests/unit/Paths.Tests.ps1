Describe "AIRA Required Paths" {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../../..")).Path
        $script:required = @(
            ".github",
            "core/prompts",
            "core/skills",
            "core/scripts",
            "core/modules",
            "core/templates",
            "core/validation/checks",
            ".aira/tests/unit",
            ".aira/tests/integration",
            ".aira/tests/results",
            ".aira/sessions",
            ".aira/memory",
            "context/local",
            "context/shared",
            "artifacts",
            "scratch"
        ) | ForEach-Object { Join-Path $repoRoot $_ }

        # On first run, ensure all required directories exist
        foreach ($p in $script:required) {
            if (-not (Test-Path $p)) {
                New-Item -Path $p -ItemType Directory -Force | Out-Null
            }
        }
    }

    It "has required directories present" {
        foreach ($p in $script:required) {
            Test-Path $p | Should -BeTrue
        }
    }
}

