# ProjectMe 无损更新器
#
# 用法：
#   .\Update-ProjectMe.ps1 -Package .\ProjectMe-v1.1.11.zip
#   .\Update-ProjectMe.ps1 -Package .\解压后的新版本目录 -WhatIf
#   .\Update-ProjectMe.ps1 -Package .\ProjectMe-v1.1.11.zip -Overwrite
#   .\Update-ProjectMe.ps1 -Package .\ProjectMe-v1.1.11.zip -ProjectRoot D:\ProjectMe
#
# 行为：
#   * 只写入包体内的“程序文件”，用户数据（articles/、articles.json、timeline.json、
#     projectme.config.json、.gitignore、logs/、old/、.git/）永不写入、永不删除；
#   * 插件是用户数据：**安装目录里已经存在的插件**（plugins\<插件名>\ 整个目录，含它自己的
#     config.json 与代码）一律跳过，包体永远不会覆盖它；包体里携带的**新**插件包（例如
#     plugins\markdown-split-import.zip）或本机还没有的插件目录仍会正常落地，用户可在插件管理器里安装。
#     因此更新不会动你已装好的插件，也不会丢插件的启用状态与设置；
#   * project-info.json 采用合并策略：版本号（含 Gen）取自包体，其余键保留本地值；
#   * 更新前自动在 old\ 生成完整备份，失败时按文件精确回滚；
#   * 本地内容与包体不同的文件会逐个询问“保留本地版本 / 用包体覆盖”。
#
# 独立性（重要）：
#   更新器天生要在**旧版本**安装目录里运行，所以它绝不加载安装目录里的 ProjectMe.Common.ps1，
#   而是自带本文下方所需的全部函数实现。旧 Common 可能缺少新函数或新参数
#   （例如 v1.1.6 的 Common 没有 Test-ProjectSafeZipEntry，New-ProjectSnapshot 也不支持 -Exclude，
#   Get-SnapshotPath 不支持 -Label），一旦依赖它，任何版本跨度上的更新都会失败。
#   本脚本因此只依赖 Windows PowerShell 5.1 自身。
#
# 安装目录的判定顺序：
#   1. -ProjectRoot 指定的目录；
#   2. 当前工作目录（如果它看起来是一个 ProjectMe 安装目录）；
#   3. 本脚本所在目录。

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

# -WhatIf 在这里是“只打印计划、不写入安装目录”的预演开关。PowerShell 的 -WhatIf 会连带抑制
# 脚本内部所有支持 ShouldProcess 的 cmdlet（连解压包体、创建日志目录都会被跳过），因此先把
# 偏好变量关掉，改由脚本自己在写入闸门处停止。
$updateDryRun = [bool]$WhatIfPreference
if ($updateDryRun) { $WhatIfPreference = $false }

if ($Overwrite -and $KeepLocal) { throw '不能同时使用 -Overwrite 与 -KeepLocal。' }

# ============================================================================================
# 脚本自带的公共实现
# 以下函数与 ProjectMe.Common.ps1 中的同名函数语义保持一致，但刻意使用 Update- 前缀，
# 既避免加载旧安装目录里的实现，也避免在交互式会话里 dot-source 本脚本时覆盖宿主的函数。
# ============================================================================================

