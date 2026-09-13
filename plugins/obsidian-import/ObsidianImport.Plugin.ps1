# ProjectMe 插件：从 Obsidian 导入
#
# 清单：plugins\obsidian-import\plugin.json
# 开关：projectme.config.json → plugins.obsidian-import.enabled（默认 false）
#
# 本文件由宿主 dot-source 载入（CLI：ProjectMe.ps1；GUI：ProjectMe.Gui.ps1），
# 因此可以直接使用宿主的 $root、$config / $script:config、Get-Control、Show-Message、
# Show-Error、Show-TextDialog、Write-ProjectLog、Refresh-Articles、Pause-Menu 等。
# 清单中的 cli.function / gui.function 由宿主无参调用。
#
# 除导入器路径与 -ProjectRoot 传参外，下列函数保持与原 ProjectMe.ps1 / ProjectMe.Gui.ps1 /
# ProjectMe.Common.ps1 中的实现一致。

$ProjectMePluginObsidianImportRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

function Save-ProjectObsidianSourceRoot {
  param([AllowEmptyString()][string]$SourceRoot = '', [string]$Root = (Get-ProjectRoot))
  $path = Join-Path $Root 'projectme.config.json'
  $config = if (Test-Path $path -PathType Leaf) {
    Get-Content -Raw -Encoding UTF8 $path | ConvertFrom-Json
  } else {
    Get-DefaultProjectConfig
  }
  if ($null -eq $config.PSObject.Properties['obsidian']) {
    $config | Add-Member -NotePropertyName obsidian -NotePropertyValue ([pscustomobject]@{}) -Force
  }
  if ($null -eq $config.obsidian.PSObject.Properties['sourceRoot']) {
    $config.obsidian | Add-Member -NotePropertyName sourceRoot -NotePropertyValue '' -Force
  }
  $config.obsidian.sourceRoot = $SourceRoot
  Write-ProjectJsonAtomic -Value $config -Path $path -Depth 12
}

function Import-ObsidianInteractive {
  $source = Read-Host "请输入 Obsidian 文集根目录（回车使用默认值“$($config.obsidian.sourceRoot)”）"
  if ([string]::IsNullOrWhiteSpace($source)) { $source = $config.obsidian.sourceRoot }
  if ([string]::IsNullOrWhiteSpace($source)) { return }
  try {
    Write-ProjectLog "开始 Obsidian 导入，源目录：$source"
    $preview = Read-Host "是否先预览导入结果？（Y/N，默认 $($config.obsidian.preview)）"
    $importScript = Join-Path $ProjectMePluginObsidianImportRoot 'Import-ObsidianCorpus.ps1'
    $isPreview = if ($preview -eq '') { [bool]$config.obsidian.preview } else { $preview -match '^[yY是]' }
    if ($isPreview) { & $importScript -SourceRoot $source -ProjectRoot $root -WhatIf }
    else { & $importScript -SourceRoot $source -ProjectRoot $root }
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "导入脚本退出，代码：$LASTEXITCODE" }
    if ($isPreview) {
      if ((Read-Host '预览完成，是否执行实际导入？（Y/N）') -match '^[yY是]') {
        & $importScript -SourceRoot $source -ProjectRoot $root
        if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "导入脚本退出，代码：$LASTEXITCODE" }
      }
    }
    Write-ProjectLog 'Obsidian 导入流程结束'
  } catch {
    Write-ProjectLog ("Obsidian 导入失败：{0}`n{1}" -f $_.Exception.Message, $_.ScriptStackTrace) 'ERROR'
    Write-Host "`n导入失败：$($_.Exception.Message)" -ForegroundColor Red
    Write-Host "详细信息已写入：$root\logs\projectme-cli.log"
    Pause-Menu
    return
  }
  Pause-Menu
}

function Update-DefaultObsidianSourceUi {
  $sourceRoot = [string]$script:config.obsidian.sourceRoot
  (Get-Control 'DefaultObsidianSourceBox').Text = $sourceRoot
  (Get-Control 'DefaultObsidianSourceBox').ToolTip = $sourceRoot
  if ([string]::IsNullOrWhiteSpace($sourceRoot)) {
    (Get-Control 'DefaultObsidianSourceHintText').Text = '未设置默认源，导入时会从系统默认位置打开目录选择窗口。'
  } elseif (Test-Path -LiteralPath $sourceRoot -PathType Container) {
    (Get-Control 'DefaultObsidianSourceHintText').Text = '已保存默认源。导入时目录选择窗口会默认定位到这里。'
  } else {
    (Get-Control 'DefaultObsidianSourceHintText').Text = '已保存的默认源当前不存在，请重新选择目录并保存。'
  }
}

