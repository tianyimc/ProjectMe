# ProjectMe 插件管理器
#
# 用法：
#   .\Manage-Plugins.ps1                      # 交互菜单
#   .\Manage-Plugins.ps1 -List                # 只打印插件清单
#   .\Manage-Plugins.ps1 -Install .\demo.zip  # 安装插件包
#   .\Manage-Plugins.ps1 -Enable demo         # 启用插件
#   .\Manage-Plugins.ps1 -Disable demo        # 禁用插件
#   .\Manage-Plugins.ps1 -Uninstall demo      # 卸载插件（移入 old\removed-plugins）
#   .\Manage-Plugins.ps1 -AllDisabled         # 一键禁用全部插件
#   .\Manage-Plugins.ps1 -SafeModeCli         # 以安全模式启动 CLI（本次不加载任何插件）
#   .\Manage-Plugins.ps1 -SafeModeGui         # 以安全模式启动 GUI
#
# 扫描规则：plugins\ 下的文件夹 = 已安装插件；plugins\*.zip = 发现的未安装插件。
# 安装后默认禁用；升级（同名已存在）会保留原启用状态，并把旧目录移入 old\removed-plugins\。

[CmdletBinding()]
param(
  [string]$ProjectRoot = '',
  [switch]$List,
  [string]$Install = '',
  [string]$Enable = '',
  [string]$Disable = '',
  [string]$Uninstall = '',
  [switch]$AllEnabled,
  [switch]$AllDisabled,
  [switch]$Purge,
  [switch]$SafeModeCli,
  [switch]$SafeModeGui,
  [switch]$Yes
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = $PSScriptRoot }
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }
$root = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\', '/')
if (-not (Test-Path (Join-Path $root 'ProjectMe.ps1') -PathType Leaf)) { throw "这不是一个 ProjectMe 安装目录：$root" }
$commonPath = Join-Path $root 'ProjectMe.Common.ps1'
if (-not (Test-Path $commonPath -PathType Leaf)) { throw "安装目录缺少 ProjectMe.Common.ps1：$commonPath" }

# 管理器要用到同一版本的插件宿主 API。这里先“只读地”检查公共脚本，不执行旧代码，
# 就能在安装目录过旧时给出可执行的提示，而不是让用户面对一堆难以理解的报错：
#   * 旧版本的 Common 可能根本无法解析（早期版本含中文的 .ps1 没有保存为带 BOM 的 UTF-8，
#     Windows PowerShell 5.1 会按系统代码页解码，脚本直接是语法错误）；
#   * 也可能能解析但缺少插件宿主 API（例如 v1.1.6 没有 Get-ProjectPlugins）。
$commonTokens = $null
$commonParseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($commonPath, [ref]$commonTokens, [ref]$commonParseErrors)
if ($commonParseErrors.Count -gt 0) {
  throw ("插件管理器无法加载 {0}：该文件有 {1} 处解析错误（旧版本常见原因是含中文的 .ps1 未保存为带 BOM 的 UTF-8）。请先在该目录运行 Update-ProjectMe.ps1 更新项目。" -f $commonPath, $commonParseErrors.Count)
}
$commonText = Get-Content -Raw -Encoding UTF8 $commonPath
$requiredCommonFunctions = @('Get-ProjectPlugins', 'Get-ProjectPluginConfig', 'Set-ProjectPluginEnabled', 'Test-ProjectPluginManifest', 'Test-ProjectSafeZipEntry', 'Write-ProjectJsonAtomic', 'Write-ProjectLog', 'Get-ProjectPluginGuiPanelEntries', 'Get-ProjectPluginGuiType')
$missingCommonFunctions = @($requiredCommonFunctions | Where-Object { $commonText -notmatch ('function\s+' + [regex]::Escape($_) + '\b') })
if ($missingCommonFunctions.Count -gt 0) {
  throw ("插件管理器需要与主程序同版本：{0} 里的 ProjectMe.Common.ps1 缺少 {1}。请先在该目录运行 Update-ProjectMe.ps1 更新项目，或用 -ProjectRoot 指向已更新的安装目录。" -f $root, ($missingCommonFunctions -join '、'))
}
. $commonPath

$pluginsDirectory = Join-Path $root 'plugins'
$removedDirectory = Join-Path $root 'old\removed-plugins'

function Clear-PluginScreen { try { Clear-Host } catch { } }
function Pause-PluginMenu { [void](Read-Host '按 Enter 继续') }

