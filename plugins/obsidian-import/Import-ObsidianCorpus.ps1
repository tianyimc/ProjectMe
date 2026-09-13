[CmdletBinding(SupportsShouldProcess)]
param(
  [Parameter(Mandatory = $true)] [string]$SourceRoot,
  [string]$ProjectRoot = (Split-Path -Parent $MyInvocation.MyCommand.Path)
)

$ErrorActionPreference = 'Stop'
$sourceRootPath = [System.IO.Path]::GetFullPath($SourceRoot)
$projectRootPath = [System.IO.Path]::GetFullPath($ProjectRoot)
$articlesPath = Join-Path $projectRootPath 'articles'
$indexPath = Join-Path $projectRootPath 'articles.json'
$prefaceMarker = ([char]0x5E8F).ToString()
$epilogueMarker = ([char]0x8DCB).ToString()
$chapterWord = ([char]0x7B2C).ToString()
$sectionWord = ([char]0x8282).ToString()
$middleDot = ([char]0x00B7).ToString()
$collectionWord = ([char]0x6587).ToString() + ([char]0x96C6).ToString()

if (-not (Test-Path $sourceRootPath -PathType Container)) { throw "Source folder not found: $sourceRootPath" }
if (-not (Test-Path $articlesPath -PathType Container)) { New-Item -ItemType Directory -Path $articlesPath | Out-Null }

$articles = @(Get-Content -Raw -Encoding utf8 $indexPath | ConvertFrom-Json | ForEach-Object { $_ })
$knownKeys = @{}
$knownArticles = @{}
foreach ($article in $articles) {
  $sourceKeyProperty = $article.PSObject.Properties | Where-Object { $_.Name -eq 'sourceKey' }
  if ($sourceKeyProperty) {
    $knownKeys[$sourceKeyProperty.Value] = $true
    $knownArticles[$sourceKeyProperty.Value] = $article
  }
}

function Get-RelativePath([string]$path) {
  return $path.Substring($sourceRootPath.Length).TrimStart('\', '/')
}

function Get-ImportSlug([string]$sourceKey) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($sourceKey)
    $hash = $sha.ComputeHash($bytes)
    $hex = -join ($hash | ForEach-Object { $_.ToString('x2') })
    return "import-$($hex.Substring(0, 12))"
  }
  finally { $sha.Dispose() }
}

function Get-Excerpt([string[]]$lines) {
  $plain = ($lines | Where-Object { $_.Trim() -and $_ -notmatch '^#{1,6}\s' -and $_ -notmatch '^```' -and $_ -notmatch '^[-*>]\s' }) -join ' '
  $plain = $plain -replace '`', '' -replace '\*\*|__', ''
  if ($plain.Length -gt 120) { return $plain.Substring(0, 120) + '...' }
  return $plain
}

function Get-SectionLabel([string]$sectionTitle, [bool]$isHighSchool) {
  $match = [regex]::Match($sectionTitle, '(\d+)\.(\d+)(.*)$')
  if (-not $match.Success) { return $sectionTitle }
  $volumeNumber = [int]$match.Groups[1].Value
  $sectionNumber = $match.Groups[2].Value
  if ($isHighSchool) { $volumeNumber += 4 }
  $suffix = $match.Groups[3].Value.Trim()
  if ($suffix.StartsWith($sectionWord)) { $suffix = $suffix.Substring(1).Trim() }
  if ($suffix.StartsWith($middleDot)) { $suffix = $suffix.Substring(1).Trim() }
  return "$chapterWord$volumeNumber.$sectionNumber$sectionWord$middleDot$suffix".TrimEnd($middleDot)
}

function Get-SectionOrder([string]$sectionLabel, [int]$stageOrder) {
  $match = [regex]::Match($sectionLabel, '(\d+)\.(\d+)')
  if (-not $match.Success) { return ($stageOrder * 1000000) + 500000 }
  return ($stageOrder * 1000000) + ([int]$match.Groups[1].Value * 10000) + ([int]$match.Groups[2].Value * 100)
}

function Get-NormalizedBody([string]$text) {
  return (($text -replace "`r`n", "`n") -replace "`r", "`n").Trim()
}

function Update-ImportedArticleBody([object]$existing, [string[]]$bodyLines) {
  $fileName = [string]$existing.file
  if (-not $fileName) { throw "Existing imported article has no file: $($existing.slug)" }
  $targetPath = Join-Path $articlesPath $fileName
  if (-not (Test-Path $targetPath -PathType Leaf)) { throw "Existing imported article file is missing: $targetPath" }
  $body = ($bodyLines -join "`r`n").Trim()
  if (-not $body) { $body = '_No content yet._' }
  $newText = "$body`r`n"
  $currentText = [System.IO.File]::ReadAllText($targetPath, [System.Text.UTF8Encoding]::new($false))
  if ((Get-NormalizedBody $currentText) -eq (Get-NormalizedBody $newText)) { return $false }
  if ($PSCmdlet.ShouldProcess($targetPath, 'Update imported Markdown article')) {
    [System.IO.File]::WriteAllText($targetPath, $newText, [System.Text.UTF8Encoding]::new($false))
  }
  return $true
}

