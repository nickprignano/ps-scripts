#requires -Version 7.0
# Configures the current user's Windows Terminal and PowerShell profile.
# No elevation is required.
# Windows Terminal settings are rewritten as JSON; comments and formatting are not retained.

$ErrorActionPreference = 'Stop'

function ConvertFrom-JsoncText {
    param([Parameter(Mandatory)][string] $Text)

    # Remove comments outside strings while preserving line breaks.
    $clean = [System.Text.StringBuilder]::new()
    $inString = $false
    $escaped = $false
    for ($i = 0; $i -lt $Text.Length; $i++) {
        $ch = $Text[$i]
        if ($inString) {
            [void]$clean.Append($ch)
            if ($escaped) { $escaped = $false }
            elseif ($ch -eq '\') { $escaped = $true }
            elseif ($ch -eq '"') { $inString = $false }
            continue
        }
        if ($ch -eq '"') {
            $inString = $true
            [void]$clean.Append($ch)
            continue
        }
        if ($ch -eq '/' -and $i + 1 -lt $Text.Length) {
            $next = $Text[$i + 1]
            if ($next -eq '/') {
                [void]$clean.Append('  ')
                $i += 2
                while ($i -lt $Text.Length -and $Text[$i] -ne "`n" -and $Text[$i] -ne "`r") {
                    [void]$clean.Append(' ')
                    $i++
                }
                if ($i -lt $Text.Length) { [void]$clean.Append($Text[$i]) }
                continue
            }
            if ($next -eq '*') {
                [void]$clean.Append('  ')
                $i += 2
                $closed = $false
                while ($i -lt $Text.Length) {
                    if ($Text[$i] -eq '*' -and $i + 1 -lt $Text.Length -and $Text[$i + 1] -eq '/') {
                        [void]$clean.Append('  ')
                        $i++
                        $closed = $true
                        break
                    }
                    $c = $Text[$i]
                    [void]$clean.Append($(if ($c -eq "`n" -or $c -eq "`r") { $c } else { ' ' }))
                    $i++
                }
                if (-not $closed) { throw 'Unterminated block comment in Windows Terminal settings.' }
                continue
            }
        }
        [void]$clean.Append($ch)
    }

    # JSONC permits trailing commas; remove them outside strings.
    $source = $clean.ToString()
    $result = [System.Text.StringBuilder]::new()
    $inString = $false
    $escaped = $false
    for ($i = 0; $i -lt $source.Length; $i++) {
        $ch = $source[$i]
        if ($inString) {
            [void]$result.Append($ch)
            if ($escaped) { $escaped = $false }
            elseif ($ch -eq '\') { $escaped = $true }
            elseif ($ch -eq '"') { $inString = $false }
            continue
        }
        if ($ch -eq '"') {
            $inString = $true
            [void]$result.Append($ch)
        } elseif ($ch -eq ',') {
            $j = $i + 1
            while ($j -lt $source.Length -and [char]::IsWhiteSpace($source[$j])) { $j++ }
            if ($j -lt $source.Length -and ($source[$j] -eq '}' -or $source[$j] -eq ']')) {
                [void]$result.Append(' ')
            } else {
                [void]$result.Append($ch)
            }
        } else {
            [void]$result.Append($ch)
        }
    }
    return $result.ToString()
}

function Backup-IfPresent {
    param([Parameter(Mandatory)][string] $Path)
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $backup = "$Path.bak.$script:BackupSuffix"
        Copy-Item -LiteralPath $Path -Destination $backup
        Write-Output "Backup: $backup"
    }
}

if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    throw 'LOCALAPPDATA is unavailable; cannot locate Windows Terminal settings.'
}