# 插件文件是从网上下载的插件包里解出来的，Windows 可能给它们打上「来自 Internet」的阻止标记；
# 一旦带上这个标记，宿主 dot-source 插件入口时会直接被拒（RemoteSigned/Restricted 都拦）。
# 因此安装或启用插件后调用一次根目录的 Start-ProjectMe.bat 解除阻止。
# 只做许可、不做撤销：禁用或卸载插件都不会把标记加回去。
function Invoke-PluginScriptUnblock {
  $launcher = Join-Path $root 'Start-ProjectMe.bat'
  if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) { return }
  try {
    # 直接调用批处理即可：它在本进程已有的控制台里运行，不会弹出新的控制台窗口
    $null = & $launcher
    $code = $LASTEXITCODE
    if ($code -eq 0) {
      Write-Host '已解除插件脚本的下载阻止（Start-ProjectMe.bat）。' -ForegroundColor DarkGray
      Write-ProjectLog '已调用 Start-ProjectMe.bat 解除插件脚本的下载阻止。' 'INFO' $root
    } else {
      Write-Host "解除下载阻止失败（Start-ProjectMe.bat 退出码 $code），插件可能无法加载。" -ForegroundColor Yellow
      Write-ProjectLog "调用 Start-ProjectMe.bat 失败，退出码 $code。" 'WARN' $root
    }
  } catch {
    Write-Host "解除下载阻止失败：$($_.Exception.Message)" -ForegroundColor Yellow
    Write-ProjectLog ("调用 Start-ProjectMe.bat 失败：{0}`n{1}" -f $_.Exception.Message, $_.ScriptStackTrace) 'WARN' $root
  }
}

