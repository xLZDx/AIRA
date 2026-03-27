Describe "AIRA Resource Resolution Precedence" {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../../..")).Path
        $configModule = Join-Path $repoRoot "core/modules/Aira.Config.psm1"
        Import-Module $configModule -Force
    }

    It "resolves core template when no override exists" {
        $resolved = Resolve-AiraResourcePath -Kind templates -Name "spec_template.md" -RepoRoot $repoRoot
        $resolved | Should -Not -BeNullOrEmpty
        $resolved.Replace('\','/') | Should -Match "core/templates/spec_template\.md$"
    }

    It "prefers overrides over core" {
        $overridePath = Join-Path $repoRoot "overrides/templates/spec_template.md"
        $overrideDir = Split-Path -Parent $overridePath
        if (-not (Test-Path $overrideDir)) { New-Item -ItemType Directory -Path $overrideDir -Force | Out-Null }

        try {
            "OVERRIDE TEMPLATE" | Out-File -FilePath $overridePath -Encoding UTF8
            $resolved = Resolve-AiraResourcePath -Kind templates -Name "spec_template.md" -RepoRoot $repoRoot
            $resolved.Replace('\','/') | Should -Match "overrides/templates/spec_template\.md$"
        } finally {
            if (Test-Path $overridePath) { Remove-Item $overridePath -Force }
        }
    }

    It "skips disabled plugins" {
        $pluginDir = Join-Path $repoRoot "plugins/test-disabled-plugin/templates"
        $pluginManifest = Join-Path $repoRoot "plugins/test-disabled-plugin/manifest.json"

        try {
            New-Item -ItemType Directory -Path $pluginDir -Force | Out-Null
            '{"name":"test-disabled-plugin","enabled":false,"load_order":1}' | Out-File -FilePath $pluginManifest -Encoding UTF8
            "DISABLED PLUGIN TEMPLATE" | Out-File -FilePath (Join-Path $pluginDir "unique_test_resource.md") -Encoding UTF8

            $resolved = Resolve-AiraResourcePath -Kind templates -Name "unique_test_resource.md" -RepoRoot $repoRoot
            $resolved | Should -BeNullOrEmpty
        } finally {
            $pluginRoot = Join-Path $repoRoot "plugins/test-disabled-plugin"
            if (Test-Path $pluginRoot) { Remove-Item -Recurse -Force $pluginRoot }
        }
    }

    It "resolves from enabled plugins" {
        $pluginDir = Join-Path $repoRoot "plugins/test-enabled-plugin/templates"
        $pluginManifest = Join-Path $repoRoot "plugins/test-enabled-plugin/manifest.json"

        try {
            New-Item -ItemType Directory -Path $pluginDir -Force | Out-Null
            '{"name":"test-enabled-plugin","enabled":true,"load_order":1}' | Out-File -FilePath $pluginManifest -Encoding UTF8
            "ENABLED PLUGIN TEMPLATE" | Out-File -FilePath (Join-Path $pluginDir "unique_test_resource2.md") -Encoding UTF8

            $resolved = Resolve-AiraResourcePath -Kind templates -Name "unique_test_resource2.md" -RepoRoot $repoRoot
            $resolved | Should -Not -BeNullOrEmpty
            $resolved.Replace('\','/') | Should -Match "plugins/test-enabled-plugin/templates/unique_test_resource2\.md$"
        } finally {
            $pluginRoot = Join-Path $repoRoot "plugins/test-enabled-plugin"
            if (Test-Path $pluginRoot) { Remove-Item -Recurse -Force $pluginRoot }
        }
    }

    It "prefers lower load_order plugin over higher" {
        $pluginA = Join-Path $repoRoot "plugins/test-plugin-a"
        $pluginB = Join-Path $repoRoot "plugins/test-plugin-b"

        try {
            New-Item -ItemType Directory -Path (Join-Path $pluginA "templates") -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $pluginB "templates") -Force | Out-Null
            '{"name":"test-plugin-a","enabled":true,"load_order":100}' | Out-File -FilePath (Join-Path $pluginA "manifest.json") -Encoding UTF8
            '{"name":"test-plugin-b","enabled":true,"load_order":10}' | Out-File -FilePath (Join-Path $pluginB "manifest.json") -Encoding UTF8
            "PLUGIN A" | Out-File -FilePath (Join-Path $pluginA "templates/shared_resource.md") -Encoding UTF8
            "PLUGIN B" | Out-File -FilePath (Join-Path $pluginB "templates/shared_resource.md") -Encoding UTF8

            $resolved = Resolve-AiraResourcePath -Kind templates -Name "shared_resource.md" -RepoRoot $repoRoot
            $resolved | Should -Not -BeNullOrEmpty
            # Plugin B has lower load_order (10 < 100), so it should win
            $resolved.Replace('\','/') | Should -Match "plugins/test-plugin-b/templates/shared_resource\.md$"
        } finally {
            if (Test-Path $pluginA) { Remove-Item -Recurse -Force $pluginA }
            if (Test-Path $pluginB) { Remove-Item -Recurse -Force $pluginB }
        }
    }

    It "returns null for a resource that does not exist anywhere" {
        $resolved = Resolve-AiraResourcePath -Kind templates -Name "nonexistent_resource_xyz.md" -RepoRoot $repoRoot
        $resolved | Should -BeNullOrEmpty
    }
}