$settingsCandidates = @(
    (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
    (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
    (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
)
$settingsPath = $settingsCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if (-not $settingsPath) {
    throw 'Windows Terminal settings.json was not found in the standard per-user locations.'
}

$settings = (ConvertFrom-JsoncText (Get-Content -LiteralPath $settingsPath -Raw -Encoding utf8)) |
    ConvertFrom-Json -AsHashtable
if ($settings -isnot [System.Collections.IDictionary]) { throw 'Expected a JSON object in settings.json.' }

if (-not $settings.Contains('profiles') -or $null -eq $settings['profiles']) {
    $settings['profiles'] = [ordered]@{}
}
if ($settings['profiles'] -isnot [System.Collections.IDictionary]) { throw 'The profiles setting is not an object.' }
if (-not $settings['profiles'].Contains('defaults') -or $null -eq $settings['profiles']['defaults']) {
    $settings['profiles']['defaults'] = [ordered]@{}
}
if ($settings['profiles']['defaults'] -isnot [System.Collections.IDictionary]) {
    throw 'The profiles.defaults setting is not an object.'
}

$matrixScheme = [ordered]@{
    name = 'Matrix'; background = '#000000'; foreground = '#00FF41'
    cursorColor = '#00FF41'; selectionBackground = '#003B00'
    black = '#0D0208'; red = '#003B00'; green = '#008F11'; yellow = '#00FF41'
    blue = '#003B00'; purple = '#00CC33'; cyan = '#00FF41'; white = '#00FF41'
    brightBlack = '#006B00'; brightRed = '#00CC33'; brightGreen = '#00FF41'; brightYellow = '#39FF14'
    brightBlue = '#00CC33'; brightPurple = '#00FF41'; brightCyan = '#39FF14'; brightWhite = '#CCFFCC'
}
$settings['profiles']['defaults']['colorScheme'] = 'Matrix'
$schemes = @($settings['schemes'] | Where-Object { $null -ne $_ -and $_['name'] -ne 'Matrix' })
$settings['schemes'] = @($schemes) + @($matrixScheme)
$serializedSettings = ConvertTo-Json -InputObject $settings -Depth 100
$null = $serializedSettings | ConvertFrom-Json -AsHashtable

$rainPath = Join-Path $HOME 'matrix-rain.ps1'
$profilePath = $PROFILE
$profileDirectory = Split-Path -Parent $profilePath
if (-not (Test-Path -LiteralPath $profileDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $profileDirectory -Force | Out-Null
}

$beginMarker = '### BEGIN MATRIX SETUP ###'
$endMarker = '### END MATRIX SETUP ###'
$quotedRainPath = $rainPath.Replace("'", "''")
$profileBlock = @"
$beginMarker
function matrix {
    & '$quotedRainPath'
}
$endMarker
"@
$profileText = if (Test-Path -LiteralPath $profilePath -PathType Leaf) {
    Get-Content -LiteralPath $profilePath -Raw -Encoding utf8
} else { '' }
$blockPattern = '(?s)' + [regex]::Escape($beginMarker) + '.*?' + [regex]::Escape($endMarker)
$profileBlockMatches = [regex]::Matches($profileText, $blockPattern)
if ($profileBlockMatches.Count -gt 1) { throw 'Multiple Matrix blocks found in the PowerShell profile; edit it manually first.' }
if ($profileBlockMatches.Count -eq 1) {
    $m = $profileBlockMatches[0]
    $profileText = $profileText.Remove($m.Index, $m.Length).Insert($m.Index, $profileBlock)
} else {
    if ($profileText.Contains($beginMarker) -or $profileText.Contains($endMarker)) {
        throw 'An incomplete Matrix block exists in the PowerShell profile; edit it manually first.'
    }
    if ($profileText.Length -gt 0 -and -not $profileText.EndsWith("`n")) { $profileText += [Environment]::NewLine }
    $profileText += $profileBlock
}

$rainScript = @'
$ErrorActionPreference = 'Stop'
$oldColor = $null
$oldCursor = $null
$oldPosition = $null
try {
    $oldColor = [Console]::ForegroundColor
    $oldCursor = [Console]::CursorVisible
    $oldPosition = [Console]::GetCursorPosition()
    $width = [Console]::WindowWidth
    $height = [Console]::WindowHeight
    if ($width -lt 1 -or $height -lt 2) { throw 'The terminal window is too small for the animation.' }

    $glyphs = 'アカサタナハマヤラワ012345789:・=*+-<>'
    $drops = [int[]]::new($width)
    for ($x = 0; $x -lt $width; $x++) { $drops[$x] = Get-Random -Minimum 0 -Maximum $height }
    Clear-Host
    [Console]::CursorVisible = $false
    while ($true) {
        for ($x = 0; $x -lt $width; $x++) {
            $y = $drops[$x]
            if ($y -ge 0 -and $y -lt $height) {
                $tail = $y - 4
                if ($tail -ge 0) {
                    [Console]::SetCursorPosition($x, $tail)
                    [Console]::ForegroundColor = [ConsoleColor]::DarkGreen
                    [Console]::Write(' ')
                }
                [Console]::SetCursorPosition($x, $y)
                [Console]::ForegroundColor = [ConsoleColor]::Green
                [Console]::Write($glyphs[(Get-Random -Minimum 0 -Maximum $glyphs.Length)])
            }
            $drops[$x]++
            if ($drops[$x] -ge $height) { $drops[$x] = - (Get-Random -Minimum 0 -Maximum $height) }
        }
        Start-Sleep -Milliseconds 70
    }
} finally {
    if ($null -ne $oldColor) { try { [Console]::ForegroundColor = $oldColor } catch {} }
    if ($null -ne $oldCursor) { try { [Console]::CursorVisible = $oldCursor } catch {} }
    if ($null -ne $oldPosition) {
        try {
            $x = [Math]::Min($oldPosition.Left, [Console]::BufferWidth - 1)
            $y = [Math]::Min($oldPosition.Top, [Console]::BufferHeight - 1)
            [Console]::SetCursorPosition([Math]::Max(0, $x), [Math]::Max(0, $y))
        } catch {}
    }
}
'@

$script:BackupSuffix = (Get-Date -Format 'yyyyMMdd-HHmmss') + '.' + [guid]::NewGuid().ToString('N').Substring(0, 8)
Backup-IfPresent -Path $settingsPath
Backup-IfPresent -Path $profilePath
Backup-IfPresent -Path $rainPath

[System.IO.File]::WriteAllText($rainPath, $rainScript, [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllText($profilePath, $profileText, [System.Text.UTF8Encoding]::new($false))
$tempSettingsPath = "$settingsPath.tmp.$([guid]::NewGuid().ToString('N'))"
try {
    [System.IO.File]::WriteAllText($tempSettingsPath, $serializedSettings, [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tempSettingsPath -Destination $settingsPath -Force
} finally {
    if (Test-Path -LiteralPath $tempSettingsPath) { Remove-Item -LiteralPath $tempSettingsPath -Force }
}

Write-Output 'Matrix theme configured. Open a new PowerShell 7 session and type matrix; press Ctrl+C to stop.'
