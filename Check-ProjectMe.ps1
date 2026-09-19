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
$pluginsPath = Join-Path $root 'plugins'
$pluginCount = 0
if (Test-Path $pluginsPath -PathType Container) {
  foreach ($folder in @(Get-ChildItem -LiteralPath $pluginsPath -Directory)) {
    $manifestPath = Join-Path $folder.FullName 'plugin.json'
    if (-not (Test-Path $manifestPath -PathType Leaf)) { throw "Plugin manifest missing: $manifestPath" }
    try { $manifest = Get-Content -Raw -Encoding UTF8 $manifestPath | ConvertFrom-Json } catch { throw "Invalid plugin manifest: $manifestPath" }
    if ([string]::IsNullOrWhiteSpace([string]$manifest.entry)) { throw "Plugin entry is required: $manifestPath" }
    if ($null -ne $manifest.PSObject.Properties['cli'] -and $null -ne $manifest.cli) {
      if ([string]::IsNullOrWhiteSpace([string]$manifest.cli.label)) { throw "Plugin cli.label is required: $manifestPath" }
      if ([string]::IsNullOrWhiteSpace([string]$manifest.cli.function)) { throw "Plugin cli.function is required: $manifestPath" }
    }
    if ($null -ne $manifest.PSObject.Properties['gui'] -and $null -ne $manifest.gui) {
      # 第三方插件不能自己写 XAML：GUI 入口要么用清单 gui.panel 声明控件（宿主运行时现造），
      # 要么用 gui.controls 引用主程序已经预留的控件名。两者至少要有一个，见 README 插件设计规范 §7。
      $declaredControls = @($manifest.gui.controls | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
      $panelEntries = @()
      if ($null -ne $manifest.gui.PSObject.Properties['panel'] -and $null -ne $manifest.gui.panel -and $manifest.gui.panel -isnot [string]) {
        if ($manifest.gui.panel -is [array]) { $panelEntries = @($manifest.gui.panel | Where-Object { $null -ne $_ }) }
        else { $panelEntries = @($manifest.gui.panel) }
      }
      $guiFunctionName = ''
      if ($null -ne $manifest.gui.PSObject.Properties['function'] -and $null -ne $manifest.gui.PSObject.Properties['function'].Value) { $guiFunctionName = ([string]$manifest.gui.PSObject.Properties['function'].Value).Trim() }
      if ([string]::IsNullOrWhiteSpace($guiFunctionName) -and $panelEntries.Count -eq 0 -and $declaredControls.Count -eq 0) {
        throw "Plugin gui.function is required (or declare gui.panel / gui.controls): $manifestPath"
      }
      if ($panelEntries.Count -gt 0 -and [string]::IsNullOrWhiteSpace($guiFunctionName)) {
        throw "Plugin gui.function is required when gui.panel is declared: $manifestPath"
      }
      $seenIds = @{}
      $allowedTypes = @('button', 'checkbox', 'textbox', 'text', 'combo')
      foreach ($panelEntry in $panelEntries) {
        $panelId = ([string]$panelEntry.id).Trim().ToLowerInvariant()
        $panelId = [regex]::Replace($panelId, '[^a-z0-9]+', '_').Trim('_')
        if ([string]::IsNullOrWhiteSpace($panelId)) { throw "Plugin gui.panel id is required: $manifestPath" }
        if ($seenIds.ContainsKey($panelId)) { throw "Plugin gui.panel id is duplicated ($panelId): $manifestPath" }
        $seenIds[$panelId] = $true
        $panelType = ([string]$panelEntry.type).Trim().ToLowerInvariant()
        if ($panelType -eq '') { $panelType = 'text' }
        if ($panelType -eq 'label' -or $panelType -eq 'textblock') { $panelType = 'text' }
        if ($panelType -eq 'btn') { $panelType = 'button' }
        if ($panelType -eq 'check' -or $panelType -eq 'bool') { $panelType = 'checkbox' }
        if ($panelType -eq 'input' -or $panelType -eq 'edit') { $panelType = 'textbox' }
        if ($panelType -eq 'combobox' -or $panelType -eq 'select' -or $panelType -eq 'list') { $panelType = 'combo' }
        if ($allowedTypes -notcontains $panelType) { throw "Plugin gui.panel type must be button/checkbox/textbox/text/combo ($panelId): $manifestPath" }
        if ($panelType -eq 'button' -and [string]::IsNullOrWhiteSpace([string]$panelEntry.content)) { throw "Plugin gui.panel button needs content ($panelId): $manifestPath" }
        if ($null -ne $panelEntry.PSObject.Properties['page'] -and -not [string]::IsNullOrWhiteSpace([string]$panelEntry.page)) {
          if (@('plugin', 'maintenance', 'articles') -notcontains ([string]$panelEntry.page).Trim().ToLowerInvariant()) { throw "Plugin gui.panel page must be plugin/maintenance/articles ($panelId): $manifestPath" }
        }
      }
    }
    $entryPath = Join-Path $folder.FullName ([string]$manifest.entry)
    if (-not (Test-Path $entryPath -PathType Leaf)) { throw "Plugin entry file missing: $entryPath" }
    $pluginConfigPath = Join-Path $folder.FullName 'config.json'
    if (Test-Path $pluginConfigPath -PathType Leaf) {
      try { $null = Get-Content -Raw -Encoding UTF8 $pluginConfigPath | ConvertFrom-Json } catch { throw "Invalid plugin config: $pluginConfigPath" }
    }
    $pluginCount++
  }
}
Write-Output "ProjectMe check passed: $($articles.Count) articles, $pluginCount plugins."
