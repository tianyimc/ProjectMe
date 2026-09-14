[CmdletBinding()]
param(
  [switch]$SafeMode
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $root 'ProjectMe.Common.ps1')
Write-ProjectLog 'CLI 启动'
$config = Get-ProjectConfig -Root $root
if ($SafeMode) {
  Write-Host '安全模式：本次运行不加载任何插件。' -ForegroundColor Yellow
  Write-ProjectLog '安全模式：本次运行已忽略全部插件' 'INFO' $root
}

function Pause-Menu { [void](Read-Host '按 Enter 返回菜单') }
function Clear-Menu { try { Clear-Host } catch { } }
function Read-Optional([string]$Prompt, [string]$Current = '') {
  $value = Read-Host "$Prompt [$Current]（回车保留，输入 - 清空）"
  if ($value -eq '') { return $Current }
  if ($value -eq '-') { return '' }
  return $value
}
function Read-Tags([object]$Current) {
  $shown = @($Current) -join ', '
  $value = Read-Host "主题标签（逗号分隔） [$shown]（回车保留，输入 - 清空）"
  if ($value -eq '') { return @($Current) }
  if ($value -eq '-') { return @() }
  return @($value -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}
function Set-ArticleProperty([object]$Article, [string]$Name, $Value) {
  if ($null -ne $Article.PSObject.Properties[$Name]) { [void]($Article.PSObject.Properties[$Name].Value = $Value) }
  else { $Article | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force }
}
function Get-OrderedArticles([object[]]$Articles) {
  return @($Articles | Sort-Object @{ Expression = { if ($null -ne $_.order) { [double]$_.order } else { try { (Get-Item (Join-Path $root ('articles\' + $_.file))).LastWriteTimeUtc.Ticks } catch { 0 } } }; Descending = $true })
}
function Show-ArticleList {
  $articles = Get-OrderedArticles (Get-Articles)
  $query = Read-Host '标题模糊搜索（回车显示全部）'
  if ($query) { $articles = @($articles | Where-Object { $_.title -like "*$query*" }) }
  $sectionMode = (Read-Host "按节分组显示？（Y/N，默认 $($config.articleList.groupBySection)）")
  $grouped = if ($sectionMode -eq '') { [bool]$config.articleList.groupBySection } else { $sectionMode -match '^[yY是]' }
  $pageSizeText = Read-Host "每页条数（默认 $($config.articleList.pageSize)）"
  $pageSize = [int]$config.articleList.pageSize; if ($pageSizeText -match '^\d+$' -and [int]$pageSizeText -gt 0) { $pageSize = [int]$pageSizeText }
  if ($grouped) {
    $articles = @($articles | Sort-Object @{Expression={ if ($_.section) {$_.section} else {'未分类'} }}, @{Expression={ if ($null -ne $_.order) { [double]$_.order } else { 0 } }; Descending=$true})
  }
  $page = 1
  do {
    $pages = [Math]::Max(1, [Math]::Ceiling($articles.Count / $pageSize))
    $page = [Math]::Min([Math]::Max($page, 1), $pages)
    Clear-Menu; Write-Host "ProjectMe 文章列表 · 第 $page/$pages 页" -ForegroundColor Cyan
    $start = ($page - 1) * $pageSize; $slice = @($articles | Select-Object -Skip $start -First $pageSize)
    $lastSection = $null; $number = $start
    foreach ($article in $slice) {
      $number++
      $section = if ($article.section) { $article.section } else { '未分类' }
      if ($grouped -and $section -ne $lastSection) { Write-Host "`n[$section]" -ForegroundColor Yellow; $lastSection = $section }
      Write-Host ("{0,3}. {1}  ({2})" -f $number, $article.title, $article.file)
    }
    Write-Host "`nn 下一页 | p 上一页 | 输入页码 | q 返回"
    $command = Read-Host '操作'
    if ($command -match '^\d+$') { $page = [int]$command }
    elseif ($command -match '^[nN]') { $page++ }
    elseif ($command -match '^[pP]') { $page-- }
  } while ($command -notmatch '^[qQ]')
}
function Select-Article {
  $articles = Get-OrderedArticles (Get-Articles); $query = Read-Host '输入标题关键词（回车显示全部）'
  if ($query) { $articles = @($articles | Where-Object { $_.title -like "*$query*" }) }
  for ($i = 0; $i -lt $articles.Count; $i++) { Write-Host ("{0,3}. {1} ({2})" -f ($i + 1), $articles[$i].title, $articles[$i].file) }
  $choice = Read-Host '选择编号（回车取消）'; if ($choice -notmatch '^\d+$') { return $null }
  $index = [int]$choice - 1; if ($index -lt 0 -or $index -ge $articles.Count) { return $null }; return $articles[$index]
}
function Edit-Article {
  $selected = Select-Article; if ($null -eq $selected) { return }
  $confirmFile = Read-Host "请输入文件名确认 [$($selected.file)]"; if ($confirmFile -ne $selected.file) { Write-Warning '文件名不匹配，已取消。'; Pause-Menu; return }
  $updated = $selected.PSObject.Copy()
  Set-ArticleProperty $updated 'title' (Read-Optional '标题' $selected.title); Set-ArticleProperty $updated 'category' (Read-Optional '类别' $selected.category)
  Set-ArticleProperty $updated 'tags' (Read-Tags $selected.tags); Set-ArticleProperty $updated 'section' (Read-Optional '节' $selected.section)
  Set-ArticleProperty $updated 'date' (Read-Optional '日期' $selected.date); Set-ArticleProperty $updated 'readingTime' (Read-Optional '阅读时间' $selected.readingTime)
  Set-ArticleProperty $updated 'excerpt' (Read-Optional '摘要' $selected.excerpt); Set-ArticleProperty $updated 'titleFont' (Read-Optional '目录标题字体' $selected.titleFont)
  do { $titleColor = Read-Optional '目录标题颜色' $selected.titleColor; $valid = [string]::IsNullOrWhiteSpace($titleColor) -or (Test-ProjectColor $titleColor); if (-not $valid) { Write-Warning '颜色格式无效。' } } while (-not $valid)
  Set-ArticleProperty $updated 'titleColor' $titleColor
  Write-Host "`n标题: $($selected.title) -> $($updated.title)"; Write-Host "主题: $(@($selected.tags) -join ', ') -> $(@($updated.tags) -join ', ')"; Write-Host "节: $($selected.section) -> $($updated.section)"
  if ((Read-Host '确认保存？（Y/N）') -notmatch '^[yY是]') { return }
  $articles = @(Get-Articles); for ($i = 0; $i -lt $articles.Count; $i++) { if ($articles[$i].slug -eq $selected.slug) { $articles[$i] = $updated } }; Save-Articles $articles
  Write-Host '属性已保存，articles.json 已更新。' -ForegroundColor Green; Pause-Menu
}
function Remove-ArticleInteractive {
  $selected = Select-Article
  if ($null -eq $selected) { return }
  Write-Host "`n警告：即将永久删除文章。" -ForegroundColor Red
  Write-Host "标题：$($selected.title)"
  $selectedSource = if ($selected.PSObject.Properties.Name -contains 'path' -and -not [string]::IsNullOrWhiteSpace([string]$selected.path)) { [string]$selected.path } else { "articles\$($selected.file)" }
  Write-Host "文件：$selectedSource"
  Write-Host '此操作会同时移除文章索引、Markdown 正文和时间轴中的对应条目；由插件导入的源文件不会被删除，下次导入仍可能重新创建此文章。'
  Write-Host "请输入文件名（含 .md）确认删除：$($selected.file)" -ForegroundColor Yellow
  $confirmFile = Read-Host '确认删除文件名'
  if ($confirmFile -ne $selected.file) {
    Write-ProjectLog "取消删除文章：$($selected.slug)"
    Write-Host '文件名不匹配，已取消删除。' -ForegroundColor Yellow
    Pause-Menu
    return
  }
  try {
    $result = Remove-ProjectArticle -Root $root -Slug $selected.slug
    Write-ProjectLog "CLI 删除文章：$($result.file)，清除时间轴条目 $($result.removedTimelineEntries) 条" 'INFO' $root
    Write-Host "已删除文章：$($result.title)" -ForegroundColor Green
  } catch {
    Write-ProjectLog ("CLI 删除文章失败：{0}`n{1}" -f $_.Exception.Message, $_.ScriptStackTrace) 'ERROR' $root
    Write-Host "删除失败：$($_.Exception.Message)" -ForegroundColor Red
  }
  Pause-Menu
}
function Invoke-Script([string]$Name, [string[]]$Arguments = @()) { & (Join-Path $root $Name) @Arguments; Pause-Menu }
function New-ArticleInteractive {
  $params = @{}
  $prompts = [ordered]@{ Slug = '文章标识（仅限小写字母、数字和连字符）'; Title = '文章标题'; Category = '文章类别'; Excerpt = '文章摘要' }
  foreach ($field in $prompts.Keys) { $value = Read-Host $prompts[$field]; if ($value) { $params[$field] = $value } }
  $tags = Read-Host "主题标签（逗号分隔，回车使用默认“$(@($config.newArticle.tags) -join ', ')”）"; if ($tags) { $params['Tags'] = @($tags -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) } else { $params['Tags'] = @($config.newArticle.tags) }
  $date = Read-Host "日期（回车使用默认值“$($config.newArticle.date)”）"; if ($date) { $params['Date'] = $date } elseif ($config.newArticle.date) { $params['Date'] = $config.newArticle.date }
  $reading = Read-Host "阅读时间（回车使用 $($config.newArticle.readingTime)）"; if ($reading) { $params['ReadingTime'] = $reading } else { $params['ReadingTime'] = $config.newArticle.readingTime }
  & (Join-Path $root 'New-Article.ps1') @params; Pause-Menu
}
function Show-Log {
  $logPath = Join-Path $root 'logs\projectme-cli.log'
  if (-not (Test-Path $logPath)) { Write-Host '暂时没有日志。'; Pause-Menu; return }
  Write-Host "--- 最近 80 行日志：$logPath ---" -ForegroundColor Cyan
  Get-Content -LiteralPath $logPath -Encoding UTF8 -Tail 80
  Pause-Menu
}
function Start-Gui {
  $hostCommand = (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source
  if (-not $hostCommand) { $hostCommand = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source }
  if (-not $hostCommand) { throw '找不到 PowerShell 启动程序，无法打开 GUI。' }
  Start-Process $hostCommand -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $root 'ProjectMe.Gui.ps1')) -WindowStyle Normal
}
function Serve-Menu {
  $port = Read-Host "端口（回车使用 $($config.serve.port)）"; if (-not $port) { $port = [string]$config.serve.port }; $mode = Read-Host "前台运行还是后台运行？（F/B，默认 $($config.serve.mode)）"
  if (-not $mode) { $mode = $config.serve.mode }
  if ($mode -match '^[bB]') {
    $statePath = Join-Path $root '.projectme-serve.json'; $process = Start-Process powershell -ArgumentList @('-ExecutionPolicy','Bypass','-File',(Join-Path $root 'serve.ps1'),'-Port',$port) -PassThru
    Write-ProjectJsonAtomic -Value ([pscustomobject]@{ pid = $process.Id; port = [int]$port; started = (Get-Date).ToString('o') }) -Path $statePath; Write-Host "后台服务已启动，PID $($process.Id)"; Pause-Menu
  } else {
    Write-Host '前台服务将在新的服务窗口中运行，关闭该窗口即可停止服务。' -ForegroundColor Cyan
    Start-Process powershell -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $root 'serve.ps1'),'-Port',$port) -Wait -WindowStyle Normal
  }
}
function Timeline-Menu { & (Join-Path $root 'Timeline.ps1') }
function Service-Status {
  $state = Get-PreviewState -Root $root
  if ($null -eq $state) { Write-Host '没有运行中的后台服务。'; return }
  $listeningPid = if ($state.port) { Get-ListeningPreviewProcessId -Port ([int]$state.port) } else { $null }
  $running = if ($state.pid) { Get-Process -Id ([int]$state.pid) -ErrorAction SilentlyContinue } else { $null }
  if ($listeningPid -or $running) {
    $displayPid = if ($listeningPid) { $listeningPid } else { [int]$state.pid }
    $displayPort = if ($state.port) { $state.port } else { '?' }
    Write-Host "运行中：PID $displayPid，端口 $displayPort"
  } else {
    Remove-Item -LiteralPath (Get-PreviewStatePath -Root $root) -Force -ErrorAction SilentlyContinue
    Write-Host '服务已停止。'
  }
}
function Service-Stop {
  if (Stop-ProjectPreview -Root $root) { Write-Host '后台服务已停止。' }
  else { Write-Host '没有运行中的后台服务。' }
  Pause-Menu
}
function Rollback-Version {
  $version = Read-Host '请输入需要回滚的版本号（X.X.X）'
  if (-not (Test-ProjectVersion $version)) { Write-Warning '版本号格式无效。'; Pause-Menu; return $false }
  $snapshots = @(Get-VersionSnapshots -Root $root -Version $version)
  if ($snapshots.Count -eq 0) { Write-Warning "old 目录中没有找到 v$version 的快照。"; Pause-Menu; return $false }
  Write-Host "找到以下 v$version 快照：" -ForegroundColor Cyan
  for ($i = 0; $i -lt $snapshots.Count; $i++) { Write-Host ("{0,3}. {1}  ({2})" -f ($i + 1), $snapshots[$i].Name, $snapshots[$i].LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')) }
  $choice = Read-Host '请选择要释放的快照编号（回车取消）'
  if ($choice -notmatch '^\d+$' -or [int]$choice -lt 1 -or [int]$choice -gt $snapshots.Count) { return $false }
  $snapshot = $snapshots[[int]$choice - 1]
  $current = Get-ProjectInfo
  Write-Host "当前版本：$(Get-DisplayVersion $current)`n目标快照：$($snapshot.Name)"
  if ((Read-Host '确认回滚？这会替换主目录项目文件（Y/N）') -notmatch '^[yY是]') { Write-ProjectLog "取消回滚：$($snapshot.FullName)"; return $false }
  try {
    $backup = Restore-ProjectSnapshot -Root $root -Snapshot $snapshot.FullName
    Write-ProjectLog "回滚成功：$($snapshot.FullName)；回滚前备份：$backup"
    Write-Host "回滚完成。当前 CLI 需要退出，请重新启动 ProjectMe.ps1。" -ForegroundColor Green
    Pause-Menu
    return $true
  } catch {
    Write-ProjectLog ("回滚失败：{0}`n{1}" -f $_.Exception.Message, $_.ScriptStackTrace) 'ERROR'
    throw
  }
}
function Build-MainMenu([object]$Config, [switch]$SafeMode) {
  $pluginItems = @(Get-ProjectPlugins -Root $root -SafeMode:$SafeMode | Where-Object { $_.Enabled -and $null -ne $_.Manifest.PSObject.Properties['cli'] -and $null -ne $_.Manifest.cli })
  $items = @(
    [pscustomobject]@{ Number = 1; Label = '文章列表'; Kind = 'builtin'; Action = 'list' }
    [pscustomobject]@{ Number = 2; Label = '编辑文章属性'; Kind = 'builtin'; Action = 'edit' }
    [pscustomobject]@{ Number = 3; Label = '删除文章'; Kind = 'builtin'; Action = 'remove' }
    [pscustomobject]@{ Number = 4; Label = 'GUI 窗口管理器'; Kind = 'builtin'; Action = 'gui' }
    [pscustomobject]@{ Number = 5; Label = 'Check-ProjectMe'; Kind = 'builtin'; Action = 'check' }
    [pscustomobject]@{ Number = 6; Label = 'New-Article'; Kind = 'builtin'; Action = 'new' }
    [pscustomobject]@{ Number = 7; Label = 'serve'; Kind = 'builtin'; Action = 'serve' }
    [pscustomobject]@{ Number = 8; Label = '服务状态'; Kind = 'builtin'; Action = 'status' }
    [pscustomobject]@{ Number = 9; Label = '停止后台服务'; Kind = 'builtin'; Action = 'stop' }
    [pscustomobject]@{ Number = 10; Label = '查看 CLI 日志'; Kind = 'builtin'; Action = 'log' }
    [pscustomobject]@{ Number = 11; Label = '时间轴'; Kind = 'builtin'; Action = 'timeline' }
    [pscustomobject]@{ Number = 12; Label = '回滚版本'; Kind = 'builtin'; Action = 'rollback' }
    [pscustomobject]@{ Number = 13; Label = '关于/版本信息'; Kind = 'builtin'; Action = 'about' }
    [pscustomobject]@{ Number = 14; Label = '插件管理器'; Kind = 'builtin'; Action = 'plugins' }
  )
  foreach ($pluginItem in $pluginItems) {
    $items += [pscustomobject]@{ Number = $items.Count + 1; Label = [string]$pluginItem.Manifest.cli.label; Kind = 'plugin'; Plugin = $pluginItem }
  }
  foreach ($pluginItem in $pluginItems) { Write-ProjectLog "已启用插件：$($pluginItem.Id)（CLI 菜单 $($items | Where-Object { $_.Plugin -eq $pluginItem } | Select-Object -First 1 | ForEach-Object { $_.Number })）" }
  return [pscustomobject]@{ Items = $items; Text = (@($items | ForEach-Object { "$($_.Number). $($_.Label)" }) + '0. 退出') -join "`n" }
}
$menu = Build-MainMenu -Config $config -SafeMode:$SafeMode
$menuDirty = $false

while ($true) {
  if ($menuDirty) { $config = Get-ProjectConfig -Root $root; $menu = Build-MainMenu -Config $config -SafeMode:$SafeMode; $menuDirty = $false }
  $info = Get-ProjectInfo
  Clear-Menu
  Write-Host "$(Get-DisplayVersion $info)" -ForegroundColor Cyan
  Write-Host "$($info.title) · 作者：$($info.author) · $($info.copyright)`n"
  Write-Host $menu.Text
  $choice = Read-Host '请选择'
  if ([Console]::IsInputRedirected -and [string]::IsNullOrWhiteSpace($choice)) { break }
  Write-ProjectLog "菜单选择：$choice"
  try {
    if ($choice -notmatch '^\d+$') { Write-Host '请输入菜单编号。' -ForegroundColor Yellow; Start-Sleep -Milliseconds 500; continue }
    if ([int]$choice -eq 0) { Write-ProjectLog 'CLI 退出'; exit }
    $selected = @($menu.Items | Where-Object { $_.Number -eq [int]$choice } | Select-Object -First 1)
    if ($selected.Count -eq 0) { Write-Host '无效的菜单选项。' -ForegroundColor Yellow; Start-Sleep -Milliseconds 500; continue }
    if ($selected[0].Kind -eq 'plugin') {
      try {
        . ($selected[0].Plugin.EntryPath)
        & ([string]$selected[0].Plugin.Manifest.cli.function)
      } catch {
        Write-ProjectLog ("插件执行失败：{0}`n{1}" -f $_.Exception.Message, $_.ScriptStackTrace) 'ERROR'
        Write-Host "`n插件执行失败：$($_.Exception.Message)" -ForegroundColor Red
        Pause-Menu
      }
      continue
    }
    switch ($selected[0].Action) {
      'list' { Show-ArticleList }
      'edit' { Edit-Article }
      'remove' { Remove-ArticleInteractive }
      'gui' { Start-Gui }
      'check' { Invoke-Script 'Check-ProjectMe.ps1' }
      'new' { New-ArticleInteractive }
      'serve' { Serve-Menu }
      'status' { Service-Status; Pause-Menu }
      'stop' { Service-Stop }
      'log' { Show-Log }
      'timeline' { Timeline-Menu }
      'rollback' { if (Rollback-Version) { exit } }
      'about' { $currentLog = Get-CurrentChangelog -Root $root -Version $info.version; Write-Host "$($info.description)`n版本 $(Get-DisplayVersion $info)`n作者 $($info.author)`n作者主页 $($info.authorUrl)`n许可证 $($info.licenseName)`n$($info.copyright)`n`n当前版本更新日志：$currentLog"; Pause-Menu }
      'plugins' { try { & (Join-Path $root 'Manage-Plugins.ps1') } finally { $menuDirty = $true } }
    }
  } catch {
    Write-ProjectLog ("未处理异常：{0}`n{1}" -f $_.Exception.Message, $_.ScriptStackTrace) 'ERROR'
    Write-Host "`n发生错误：$($_.Exception.Message)" -ForegroundColor Red
    Write-Host "详细信息已写入：$root\logs\projectme-cli.log"
    Pause-Menu
  }
}
