BeforeAll {
    $modulesRoot = Join-Path $PSScriptRoot "../../../core/modules"
    Import-Module (Join-Path $modulesRoot "Aira.Common.psm1") -Force
    Import-Module (Join-Path $modulesRoot "Aira.Templating.psm1") -Force
}

Describe "Render-AiraTemplate" {
    It "replaces simple placeholders" {
        $template = "Hello, {{ NAME }}!"
        $result = Render-AiraTemplate -Template $template -Data @{ NAME = "World" }
        $result | Should -Be "Hello, World!"
    }

    It "replaces multiple distinct placeholders" {
        $template = "{{TITLE}} - {{STATUS}}"
        $result = Render-AiraTemplate -Template $template -Data @{ TITLE = "REQ-01"; STATUS = "Draft" }
        $result | Should -Be "REQ-01 - Draft"
    }

    It "replaces the same placeholder used multiple times" {
        $template = "{{KEY}} is {{KEY}}"
        $result = Render-AiraTemplate -Template $template -Data @{ KEY = "ABC" }
        $result | Should -Be "ABC is ABC"
    }

    It "leaves unknown placeholders intact" {
        $template = "Hello, {{UNKNOWN}}!"
        $result = Render-AiraTemplate -Template $template -Data @{ NAME = "World" }
        $result | Should -Be "Hello, {{UNKNOWN}}!"
    }

    It "handles null values by replacing with empty string" {
        $template = "Value: [{{MAYBE}}]"
        $result = Render-AiraTemplate -Template $template -Data @{ MAYBE = $null }
        $result | Should -Be "Value: []"
    }

    It "joins arrays with newlines" {
        $template = "Items:
{{ITEMS}}"
        $result = Render-AiraTemplate -Template $template -Data @{ ITEMS = @("one", "two", "three") }
        $result | Should -Be "Items:
one
two
three"
    }

    It "handles empty template by throwing" {
        { Render-AiraTemplate -Template "" -Data @{ KEY = "val" } } | Should -Throw
    }

    It "handles template with no placeholders" {
        $template = "No placeholders here."
        $result = Render-AiraTemplate -Template $template -Data @{ KEY = "val" }
        $result | Should -Be "No placeholders here."
    }

    It "handles whitespace variations in placeholder syntax" {
        $template = "A={{ A }} B={{B}} C={{  C  }}"
        $result = Render-AiraTemplate -Template $template -Data @{ A = "1"; B = "2"; C = "3" }
        $result | Should -Be "A=1 B=2 C=3"
    }
}
