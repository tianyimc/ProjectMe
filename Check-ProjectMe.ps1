$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$indexPath = Join-Path $root 'articles.json'
$articlesPath = Join-Path $root 'articles'

$articles = @(Get-Content -Raw -Encoding utf8 $indexPath | ConvertFrom-Json | ForEach-Object { $_ })
if ($articles.Count -eq 0) { throw 'articles.json contains no article records.' }

$required = 'slug', 'title', 'category', 'tags', 'readingTime', 'excerpt', 'file'
$slugs = @{}
$indexedFiles = @{}
foreach ($article in $articles) {
  foreach ($field in $required) {
    $property = $article.PSObject.Properties | Where-Object { $_.Name -eq $field }
    $value = if ($property) { $property.Value } else { $null }
    if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) {
      throw "Article is missing field '$field'."
    }
  }
  if ($article.slug -notmatch '^[a-z0-9-]+$') { throw "Invalid slug: $($article.slug)" }
  if ($slugs.ContainsKey($article.slug)) { throw "Duplicate slug: $($article.slug)" }
  if ($indexedFiles.ContainsKey($article.file)) { throw "Duplicate file: $($article.file)" }
  $slugs[$article.slug] = $true
  $indexedFiles[$article.file] = $true
  $customPath = if ($article.PSObject.Properties.Name -contains 'path') { [string]$article.path } else { '' }
  if (-not [string]::IsNullOrWhiteSpace($customPath)) {
    $rootPrefix = [IO.Path]::GetFullPath($root).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $sourcePath = [IO.Path]::GetFullPath((Join-Path $root $customPath))
    if (-not $sourcePath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Article path escapes the project root: $customPath" }
  } else {
    $sourcePath = Join-Path $articlesPath $article.file
  }
  if (-not (Test-Path $sourcePath -PathType Leaf)) { throw "Missing Markdown file: $sourcePath" }
}

$orphaned = Get-ChildItem $articlesPath -Filter '*.md' -File | Where-Object { -not $indexedFiles.ContainsKey($_.Name) }
if ($orphaned) { throw "Unindexed Markdown file: $($orphaned.Name -join ', ')" }
foreach ($article in $articles) {
  foreach ($field in @('titleColor')) {
    if ($article.PSObject.Properties.Name -contains $field -and -not [string]::IsNullOrWhiteSpace([string]$article.$field)) {
      if ($article.$field -notmatch '^(#[0-9a-fA-F]{3,8}|[a-zA-Z]+|rgba?\([^()]+\)|hsla?\([^()]+\))$') { throw "Invalid $field for article: $($article.slug)" }
    }
  }
}

$timelinePath = Join-Path $root 'timeline.json'
if (Test-Path $timelinePath -PathType Leaf) {
  $timeline = Get-Content -Raw -Encoding utf8 $timelinePath | ConvertFrom-Json
  $timelineEntries = @($timeline.entries)
  $activeSlugs = @{}
  foreach ($entry in $timelineEntries) {
    if (-not $slugs.ContainsKey($entry.slug)) { throw "Timeline references unknown slug: $($entry.slug)" }
    if ([string]::IsNullOrWhiteSpace([string]$entry.date) -or $entry.date -notmatch '^\d{8}$') { throw "Invalid timeline date: $($entry.slug)" }
    try { [datetime]::ParseExact($entry.date, 'yyyyMMdd', $null) | Out-Null } catch { throw "Invalid timeline date: $($entry.slug)" }
    if ($null -eq $entry.PSObject.Properties['priority'] -or [int]$entry.priority -lt 1) { throw "Invalid timeline priority: $($entry.slug)" }
    if (-not $entry.disabled) {
      if ($activeSlugs.ContainsKey($entry.slug)) { throw "Duplicate active timeline slug: $($entry.slug)" }
      $activeSlugs[$entry.slug] = $true
    }
  }
  foreach ($group in @($timelineEntries | Where-Object { -not $_.disabled } | Group-Object date)) {
    $priorities = @($group.Group | ForEach-Object { [int]$_.priority })
    if (($priorities | Select-Object -Unique).Count -ne $priorities.Count) { throw "Duplicate timeline priority on date: $($group.Name)" }
  }
}
Write-Output "ProjectMe check passed: $($articles.Count) articles."