function Get-ZipPluginInfo {
  param([Parameter(Mandatory)][string]$ZipPath)
  $info = [pscustomobject]@{ Id = ''; Name = ''; Version = ''; Prefix = ''; Problem = '' }
  try {
    $archive = [IO.Compression.ZipFile]::OpenRead($ZipPath)
  } catch {
    $info.Problem = "无法读取压缩包：$($_.Exception.Message)"
    return $info
  }
  try {
    $entries = @($archive.Entries | Where-Object { -not [string]::IsNullOrWhiteSpace($_.FullName) -and -not ($_.FullName -replace '\\', '/').EndsWith('/') })
    $manifestEntries = @($entries | Where-Object { ($_.FullName -replace '\\', '/') -match '(^|/)plugin\.json$' })
    if ($manifestEntries.Count -eq 0) { $info.Problem = '包内没有找到 plugin.json'; return $info }
    if ($manifestEntries.Count -gt 1) { $info.Problem = '包内有多个 plugin.json，无法确定插件主目录'; return $info }
    $normalized = $manifestEntries[0].FullName -replace '\\', '/'
    $info.Prefix = $normalized.Substring(0, $normalized.Length - 'plugin.json'.Length).TrimEnd('/')
    $reader = New-Object IO.StreamReader($manifestEntries[0].Open(), [Text.UTF8Encoding]::new($false))
    try { $manifest = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
    $defaultId = if ([string]::IsNullOrWhiteSpace($info.Prefix)) { [IO.Path]::GetFileNameWithoutExtension($ZipPath) } else { Split-Path -Leaf $info.Prefix }
    $info.Id = if ($null -ne $manifest.PSObject.Properties['id'] -and -not [string]::IsNullOrWhiteSpace([string]$manifest.id)) { [string]$manifest.id } else { $defaultId }
    if ($null -ne $manifest.PSObject.Properties['name']) { $info.Name = [string]$manifest.name }
    if ($null -ne $manifest.PSObject.Properties['version']) { $info.Version = [string]$manifest.version }
  } catch {
    $info.Problem = "plugin.json 读取失败：$($_.Exception.Message)"
  } finally {
    $archive.Dispose()
  }
  return $info
}

function Get-PluginInventory {
  $installed = @(Get-ProjectPlugins -Root $root)
  $pending = New-Object System.Collections.Generic.List[object]
  $ignored = New-Object System.Collections.Generic.List[string]
  if (Test-Path $pluginsDirectory -PathType Container) {
    foreach ($item in @(Get-ChildItem -LiteralPath $pluginsDirectory -Force | Sort-Object Name)) {
      if ($item.PSIsContainer) { continue }
      if ([IO.Path]::GetExtension($item.Name) -eq '.zip') {
        $zipInfo = Get-ZipPluginInfo -ZipPath $item.FullName
        $alreadyInstalled = $false
        if (-not [string]::IsNullOrWhiteSpace($zipInfo.Id)) {
          $alreadyInstalled = @($installed | Where-Object { $_.Id -eq $zipInfo.Id }).Count -gt 0
        }
        $pending.Add([pscustomobject]@{ File = $item; Id = $zipInfo.Id; Name = $zipInfo.Name; Version = $zipInfo.Version; Problem = $zipInfo.Problem; Installed = $alreadyInstalled })
      } else {
        $ignored.Add($item.Name) | Out-Null
      }
    }
  }
  return [pscustomobject]@{
    Installed = $installed
    Pending = $pending.ToArray()
    Ignored = $ignored.ToArray()
    Directory = $pluginsDirectory
  }
}

function Show-PluginInventory {
  param($Inventory)
  Write-Host "插件目录：$($Inventory.Directory)" -ForegroundColor DarkGray
  Write-Host ''
  Write-Host ("已安装插件（{0}）" -f $Inventory.Installed.Count) -ForegroundColor Cyan
  if ($Inventory.Installed.Count -eq 0) {
    Write-Host '  （无）' -ForegroundColor DarkGray
  } else {
    $index = 0
    foreach ($plugin in $Inventory.Installed) {
      $index++
      $state = if ($plugin.Enabled) { '已启用' } else { '已禁用' }
      $stateColor = if ($plugin.Enabled) { 'Green' } else { 'DarkGray' }
      $name = ''
      $version = ''
      if ($null -ne $plugin.Manifest) {
        if ($null -ne $plugin.Manifest.PSObject.Properties['name']) { $name = [string]$plugin.Manifest.name }
        if ($null -ne $plugin.Manifest.PSObject.Properties['version']) { $version = [string]$plugin.Manifest.version }
      }
      Write-Host ("  [{0}] {1,-22} " -f $index, $plugin.Id) -NoNewline
      Write-Host $state -ForegroundColor $stateColor -NoNewline
      if ($name -or $version) { Write-Host ("   {0} {1}" -f $name, $version) -NoNewline }
      Write-Host ''
      if ($plugin.Status -ne 'ok') { Write-Host ("       [!] 状态异常（{0}）：{1}" -f $plugin.Status, $plugin.Problem) -ForegroundColor Yellow }
    }
  }
  Write-Host ''
  Write-Host ("发现的未安装插件（{0}）" -f $Inventory.Pending.Count) -ForegroundColor Cyan
  if ($Inventory.Pending.Count -eq 0) {
    Write-Host '  （无）' -ForegroundColor DarkGray
  } else {
    $index = 0
    foreach ($zip in $Inventory.Pending) {
      $index++
      Write-Host ("  [{0}] {1}" -f $index, $zip.File.Name) -NoNewline
      if ($zip.Problem) {
        Write-Host ("   [!] {0}" -f $zip.Problem) -ForegroundColor Yellow
      } else {
        $target = if ($zip.Installed) { "（同名插件已安装：$($zip.Id)，可重装/升级）" } else { "→ 将安装为 $($zip.Id)" }
        Write-Host ("   {0} {1} {2}" -f $zip.Id, $zip.Version, $target)
      }
    }
  }
  if ($Inventory.Ignored.Count -gt 0) {
    Write-Host ''
    Write-Host ("已忽略的非插件文件（{0}）：{1}" -f $Inventory.Ignored.Count, ($Inventory.Ignored -join ', ')) -ForegroundColor DarkGray
  }
}

function Resolve-PluginById {
  param([string]$Id)
  $installed = @(Get-ProjectPlugins -Root $root)
  return @($installed | Where-Object { $_.Id -eq $Id } | Select-Object -First 1)
}

function Select-PluginInteractive {
  param([object[]]$Installed, [string]$Prompt = '请输入插件编号或名称（回车取消）')
  for ($i = 0; $i -lt $Installed.Count; $i++) {
    $state = if ($Installed[$i].Enabled) { '已启用' } else { '已禁用' }
    Write-Host ("  [{0}] {1}  ({2})" -f ($i + 1), $Installed[$i].Id, $state)
  }
  $answer = ([string](Read-Host $Prompt)).Trim()
  if ([string]::IsNullOrWhiteSpace($answer)) { return $null }
  if ($answer -match '^\d+$') {
    $index = [int]$answer - 1
    if ($index -ge 0 -and $index -lt $Installed.Count) { return $Installed[$index] }
    return $null
  }
  return @($Installed | Where-Object { $_.Id -eq $answer } | Select-Object -First 1)
}

function Move-PluginToRemoved {
  param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Id, [switch]$Purge)
  if ($Purge) {
    Remove-Item -LiteralPath $Path -Recurse -Force
    Write-ProjectLog "已删除插件目录：$Id" 'INFO' $root
    return ''
  }
  if (-not (Test-Path $removedDirectory -PathType Container)) { New-Item -ItemType Directory -Path $removedDirectory -Force | Out-Null }
  $target = Join-Path $removedDirectory ("$Id-" + (Get-Date).ToString('yyyyMMddHHmmss'))
  while (Test-Path $target) { $target = Join-Path $removedDirectory ("$Id-" + (Get-Date).ToString('yyyyMMddHHmmss') + '-' + (Get-Random -Maximum 9999)) }
  Move-Item -LiteralPath $Path -Destination $target -Force
  Write-ProjectLog "插件目录已移入回收站：$Id → $target" 'INFO' $root
  return $target
}

