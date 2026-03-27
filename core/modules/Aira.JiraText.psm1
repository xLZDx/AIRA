Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "Aira.Common.psm1") -Force

function Convert-JiraContentToText {
    [CmdletBinding()]
    param([object]$Value)

    if ($null -eq $Value) { return $null }
    if ($Value -is [string]) { return $Value }

    # Best-effort flattening for Atlassian Document Format (ADF)
    $texts = New-Object System.Collections.Generic.List[string]

    function Walk {
        param([object]$Node)
        if ($null -eq $Node) { return }
        if ($Node -is [string]) { $texts.Add($Node) | Out-Null; return }

        if ($Node.PSObject.Properties.Name -contains "text" -and $Node.text) {
            $texts.Add([string]$Node.text) | Out-Null
        }

        foreach ($p in $Node.PSObject.Properties) {
            $v = $p.Value
            if ($v -is [System.Collections.IEnumerable] -and $v -isnot [string]) {
                foreach ($item in $v) { Walk -Node $item }
            } elseif ($v -is [pscustomobject]) {
                Walk -Node $v
            }
        }
    }

    Walk -Node $Value
    return (($texts | Where-Object { $_ -and $_.Trim() }) -join "`n").Trim()
}

function Convert-JiraWikiToMarkdown {
    [CmdletBinding()]
    param([string]$Text)

    if (-not $Text) { return "" }

    $lines = $Text -split "`r?`n"
    $result = New-Object System.Collections.Generic.List[string]

    foreach ($line in $lines) {
        $l = $line

        # Headings: h1. through h6.
        if ($l -match '^h([1-6])\.\s+(.*)$') {
            $level = [int]$Matches[1]
            $heading = $Matches[2]
            $result.Add(("#" * $level) + " " + $heading) | Out-Null
            continue
        }

        # Jira table header row: ||Col1||Col2||...||
        if ($l -match '^\|\|.*\|\|$') {
            $cells = $l -replace '^\|\|', '' -replace '\|\|$', ''
            $cols = $cells -split '\|\|'
            $headerLine = "| " + (($cols | ForEach-Object { "**$($_.Trim())**" }) -join " | ") + " |"
            $separatorLine = "| " + (($cols | ForEach-Object { "---" }) -join " | ") + " |"
            $result.Add($headerLine) | Out-Null
            $result.Add($separatorLine) | Out-Null
            continue
        }

        # Jira table data row: |Val1|Val2|...|
        if ($l -match '^\|[^|]' -and $l -match '\|$') {
            $cells = $l -replace '^\|', '' -replace '\|$', ''
            $cols = $cells -split '\|'
            $dataLine = "| " + (($cols | ForEach-Object { $_.Trim() }) -join " | ") + " |"
            $result.Add($dataLine) | Out-Null
            continue
        }

        # Inline code: {{text}} -> `text`
        $l = [regex]::Replace($l, '\{\{(.+?)\}\}', '`$1`')

        # Bold: *text* -> **text** (but not bullet lists)
        $l = [regex]::Replace($l, '(?<!\w)\*([^\*\n]+?)\*(?!\w)', '**$1**')

        # Italic: _text_ -> *text*
        $l = [regex]::Replace($l, '(?<!\w)_([^_\n]+?)_(?!\w)', '*$1*')

        # Strikethrough: -text- -> ~~text~~
        $l = [regex]::Replace($l, '(?<!\w)-([^\-\n]+?)-(?!\w)', '~~$1~~')

        # Unordered list
        if ($l -match '^\*\s+(.*)$') {
            $l = "- " + $Matches[1]
        }

        # Ordered list: # item
        if ($l -match '^#\s+(.*)$') {
            $l = "1. " + $Matches[1]
        }

        # Monospace block {noformat} or {code}
        $l = $l -replace '\{noformat\}', '```' -replace '\{code(?::[^}]*)?\}', '```'

        $result.Add($l) | Out-Null
    }

    return ($result -join "`n").Trim()
}

function Extract-AcceptanceCriteria {
    [CmdletBinding()]
    param([string]$DescriptionText)

    if (-not $DescriptionText) { return @() }

    $lines = $DescriptionText -split "`r?`n"
    $start = ($lines | Select-String -Pattern "Acceptance Criteria" -SimpleMatch | Select-Object -First 1)
    if (-not $start) { return @() }

    $idx = $start.LineNumber - 1
    $ac = @()

    # Detect if the AC section uses a Jira table format (||header||)
    $tableMode = $false
    $tableHeaders = @()
    for ($i = $idx + 1; $i -lt $lines.Length; $i++) {
        $line = $lines[$i].Trim()
        if (-not $line) { continue }
        if ($line -match '^\|\|.*\|\|$') { $tableMode = $true; break }
        if ($line -match '^(h[1-6]\.|#{1,6}\s)') { break }
        break
    }

    if ($tableMode) {
        # Parse Jira table: header row then data rows
        $inTable = $false
        for ($i = $idx + 1; $i -lt $lines.Length; $i++) {
            $line = $lines[$i].Trim()
            if (-not $line) { continue }
            if ($line -match '^\|\|.*\|\|$') {
                $cells = $line -replace '^\|\|', '' -replace '\|\|$', ''
                $tableHeaders = @($cells -split '\|\|' | ForEach-Object { $_.Trim() })
                $inTable = $true
                continue
            }
            if ($inTable -and $line -match '^\|[^|]' -and $line -match '\|$') {
                $cells = $line -replace '^\|', '' -replace '\|$', ''
                $cols = @($cells -split '\|' | ForEach-Object { $_.Trim() })
                # Build a structured AC line
                $parts = @()
                for ($c = 0; $c -lt [Math]::Min($tableHeaders.Count, $cols.Count); $c++) {
                    $parts += "$($tableHeaders[$c]): $($cols[$c])"
                }
                $ac += ($parts -join " | ")
                continue
            }
            if ($line -match '^(h[1-6]\.|#{1,6}\s)') { break }
        }
    } else {
        # Original list-based extraction
        for ($i = $idx + 1; $i -lt $lines.Length; $i++) {
            $line = $lines[$i].Trim()
            if (-not $line) { continue }
            if ($line -match '^(#+\s+|[A-Z][A-Za-z ]+:)$') { break }
            if ($line -match '^(h[1-6]\.)') { break }
            if ($line -match '^[-*]\s+') { $ac += ($line -replace '^[-*]\s+', ''); continue }
            if ($line -match '^\d+[\).\s]+') { $ac += ($line -replace '^\d+[\).\s]+', ''); continue }
            if ($line -match '^(Given|When|Then)\b') { $ac += $line; continue }
        }
    }

    return @($ac)
}

function Extract-ConfluencePageIds {
    [CmdletBinding()]
    param([string]$Text)

    if (-not $Text) { return @() }
    $ids = @{}
    foreach ($m in [regex]::Matches($Text, '(?i)(?:pageId=|/pages/)(\d{5,})')) {
        $ids[$m.Groups[1].Value] = $true
    }
    return @($ids.Keys)
}

Export-ModuleMember -Function Convert-JiraContentToText, Convert-JiraWikiToMarkdown, Extract-AcceptanceCriteria, Extract-ConfluencePageIds

