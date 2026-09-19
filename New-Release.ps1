# ProjectMe 发布包打包脚本
#
# 用法：
#   .\New-Release.ps1
#   .\New-Release.ps1 -OutputDirectory D:\发布
#   .\New-Release.ps1 -NoPlugin        # 不带插件包，只打主程序
#
# 行为：
#   * 版本号取自 project-info.json：Gen1 包名 `ProjectMe-v<版本>.zip`，Gen2 起 `ProjectMe-v<版本>Gen<X>.zip`
#     （同一个 C 版本的多代包互不覆盖；同名包已存在时先删掉再生成）；
#   * zip 内是一个与包名同名的顶层目录（与既有发布包一致），解压后即是一个可直接使用的安装目录；
#   * 排除本地数据与产物：`old\`、`logs\`、`.git\`、`ProjectMe-*.zip` 这些发布包本身、
#     `_` 开头的临时/验证脚本，以及打包脚本自身；
#   * 默认把 `plugins\` 下**所有**插件包（`*.zip`）一起打进发布包（本版本附带 `markdown-split-import.zip`）；
#     不会打包 `plugins\` 下已安装的插件文件夹（那属于用户数据）。

[CmdletBinding()]
param(
  [string]$OutputDirectory = '',
  [switch]$NoPlugin
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($root)) { $root = (Get-Location).ProviderPath }
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { $OutputDirectory = $root }
if (-not (Test-Path $OutputDirectory -PathType Container)) { New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null }

$infoPath = Join-Path $root 'project-info.json'
if (-not (Test-Path $infoPath -PathType Leaf)) { throw "找不到 project-info.json：$infoPath" }
$info = [System.IO.File]::ReadAllText($infoPath, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
$version = [string]$info.version
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw "project-info.json 里的版本号无效：$version" }
# 包名规则：Gen1（或不写 generation）不加后缀；Gen2 起加 Gen<X>，
# 这样同一个 C 版本的多代修复包不会互相覆盖（例如 ProjectMe-v1.1.11.zip 与 ProjectMe-v1.1.11Gen2.zip 并存）。
$generation = if ($null -ne $info.PSObject.Properties['generation'] -and [int]$info.generation -gt 0) { [int]$info.generation } else { 1 }
$baseName = if ($generation -le 1) { "ProjectMe-v$version" } else { "ProjectMe-v${version}Gen$generation" }
$zipPath = Join-Path $OutputDirectory "$baseName.zip"

# 顶层目录名 = 包名（去掉 .zip），解压出来就是安装目录
$excludeNames = @('old', 'logs', '.git', 'Release')
# 本地运行时状态与临时文件不进发布包
$excludeFiles = @('.projectme-serve.json', '00Bugs.txt')
$staging = Join-Path ([IO.Path]::GetTempPath()) ("$baseName-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $staging -Force | Out-Null
$stagingRoot = Join-Path $staging $baseName
New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null

try {
  $included = 0
  foreach ($item in @(Get-ChildItem -LiteralPath $root -Force)) {
    if ($excludeNames -contains $item.Name) { continue }
    if ($excludeFiles -contains $item.Name) { continue }
    if (-not $item.PSIsContainer -and $item.Name -like 'ProjectMe-v*.zip') { continue }
    if ($item.Name -like '.projectme-delete-*.tmp') { continue }
    if ($item.Name -like '_*') { continue }              # 下划线开头的临时/验证脚本不进发布包
    if ($item.Name -eq 'New-Release.ps1') { continue }   # 打包脚本本身不进发布包
    $destination = Join-Path $stagingRoot $item.Name
    if ($item.PSIsContainer) {
      if ($item.Name -eq 'plugins') {
        # plugins\ 只带插件包，不带本机已安装的插件目录
        $pluginDirectory = New-Item -ItemType Directory -Path $destination -Force
        if (-not $NoPlugin) {
          foreach ($package in @(Get-ChildItem -LiteralPath $item.FullName -File -Filter *.zip -Force)) {
            Copy-Item -LiteralPath $package.FullName -Destination (Join-Path $pluginDirectory.FullName $package.Name) -Force
            Write-Host ("  + plugins\{0}（{1:N0} 字节）" -f $package.Name, $package.Length)
          }
        }
        continue
      }
      Copy-Item -LiteralPath $item.FullName -Destination $destination -Recurse -Force
      continue
    }
    Copy-Item -LiteralPath $item.FullName -Destination $destination -Force
    $included++
  }

  if (Test-Path $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
  $temporaryZip = "$zipPath.tmp.zip"
  [IO.Compression.ZipFile]::CreateFromDirectory($staging, $temporaryZip, [IO.Compression.CompressionLevel]::Optimal, $false)
  Move-Item -LiteralPath $temporaryZip -Destination $zipPath -Force

  $zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
  try {
    $entryCount = $zip.Entries.Count
    $pluginEntries = @($zip.Entries | Where-Object { ($_.FullName -replace '\\', '/') -match '^[^/]+/plugins/.+\.zip$' })
    $size = (Get-Item -LiteralPath $zipPath).Length
    Write-Host ''
    Write-Host ("发布包已生成：{0}" -f $zipPath) -ForegroundColor Green
    Write-Host ("  包内顶层目录：{0}\    条目数：{1}    大小：{2:N2} MB" -f $baseName, $entryCount, ($size / 1MB))
    if ($pluginEntries.Count) {
      foreach ($entry in $pluginEntries) { Write-Host ("  附带的插件包：{0}" -f $entry.FullName) }
    } else {
      Write-Host '  未附带任何插件包。' -ForegroundColor DarkGray
    }
  } finally {
    $zip.Dispose()
  }
} finally {
  if (Test-Path $staging) { Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue }
}