function Install-PluginPackage {
  param([Parameter(Mandatory)][string]$Source, [switch]$Force)
  $stagingRoot = $null
  try {
    if (Test-Path -LiteralPath $Source -PathType Container) {
      $sourceRoot = [IO.Path]::GetFullPath($Source).TrimEnd('\', '/')
      $sourceName = Split-Path -Leaf $sourceRoot
      $isZip = $false
    } elseif (Test-Path -LiteralPath $Source -PathType Leaf) {
      if ([IO.Path]::GetExtension($Source) -ne '.zip') { throw "插件包必须是 .zip 文件或目录：$Source" }
      $zipPath = [IO.Path]::GetFullPath($Source)
      $sourceName = [IO.Path]::GetFileNameWithoutExtension($zipPath)
      $archive = [IO.Compression.ZipFile]::OpenRead($zipPath)
      try {
        foreach ($entry in $archive.Entries) {
          if (-not (Test-ProjectSafeZipEntry -Name $entry.FullName)) { throw "插件包包含不安全的路径，已拒绝：$($entry.FullName)" }
        }
      } finally {
        $archive.Dispose()
      }
      $stagingRoot = Join-Path ([IO.Path]::GetTempPath()) ('ProjectMePlugin-' + [guid]::NewGuid().ToString('N'))
      New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null
      Expand-Archive -LiteralPath $zipPath -DestinationPath $stagingRoot -Force
      $sourceRoot = $stagingRoot
      $isZip = $true
    } else {
      throw "找不到插件包：$Source"
    }

    # 定位插件主目录：自身或直接子目录中包含 plugin.json，且必须唯一
    $candidates = New-Object System.Collections.Generic.List[string]
    if (Test-Path (Join-Path $sourceRoot 'plugin.json') -PathType Leaf) { $candidates.Add($sourceRoot) | Out-Null }
    foreach ($child in @(Get-ChildItem -LiteralPath $sourceRoot -Directory -Force)) {
      if (Test-Path (Join-Path $child.FullName 'plugin.json') -PathType Leaf) { $candidates.Add($child.FullName) | Out-Null }
    }
    if ($candidates.Count -eq 0) { throw '插件包内没有找到 plugin.json（插件主目录必须是包含 plugin.json 的那一层）' }
    if ($candidates.Count -gt 1) { throw "插件包内有多个可能的插件主目录，无法确定：$((@($candidates | ForEach-Object { Split-Path -Leaf $_ })) -join ', ')" }
    $pluginRoot = $candidates[0]
    if (-not $isZip) { $sourceName = Split-Path -Leaf $pluginRoot }

    $manifest = Get-Content -Raw -Encoding UTF8 (Join-Path $pluginRoot 'plugin.json') | ConvertFrom-Json
    $problem = Test-ProjectPluginManifest -Manifest $manifest
    if ($problem) { throw "插件清单无效：$problem" }
    $entryPath = Join-Path $pluginRoot ([string]$manifest.entry)
    if (-not (Test-Path $entryPath -PathType Leaf)) { throw "插件入口不存在：$($manifest.entry)" }

    $id = if ($null -ne $manifest.PSObject.Properties['id'] -and -not [string]::IsNullOrWhiteSpace([string]$manifest.id)) { [string]$manifest.id } else { $sourceName }
    if ($id -ne (Split-Path -Leaf $pluginRoot) -and -not $isZip) { Write-Host "提示：清单 id（$id）与目录名（$(Split-Path -Leaf $pluginRoot)）不同，按清单 id 安装。" -ForegroundColor DarkGray }
    $newVersion = if ($null -ne $manifest.PSObject.Properties['version']) { [string]$manifest.version } else { '' }

    if (-not (Test-Path $pluginsDirectory -PathType Container)) { New-Item -ItemType Directory -Path $pluginsDirectory -Force | Out-Null }
    $target = Join-Path $pluginsDirectory $id
    $existing = Resolve-PluginById -Id $id
    $targetConfigPath = Join-Path $target 'config.json'
    $savedConfigText = $null
    $hadConfig = $false
    if (Test-Path $targetConfigPath -PathType Leaf) {
      $savedConfigText = [IO.File]::ReadAllText($targetConfigPath, [Text.UTF8Encoding]::new($false))
      $hadConfig = $true
    }

    if (Test-Path $target -PathType Container) {
      $installedVersion = if ($null -ne $existing -and $null -ne $existing.Manifest -and $null -ne $existing.Manifest.PSObject.Properties['version']) { [string]$existing.Manifest.version } else { '未知' }
      Write-Host "同名插件已安装：$id（当前版本 $installedVersion，包内版本 $newVersion）" -ForegroundColor Yellow
      if (-not $Force -and -not $Yes) {
        if (([string](Read-Host '确认覆盖安装？旧目录会移入 old\removed-plugins（Y/N）')).Trim() -notmatch '^[yY]') {
          Write-Host '已取消安装。' -ForegroundColor Yellow
          return $false
        }
      }
      $removed = Move-PluginToRemoved -Path $target -Id $id
      if ($removed) { Write-Host "旧版本已保留：$removed" -ForegroundColor DarkGray }
    }

    New-Item -ItemType Directory -Path $target -Force | Out-Null
    Get-ChildItem -LiteralPath $pluginRoot -Force | ForEach-Object {
      Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $target $_.Name) -Recurse -Force
    }

    # 插件的 config.json 属于用户数据：升级时保留本地已有的那一份，缺失时才落回包内默认值。
    if ($hadConfig) {
      [IO.File]::WriteAllText($targetConfigPath, $savedConfigText, [Text.UTF8Encoding]::new($false))
      Write-Host '已保留原有的插件配置 config.json。' -ForegroundColor DarkGray
    } elseif (-not (Test-Path $targetConfigPath -PathType Leaf)) {
      $defaultEnabled = $false
      if ($null -ne $manifest.PSObject.Properties['defaultEnabled'] -and $null -ne $manifest.defaultEnabled) { $defaultEnabled = [bool]$manifest.defaultEnabled }
      $defaultConfig = [pscustomobject]@{ enabled = $defaultEnabled }
      Write-ProjectJsonAtomic -Value $defaultConfig -Path $targetConfigPath -Depth 12
      Write-Host '已按规范生成插件配置 config.json（enabled = ' -NoNewline -ForegroundColor DarkGray
      Write-Host $defaultEnabled -NoNewline -ForegroundColor DarkGray
      Write-Host '）。' -ForegroundColor DarkGray
    }

    Write-ProjectLog "已安装插件：$id（版本 $newVersion）" 'INFO' $root
    Write-Host "已安装插件：$id（$newVersion）" -ForegroundColor Green
    $stateNow = Get-ProjectPluginConfig -Id $id -Root $root
    if ($null -ne $stateNow -and [bool]$stateNow.enabled) {
      Write-Host '当前开关状态：已启用。' -ForegroundColor DarkGray
    } else {
      Write-Host '当前开关状态：已禁用；用 -Enable 或菜单「启用插件」打开它。' -ForegroundColor DarkGray
    }
    Invoke-PluginScriptUnblock
    return $true
  } finally {
    if ($stagingRoot -and (Test-Path $stagingRoot -PathType Container)) { Remove-Item -LiteralPath $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue }
  }
}

