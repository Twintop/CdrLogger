<#
.SYNOPSIS
	Stages the addon into a clean directory and zips it for release.

.DESCRIPTION
	Builds the release tree under <OutDir>\CdrLogger and zips it as <OutDir>\CdrLogger-<version>-<releaseType>.zip.
	Only the TOC, the files it lists, LICENSE and README.md ship.

	Runs on Windows PowerShell 5.1 and PowerShell 7 (GitHub-hosted runners included).

.PARAMETER Version
	Overrides the TOC's "## Version:" in the staged copy (e.g. from a release tag).

.PARAMETER ReleaseType
	Overrides "## X-ReleaseType:" (release, betaNN, alphaNN).

.PARAMETER ReleaseDate
	Overrides "## X-ReleaseDate:" (e.g. "February 14, 2026"). Defaults to today when -Version is given.

.PARAMETER OutDir
	Output root. Defaults to <repo>\dist.

.PARAMETER NoZip
	Stage only; skip creating the archive.
#>
[CmdletBinding()]
param(
	[string]$Version = "",
	[string]$ReleaseType = "",
	[string]$ReleaseDate = "",
	[string]$OutDir = "",
	[switch]$NoZip
)

$ErrorActionPreference = "Stop"
# $PSScriptRoot is not populated inside param() defaults on Windows PowerShell 5.1 when run with -File.
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$root = Split-Path -Parent $scriptDir
$addonName = "CdrLogger"

$tocSource = Join-Path $root "$addonName.toc"
if (-not (Test-Path $tocSource)) { throw "TOC not found: $tocSource" }

if ($OutDir -eq "") { $OutDir = Join-Path $root "dist" }
$stageDir = Join-Path $OutDir $addonName
if (Test-Path $stageDir) { Remove-Item -Recurse -Force $stageDir }
New-Item -ItemType Directory -Force -Path $stageDir | Out-Null

# Read the TOC (BOM and line endings preserved on write).
$tocBytes = [System.IO.File]::ReadAllBytes($tocSource)
$hasBom = $tocBytes.Length -ge 3 -and $tocBytes[0] -eq 0xEF -and $tocBytes[1] -eq 0xBB -and $tocBytes[2] -eq 0xBF
$tocText = [System.Text.Encoding]::UTF8.GetString($tocBytes)
if ($hasBom -and $tocText.Length -gt 0 -and [int]$tocText[0] -eq 0xFEFF) { $tocText = $tocText.Substring(1) }

# Include list, not an exclude list: anything the TOC does not load never ships.
$includeFiles = @("LICENSE", "README.md")
$tocFiles = $tocText -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" -and -not $_.StartsWith("#") }
foreach ($file in $tocFiles) {
	$src = Join-Path $root $file
	if (-not (Test-Path $src)) { throw "TOC lists $file, which does not exist" }
	$dest = Join-Path $stageDir $file
	New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
	Copy-Item -Force $src $dest
}
foreach ($file in $includeFiles) {
	$src = Join-Path $root $file
	if (Test-Path $src) { Copy-Item -Force $src (Join-Path $stageDir $file) }
}

function Get-TocField([string]$text, [string]$field) {
	$m = [regex]::Match($text, "(?m)^## " + [regex]::Escape($field) + ":[ \t]*(.*?)[ \t]*\r?$")
	if ($m.Success) { return $m.Groups[1].Value } else { return "" }
}
function Set-TocField([string]$text, [string]$field, [string]$value) {
	$pattern = "(?m)^(## " + [regex]::Escape($field) + ":[ \t]*)(.*?)([ \t]*\r?)$"
	if ([regex]::IsMatch($text, $pattern)) {
		return [regex]::Replace($text, $pattern, { param($m) $m.Groups[1].Value + $value + $m.Groups[3].Value }, 1)
	}
	return $text
}

if ($Version -ne "") {
	$tocText = Set-TocField $tocText "Version" $Version
	if ($ReleaseDate -eq "") { $ReleaseDate = (Get-Date).ToString("MMMM d, yyyy", [System.Globalization.CultureInfo]::InvariantCulture) }
}
if ($ReleaseType -ne "") { $tocText = Set-TocField $tocText "X-ReleaseType" $ReleaseType }
if ($ReleaseDate -ne "") { $tocText = Set-TocField $tocText "X-ReleaseDate" $ReleaseDate }

$finalVersion = Get-TocField $tocText "Version"
$finalReleaseType = Get-TocField $tocText "X-ReleaseType"
if ($finalReleaseType -eq "") { $finalReleaseType = "release" }

$encoding = New-Object System.Text.UTF8Encoding($hasBom)
[System.IO.File]::WriteAllText((Join-Path $stageDir "$addonName.toc"), $tocText, $encoding)

Write-Host ("Staged {0} {1} at {2}" -f $finalVersion, $finalReleaseType, $stageDir)

if ($NoZip) { exit 0 }

$zipName = "{0}-{1}-{2}.zip" -f $addonName, $finalVersion, $finalReleaseType
$zipPath = Join-Path $OutDir $zipName
if (Test-Path $zipPath) { Remove-Item -Force $zipPath }

# Build the archive entry by entry with forward-slash names so every extractor (including macOS)
# reproduces the folder tree; Compress-Archive on Windows PowerShell 5.1 writes backslashes.
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
	$prefixLen = $OutDir.TrimEnd("\", "/").Length + 1
	Get-ChildItem -Path $stageDir -Recurse -File | Sort-Object FullName | ForEach-Object {
		$entryName = $_.FullName.Substring($prefixLen) -replace "\\", "/"
		[System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $_.FullName, $entryName, [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
	}
}
finally {
	$zip.Dispose()
}

Write-Host ("Wrote {0} ({1:N0} bytes)" -f $zipPath, (Get-Item $zipPath).Length)
# Emit the path last on its own line so callers (CI) can capture it.
Write-Output $zipPath
