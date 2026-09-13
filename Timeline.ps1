[CmdletBinding()]
param(
  [ValidateSet('menu','list','search','select','edit','remove')][string]$Action = 'menu',
  [string]$Slug,
  [string]$Date,
  [int]$Priority,
  [AllowEmptyString()][string]$Description,
  [string]$Query,
  [string]$Root = ''
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Split-Path -Parent $MyInvocation.MyCommand.Path }
. (Join-Path $Root 'ProjectMe.Common.ps1')
$DescriptionProvided = $PSBoundParameters.ContainsKey('Description')
$script:TimelineDescriptionProvided = $DescriptionProvided
$script:TimelinePriorityProvided = $PSBoundParameters.ContainsKey('Priority')
$script:TimelinePriority = $Priority

function Save-Entries([object[]]$Entries) {
  Save-Timeline ([pscustomobject]@{ entries = @($Entries) }) $Root
  Write-ProjectLog "时间轴已保存：$($Entries.Count) 条" 'INFO' $Root
}

function Find-Entry([object[]]$Entries, [string]$Value) {
  if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
  if ($Value -match '^\d+$') { $index = [int]$Value - 1; if ($index -ge 0 -and $index -lt $Entries.Count) { return $Entries[$index] } }
  return $Entries | Where-Object { $_.slug -eq $Value } | Select-Object -First 1
}

function Read-DateValue([string]$Current = '', [switch]$Required) {
  do {
    $value = Read-Host "日期 YYYYMMDD [$Current]（回车保留当前值）"
    if ($value -eq '' -and $Current) { return $Current }
    if ($value -eq '' -and -not $Required) { return '' }
    if ($value -match '^\d{8}$') { try { [datetime]::ParseExact($value, 'yyyyMMdd', $null) | Out-Null; return $value } catch { } }
    Write-Warning '日期必须是有效的 YYYYMMDD。'
  } while ($true)
}

function Select-Candidate([object[]]$Articles) {
  $queryValue = if ($Query) { $Query } else { Read-Host '搜索标题、slug、类别或主题（回车显示全部）' }
  $candidates = @($Articles | Where-Object { !$queryValue -or @($_.title, $_.slug, $_.category, $_.excerpt, @($_.tags)) -join ' ' -like "*$queryValue*" })
  if (-not $candidates) { Write-Host '没有匹配的文章。' -ForegroundColor Yellow; return $null }
  for ($i = 0; $i -lt $candidates.Count; $i++) { Write-Host ("{0,3}. {1} [{2}]" -f ($i + 1), $candidates[$i].title, $candidates[$i].slug) }
  $choice = if ($Slug) { $Slug } else { Read-Host '选择编号或 slug（回车取消）' }
  if ($choice -match '^\d+$') { $index = [int]$choice - 1; if ($index -ge 0 -and $index -lt $candidates.Count) { return $candidates[$index] } }
  return $candidates | Where-Object { $_.slug -eq $choice } | Select-Object -First 1
}

function Ensure-Priorities([object[]]$Entries) {
  $groups = @($Entries | Where-Object { -not $_.disabled -and $_.date } | Group-Object date)
  foreach ($group in $groups) {
    $next = 1
    foreach ($entry in @($group.Group)) {
      if ($null -eq $entry.PSObject.Properties['priority'] -or [int]$entry.priority -lt 1) { $entry | Add-Member -NotePropertyName priority -NotePropertyValue $next -Force }
      $next++
    }
  }
}

function Get-SameDayEntries([object[]]$Entries, [string]$Date, [string]$ExcludeSlug = '') {
  return @($Entries | Where-Object { -not $_.disabled -and $_.date -eq $Date -and $_.slug -ne $ExcludeSlug })
}

function Read-PriorityValue([object[]]$Entries, [string]$Date, [string]$ExcludeSlug = '', [int]$Current = 1) {
  $sameDay = Get-SameDayEntries $Entries $Date $ExcludeSlug
  if ($sameDay.Count -eq 0) { return 1 }
  if ($script:TimelinePriorityProvided) { if ($script:TimelinePriority -lt 1) { throw '同日优先级必须是大于 0 的整数。' }; return $script:TimelinePriority }
  do {
    $value = Read-Host "同日已有 $($sameDay.Count) 条文章，请输入优先级（1 最新，数字越大越早，回车保留 $Current）"
    if ($value -eq '') { return $Current }
    if ($value -match '^\d+$' -and [int]$value -gt 0) { return [int]$value }
    Write-Warning '优先级必须是大于 0 的整数。'
  } while ($true)
}

function Set-Priority([object[]]$Entries, [object]$Entry, [int]$PriorityValue) {
  $sameDay = Get-SameDayEntries $Entries $Entry.date $Entry.slug | Sort-Object @{ Expression = { if ($null -ne $_.priority) { [int]$_.priority } else { 999999 } } }, slug
  $position = [Math]::Max(1, [Math]::Min($PriorityValue, $sameDay.Count + 1))
  foreach ($other in $sameDay) { if ($null -eq $other.PSObject.Properties['priority']) { $other | Add-Member -NotePropertyName priority -NotePropertyValue 1 -Force } }
  foreach ($other in $sameDay) { if ([int]$other.priority -ge $position) { $other.priority = [int]$other.priority + 1 } }
  if ($null -eq $Entry.PSObject.Properties['priority']) { $Entry | Add-Member -NotePropertyName priority -NotePropertyValue $position -Force } else { $Entry.priority = $position }
}