function Set-PluginEnabledState {
  param([Parameter(Mandatory)][string]$Id, [Parameter(Mandatory)][bool]$Enabled)
  $plugin = Resolve-PluginById -Id $Id
  if ($null -eq $plugin) { Write-Host "找不到插件：$Id" -ForegroundColor Red; return $false }
  if ($Enabled -and $plugin.Status -ne 'ok') {
    Write-Host ("无法启用 $Id：插件状态异常（{0}）：{1}" -f $plugin.Status, $plugin.Problem) -ForegroundColor Red
    return $false
  }
  Set-ProjectPluginEnabled -Id $Id -Enabled $Enabled -Root $root
  Write-ProjectLog ("已{0}插件：{1}" -f $(if ($Enabled) { '启用' } else { '禁用' }), $Id) 'INFO' $root
  Write-Host ("已{0}插件：{1}" -f $(if ($Enabled) { '启用' } else { '禁用' }), $Id) -ForegroundColor Green
  # 启用后确认一次插件脚本已获得运行许可；禁用时不撤销（只许可、不撤销）
  if ($Enabled) { Invoke-PluginScriptUnblock }
  return $true
}

function Uninstall-PluginPackage {
  param([Parameter(Mandatory)][string]$Id, [switch]$Force)
  $plugin = Resolve-PluginById -Id $Id
  if ($null -eq $plugin) { Write-Host "找不到插件：$Id" -ForegroundColor Red; return $false }
  if (-not $Force -and -not $Yes) {
    Write-Host "即将卸载插件：$Id（$($plugin.Root)）" -ForegroundColor Yellow
    Write-Host '插件目录（含该插件自己的 config.json）会被移入 old\removed-plugins（可恢复），主程序配置不受影响。'
    if (([string](Read-Host "请输入插件名确认卸载：$Id")).Trim() -ne $Id) { Write-Host '输入不匹配，已取消卸载。' -ForegroundColor Yellow; return $false }
  }
  $moved = Move-PluginToRemoved -Path $plugin.Root -Id $Id -Purge:$Purge
  Write-Host "已卸载插件：$Id" -ForegroundColor Green
  if ($moved) { Write-Host "目录已保留在：$moved" -ForegroundColor DarkGray }
  else { Write-Host '目录已删除。' -ForegroundColor DarkGray }
  return $true
}