function Select-ObsidianFolder {
  $shell = New-Object -ComObject Shell.Application
  $initialPath = [string]$script:config.obsidian.sourceRoot
  if ($initialPath -and -not (Test-Path -LiteralPath $initialPath -PathType Container)) {
    Write-ProjectLog "默认 Obsidian 导入源不存在，已改为系统默认位置：$initialPath" 'WARN' $root
    $initialPath = ''
    Show-Message '已保存的默认 Obsidian 导入源不存在，本次将从系统默认位置打开目录选择窗口。' '默认导入源不可用'
  }
  $folder = $shell.BrowseForFolder(0, '选择 Obsidian 文集根目录', 0, $initialPath)
  if ($folder) { return $folder.Self.Path }
  return $null
}

function Save-DefaultObsidianSourceFromGui {
  param([AllowEmptyString()][string]$SourceRoot)
  $source = if ($PSBoundParameters.ContainsKey('SourceRoot')) { $SourceRoot } else { (Get-Control 'DefaultObsidianSourceBox').Text.Trim() }
  if (-not [string]::IsNullOrWhiteSpace($source) -and -not (Test-Path -LiteralPath $source -PathType Container)) {
    Show-Error '默认 Obsidian 导入源必须是一个已存在的文件夹。' '无法保存设置'
    return
  }
  try {
    Save-ProjectObsidianSourceRoot -Root $root -SourceRoot $source
    $script:config.obsidian.sourceRoot = $source
    Update-DefaultObsidianSourceUi
    Write-ProjectLog "WPF GUI 保存默认 Obsidian 导入源：$source" 'INFO' $root
    Show-Message '默认 Obsidian 导入源已保存。' '设置已保存'
  } catch {
    Write-ProjectLog ("WPF GUI 保存默认 Obsidian 导入源失败：{0}`n{1}" -f $_.Exception.Message, $_.ScriptStackTrace) 'ERROR' $root
    Show-Error $_.Exception.Message '保存设置失败'
  }
}

function Import-ObsidianFromGui {
  $source = Select-ObsidianFolder; if ([string]::IsNullOrWhiteSpace($source)) { return }; $importScript = Join-Path $ProjectMePluginObsidianImportRoot 'Import-ObsidianCorpus.ps1'
  try { $preview = (& $importScript -SourceRoot $source -ProjectRoot $root -WhatIf 2>&1 | Out-String); $confirm = Show-TextDialog 'Obsidian 导入预览' $preview '确认正式导入'; if ($confirm) { $result = (& $importScript -SourceRoot $source -ProjectRoot $root 2>&1 | Out-String); Show-TextDialog 'Obsidian 导入完成' $result '关闭' | Out-Null; Refresh-Articles; Write-ProjectLog "WPF GUI 完成 Obsidian 导入：$source" 'INFO' $root } } catch { Write-ProjectLog "WPF GUI Obsidian 导入失败：$($_.Exception.Message)`n$($_.ScriptStackTrace)" 'ERROR' $root; Show-Error $_.Exception.Message 'Obsidian 导入失败' }
}

function Initialize-ObsidianImportGui {
  (Get-Control 'ImportObsidianButton').Add_Click({ Import-ObsidianFromGui })
  (Get-Control 'BrowseDefaultObsidianSourceButton').Add_Click({ $source = Select-ObsidianFolder; if (-not [string]::IsNullOrWhiteSpace($source)) { (Get-Control 'DefaultObsidianSourceBox').Text = $source; (Get-Control 'DefaultObsidianSourceBox').ToolTip = $source; (Get-Control 'DefaultObsidianSourceHintText').Text = '已选择新目录，点击“保存设置”后生效。' } })
  (Get-Control 'SaveDefaultObsidianSourceButton').Add_Click({ Save-DefaultObsidianSourceFromGui })
  (Get-Control 'ClearDefaultObsidianSourceButton').Add_Click({ Save-DefaultObsidianSourceFromGui -SourceRoot '' })
  Update-DefaultObsidianSourceUi
}
