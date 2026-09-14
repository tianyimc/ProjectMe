# ProjectMe 无损更新器
#
# 用法：
#   .\Update-ProjectMe.ps1 -Package .\ProjectMe-v1.1.8.zip
#   .\Update-ProjectMe.ps1 -Package .\解压后的新版本目录 -WhatIf
#   .\Update-ProjectMe.ps1 -Package .\ProjectMe-v1.1.8.zip -Overwrite
#
# 行为：
#   * 只写入包体内的“程序文件”，用户数据（articles/、articles.json、timeline.json、
#     projectme.config.json、.gitignore、logs/、old/、.git/、各插件自己的 plugins\<插件名>\config.json）
#     永不写入、永不删除；
#   * project-info.json 采用合并策略：版本号取自包体，其余键保留本地值；
#   * 更新前自动在 old\ 生成完整备份，失败时按文件精确回滚；
#   * 本地内容与包体不同的文件会逐个询问“保留本地版本 / 用包体覆盖”。

[CmdletBinding(SupportsShouldProcess)]
param(
  [Parameter(Mandatory = $true, Position = 0)][string]$Package,
  [string]$ProjectRoot = '',
  [string[]]$Keep = @(),
  [switch]$Overwrite,
  [switch]$KeepLocal,
  [switch]$Force
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

# 默认安装目录 = 脚本所在目录。不能用 $MyInvocation 作为参数默认值：以 -File 方式启动时
# 参数默认值的求值阶段拿不到脚本路径。
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = $PSScriptRoot }
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }

# -WhatIf 在这里是“只打印计划、不写入安装目录”的预演开关。PowerShell 的 -WhatIf 会连带抑制
# 脚本内部所有支持 ShouldProcess 的 cmdlet（连解压包体、创建日志目录都会被跳过），因此先把
# 偏好变量关掉，改由脚本自己在写入闸门处停止。
$updateDryRun = [bool]$WhatIfPreference
if ($updateDryRun) { $WhatIfPreference = $false }

if ($Overwrite -and $KeepLocal) { throw '不能同时使用 -Overwrite 与 -KeepLocal。' }

$root = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\', '/')
if (-not (Test-Path (Join-Path $root 'project-info.json') -PathType Leaf) -or -not (Test-Path (Join-Path $root 'ProjectMe.ps1') -PathType Leaf)) {
  throw "这不是一个 ProjectMe 安装目录：$root"
}
. (Join-Path $root 'ProjectMe.Common.ps1')

$script:ProtectedDirectories = @('articles', 'logs', 'old', '.git')
$script:ProtectedFiles = @('articles.json', 'timeline.json', 'projectme.config.json', '.gitignore', '.projectme-serve.json')