function Set-AllPluginsEnabledState {
  param([Parameter(Mandatory)][bool]$Enabled)
  $installed = @(Get-ProjectPlugins -Root $root)
  $changed = 0
  $skipped = New-Object System.Collections.Generic.List[string]
  foreach ($plugin in $installed) {
    if ($Enabled -and $plugin.Status -ne 'ok') { $skipped.Add("$($plugin.Id)（$($plugin.Problem)）") | Out-Null; continue }
    Set-ProjectPluginEnabled -Id $plugin.Id -Enabled $Enabled -Root $root
    $changed++
  }
  $word = if ($Enabled) { '启用' } else { '禁用' }
  Write-ProjectLog "已全部$word $changed 个插件" 'INFO' $root
  Write-Host "已$word $changed 个插件。" -ForegroundColor Green
  if ($skipped.Count -gt 0) { Write-Host ("跳过状态异常的插件：{0}" -f ($skipped -join '、')) -ForegroundColor Yellow }
}

function Start-SafeModeHost {
  param([Parameter(Mandatory)][ValidateSet('cli', 'gui')][string]$Target)
  if ($Target -eq 'cli') {
    Write-Host '以安全模式启动 CLI（本次运行不加载任何插件，退出后自动返回）…' -ForegroundColor Cyan
    Write-ProjectLog '以安全模式启动 CLI' 'INFO' $root
    & (Join-Path $root 'ProjectMe.ps1') -SafeMode
    return
  }
  $hostCommand = (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source
  if (-not $hostCommand) { $hostCommand = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source }
  if (-not $hostCommand) { throw '找不到 PowerShell 启动程序，无法打开 GUI。' }
  Write-ProjectLog '以安全模式启动 WPF GUI' 'INFO' $root
  Start-Process $hostCommand -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $root 'ProjectMe.Gui.ps1'), '-SafeMode') -WindowStyle Normal
  Write-Host '已在新窗口中以安全模式启动 GUI。' -ForegroundColor Green
}

