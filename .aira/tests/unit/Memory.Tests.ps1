BeforeAll {
    $modulesRoot = Join-Path $PSScriptRoot "../../../core/modules"
    Import-Module (Join-Path $modulesRoot "Aira.Common.psm1") -Force
    Import-Module (Join-Path $modulesRoot "Aira.Memory.psm1") -Force

    $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("aira-test-memory-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $script:tempDir -Force | Out-Null

    # Set up a fake .aira/memory/ directory
    $script:memoryDir = Join-Path $script:tempDir ".aira/memory"
    New-Item -ItemType Directory -Path $script:memoryDir -Force | Out-Null
}

AfterAll {
    if (Test-Path $script:tempDir) {
        Remove-Item -Recurse -Force $script:tempDir -ErrorAction SilentlyContinue
    }
}

Describe "Get-AiraScalarLeafMap" {
    It "flattens a simple hashtable" {
        $ht = @{ a = "1"; b = 2 }
        $map = Get-AiraScalarLeafMap -Value $ht
        $map["a"] | Should -Be "1"
        $map["b"] | Should -Be 2
    }

    It "flattens nested hashtables using dotted paths" {
        $ht = @{ top = @{ mid = @{ leaf = "val" } } }
        $map = Get-AiraScalarLeafMap -Value $ht
        $map["top.mid.leaf"] | Should -Be "val"
    }

    It "ignores arrays and complex objects" {
        $ht = @{ arr = @(1, 2); scalar = "yes" }
        $map = Get-AiraScalarLeafMap -Value $ht
        $map.ContainsKey("arr") | Should -BeFalse
        $map["scalar"] | Should -Be "yes"
    }
}

Describe "Get-AiraDiffs" {
    It "detects changed values" {
        $before = @{ a = "old"; b = "same" }
        $after  = @{ a = "new"; b = "same" }
        $diffs = Get-AiraDiffs -Before $before -After $after
        $changed = @($diffs | Where-Object { $_.path -eq "a" })
        $changed.Count | Should -Be 1
        $changed[0].before | Should -Be "old"
        $changed[0].after | Should -Be "new"
    }

    It "detects added keys" {
        $before = @{ a = "1" }
        $after  = @{ a = "1"; b = "2" }
        $diffs = Get-AiraDiffs -Before $before -After $after
        $added = @($diffs | Where-Object { $_.path -eq "b" })
        $added.Count | Should -Be 1
    }

    It "returns empty for identical hashtables" {
        $ht = @{ x = "1"; y = "2" }
        $diffs = Get-AiraDiffs -Before $ht -After $ht
        $diffs.Count | Should -Be 0
    }
}

Describe "Set-HashtableValueByDottedPath" {
    It "sets a top-level key" {
        $ht = @{}
        Set-HashtableValueByDottedPath -Object $ht -Path "key" -Value "val"
        $ht["key"] | Should -Be "val"
    }

    It "creates nested structure when needed" {
        $ht = @{}
        Set-HashtableValueByDottedPath -Object $ht -Path "a.b.c" -Value 42
        $ht["a"]["b"]["c"] | Should -Be 42
    }

    It "overwrites existing value" {
        $ht = @{ a = @{ b = "old" } }
        Set-HashtableValueByDottedPath -Object $ht -Path "a.b" -Value "new"
        $ht["a"]["b"] | Should -Be "new"
    }
}

Describe "Promote-AiraPreferencesFromCorrections" {
    BeforeEach {
        # Clean slate
        $corrFile = Join-Path $script:memoryDir "corrections.jsonl"
        $prefFile = Join-Path $script:memoryDir "user_preferences.json"
        if (Test-Path $corrFile) { Remove-Item $corrFile -Force }
        if (Test-Path $prefFile) { Remove-Item $prefFile -Force }
    }

    It "does nothing when corrections file does not exist" {
        $result = Promote-AiraPreferencesFromCorrections -RepoRoot $script:tempDir -DryRun
        $result.promoted.Count | Should -Be 0
    }

    It "promotes a correction that meets threshold" {
        $corrFile = Join-Path $script:memoryDir "corrections.jsonl"

        # Write 5 identical corrections (threshold default is 3)
        $ts = (Get-Date).ToString("o")
        $entry = @{
            timestamp = $ts
            action    = "user_override"
            diffs     = @(@{ path = "testrail.defaults.priority"; before = "Medium"; after = "High" })
        } | ConvertTo-Json -Depth 5 -Compress

        for ($i = 0; $i -lt 5; $i++) {
            Add-Content -Path $corrFile -Value $entry -Encoding UTF8
        }

        $result = Promote-AiraPreferencesFromCorrections -RepoRoot $script:tempDir -Threshold 3 -DryRun
        $result.promoted.Count | Should -BeGreaterOrEqual 1
        @($result.promoted | Where-Object { $_.path -eq "testrail.defaults.priority" }).Count | Should -Be 1
    }

    It "does not promote when below threshold" {
        $corrFile = Join-Path $script:memoryDir "corrections.jsonl"

        $ts = (Get-Date).ToString("o")
        $entry = @{
            timestamp = $ts
            action    = "user_override"
            diffs     = @(@{ path = "testrail.defaults.priority"; before = "Medium"; after = "High" })
        } | ConvertTo-Json -Depth 5 -Compress

        # Only 2 entries, threshold is 3
        for ($i = 0; $i -lt 2; $i++) {
            Add-Content -Path $corrFile -Value $entry -Encoding UTF8
        }

        $result = Promote-AiraPreferencesFromCorrections -RepoRoot $script:tempDir -Threshold 3 -DryRun
        $result.promoted.Count | Should -Be 0
    }

    It "writes preferences file when not dry-run" {
        $corrFile = Join-Path $script:memoryDir "corrections.jsonl"
        $prefFile = Join-Path $script:memoryDir "user_preferences.json"

        $ts = (Get-Date).ToString("o")
        $entry = @{
            timestamp = $ts
            action    = "user_override"
            diffs     = @(@{ path = "testrail.defaults.priority"; before = "Medium"; after = "High" })
        } | ConvertTo-Json -Depth 5 -Compress

        for ($i = 0; $i -lt 4; $i++) {
            Add-Content -Path $corrFile -Value $entry -Encoding UTF8
        }

        Promote-AiraPreferencesFromCorrections -RepoRoot $script:tempDir -Threshold 3

        Test-Path $prefFile | Should -BeTrue
        $prefs = Get-Content $prefFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $prefs.testrail.defaults.priority | Should -Be "High"
    }
}