function Invoke-List {
  $entries = @((Get-Timeline $Root).entries)
  if (-not $entries) { Write-Host '时间轴还没有文章。' -ForegroundColor Yellow; return }
  Ensure-Priorities $entries
  for ($i = 0; $i -lt $entries.Count; $i++) { $state = if ($entries[$i].disabled) { '已禁用' } else { '启用' }; $priority = if ($entries[$i].priority) { $entries[$i].priority } else { '-' }; Write-Host ("{0,3}. {1} [{2}] {3} 优先级:{4} {5}" -f ($i + 1), $entries[$i].title, $entries[$i].slug, $entries[$i].date, $priority, $state) }
}

function Invoke-Search {
  $queryValue = if ($Query) { $Query } else { Read-Host '搜索关键词' }
  Get-Articles $Root | Where-Object { @($_.title, $_.slug, $_.category, $_.excerpt, @($_.tags)) -join ' ' -like "*$queryValue*" } | ForEach-Object { Write-Host "$($_.slug)  $($_.title)" }
}

function Invoke-Select {
  $articles = Get-Articles $Root; $entries = @((Get-Timeline $Root).entries); Ensure-Priorities $entries; $article = Select-Candidate $articles
  if ($null -eq $article) { return }
  $entry = $entries | Where-Object { $_.slug -eq $article.slug } | Select-Object -First 1
  $chosenDate = if ($Date) { $Date } elseif ($article.date -match '^\d{8}$') { $article.date } else { Read-DateValue '' -Required }
  try { [datetime]::ParseExact($chosenDate, 'yyyyMMdd', $null) | Out-Null } catch { throw '日期必须是有效的 YYYYMMDD。' }
  $oldDate = if ($entry) { $entry.date } else { '' }
  $currentPriority = if ($entry.priority) { [int]$entry.priority } else { 1 }
  $chosenPriority = Read-PriorityValue $entries $chosenDate $(if ($entry) { $entry.slug } else { '' }) $currentPriority
  $text = if ($script:TimelineDescriptionProvided) { $Description } elseif ($entry) { $entry.description } else { Read-Host '时间轴专用说明（可为空）' }
  if ($entry) { $entry.title = $article.title; $entry.date = $chosenDate; $entry.description = $text; $entry.disabled = $false; Set-Priority $entries $entry $chosenPriority }
  else { $entries += [pscustomobject]@{ slug = $article.slug; title = $article.title; date = $chosenDate; description = $text; disabled = $false; priority = $chosenPriority } }
  Save-Entries $entries; Write-Host "已选入时间轴：$($article.title)" -ForegroundColor Green
}

function Invoke-Edit {
  $entries = @((Get-Timeline $Root).entries); Ensure-Priorities $entries; if (-not $Slug) { Invoke-List }
  $entry = Find-Entry $entries $(if ($Slug) { $Slug } else { Read-Host '输入条目编号或 slug（回车取消）' }); if ($null -eq $entry) { return }
  $entry.date = if ($Date) { $Date } else { Read-DateValue $entry.date -Required }
  try { [datetime]::ParseExact($entry.date, 'yyyyMMdd', $null) | Out-Null } catch { throw '日期必须是有效的 YYYYMMDD。' }
  $entry.priority = Read-PriorityValue $entries $entry.date $entry.slug $(if ($entry.priority) { [int]$entry.priority } else { 1 })
  if ($script:TimelineDescriptionProvided) { $entry.description = $Description } else { $newText = Read-Host "时间轴专用说明 [$($entry.description)]（回车保留，输入 - 清空）"; if ($newText -eq '-') { $entry.description = '' } elseif ($newText) { $entry.description = $newText } }
  Set-Priority $entries $entry $entry.priority
  Save-Entries $entries; Write-Host '时间轴条目已更新。' -ForegroundColor Green
}

function Invoke-Remove {
  $entries = @((Get-Timeline $Root).entries); Ensure-Priorities $entries; if (-not $Slug) { Invoke-List }
  $entry = Find-Entry $entries $(if ($Slug) { $Slug } else { Read-Host '输入条目编号或 slug（回车取消）' }); if ($null -eq $entry) { return }
  $entry.disabled = $true; Save-Entries $entries; Write-Host "已禁用：$($entry.title)" -ForegroundColor Green
}

function Invoke-Menu {
  do {
    try { Clear-Host } catch { }
    Write-Host "`n时间轴`n1. 列出条目`n2. 搜索文章`n3. 选入文章`n4. 编辑条目`n5. 移除条目`n0. 返回"
    $choice = Read-Host '请选择'
    switch ($choice) { '1' { Invoke-List; Read-Host '按 Enter 返回' }; '2' { Invoke-Search; Read-Host '按 Enter 返回' }; '3' { Invoke-Select; Read-Host '按 Enter 返回' }; '4' { Invoke-Edit; Read-Host '按 Enter 返回' }; '5' { Invoke-Remove; Read-Host '按 Enter 返回' } }
  } while ($choice -ne '0')
}

switch ($Action) { 'menu' { Invoke-Menu }; 'list' { Invoke-List }; 'search' { Invoke-Search }; 'select' { Invoke-Select }; 'edit' { Invoke-Edit }; 'remove' { Invoke-Remove } }