# --- 非交互动作（给出任一开关时执行后退出） ---
try {
  $actionTaken = $false
  if ($List) { Show-PluginInventory -Inventory (Get-PluginInventory); $actionTaken = $true }
  if (-not [string]::IsNullOrWhiteSpace($Install)) { Install-PluginPackage -Source $Install -Force | Out-Null; $actionTaken = $true }
  if (-not [string]::IsNullOrWhiteSpace($Enable)) { Set-PluginEnabledState -Id $Enable -Enabled $true | Out-Null; $actionTaken = $true }
  if (-not [string]::IsNullOrWhiteSpace($Disable)) { Set-PluginEnabledState -Id $Disable -Enabled $false | Out-Null; $actionTaken = $true }
  if (-not [string]::IsNullOrWhiteSpace($Uninstall)) { Uninstall-PluginPackage -Id $Uninstall -Force | Out-Null; $actionTaken = $true }
  if ($AllEnabled) { Set-AllPluginsEnabledState -Enabled $true; $actionTaken = $true }
  if ($AllDisabled) { Set-AllPluginsEnabledState -Enabled $false; $actionTaken = $true }
  if ($SafeModeCli) { Start-SafeModeHost -Target 'cli'; $actionTaken = $true }
  if ($SafeModeGui) { Start-SafeModeHost -Target 'gui'; $actionTaken = $true }
  if ($actionTaken) { exit 0 }
} catch {
  Write-Host "`n操作失败：$($_.Exception.Message)" -ForegroundColor Red
  try { Write-ProjectLog ("插件管理器操作失败：{0}`n{1}" -f $_.Exception.Message, $_.ScriptStackTrace) 'ERROR' $root } catch { }
  exit 1
}