function Test-ProjectProtectedPath([string]$Relative) {
  $normalized = $Relative -replace '/', '\'
  if ($script:ProtectedFiles -contains $normalized) { return $true }
  # 插件自己的配置文件属于用户数据
  if ($normalized -match '^plugins\\[^\\]+\\config\.json$') { return $true }
  foreach ($directory in $script:ProtectedDirectories) {
    if ($normalized -eq $directory) { return $true }
    if ($normalized.StartsWith($directory + '\', [StringComparison]::OrdinalIgnoreCase)) { return $true }
  }
  return $false
}

function Test-ProjectKeptPath([string]$Relative, [string[]]$Patterns) {
  $normalized = $Relative -replace '/', '\'
  foreach ($pattern in @($Patterns)) {
    if ([string]::IsNullOrWhiteSpace([string]$pattern)) { continue }
    $trimmed = ([string]$pattern).Trim().TrimEnd('\', '/')
    if ($normalized -like $trimmed -or $normalized -like ($trimmed + '\*')) { return $true }
  }
  return $false
}

function Get-ProjectFileHashValue([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Test-ProjectPackageRoot([string]$Path) {
  return (Test-Path (Join-Path $Path 'project-info.json') -PathType Leaf) -and
         (Test-Path (Join-Path $Path 'ProjectMe.ps1') -PathType Leaf) -and
         (Test-Path (Join-Path $Path 'ProjectMe.Common.ps1') -PathType Leaf)
}

function Merge-ProjectInfo([object]$Local, [object]$Package) {
  $merged = $Local.PSObject.Copy()
  foreach ($name in @('version', 'generation')) {
    if ($null -ne $Package.PSObject.Properties[$name]) {
      if ($null -ne $merged.PSObject.Properties[$name]) { $merged.$name = $Package.$name }
      else { $merged | Add-Member -NotePropertyName $name -NotePropertyValue $Package.$name -Force }
    }
  }
  foreach ($property in $Package.PSObject.Properties) {
    if ($null -eq $merged.PSObject.Properties[$property.Name]) {
      $merged | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value -Force
    }
  }
  return $merged
}

function Save-ProjectUpdateKeep([string]$Root, [string[]]$Patterns) {
  $path = Join-Path $Root 'projectme.config.json'
  $config = if (Test-Path $path -PathType Leaf) { Get-Content -Raw -Encoding UTF8 $path | ConvertFrom-Json } else { Get-DefaultProjectConfig }
  if ($null -eq $config.PSObject.Properties['update']) { $config | Add-Member -NotePropertyName update -NotePropertyValue ([pscustomobject]@{ keep = @() }) -Force }
  if ($null -eq $config.update.PSObject.Properties['keep']) { $config.update | Add-Member -NotePropertyName keep -NotePropertyValue @() -Force }
  $config.update.keep = @($Patterns | Sort-Object -Unique)
  Write-ProjectJsonAtomic -Value $config -Path $path -Depth 12
}

function Restore-ProjectFilesFromBackup([string]$Root, [string]$BackupZip, [string[]]$WrittenPaths) {
  $archive = [IO.Compression.ZipFile]::OpenRead($BackupZip)
  try {
    foreach ($relative in $WrittenPaths) {
      $destination = Join-Path $Root $relative
      $entryName = $relative -replace '\\', '/'
      $entry = $archive.Entries | Where-Object { $_.FullName -eq $entryName } | Select-Object -First 1
      if ($null -ne $entry) {
        $directory = Split-Path -Parent $destination
        if (-not (Test-Path $directory -PathType Container)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
        [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $destination, $true)
      } elseif (Test-Path -LiteralPath $destination -PathType Leaf) {
        Remove-Item -LiteralPath $destination -Force
        $parent = Split-Path -Parent $destination
        while ($parent -and $parent.Length -gt $Root.Length -and (Test-Path $parent -PathType Container) -and -not @(Get-ChildItem -LiteralPath $parent -Force)) {
          Remove-Item -LiteralPath $parent -Force
          $parent = Split-Path -Parent $parent
        }
      }
    }
  } finally {
    $archive.Dispose()
  }
}

$script:config = Get-ProjectConfig -Root $root
$script:info = Get-ProjectInfo -Root $root
$currentVersion = [string]$script:info.version
$currentGeneration = if ($null -ne $script:info.PSObject.Properties['generation'] -and [int]$script:info.generation -gt 0) { [int]$script:info.generation } else { 1 }
$currentDisplay = if ($currentGeneration -le 1) { "v$currentVersion" } else { "v$currentVersion Gen$currentGeneration" }

Write-ProjectLog "开始更新检查：包体 $Package，当前版本 $currentDisplay" 'INFO' $root

$stagingRoot = $null
$backupPath = $null
try {
  # --- 1. 准备包体 ---
  if (Test-Path -LiteralPath $Package -PathType Container) {
    $packageRoot = [IO.Path]::GetFullPath($Package).TrimEnd('\', '/')
  } elseif (Test-Path -LiteralPath $Package -PathType Leaf) {
    if ([IO.Path]::GetExtension($Package) -ne '.zip') { throw "包体必须是 .zip 文件或目录：$Package" }
    $zipPath = [IO.Path]::GetFullPath($Package)
    $archive = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
      foreach ($entry in $archive.Entries) {
        if (-not (Test-ProjectSafeZipEntry $entry.FullName)) { throw "包体包含不安全的路径，已拒绝：$($entry.FullName)" }
      }
    } finally {
      $archive.Dispose()
    }
    $stagingRoot = Join-Path ([IO.Path]::GetTempPath()) ('ProjectMeUpdate-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null
    Expand-Archive -LiteralPath $zipPath -DestinationPath $stagingRoot -Force
    $packageRoot = $stagingRoot
  } else {
    throw "找不到包体：$Package"
  }

  if (-not (Test-ProjectPackageRoot $packageRoot)) {
    $nested = @(Get-ChildItem -LiteralPath $packageRoot -Directory -Force | Where-Object { Test-ProjectPackageRoot $_.FullName })
    if ($nested.Count -eq 1) { $packageRoot = $nested[0].FullName }
  }
  if (-not (Test-ProjectPackageRoot $packageRoot)) {
    throw "这不是一个 ProjectMe 包体（缺少 project-info.json / ProjectMe.ps1 / ProjectMe.Common.ps1）：$packageRoot"
  }
  if ($packageRoot.TrimEnd('\', '/') -eq $root) { throw '包体目录与安装目录相同。' }
  if ($packageRoot.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) {
    Write-Host '提示：包体位于安装目录内部，更新完成后建议把它移走。' -ForegroundColor DarkGray
    Write-ProjectLog "包体位于安装目录内部：$packageRoot" 'WARN' $root
  }

  $packageInfo = Get-Content -Raw -Encoding UTF8 (Join-Path $packageRoot 'project-info.json') | ConvertFrom-Json
  $targetVersion = [string]$packageInfo.version
  if (-not (Test-ProjectVersion $targetVersion)) { throw "包体版本号无效：$targetVersion" }
  $targetGeneration = if ($null -ne $packageInfo.PSObject.Properties['generation'] -and [int]$packageInfo.generation -gt 0) { [int]$packageInfo.generation } else { 1 }
  $targetDisplay = if ($targetGeneration -le 1) { "v$targetVersion" } else { "v$targetVersion Gen$targetGeneration" }

  if ($targetVersion -eq $currentVersion -and $targetGeneration -eq $currentGeneration -and -not $Force) {
    Write-Host "当前已经是 $currentDisplay，无需更新（如需强制重跑请加 -Force）。" -ForegroundColor Yellow
    Write-ProjectLog "包体版本与当前版本相同，未执行更新：$targetDisplay" 'INFO' $root
    return
  }

  # --- 2. 生成计划（只读） ---
  $keepPatterns = @()
  foreach ($pattern in @($Keep) + @($script:config.update.keep)) { if (-not [string]::IsNullOrWhiteSpace([string]$pattern)) { $keepPatterns += [string]$pattern } }

  $packageFiles = New-Object System.Collections.Generic.List[object]
  foreach ($file in @(Get-ChildItem -LiteralPath $packageRoot -Recurse -File -Force)) {
    $relative = $file.FullName.Substring($packageRoot.Length + 1)
    if ($relative -match '(^|\\)\.git(\\|$)') { continue }
    $packageFiles.Add([pscustomobject]@{ Relative = $relative; Source = $file.FullName })
  }

  $toApply = New-Object System.Collections.Generic.List[object]
  $protectedHits = New-Object System.Collections.Generic.List[string]
  $keptHits = New-Object System.Collections.Generic.List[string]
  $sameCount = 0
  foreach ($item in $packageFiles) {
    if ($item.Relative -eq 'project-info.json') { continue }
    if (Test-ProjectProtectedPath $item.Relative) { $protectedHits.Add($item.Relative); continue }
    if (Test-ProjectKeptPath $item.Relative $keepPatterns) { $keptHits.Add($item.Relative); continue }
    $destination = Join-Path $root $item.Relative
    $localHash = Get-ProjectFileHashValue $destination
    if ($null -eq $localHash) { $kind = 'New' }
    elseif ($localHash -ne (Get-ProjectFileHashValue $item.Source)) { $kind = 'Update' }
    else { $kind = 'Same' }
    if ($kind -eq 'Same') { $sameCount++; continue }
    $toApply.Add([pscustomobject]@{ Relative = $item.Relative; Source = $item.Source; Kind = $kind })
  }

  $updateItems = @($toApply | Where-Object { $_.Kind -eq 'Update' })
  $newItems = @($toApply | Where-Object { $_.Kind -eq 'New' })

  Write-Host ''
  Write-Host "当前版本：$currentDisplay    →    包体版本：$targetDisplay" -ForegroundColor Cyan
  Write-Host ("新增 {0} 个文件，更新 {1} 个文件，内容相同跳过 {2} 个。" -f $newItems.Count, $updateItems.Count, $sameCount)
  if ($updateItems.Count) {
    Write-Host '将要更新的文件：' -ForegroundColor Yellow
    foreach ($item in $updateItems) { Write-Host "  ~ $($item.Relative)" }
  }
  if ($newItems.Count) {
    Write-Host '将要新增的文件：' -ForegroundColor Green
    foreach ($item in $newItems) { Write-Host "  + $($item.Relative)" }
  }
  if ($protectedHits.Count) {
    Write-Host ("包体中的 {0} 个用户数据文件已跳过（永不覆盖），例如：{1}" -f $protectedHits.Count, (@($protectedHits | Select-Object -First 5) -join ', ')) -ForegroundColor DarkGray
  }
  if ($keptHits.Count) {
    Write-Host ("按 -Keep / update.keep 保留的包体文件 {0} 个，例如：{1}" -f $keptHits.Count, (@($keptHits | Select-Object -First 5) -join ', ')) -ForegroundColor DarkGray
  }

  if ($updateDryRun) {
    Write-Host "`n（-WhatIf 预览结束：未应用包体，安装目录中的项目文件未改动。）" -ForegroundColor DarkGray
    return
  }

  # --- 3. 询问用户：是否保留本地被修改过的文件 ---
  $selectedKeep = New-Object System.Collections.Generic.List[string]
  if ($updateItems.Count -gt 0) {
    if ($KeepLocal) {
      foreach ($item in $updateItems) { $selectedKeep.Add($item.Relative) }
      Write-Host "`n-KeepLocal：将保留全部 $($updateItems.Count) 个本地版本。" -ForegroundColor Yellow
    } elseif (-not $Overwrite) {
      $answer = Read-Host "`n有 $($updateItems.Count) 个文件的本地内容与包体不同。是否需要保留其中某些文件的本地版本？[Y]逐个选择 / [N]全部用包体覆盖 / [A]全部保留本地 / [Q]取消更新"
      $choice = ([string]$answer).Trim()
      if ($choice -match '^[qQ]') {
        Write-Host '已取消更新，未做任何修改。' -ForegroundColor Yellow
        Write-ProjectLog '用户取消了更新。' 'INFO' $root
        exit 0
      } elseif ($choice -match '^[aA]') {
        foreach ($item in $updateItems) { $selectedKeep.Add($item.Relative) }
      } elseif ($choice -match '^[nN]') {
        Write-Host '将用包体覆盖全部不同的程序文件。' -ForegroundColor DarkGray
      } elseif ($choice -match '^[yY]') {
        $decideAll = ''
        foreach ($item in $updateItems) {
          $destination = Join-Path $root $item.Relative
          $sourceFile = Get-Item -LiteralPath $item.Source
          $localFile = Get-Item -LiteralPath $destination
          Write-Host "`n  $($item.Relative)"
          Write-Host ("      包体：{0:N0} 字节，{1}" -f $sourceFile.Length, $sourceFile.LastWriteTime.ToString('yyyy-MM-dd HH:mm')) -ForegroundColor DarkGray
          Write-Host ("      本地：{0:N0} 字节，{1}" -f $localFile.Length, $localFile.LastWriteTime.ToString('yyyy-MM-dd HH:mm')) -ForegroundColor DarkGray
          if ($decideAll -eq 'overwrite') { Write-Host '      → 用包体覆盖' -ForegroundColor DarkGray; continue }
          if ($decideAll -eq 'keep') { Write-Host '      → 保留本地版本' -ForegroundColor DarkGray; $selectedKeep.Add($item.Relative); continue }
          $itemAnswer = ([string](Read-Host '      保留本地版本？[Y]保留 / [N]覆盖 / [A]之后全部覆盖 / [L]之后全部保留 / [Q]取消更新')).Trim()
          if ($itemAnswer -match '^[qQ]') {
            Write-Host '已取消更新，未做任何修改。' -ForegroundColor Yellow
            Write-ProjectLog '用户取消了更新。' 'INFO' $root
            exit 0
          } elseif ($itemAnswer -match '^[aA]') { $decideAll = 'overwrite' }
          elseif ($itemAnswer -match '^[lL]') { $decideAll = 'keep'; $selectedKeep.Add($item.Relative) }
          elseif ($itemAnswer -match '^[yY]') { $selectedKeep.Add($item.Relative) }
          elseif ($itemAnswer -match '^[nN]') { }
          else {
            Write-Host '未做选择，已取消更新，未做任何修改。' -ForegroundColor Yellow
            Write-ProjectLog '用户取消了更新。' 'INFO' $root
            exit 0
          }
        }
      } elseif ([Console]::IsInputRedirected) {
        throw '非交互环境：请使用 -Overwrite（全部覆盖）或 -KeepLocal（全部保留）重新运行。'
      } else {
        Write-Host '未做选择，已取消更新，未做任何修改。' -ForegroundColor Yellow
        Write-ProjectLog '用户取消了更新。' 'INFO' $root
        exit 0
      }
    }
    if ($selectedKeep.Count -gt 0) {
      Write-Host "`n将保留 $($selectedKeep.Count) 个本地文件。" -ForegroundColor Yellow
      if (-not $Overwrite -and -not $KeepLocal) {
        if (([string](Read-Host '是否记住这些选择（写入 projectme.config.json 的 update.keep）？(Y/N)')).Trim() -match '^[yY]') {
          try {
            Save-ProjectUpdateKeep -Root $root -Patterns @($keepPatterns + $selectedKeep)
            Write-Host '已写入 update.keep。' -ForegroundColor Green
            Write-ProjectLog "已保存 update.keep：$($selectedKeep -join ', ')" 'INFO' $root
          } catch {
            Write-Host "写入 update.keep 失败：$($_.Exception.Message)" -ForegroundColor Yellow
          }
        }
      }
    }
  }

  $applyItems = @($toApply | Where-Object { $selectedKeep -notcontains $_.Relative })

  # --- 4. 停预览 + 备份 ---
  try { if (Stop-ProjectPreview -Root $root) { Write-Host '已停止正在运行的本地预览。' -ForegroundColor DarkGray } } catch { }
  Write-Host '正在创建更新前备份…' -ForegroundColor DarkGray
  $backupPath = Get-SnapshotPath -Root $root -Version $currentVersion -Label 'preupdate'
  New-ProjectSnapshot -Root $root -Destination $backupPath -Exclude @('.git') | Out-Null
  Write-Host "备份：$backupPath" -ForegroundColor DarkGray
  Write-ProjectLog "更新前备份：$backupPath" 'INFO' $root

  # --- 5. 应用 ---
  $written = New-Object System.Collections.Generic.List[string]
  try {
    foreach ($item in $applyItems) {
      $destination = Join-Path $root $item.Relative
      $directory = Split-Path -Parent $destination
      if (-not (Test-Path $directory -PathType Container)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
      Copy-Item -LiteralPath $item.Source -Destination $destination -Force
      $written.Add($item.Relative)
    }
    $mergedInfo = Merge-ProjectInfo -Local $script:info -Package $packageInfo
    $written.Add('project-info.json')
    Write-ProjectJsonAtomic -Value $mergedInfo -Path (Join-Path $root 'project-info.json')
  } catch {
    Write-Host "`n写入过程中出错，正在回滚…" -ForegroundColor Red
    try {
      Restore-ProjectFilesFromBackup -Root $root -BackupZip $backupPath -WrittenPaths $written.ToArray()
      Write-Host '已回滚到更新前状态。' -ForegroundColor Yellow
      Write-ProjectLog "更新失败并已回滚：$($_.Exception.Message)" 'ERROR' $root
    } catch {
      Write-Host "回滚失败：$($_.Exception.Message)" -ForegroundColor Red
      Write-Host "请手动使用备份恢复：$backupPath" -ForegroundColor Red
      Write-ProjectLog ("更新失败且回滚失败：{0}`n回滚异常：{1}" -f $_.Exception.Message, $_.ScriptStackTrace) 'ERROR' $root
    }
    throw "更新失败：$($_.Exception.Message)"
  }

  # --- 6. 汇总 ---
  $stale = @()
  $packageSet = @{}
  foreach ($item in $packageFiles) { $packageSet[$item.Relative.ToLowerInvariant()] = $true }
  $archive = [IO.Compression.ZipFile]::OpenRead($backupPath)
  try {
    $stale = @($archive.Entries |
      ForEach-Object { $_.FullName -replace '/', '\' } |
      Where-Object { $_ -and -not $packageSet.ContainsKey($_.ToLowerInvariant()) -and -not (Test-ProjectProtectedPath $_) } |
      Sort-Object -Unique)
  } finally {
    $archive.Dispose()
  }

  Write-Host "`n更新完成：$currentDisplay → $targetDisplay" -ForegroundColor Green
  $writtenCount = $applyItems.Count + 1
  Write-Host ("写入 {0} 个文件（其中新增 {1} 个），保留本地版本 {2} 个，跳过用户数据 {3} 个。" -f $writtenCount, $newItems.Count, $selectedKeep.Count, $protectedHits.Count)
  if ($stale.Count) {
    Write-Host ("包体内没有、已保留在本地的旧文件 {0} 个（新版本可能已移除，可自行确认后删除）：" -f $stale.Count) -ForegroundColor DarkGray
    foreach ($item in @($stale | Select-Object -First 20)) { Write-Host "  ? $item" -ForegroundColor DarkGray }
    if ($stale.Count -gt 20) { Write-Host ("  …还有 {0} 个" -f ($stale.Count - 20)) -ForegroundColor DarkGray }
  }
  Write-Host "`n后续步骤：重新启动 ProjectMe.ps1 或 ProjectMe.Gui.ps1 以使用新版本。" -ForegroundColor Cyan
  Write-Host "如需回滚：使用 old\ 中的备份，或运行 ProjectMe.ps1 → 12. 回滚版本。" -ForegroundColor Cyan
  Write-ProjectLog "更新完成：$currentDisplay → $targetDisplay；写入 $($applyItems.Count) 个文件；保留 $($selectedKeep.Count) 个本地版本；备份 $backupPath" 'INFO' $root

  $checkPath = Join-Path $root 'Check-ProjectMe.ps1'
  if (Test-Path $checkPath -PathType Leaf) {
    try {
      $checkOutput = (& $checkPath 2>&1 | Out-String).Trim()
      Write-Host "`n自检：$checkOutput" -ForegroundColor Green
      Write-ProjectLog "更新后自检：$checkOutput" 'INFO' $root
    } catch {
      Write-Host "`n自检未通过：$($_.Exception.Message)" -ForegroundColor Yellow
      Write-Host "更新已应用；如项目状态异常，请使用备份恢复：$backupPath" -ForegroundColor Yellow
      Write-ProjectLog "更新后自检失败：$($_.Exception.Message)" 'ERROR' $root
    }
  }
} catch {
  Write-Host "`n$($_.Exception.Message)" -ForegroundColor Red
  try { Write-ProjectLog ("更新失败：{0}`n{1}" -f $_.Exception.Message, $_.ScriptStackTrace) 'ERROR' $root } catch { }
  if ($backupPath) { Write-Host "更新前备份：$backupPath" -ForegroundColor Yellow }
  exit 1
} finally {
  if ($stagingRoot -and (Test-Path $stagingRoot -PathType Container)) { Remove-Item -LiteralPath $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
