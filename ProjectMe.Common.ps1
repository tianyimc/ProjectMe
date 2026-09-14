$ErrorActionPreference = 'Stop'

function Get-ProjectRoot {
  return $PSScriptRoot
}

function Get-ProjectInfo {
  param([string]$Root = (Get-ProjectRoot))
  $path = Join-Path $Root 'project-info.json'
  if (-not (Test-Path $path -PathType Leaf)) {
    return [pscustomobject]@{
      name = 'ProjectMe'; version = '1.0.0'; generation = 1; author = 'tianyimc.com'; authorUrl = 'https://tianyimc.com'
      copyright = "© $(Get-Date -Format yyyy) tianyimc.com 依据 MIT 许可证开放源代码"
      license = 'MIT'; licenseName = 'MIT 许可证'; licenseUrl = 'https://opensource.org/license/mit'
      description = '一个无后端依赖的文集项目：网页负责阅读，CLI 与 WPF GUI 负责维护。'; title = 'ProjectMe · 个人文集'
    }
  }
  return Get-Content -Raw -Encoding UTF8 $path | ConvertFrom-Json
}

function Write-ProjectLog {
  param([Parameter(Mandatory)][string]$Message, [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO', [string]$Root = (Get-ProjectRoot))
  $logDirectory = Join-Path $Root 'logs'
  if (-not (Test-Path $logDirectory -PathType Container)) { New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null }
  $logPath = Join-Path $logDirectory 'projectme-cli.log'
  $line = "{0} [{1}] {2}`r`n" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
  $bom = [byte[]](0xEF, 0xBB, 0xBF)
  if (-not (Test-Path $logPath)) {
    [IO.File]::WriteAllText($logPath, $line, [Text.UTF8Encoding]::new($true))
    return
  }
  $bytes = [IO.File]::ReadAllBytes($logPath)
  if ($bytes.Length -lt 3 -or $bytes[0] -ne $bom[0] -or $bytes[1] -ne $bom[1] -or $bytes[2] -ne $bom[2]) {
    $oldText = [IO.File]::ReadAllText($logPath, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($logPath, $oldText, [Text.UTF8Encoding]::new($true))
  }
  [IO.File]::AppendAllText($logPath, $line, [Text.UTF8Encoding]::new($false))
}

function Get-DefaultProjectConfig {
  return [pscustomobject]@{
    serve = [pscustomobject]@{ port = 4173; mode = 'background' }
    articleList = [pscustomobject]@{ pageSize = 10; groupBySection = $true }
    newArticle = [pscustomobject]@{ tags = @('随笔'); date = ''; readingTime = '3 分钟阅读' }
    update = [pscustomobject]@{ keep = @() }
  }
}

function Get-ProjectConfig {
  param([string]$Root = (Get-ProjectRoot))
  $defaults = Get-DefaultProjectConfig
  $path = Join-Path $Root 'projectme.config.json'
  if (-not (Test-Path $path -PathType Leaf)) { Write-ProjectLog "未找到配置文件，使用默认配置：$path" 'INFO' $Root; return $defaults }
  try {
    $raw = Get-Content -Raw -Encoding UTF8 $path | ConvertFrom-Json
    if ($raw.serve.port -as [int] -and [int]$raw.serve.port -gt 0) { $defaults.serve.port = [int]$raw.serve.port } else { Write-ProjectLog '配置 serve.port 无效，使用 4173。' 'WARN' $Root }
    if ($raw.serve.mode -in @('background','foreground')) { $defaults.serve.mode = [string]$raw.serve.mode } else { Write-ProjectLog '配置 serve.mode 无效，使用 background。' 'WARN' $Root }
    if ($raw.articleList.pageSize -as [int] -and [int]$raw.articleList.pageSize -gt 0) { $defaults.articleList.pageSize = [int]$raw.articleList.pageSize } else { Write-ProjectLog '配置 articleList.pageSize 无效，使用 10。' 'WARN' $Root }
    if ($null -ne $raw.articleList.groupBySection) { $defaults.articleList.groupBySection = [bool]$raw.articleList.groupBySection }
    if ($null -ne $raw.newArticle.tags) { $defaults.newArticle.tags = @($raw.newArticle.tags | ForEach-Object { [string]$_ } | Where-Object { $_ }) }
    if ($null -ne $raw.newArticle.date) { $defaults.newArticle.date = [string]$raw.newArticle.date }
    if ($null -ne $raw.newArticle.readingTime) { $defaults.newArticle.readingTime = [string]$raw.newArticle.readingTime }
    try {
      if ($null -ne $raw.update -and $null -ne $raw.update.PSObject.Properties['keep']) {
        if ($raw.update.keep -is [string]) { Write-ProjectLog '配置 update.keep 应为数组，已按单项处理。' 'WARN' $Root }
        $defaults.update.keep = @($raw.update.keep | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
      }
    } catch {
      Write-ProjectLog "update.keep 读取失败，按空列表处理：$($_.Exception.Message)" 'WARN' $Root
    }
    if ($null -ne $raw.PSObject.Properties['plugins']) {
      Write-ProjectLog 'projectme.config.json 中残留了旧版 plugins 配置段，已忽略；插件配置现在位于 plugins\<插件名>\config.json。' 'WARN' $Root
    }
    Write-ProjectLog "已读取配置文件：$path" 'INFO' $Root
  } catch {
    Write-ProjectLog "配置文件读取失败，使用默认配置：$($_.Exception.Message)" 'ERROR' $Root
  }
  return $defaults
}

function Write-ProjectJsonAtomic {
  param([Parameter(Mandatory)]$Value, [Parameter(Mandatory)][string]$Path, [int]$Depth = 8)
  $temp = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
  try {
    $json = $Value | ConvertTo-Json -Depth $Depth
    [IO.File]::WriteAllText($temp, "$json`r`n", [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temp -Destination $Path -Force
  } finally {
    if (Test-Path $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
  }
}

# 插件配置规范：每个插件的配置放在它自己的主目录下 —— plugins\<插件名>\config.json。
# 该文件由插件自带（可选的默认值），宿主只维护其中的保留键 enabled；
# 其余键完全属于插件。主程序配置 projectme.config.json 不再保存任何插件数据。

function Get-ProjectPluginConfigPath {
  param([Parameter(Mandatory)][string]$Id, [string]$Root = (Get-ProjectRoot))
  return Join-Path (Join-Path $Root 'plugins') (Join-Path $Id 'config.json')
}

function Get-ProjectPluginConfig {
  param([Parameter(Mandatory)][string]$Id, [string]$Root = (Get-ProjectRoot))
  $path = Get-ProjectPluginConfigPath -Id $Id -Root $Root
  if (-not (Test-Path $path -PathType Leaf)) { return $null }
  try {
    return Get-Content -Raw -Encoding UTF8 $path | ConvertFrom-Json
  } catch {
    Write-ProjectLog "插件配置无法解析（$Id）：$($_.Exception.Message)" 'WARN' $Root
    return $null
  }
}

function Save-ProjectPluginConfig {
  param([Parameter(Mandatory)][string]$Id, [Parameter(Mandatory)]$Config, [string]$Root = (Get-ProjectRoot))
  $directory = Split-Path -Parent (Get-ProjectPluginConfigPath -Id $Id -Root $Root)
  if (-not (Test-Path $directory -PathType Container)) { throw "插件目录不存在：$Id" }
  Write-ProjectJsonAtomic -Value $Config -Path (Get-ProjectPluginConfigPath -Id $Id -Root $Root) -Depth 12
}

function Test-ProjectPluginEnabled {
  param([Parameter(Mandatory)][string]$Id, [string]$Root = (Get-ProjectRoot), $Manifest = $null)
  $config = Get-ProjectPluginConfig -Id $Id -Root $Root
  if ($null -ne $config -and $null -ne $config.PSObject.Properties['enabled']) {
    return [bool]$config.enabled
  }
  if ($null -ne $Manifest -and $null -ne $Manifest.PSObject.Properties['defaultEnabled'] -and $null -ne $Manifest.defaultEnabled) {
    return [bool]$Manifest.defaultEnabled
  }
  return $false
}

function Test-ProjectPluginManifest {
  param([Parameter(Mandatory)]$Manifest)
  if ($null -eq $Manifest.PSObject.Properties['entry'] -or [string]::IsNullOrWhiteSpace([string]$Manifest.entry)) { return 'entry is required' }
  if ($null -ne $Manifest.PSObject.Properties['cli'] -and $null -ne $Manifest.cli) {
    if ([string]::IsNullOrWhiteSpace([string]$Manifest.cli.label)) { return 'cli.label is required' }
    if ([string]::IsNullOrWhiteSpace([string]$Manifest.cli.function)) { return 'cli.function is required' }
  }
  if ($null -ne $Manifest.PSObject.Properties['gui'] -and $null -ne $Manifest.gui) {
    if ([string]::IsNullOrWhiteSpace([string]$Manifest.gui.function)) { return 'gui.function is required' }
    $controls = @($Manifest.gui.controls | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($controls.Count -eq 0) { return 'gui.controls is required when gui is declared' }
  }
  return ''
}

function Get-ProjectPlugins {
  param([string]$Root = (Get-ProjectRoot), [switch]$SafeMode)
  $directory = Join-Path $Root 'plugins'
  if (-not (Test-Path $directory -PathType Container)) { return @() }
  $plugins = New-Object System.Collections.Generic.List[object]
  foreach ($folder in @(Get-ChildItem -LiteralPath $directory -Directory | Sort-Object Name)) {
    $status = 'ok'
    $problem = ''
    $manifest = $null
    $entryPath = $null
    $manifestPath = Join-Path $folder.FullName 'plugin.json'
    if (-not (Test-Path $manifestPath -PathType Leaf)) {
      $status = 'missing-manifest'
      $problem = '缺少 plugin.json'
    } else {
      try {
        $manifest = Get-Content -Raw -Encoding UTF8 $manifestPath | ConvertFrom-Json
      } catch {
        $status = 'invalid-manifest'
        $problem = "plugin.json 无法解析：$($_.Exception.Message)"
      }
      if ($status -eq 'ok') {
        $manifestProblem = Test-ProjectPluginManifest -Manifest $manifest
        if ($manifestProblem) { $status = 'invalid-manifest'; $problem = $manifestProblem }
      }
      if ($status -eq 'ok') {
        if ($null -ne $manifest.PSObject.Properties['id'] -and -not [string]::IsNullOrWhiteSpace([string]$manifest.id) -and [string]$manifest.id -ne $folder.Name) {
          Write-ProjectLog "插件 id（$($manifest.id)）与文件夹名（$($folder.Name)）不一致，按文件夹名处理。" 'WARN' $Root
        }
        $entryPath = Join-Path $folder.FullName ([string]$manifest.entry)
        if (-not (Test-Path $entryPath -PathType Leaf)) {
          $status = 'missing-entry'
          $problem = "入口脚本不存在：$($manifest.entry)"
          $entryPath = $null
        }
      }
    }
    $configPath = Get-ProjectPluginConfigPath -Id $folder.Name -Root $Root
    $pluginConfig = $null
    if ($status -eq 'ok') {
      $pluginConfig = Get-ProjectPluginConfig -Id $folder.Name -Root $Root
      $enabled = Test-ProjectPluginEnabled -Id $folder.Name -Root $Root -Manifest $manifest
      if ($SafeMode) { $enabled = $false }
    } else {
      $enabled = $false
      Write-ProjectLog "插件 $($folder.Name) 状态异常（$status）：$problem" 'WARN' $Root
    }
    $plugins.Add([pscustomobject]@{
      Id = $folder.Name
      Root = $folder.FullName
      Manifest = $manifest
      EntryPath = $entryPath
      ConfigPath = $configPath
      Config = $pluginConfig
      Enabled = $enabled
      Status = $status
      Problem = $problem
    })
  }
  return $plugins.ToArray()
}

function Set-ProjectPluginEnabled {
  param([Parameter(Mandatory)][string]$Id, [Parameter(Mandatory)][bool]$Enabled, [string]$Root = (Get-ProjectRoot))
  $config = Get-ProjectPluginConfig -Id $Id -Root $Root
  if ($null -eq $config) { $config = [pscustomobject]@{} }
  if ($null -eq $config.PSObject.Properties['enabled']) {
    $config | Add-Member -NotePropertyName enabled -NotePropertyValue $false -Force
  }
  $config.enabled = [bool]$Enabled
  Save-ProjectPluginConfig -Id $Id -Config $config -Root $Root
}

function Test-ProjectSafeZipEntry {
  param([Parameter(Mandatory)][string]$Name)
  if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
  $normalized = $Name -replace '\\', '/'
  if ($normalized.StartsWith('/')) { return $false }
  if ($normalized -match '^[A-Za-z]:') { return $false }
  foreach ($segment in @($normalized -split '/')) {
    if ($segment -eq '..') { return $false }
    $base = [IO.Path]::GetFileNameWithoutExtension($segment)
    if ($base -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$') { return $false }
  }
  return $true
}

function Get-Articles {
  param([string]$Root = (Get-ProjectRoot))
  $path = Join-Path $Root 'articles.json'
  return @(Get-Content -Raw -Encoding UTF8 $path | ConvertFrom-Json | ForEach-Object { $_ })
}

function Set-ArticlePropertyValue {
  param([Parameter(Mandatory)]$Article, [Parameter(Mandatory)][string]$Name, $Value)
  if ($null -ne $Article.PSObject.Properties[$Name]) { [void]($Article.PSObject.Properties[$Name].Value = $Value) }
  else { $Article | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force }
}

function Save-Articles {
  param([Parameter(Mandatory)]$Articles, [string]$Root = (Get-ProjectRoot))
  foreach ($article in @($Articles)) {
    if ($article.tags -is [string]) {
      $tags = if ([string]::IsNullOrWhiteSpace($article.tags)) { @() } else { @($article.tags) }
      Set-ArticlePropertyValue -Article $article -Name 'tags' -Value $tags
    }
  }
  Write-ProjectJsonAtomic -Value @($Articles) -Path (Join-Path $Root 'articles.json')
}

function Remove-ProjectArticle {
  param(
    [Parameter(Mandatory)][string]$Slug,
    [string]$Root = (Get-ProjectRoot)
  )
  $articles = @(Get-Articles -Root $Root)
  if ($articles.Count -le 1) { throw '项目中至少需要保留一篇文章，无法删除最后一篇。' }

  $article = $null
  for ($i = 0; $i -lt $articles.Count; $i++) {
    if ($articles[$i].slug -eq $Slug) { $article = $articles[$i]; break }
  }
  if ($null -eq $article) { throw "找不到文章：$Slug" }
  if ([string]::IsNullOrWhiteSpace([string]$article.file)) { throw "文章缺少文件名：$Slug" }

  $articlesPath = [IO.Path]::GetFullPath((Join-Path $Root 'articles'))
  $targetPath = [IO.Path]::GetFullPath((Join-Path $articlesPath ([string]$article.file)))
  $articlesPrefix = $articlesPath.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
  if (-not $targetPath.StartsWith($articlesPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "文章文件名超出 articles 目录：$($article.file)"
  }

  $timeline = Get-Timeline -Root $Root
  $originalEntries = @($timeline.entries)
  $remainingEntries = @($originalEntries | Where-Object { $_.slug -ne $Slug })
  $removedTimelineEntries = $originalEntries.Count - $remainingEntries.Count
  $remainingArticles = @($articles | Where-Object { $_.slug -ne $Slug })
  $backupPath = Join-Path $Root ('.projectme-delete-' + [guid]::NewGuid().ToString('N') + '.tmp')
  $fileMoved = $false
  $articlesSaved = $false
  $timelineSaved = $false

  try {
    if (Test-Path $targetPath -PathType Leaf) {
      Move-Item -LiteralPath $targetPath -Destination $backupPath
      $fileMoved = $true
    }
    Save-Articles -Articles $remainingArticles -Root $Root
    $articlesSaved = $true
    if ($removedTimelineEntries -gt 0) {
      Save-Timeline -Timeline ([pscustomobject]@{ entries = $remainingEntries }) -Root $Root
      $timelineSaved = $true
    }
    if ($fileMoved) { Remove-Item -LiteralPath $backupPath -Force }
  } catch {
    try {
      if ($articlesSaved) { Save-Articles -Articles $articles -Root $Root }
      if ($timelineSaved) { Save-Timeline -Timeline ([pscustomobject]@{ entries = $originalEntries }) -Root $Root }
      if ($fileMoved -and (Test-Path $backupPath -PathType Leaf)) { Move-Item -LiteralPath $backupPath -Destination $targetPath -Force }
    } catch {
      Write-ProjectLog ("删除文章后回滚失败：{0}`n{1}" -f $_.Exception.Message, $_.ScriptStackTrace) 'ERROR' $Root
    }
    throw
  } finally {
    if (Test-Path $backupPath -PathType Leaf) { Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue }
  }

  return [pscustomobject]@{
    title = [string]$article.title
    file = [string]$article.file
    removedTimelineEntries = $removedTimelineEntries
  }
}

function Save-ProjectInfo {
  param([Parameter(Mandatory)]$Info, [string]$Root = (Get-ProjectRoot))
  Write-ProjectJsonAtomic -Value $Info -Path (Join-Path $Root 'project-info.json')
}

function Get-PreviewStatePath {
  param([string]$Root = (Get-ProjectRoot))
  return Join-Path $Root '.projectme-serve.json'
}

function Get-PreviewState {
  param([string]$Root = (Get-ProjectRoot))
  $path = Get-PreviewStatePath -Root $Root
  if (-not (Test-Path $path -PathType Leaf)) { return $null }
  return Get-Content -Raw -Encoding UTF8 $path | ConvertFrom-Json
}

function Get-ListeningPreviewProcessId {
  param([int]$Port)
  foreach ($line in @(& netstat.exe -ano -p tcp 2>$null)) {
    if ($line -match "TCP\s+\S+:$([regex]::Escape([string]$Port))\s+\S+\s+LISTENING\s+(\d+)") {
      return [int]$Matches[1]
    }
  }
  return $null
}

function Stop-ProjectPreview {
  param(
    [string]$Root = (Get-ProjectRoot),
    [int[]]$Ports = @()
  )
  $state = Get-PreviewState -Root $Root
  $statePath = Get-PreviewStatePath -Root $Root
  $processIds = @{}
  $candidatePorts = @{}
  foreach ($port in @($Ports)) {
    if ($port -gt 0) { $candidatePorts[$port] = $true }
  }
  if ($null -ne $state) {
    $statePort = if ($null -ne $state.port) { [int]$state.port } else { 0 }
    $recordedPid = if ($null -ne $state.pid) { [int]$state.pid } else { 0 }
    if ($statePort -gt 0) { $candidatePorts[$statePort] = $true }
    if ($recordedPid -gt 0) { $processIds[$recordedPid] = $true }
  }
  foreach ($port in @($candidatePorts.Keys)) {
    $listeningPid = Get-ListeningPreviewProcessId -Port ([int]$port)
    if ($listeningPid -and -not $processIds.ContainsKey($listeningPid)) { $processIds[$listeningPid] = $true }
  }
  $stopped = $processIds.Count -gt 0
  foreach ($processId in @($processIds.Keys)) {
    Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
  }
  if ($stopped) { Start-Sleep -Milliseconds 250 }
  if (Test-Path $statePath -PathType Leaf) { Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue }
  return $stopped
}

function Get-Timeline {
  param([string]$Root = (Get-ProjectRoot))
  $path = Join-Path $Root 'timeline.json'
  if (-not (Test-Path $path -PathType Leaf)) { return [pscustomobject]@{ entries = @() } }
  return Get-Content -Raw -Encoding UTF8 $path | ConvertFrom-Json
}

function Save-Timeline {
  param([Parameter(Mandatory)]$Timeline, [string]$Root = (Get-ProjectRoot))
  Write-ProjectJsonAtomic -Value $Timeline -Path (Join-Path $Root 'timeline.json')
}

function Test-ProjectColor { param([string]$Value) return $Value -match '^(#[0-9a-fA-F]{3,8}|[a-zA-Z]+|rgba?\([^()]+\)|hsla?\([^()]+\))$' }

function Test-ProjectVersion { param([string]$Version) return $Version -match '^\d+\.\d+\.\d+$' }

function Get-DisplayVersion {
  param([Parameter(Mandatory)]$Info)
  $generation = if ($Info.PSObject.Properties.Name -contains 'generation' -and [int]$Info.generation -gt 0) { [int]$Info.generation } else { 1 }
  if ($generation -le 1) { return "v$($Info.version)" }
  return "v$($Info.version) Gen$generation"
}

function Get-CurrentChangelog {
  param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Version)
  $path = Join-Path $Root 'CHANGELOG.md'
  if (-not (Test-Path $path -PathType Leaf)) { return '手动更新，未提供更新日志。' }
  $lines = @(Get-Content -Encoding UTF8 $path)
  $start = -1
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match "^##\s+v$([regex]::Escape($Version))(?:\s|$)") { $start = $i + 1; break }
  }
  if ($start -lt 0) { return '手动更新，未提供更新日志。' }
  $notes = New-Object System.Collections.Generic.List[string]
  for ($i = $start; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^##\s+') { break }
    if ($lines[$i] -match '^\s*[-*]\s+(.+)$') { $notes.Add($Matches[1].Trim()) }
  }
  if ($notes.Count -eq 0) { return '手动更新，未提供更新日志。' }
  return ($notes -join '；')
}

function Add-ChangelogEntry {
  param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Version, [string]$Message = '手动更新，未提供更新日志。', [datetime]$Date = (Get-Date))
  if ([string]::IsNullOrWhiteSpace($Message)) { $Message = '手动更新，未提供更新日志。' }
  $path = Join-Path $Root 'CHANGELOG.md'
  $header = '# ProjectMe 更新日志'
  $old = if (Test-Path $path -PathType Leaf) { Get-Content -Raw -Encoding UTF8 $path } else { "$header`r`n" }
  $body = $old -replace '^# ProjectMe 更新日志\s*', ''
  $entry = "## v$Version - $($Date.ToString('yyyy-MM-dd'))`r`n- $Message`r`n`r`n"
  $content = "$header`r`n`r`n$entry$body".TrimEnd() + "`r`n"
  $temp = "$path.$([guid]::NewGuid().ToString('N')).tmp"
  try { [IO.File]::WriteAllText($temp, $content, [Text.UTF8Encoding]::new($true)); Move-Item -LiteralPath $temp -Destination $path -Force }
  finally { if (Test-Path $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue } }
}

function Get-SnapshotPath {
  param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Version, [datetime]$Date = (Get-Date), [string]$Label = '')
  $oldDirectory = Join-Path $Root 'old'
  if (-not (Test-Path $oldDirectory -PathType Container)) { New-Item -ItemType Directory -Path $oldDirectory -Force | Out-Null }
  $dateName = $Date.ToString('yyyyMMdd')
  $labelSuffix = ''
  if (-not [string]::IsNullOrWhiteSpace($Label)) { $labelSuffix = '-' + ($Label.Trim() -replace '[^\w\-]', '-') }
  $versionPattern = "v$([regex]::Escape($Version))-*.zip"
  $existing = @(Get-ChildItem -LiteralPath $oldDirectory -Filter $versionPattern -File -ErrorAction SilentlyContinue)
  $generation = 1
  if ($existing.Count -gt 0) {
    $numbers = @($existing | ForEach-Object { if ($_.BaseName -match '-Gen(\d+)$') { [int]$Matches[1] } else { 1 } })
    $generation = ([int]($numbers | Measure-Object -Maximum).Maximum) + 1
  }
  $name = if ($generation -eq 1) { "v$Version-$dateName$labelSuffix.zip" } else { "v$Version-$dateName$labelSuffix-Gen$generation.zip" }
  $path = Join-Path $oldDirectory $name
  while (Test-Path $path) {
    $generation++
    $path = Join-Path $oldDirectory "v$Version-$dateName$labelSuffix-Gen$generation.zip"
  }
  return $path
}

function New-ProjectSnapshot {
  param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Destination, [string[]]$Exclude = @())
  $destinationDirectory = Split-Path -Parent $Destination
  if (-not (Test-Path $destinationDirectory -PathType Container)) { New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null }
  $staging = Join-Path ([IO.Path]::GetTempPath()) ('ProjectMeSnapshot-' + [guid]::NewGuid().ToString('N'))
  $temporaryZip = "$Destination.$([guid]::NewGuid().ToString('N')).tmp.zip"
  New-Item -ItemType Directory -Path $staging -Force | Out-Null
  try {
    $skipNames = @('old', 'logs', '.projectme-serve.json') + @($Exclude | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    Get-ChildItem -LiteralPath $Root -Force | Where-Object { $_.Name -notin $skipNames } | ForEach-Object {
      Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $staging $_.Name) -Recurse -Force
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory($staging, $temporaryZip, [IO.Compression.CompressionLevel]::Optimal, $false)
    Move-Item -LiteralPath $temporaryZip -Destination $Destination -Force
    return $Destination
  } finally {
    if (Test-Path $staging) { Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue }
    if (Test-Path $temporaryZip) { Remove-Item -LiteralPath $temporaryZip -Force -ErrorAction SilentlyContinue }
  }
}

function Get-VersionSnapshots {
  param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Version)
  $oldDirectory = Join-Path $Root 'old'
  if (-not (Test-Path $oldDirectory -PathType Container)) { return @() }
  return @(Get-ChildItem -LiteralPath $oldDirectory -Filter "v$Version-*.zip" -File | Sort-Object Name)
}

function Restore-ProjectSnapshot {
  param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Snapshot)
  $oldDirectory = Join-Path $Root 'old'
  $resetDirectory = Join-Path $oldDirectory 'reseted'
  if (-not (Test-Path $resetDirectory -PathType Container)) { New-Item -ItemType Directory -Path $resetDirectory -Force | Out-Null }
  $backupPath = Join-Path $resetDirectory ((Get-Date).ToString('yyMMddHHmmss') + '.zip')
  while (Test-Path $backupPath) { $backupPath = Join-Path $resetDirectory ((Get-Date).ToString('yyMMddHHmmss') + '-' + (Get-Random -Maximum 9999) + '.zip') }
  New-ProjectSnapshot -Root $Root -Destination $backupPath | Out-Null

  $staging = Join-Path ([IO.Path]::GetTempPath()) ('ProjectMeRestore-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $staging -Force | Out-Null
  try {
    Expand-Archive -LiteralPath $Snapshot -DestinationPath $staging -Force
    Get-ChildItem -LiteralPath $Root -Force | Where-Object { $_.Name -notin @('old', '.git') } | Remove-Item -Recurse -Force
    Get-ChildItem -LiteralPath $staging -Force | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $Root $_.Name) -Recurse -Force }
    return $backupPath
  } finally {
    if (Test-Path $staging) { Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue }
  }
}