# --- 交互菜单 ---
while ($true) {
  $inventory = Get-PluginInventory
  Clear-PluginScreen
  Write-Host 'ProjectMe 插件管理器' -ForegroundColor Cyan
  Write-Host ''
  Show-PluginInventory -Inventory $inventory
  Write-Host ''
  Write-Host '1. 安装插件      2. 启用插件      3. 禁用插件      4. 卸载插件'
  Write-Host '5. 全部启用      6. 全部禁用      7. 以安全模式启动'
  Write-Host '8. 查看插件详情  9. 重新扫描      0. 退出'
  $choice = ([string](Read-Host '请选择')).Trim()
  if ([Console]::IsInputRedirected -and [string]::IsNullOrWhiteSpace($choice)) {
    Write-Host '非交互环境：可改用 -List / -Install / -Enable / -Disable / -Uninstall / -AllEnabled / -AllDisabled / -SafeModeCli / -SafeModeGui。' -ForegroundColor Yellow
    exit 0
  }
  Write-ProjectLog "插件管理器菜单选择：$choice" 'INFO' $root
  Write-Host ''
  try {
    switch ($choice) {
      '1' {
        if ($inventory.Pending.Count -gt 0) {
          $index = 0
          foreach ($zip in $inventory.Pending) {
            $index++
            Write-Host ("  [{0}] {1}" -f $index, $zip.File.FullName)
          }
          $answer = ([string](Read-Host '输入编号安装（输入 a 安装全部，回车取消）')).Trim()
          if ($answer -match '^[aA]') {
            foreach ($zip in $inventory.Pending) {
              if ($zip.Problem) { Write-Host "跳过 $($zip.File.Name)：$($zip.Problem)" -ForegroundColor Yellow; continue }
              Install-PluginPackage -Source $zip.File.FullName | Out-Null
            }
          } elseif ($answer -match '^\d+$') {
            $pick = [int]$answer - 1
            if ($pick -ge 0 -and $pick -lt $inventory.Pending.Count) {
              if ($inventory.Pending[$pick].Problem) { Write-Host "无法安装：$($inventory.Pending[$pick].Problem)" -ForegroundColor Red }
              else { Install-PluginPackage -Source $inventory.Pending[$pick].File.FullName | Out-Null }
            } else { Write-Host '编号无效。' -ForegroundColor Yellow }
          }
        } else {
          $path = ([string](Read-Host '没有待安装的插件包。请输入 zip 或目录路径（回车取消）')).Trim()
          if (-not [string]::IsNullOrWhiteSpace($path)) { Install-PluginPackage -Source $path | Out-Null }
        }
      }
      '2' {
        $plugin = Select-PluginInteractive -Installed $inventory.Installed
        if ($null -ne $plugin) { Set-PluginEnabledState -Id $plugin.Id -Enabled $true | Out-Null }
      }
      '3' {
        $plugin = Select-PluginInteractive -Installed $inventory.Installed
        if ($null -ne $plugin) { Set-PluginEnabledState -Id $plugin.Id -Enabled $false | Out-Null }
      }
      '4' {
        $plugin = Select-PluginInteractive -Installed $inventory.Installed
        if ($null -ne $plugin) { Uninstall-PluginPackage -Id $plugin.Id | Out-Null }
      }
      '5' { Set-AllPluginsEnabledState -Enabled $true }
      '6' { Set-AllPluginsEnabledState -Enabled $false }
      '7' {
        Write-Host '1. CLI（安全模式）   2. GUI（安全模式）   回车返回'
        $target = ([string](Read-Host '请选择')).Trim()
        if ($target -eq '1') { Start-SafeModeHost -Target 'cli' }
        elseif ($target -eq '2') { Start-SafeModeHost -Target 'gui' }
      }
      '8' {
        $plugin = Select-PluginInteractive -Installed $inventory.Installed
        if ($null -ne $plugin) {
          Write-Host ''
          Write-Host "插件：$($plugin.Id)   状态：$(if ($plugin.Status -eq 'ok') { '正常' } else { $plugin.Status })   启用：$($plugin.Enabled)"
          Write-Host "目录：$($plugin.Root)"
          if ($plugin.Status -eq 'ok') { Write-Host "入口：$($plugin.EntryPath)" }
          if ($plugin.Problem) { Write-Host "问题：$($plugin.Problem)" -ForegroundColor Yellow }
          if ($plugin.Status -eq 'ok' -and $null -ne $plugin.Manifest -and $null -ne $plugin.Manifest.PSObject.Properties['gui'] -and $null -ne $plugin.Manifest.gui) {
            # GUI 入口由宿主按清单声明在运行时创建；这里只提示入口位置，方便用户知道装完后去哪里看。
            $panelItems = @(Get-ProjectPluginGuiPanelEntries -Gui $plugin.Manifest.gui)
            $legacyControls = @($plugin.Manifest.gui.controls | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
            if ($panelItems.Count -gt 0) {
              $pageNames = @{ plugin = '插件页'; maintenance = '预览与维护页'; articles = '文章管理页' }
              $pageList = @($panelItems | ForEach-Object {
                $page = if ($_.PSObject.Properties['page'] -and -not [string]::IsNullOrWhiteSpace([string]$_.page)) { ([string]$_.page).Trim().ToLowerInvariant() } elseif ((Get-ProjectPluginGuiType ([string]$_.type)) -in @('textbox', 'combo')) { 'articles' } else { 'maintenance' }
                if ($pageNames.ContainsKey($page)) { $pageNames[$page] } else { $page }
              } | Select-Object -Unique)
              Write-Host "GUI 入口：$($panelItems.Count) 个控件，位于 $(($pageList) -join '、')（由宿主运行时创建，无需改 ProjectMe.Gui.xaml）" -ForegroundColor DarkGray
            } elseif ($legacyControls.Count -gt 0) {
              Write-Host "GUI 入口：引用主程序预留控件 $(($legacyControls) -join ', ')（旧写法 gui.controls）" -ForegroundColor DarkGray
            }
          }
          Write-Host "插件配置：$($plugin.Id)\config.json$(if (Test-Path $plugin.ConfigPath -PathType Leaf) { '' } else { '（尚未生成；启用或首次保存时创建）' })"
          Write-Host ''
          Write-Host (Get-Content -Raw -Encoding UTF8 (Join-Path $plugin.Root 'plugin.json'))
          if (Test-Path $plugin.ConfigPath -PathType Leaf) {
            Write-Host '--- config.json ---'
            Write-Host (Get-Content -Raw -Encoding UTF8 $plugin.ConfigPath)
          }
        }
      }
      '9' { }
      '0' { Write-ProjectLog '插件管理器退出' 'INFO' $root; exit 0 }
      default { Write-Host '无效的选择。' -ForegroundColor Yellow }
    }
  } catch {
    Write-Host "`n操作失败：$($_.Exception.Message)" -ForegroundColor Red
    Write-ProjectLog ("插件管理器操作失败：{0}`n{1}" -f $_.Exception.Message, $_.ScriptStackTrace) 'ERROR' $root
  }
  if ($choice -ne '9') { Pause-PluginMenu }
}