function Add-ImportedArticle([string]$title, [string[]]$bodyLines, [string]$sourceKey, [string]$relativeFile, [string]$stage, [string]$section, [string]$date, [string]$kind, [int]$sortOrder) {
  if (-not $title) { return $false }
  if ($knownKeys.ContainsKey($sourceKey)) {
    $existing = $knownArticles[$sourceKey]
    if (Update-ImportedArticleBody $existing $bodyLines) { $script:updatedArticles++ }
    return $false
  }
  $slug = Get-ImportSlug $sourceKey
  $fileName = "$slug.md"
  $targetPath = Join-Path $articlesPath $fileName
  $body = ($bodyLines -join "`r`n").Trim()
  if (-not $body) { $body = '_No content yet._' }
  if ($PSCmdlet.ShouldProcess($targetPath, 'Create imported Markdown article')) {
    [System.IO.File]::WriteAllText($targetPath, "$body`r`n", [System.Text.UTF8Encoding]::new($false))
  }
  $newArticle = [ordered]@{
    slug = $slug; title = $title; date = $date; category = $stage
    tags = @($collectionWord); readingTime = 'To be filled'; excerpt = (Get-Excerpt $bodyLines)
    file = $fileName; sourceKey = $sourceKey; sourcePath = $relativeFile
    kind = $kind; section = $section; order = $sortOrder
  }
  $script:articles += [pscustomobject]$newArticle
  $knownKeys[$sourceKey] = $true
  return $true
}

$script:updatedArticles = 0
$created = 0
$skipped = 0
$files = @(Get-ChildItem -Path $sourceRootPath -Recurse -Filter '*.md' -File | Where-Object { $_.FullName -notmatch '[\\/]\.obsidian([\\/]|$)' } | Sort-Object FullName)
$stageNames = @($files | ForEach-Object { $relative = Get-RelativePath $_.FullName; ($relative -split '[\\/]')[0] } | Select-Object -Unique)
$stageNames = @($stageNames | Sort-Object @{ Expression = { if ($_ -match '\u521D\u4E2D') { 0 } elseif ($_ -match '\u9AD8\u4E2D') { 1 } else { 2 } } }, @{ Expression = { $_ } })

foreach ($file in $files) {
  $relativeFile = Get-RelativePath $file.FullName
  $parts = $relativeFile -split '[\\/]'
  $stage = if ($parts.Count -ge 1) { $parts[0] } else { 'Imported' }
  $stageOrder = [array]::IndexOf($stageNames, $stage)
  if ($stageOrder -lt 0) { $stageOrder = 0 }
  $isHighSchool = $stage -match '\u9AD8\u4E2D'
  $fileBase = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
  $lines = @(Get-Content -Encoding utf8 $file.FullName)

  $isStageRootFile = $parts.Count -eq 2
  if ($isStageRootFile -and ($fileBase -eq $prefaceMarker -or $fileBase -eq $epilogueMarker)) {
    $date = ''
    $kind = if ($fileBase -eq $prefaceMarker) { 'stage-preface' } else { 'stage-epilogue' }
    $sortOrder = if ($kind -eq 'stage-preface') { $stageOrder * 1000000 } else { ($stageOrder * 1000000) + 999999 }
    $key = "$relativeFile::$kind"
    if (Add-ImportedArticle $fileBase $lines $key $relativeFile $stage '' $date $kind $sortOrder) { $created++ } else { $skipped++ }
    continue
  }

  if ($parts.Count -lt 3) { continue }
  $sectionLabel = Get-SectionLabel $fileBase $isHighSchool
  $sectionOrder = Get-SectionOrder $sectionLabel $stageOrder
  $currentTitle = $null
  $currentLines = New-Object System.Collections.Generic.List[string]
  $sectionNumber = 0

  foreach ($line in $lines) {
    if ($line -match '^##\s+(.+?)\s*$') {
      if ($currentTitle) {
        $key = "$relativeFile::$sectionNumber::$currentTitle"
        $sortOrder = $sectionOrder + $sectionNumber
        if (Add-ImportedArticle $currentTitle $currentLines.ToArray() $key $relativeFile $stage $sectionLabel '' 'article' $sortOrder) { $created++ } else { $skipped++ }
      }
      elseif ($currentLines.Count -gt 0 -and (($currentLines -join '').Trim())) {
        $key = "$relativeFile::section-preface"
        if (Add-ImportedArticle "$sectionLabel - Preface" $currentLines.ToArray() $key $relativeFile $stage $sectionLabel '' 'section-preface' $sectionOrder) { $created++ } else { $skipped++ }
      }
      $sectionNumber++
      $currentTitle = $Matches[1].Trim()
      $currentLines = New-Object System.Collections.Generic.List[string]
    }
    else { $currentLines.Add($line) }
  }
  if ($currentTitle) {
    $key = "$relativeFile::$sectionNumber::$currentTitle"
    $sortOrder = $sectionOrder + $sectionNumber
    if (Add-ImportedArticle $currentTitle $currentLines.ToArray() $key $relativeFile $stage $sectionLabel '' 'article' $sortOrder) { $created++ } else { $skipped++ }
  }
  elseif ($currentLines.Count -gt 0 -and (($currentLines -join '').Trim())) {
    $key = "$relativeFile::section-preface"
    if (Add-ImportedArticle $sectionLabel $currentLines.ToArray() $key $relativeFile $stage $sectionLabel '' 'section-preface' $sectionOrder) { $created++ } else { $skipped++ }
  }
}

if ($PSCmdlet.ShouldProcess($indexPath, 'Update article index')) {
  $json = $articles | ConvertTo-Json -Depth 6
  [System.IO.File]::WriteAllText($indexPath, "$json`r`n", [System.Text.UTF8Encoding]::new($false))
}
$unchangedSkipped = [Math]::Max(0, $skipped - $script:updatedArticles)
Write-Output "Imported: $created; updated content: $script:updatedArticles; skipped existing: $unchangedSkipped; source files: $($files.Count)."