function Write-UpdateLog {
  param([Parameter(Mandatory)][string]$Message, [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO', [string]$Root = '')
  if ([string]::IsNullOrWhiteSpace($Root)) { return }
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

function Get-UpdateProjectInfo {
  param([Parameter(Mandatory)][string]$Root)
  $path = Join-Path $Root 'project-info.json'
  if (-not (Test-Path $path -PathType Leaf)) { throw "安装目录缺少 project-info.json：$path" }
  try {
    return Get-Content -Raw -Encoding UTF8 $path | ConvertFrom-Json
  } catch {
    throw "project-info.json 无法解析：$($_.Exception.Message)"
  }
}

function Get-UpdateKeepFromConfig {
  param([Parameter(Mandatory)][string]$Root)
  # 安装目录里可能是很旧的配置结构，这里只挑更新器需要的一项，其它键一概不动。
  $path = Join-Path $Root 'projectme.config.json'
  if (-not (Test-Path $path -PathType Leaf)) { return @() }
  try {
    $raw = Get-Content -Raw -Encoding UTF8 $path | ConvertFrom-Json
    if ($null -ne $raw.update -and $null -ne $raw.update.PSObject.Properties['keep']) {
      return @($raw.update.keep | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
  } catch {
    Write-UpdateLog "读取 projectme.config.json 的 update.keep 失败，按空列表处理：$($_.Exception.Message)" 'WARN' $Root
  }
  return @()
}

function Write-UpdateJson {
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

function Test-UpdateVersion { param([string]$Version) return $Version -match '^\d+\.\d+\.\d+$' }

function Get-UpdateDisplayVersion {
  param([Parameter(Mandatory)]$Info)
  $version = [string]$Info.version
  $generation = 1
  if ($null -ne $Info.PSObject.Properties['generation'] -and [int]$Info.generation -gt 0) { $generation = [int]$Info.generation }
  if ($generation -le 1) { return "v$version" }
  return "v$version Gen$generation"
}

function Test-UpdateZipEntry {
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

function Get-UpdateSnapshotPath {
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

function New-UpdateSnapshot {
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
    [IO.Compression.ZipFile]::CreateFromDirectory($staging, $temporaryZip, [IO.Compression.CompressionLevel]::Optimal, $false)
    Move-Item -LiteralPath $temporaryZip -Destination $Destination -Force
    return $Destination
  } finally {
    if (Test-Path $staging) { Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue }
    if (Test-Path $temporaryZip) { Remove-Item -LiteralPath $temporaryZip -Force -ErrorAction SilentlyContinue }
  }
}

function Get-UpdatePreviewState {
  param([Parameter(Mandatory)][string]$Root)
  $path = Join-Path $Root '.projectme-serve.json'
  if (-not (Test-Path $path -PathType Leaf)) { return $null }
  try {
    return Get-Content -Raw -Encoding UTF8 $path | ConvertFrom-Json
  } catch {
    Write-UpdateLog "本地预览状态文件无法解析，已忽略：$($_.Exception.Message)" 'WARN' $Root
    return $null
  }
}

function Get-UpdateListeningProcessId {
  param([int]$Port)
  foreach ($line in @(& netstat.exe -ano -p tcp 2>$null)) {
    if ($line -match "TCP\s+\S+:$([regex]::Escape([string]$Port))\s+\S+\s+LISTENING\s+(\d+)") {
      return [int]$Matches[1]
    }
  }
  return $null
}

function Stop-UpdatePreview {
  param([Parameter(Mandatory)][string]$Root)
  $statePath = Join-Path $Root '.projectme-serve.json'
  $state = Get-UpdatePreviewState -Root $Root
  $ports = @()
  if ($null -ne $state -and $null -ne $state.port -and [int]$state.port -gt 0) { $ports = @([int]$state.port) }
  $targets = @{}
  foreach ($port in $ports) {
    $listeningPid = Get-UpdateListeningProcessId -Port $port
    if ($listeningPid) { $targets[$listeningPid] = $port }
  }
  # 只结束“确实在监听该项目预览端口”的 PowerShell 进程：状态文件可能是旧的，
  # 记录下来的 PID 也许已经被别的程序复用，凭 PID 直接杀会误伤无关进程。
  foreach ($processId in @($targets.Keys)) {
    $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
    if ($null -eq $process) { continue }
    if ($process.ProcessName -notin @('powershell', 'pwsh')) {
      Write-UpdateLog "端口 $($targets[$processId]) 正被非 PowerShell 进程占用（PID $processId，$($process.ProcessName)），未结束它。" 'WARN' $Root
      continue
    }
    Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 250
  }
  if (Test-Path $statePath -PathType Leaf) { Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue }
  return ($targets.Count -gt 0)
}

function Test-UpdatePackageRoot([string]$Path) {
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
  if (Test-Path $path -PathType Leaf) {
    try {
      $config = Get-Content -Raw -Encoding UTF8 $path | ConvertFrom-Json
    } catch {
      throw "projectme.config.json 无法解析，未写入 update.keep：$($_.Exception.Message)"
    }
  } else {
    $config = [pscustomobject]@{}
  }
  if ($null -eq $config.PSObject.Properties['update']) { $config | Add-Member -NotePropertyName update -NotePropertyValue ([pscustomobject]@{}) -Force }
  if ($null -eq $config.update.PSObject.Properties['keep']) { $config.update | Add-Member -NotePropertyName keep -NotePropertyValue @() -Force }
  $config.update.keep = @($Patterns | Sort-Object -Unique)
  Write-UpdateJson -Value $config -Path $path -Depth 12
}

# ============================================================================================
# 路径与保护规则
# ============================================================================================

function Test-ProjectProtectedPath([string]$Relative) {
  $normalized = $Relative -replace '/', '\'
  if ($script:ProtectedFiles -contains $normalized) { return $true }
  foreach ($directory in $script:ProtectedDirectories) {
    if ($normalized -eq $directory) { return $true }
    if ($normalized.StartsWith($directory + '\', [StringComparison]::OrdinalIgnoreCase)) { return $true }
  }
  return $false
}

# 插件属于用户数据。规则：
#   * 安装目录里**已经存在**的插件（plugins\<插件名>\ 整个目录，含它自己的 config.json、
#     入口脚本与其它文件）一律跳过——包体永不覆盖，插件的开关与设置都不会丢；
#   * 本机还没有的插件目录，以及 plugins\ 下的 .zip 插件包，视作包体内容正常落地，
#     这样新版附带的插件仍然能交付给用户，再由插件管理器安装。
function Test-ProjectProtectedPluginPath([string]$Root, [string]$Relative) {
  $normalized = $Relative -replace '/', '\'
  $match = [regex]::Match($normalized, '^plugins\\([^\\]+)\\')
  if (-not $match.Success) { return $false }
  $pluginDirectory = Join-Path (Join-Path $Root 'plugins') $match.Groups[1].Value
  return (Test-Path -LiteralPath $pluginDirectory -PathType Container)
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

function Restore-ProjectFilesFromBackup([string]$Root, [string]$BackupZip, [string[]]$WrittenPaths) {
  $archive = [IO.Compression.ZipFile]::OpenRead($BackupZip)
  try {
    foreach ($relative in $WrittenPaths) {
      $destination = Join-Path $Root $relative
      # 备份是用 .NET Framework 的 ZipFile.CreateFromDirectory 生成的，嵌套条目的名字用的是
      # 反斜杠（articles\my-note.md）。两边归一化后再比较，否则会误判成“备份里没有这个文件”，
      # 于是把本该还原的文件删掉 —— 回滚反而毁数据。
      $entryName = $relative -replace '\\', '/'
      $entry = $archive.Entries | Where-Object { ($_.FullName -replace '\\', '/') -eq $entryName } | Select-Object -First 1
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

$script:ProtectedDirectories = @('articles', 'logs', 'old', '.git')
$script:ProtectedFiles = @('articles.json', 'timeline.json', 'projectme.config.json', '.gitignore', '.projectme-serve.json')

# ============================================================================================
# 定位安装目录与包体
# ============================================================================================

$baseDirectory = ''
try { $baseDirectory = (Get-Location).ProviderPath } catch { }
if ([string]::IsNullOrWhiteSpace($baseDirectory)) { $baseDirectory = [Environment]::CurrentDirectory }

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
  if (-not [string]::IsNullOrWhiteSpace($baseDirectory) -and (Test-Path (Join-Path $baseDirectory 'project-info.json') -PathType Leaf) -and (Test-Path (Join-Path $baseDirectory 'ProjectMe.ps1') -PathType Leaf)) {
    # 最常见的情形：cd 到安装目录（或直接在安装目录里打开终端）后运行更新器。
    $ProjectRoot = $baseDirectory
  } elseif (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $ProjectRoot = $PSScriptRoot
  } else {
    $ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
  }
}

$root = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\', '/')
if (-not (Test-Path (Join-Path $root 'project-info.json') -PathType Leaf) -or -not (Test-Path (Join-Path $root 'ProjectMe.ps1') -PathType Leaf)) {
  throw "这不是一个 ProjectMe 安装目录：$root`n（当前工作目录：$baseDirectory；可用 -ProjectRoot <目录> 指定安装目录。）"
}

# 相对路径按当前工作目录解析，不依赖 .NET 的进程当前目录。
if (-not [IO.Path]::IsPathRooted($Package)) { $Package = Join-Path $baseDirectory $Package }

$script:config = [pscustomobject]@{ update = [pscustomobject]@{ keep = @(Get-UpdateKeepFromConfig -Root $root) } }
$script:info = Get-UpdateProjectInfo -Root $root
$currentVersion = [string]$script:info.version
$currentDisplay = Get-UpdateDisplayVersion -Info $script:info

Write-Host "安装目录：$root" -ForegroundColor DarkGray
Write-Host "包体路径：$Package" -ForegroundColor DarkGray
Write-UpdateLog "开始更新检查：包体 $Package，当前版本 $currentDisplay" 'INFO' $root

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
        if (-not (Test-UpdateZipEntry $entry.FullName)) { throw "包体包含不安全的路径，已拒绝：$($entry.FullName)" }
      }
    } finally {
      $archive.Dispose()
    }
    $stagingRoot = Join-Path ([IO.Path]::GetTempPath()) ('ProjectMeUpdate-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null
    Expand-Archive -LiteralPath $zipPath -DestinationPath $stagingRoot -Force
    $packageRoot = $stagingRoot
  } else {
    $message = "找不到包体：$Package`n（当前工作目录：$baseDirectory）"
    $hints = New-Object System.Collections.Generic.List[string]
    foreach ($directory in @($root, $baseDirectory, $PSScriptRoot)) {
      if ([string]::IsNullOrWhiteSpace($directory) -or -not (Test-Path -LiteralPath $directory -PathType Container)) { continue }
      foreach ($file in @(Get-ChildItem -LiteralPath $directory -File -Filter 'ProjectMe-*.zip' -ErrorAction SilentlyContinue)) {
        if (-not $hints.Contains($file.FullName)) { $hints.Add($file.FullName) }
      }
    }
    if ($hints.Count -gt 0) {
      $message += "`n在项目里找到了这些包体，请核对路径：`n  " + (@($hints | Select-Object -First 10) -join "`n  ")
    } else {
      $message += "`n请传入完整的 zip 路径或解压后的目录，例如：-Package .\ProjectMe-v1.1.11.zip"
    }
    throw $message
  }

  if (-not (Test-UpdatePackageRoot $packageRoot)) {
    $nested = @(Get-ChildItem -LiteralPath $packageRoot -Directory -Force | Where-Object { Test-UpdatePackageRoot $_.FullName })
    if ($nested.Count -eq 1) { $packageRoot = $nested[0].FullName }
  }
  if (-not (Test-UpdatePackageRoot $packageRoot)) {
    throw "这不是一个 ProjectMe 包体（缺少 project-info.json / ProjectMe.ps1 / ProjectMe.Common.ps1）：$packageRoot"
  }
  if ($packageRoot.TrimEnd('\', '/') -eq $root) { throw '包体目录与安装目录相同。' }
  if ($packageRoot.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) {
    Write-Host '提示：包体位于安装目录内部，更新完成后建议把它移走。' -ForegroundColor DarkGray
    Write-UpdateLog "包体位于安装目录内部：$packageRoot" 'WARN' $root
  }

  $packageInfo = Get-UpdateProjectInfo -Root $packageRoot
  $targetVersion = [string]$packageInfo.version
  if (-not (Test-UpdateVersion $targetVersion)) { throw "包体版本号无效：$targetVersion" }
  $targetDisplay = Get-UpdateDisplayVersion -Info $packageInfo
  $targetGeneration = if ($null -ne $packageInfo.PSObject.Properties['generation'] -and [int]$packageInfo.generation -gt 0) { [int]$packageInfo.generation } else { 1 }
  $currentGeneration = if ($null -ne $script:info.PSObject.Properties['generation'] -and [int]$script:info.generation -gt 0) { [int]$script:info.generation } else { 1 }

  if ($targetVersion -eq $currentVersion -and $targetGeneration -eq $currentGeneration -and -not $Force) {
    Write-Host "当前已经是 $currentDisplay，无需更新（如需强制重跑请加 -Force）。" -ForegroundColor Yellow
    Write-UpdateLog "包体版本与当前版本相同，未执行更新：$targetDisplay" 'INFO' $root
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
    if (Test-ProjectProtectedPluginPath -Root $root -Relative $item.Relative) { $protectedHits.Add($item.Relative); continue }
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
  # 已安装的插件整个目录都跳过，单独说明一句，避免用户以为插件被更新了
  $protectedPlugins = @($protectedHits |
    ForEach-Object { if (([string]$_ -replace '/', '\') -match '^plugins\\([^\\]+)\\') { $Matches[1] } } |
    Where-Object { $_ } | Sort-Object -Unique)
  foreach ($pluginId in $protectedPlugins) {
    Write-Host ("已安装插件未覆盖（保留本地版本与设置）：plugins\{0}\" -f $pluginId) -ForegroundColor DarkGray
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
        Write-UpdateLog '用户取消了更新。' 'INFO' $root
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
            Write-UpdateLog '用户取消了更新。' 'INFO' $root
            exit 0
          } elseif ($itemAnswer -match '^[aA]') { $decideAll = 'overwrite' }
          elseif ($itemAnswer -match '^[lL]') { $decideAll = 'keep'; $selectedKeep.Add($item.Relative) }
          elseif ($itemAnswer -match '^[yY]') { $selectedKeep.Add($item.Relative) }
          elseif ($itemAnswer -match '^[nN]') { }
          else {
            Write-Host '未做选择，已取消更新，未做任何修改。' -ForegroundColor Yellow
            Write-UpdateLog '用户取消了更新。' 'INFO' $root
            exit 0
          }
        }
      } elseif ([Console]::IsInputRedirected) {
        throw '非交互环境：请使用 -Overwrite（全部覆盖）或 -KeepLocal（全部保留）重新运行。'
      } else {
        Write-Host '未做选择，已取消更新，未做任何修改。' -ForegroundColor Yellow
        Write-UpdateLog '用户取消了更新。' 'INFO' $root
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
            Write-UpdateLog "已保存 update.keep：$($selectedKeep -join ', ')" 'INFO' $root
          } catch {
            Write-Host "写入 update.keep 失败：$($_.Exception.Message)" -ForegroundColor Yellow
          }
        }
      }
    }
  }

  $applyItems = @($toApply | Where-Object { $selectedKeep -notcontains $_.Relative })

  # --- 4. 停预览 + 备份 ---
  try { if (Stop-UpdatePreview -Root $root) { Write-Host '已停止正在运行的本地预览。' -ForegroundColor DarkGray } } catch { }
  Write-Host '正在创建更新前备份…' -ForegroundColor DarkGray
  $backupPath = Get-UpdateSnapshotPath -Root $root -Version $currentVersion -Label 'preupdate'
  New-UpdateSnapshot -Root $root -Destination $backupPath -Exclude @('.git') | Out-Null
  Write-Host "备份：$backupPath" -ForegroundColor DarkGray
  Write-UpdateLog "更新前备份：$backupPath" 'INFO' $root

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
    Write-UpdateJson -Value $mergedInfo -Path (Join-Path $root 'project-info.json')
  } catch {
    Write-Host "`n写入过程中出错，正在回滚…" -ForegroundColor Red
    try {
      Restore-ProjectFilesFromBackup -Root $root -BackupZip $backupPath -WrittenPaths $written.ToArray()
      Write-Host '已回滚到更新前状态。' -ForegroundColor Yellow
      Write-UpdateLog "更新失败并已回滚：$($_.Exception.Message)" 'ERROR' $root
    } catch {
      Write-Host "回滚失败：$($_.Exception.Message)" -ForegroundColor Red
      Write-Host "请手动使用备份恢复：$backupPath" -ForegroundColor Red
      Write-UpdateLog ("更新失败且回滚失败：{0}`n回滚异常：{1}" -f $_.Exception.Message, $_.ScriptStackTrace) 'ERROR' $root
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
  Write-UpdateLog "更新完成：$currentDisplay → $targetDisplay；写入 $($applyItems.Count) 个文件；保留 $($selectedKeep.Count) 个本地版本；备份 $backupPath" 'INFO' $root

  $checkPath = Join-Path $root 'Check-ProjectMe.ps1'
  if (Test-Path $checkPath -PathType Leaf) {
    try {
      $checkOutput = (& $checkPath 2>&1 | Out-String).Trim()
      Write-Host "`n自检：$checkOutput" -ForegroundColor Green
      Write-UpdateLog "更新后自检：$checkOutput" 'INFO' $root
    } catch {
      Write-Host "`n自检未通过：$($_.Exception.Message)" -ForegroundColor Yellow
      Write-Host "更新已应用；如项目状态异常，请使用备份恢复：$backupPath" -ForegroundColor Yellow
      Write-UpdateLog "更新后自检失败：$($_.Exception.Message)" 'ERROR' $root
    }
  }
} catch {
  Write-Host "`n$($_.Exception.Message)" -ForegroundColor Red
  try { Write-UpdateLog ("更新失败：{0}`n{1}" -f $_.Exception.Message, $_.ScriptStackTrace) 'ERROR' $root } catch { }
  if ($backupPath) { Write-Host "更新前备份：$backupPath" -ForegroundColor Yellow }
  exit 1
} finally {
  if ($stagingRoot -and (Test-Path $stagingRoot -PathType Container)) { Remove-Item -LiteralPath $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
