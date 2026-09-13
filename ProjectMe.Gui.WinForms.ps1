try {
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $root 'ProjectMe.Common.ps1')

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:info = Get-ProjectInfo $root
$script:config = Get-ProjectConfig $root
$script:articles = @()
$script:visibleArticles = @()
$script:selectedArticle = $null
$script:serveProcess = $null

function New-Label([string]$Text, [int]$X, [int]$Y, [int]$Width = 100) {
  $label = New-Object Windows.Forms.Label
  $label.Text = $Text; $label.Location = New-Object Drawing.Point($X, $Y); $label.Size = New-Object Drawing.Size($Width, 24)
  $label.TextAlign = 'MiddleLeft'; return $label
}

function New-TextBox([int]$X, [int]$Y, [int]$Width, [string]$Text = '') {
  $box = New-Object Windows.Forms.TextBox
  $box.Location = New-Object Drawing.Point($X, $Y); $box.Size = New-Object Drawing.Size($Width, 28); $box.Text = $Text
  return $box
}

function Set-Text([object]$Control, [object]$Value) { $Control.Text = if ($null -eq $Value) { '' } else { [string]$Value } }
function Get-TagsText([object]$Value) { return (@($Value) -join ', ') }
function Get-SelectedArticle { if ($script:list.SelectedIndex -lt 0) { return $null }; return $script:visibleArticles[$script:list.SelectedIndex] }

function Refresh-Articles {
  $script:articles = @(Get-Articles $root | Sort-Object @{Expression = { if ($null -ne $_.order) { [double]$_.order } else { 0 } }; Descending = $true})
  $query = $script:search.Text.Trim()
  $script:visibleArticles = @($script:articles | Where-Object { -not $query -or $_.title -like "*$query*" })
  $script:list.Items.Clear()
  foreach ($article in $script:visibleArticles) {
    [void]$script:list.Items.Add("$($article.title)  ·  $($article.category)")
  }
  $script:countLabel.Text = "$($script:list.Items.Count) 篇文章"
  if ($script:list.Items.Count -gt 0) { $script:list.SelectedIndex = 0 } else { Clear-Editor }
}

function Clear-Editor {
  $script:selectedArticle = $null
  foreach ($box in @($script:titleBox, $script:categoryBox, $script:tagsBox, $script:sectionBox, $script:dateBox, $script:readingBox, $script:excerptBox, $script:fontBox, $script:colorBox)) { if ($box) { $box.Text = '' } }
  $script:fileLabel.Text = '尚未选择文章'
}

function Load-SelectedArticle {
  $article = Get-SelectedArticle
  if ($null -eq $article) { Clear-Editor; return }
  $script:selectedArticle = $article
  Set-Text $script:titleBox $article.title; Set-Text $script:categoryBox $article.category; Set-Text $script:tagsBox (Get-TagsText $article.tags)
  Set-Text $script:sectionBox $article.section; Set-Text $script:dateBox $article.date; Set-Text $script:readingBox $article.readingTime
  Set-Text $script:excerptBox $article.excerpt; Set-Text $script:fontBox $article.titleFont; Set-Text $script:colorBox $article.titleColor
  $script:fileLabel.Text = "文件：articles\$($article.file)"
}

function Save-SelectedArticle {
  if ($null -eq $script:selectedArticle) { [Windows.Forms.MessageBox]::Show('请先选择一篇文章。', 'ProjectMe'); return }
  if ([string]::IsNullOrWhiteSpace($script:titleBox.Text)) { [Windows.Forms.MessageBox]::Show('标题不能为空。', '无法保存'); return }
  if ($script:colorBox.Text -and -not (Test-ProjectColor $script:colorBox.Text)) { [Windows.Forms.MessageBox]::Show('目录标题颜色格式无效。', '无法保存'); return }
  $updated = $script:selectedArticle.PSObject.Copy()
  Set-ArticlePropertyValue $updated 'title' $script:titleBox.Text.Trim(); Set-ArticlePropertyValue $updated 'category' $script:categoryBox.Text.Trim()
  Set-ArticlePropertyValue $updated 'tags' @($script:tagsBox.Text -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  Set-ArticlePropertyValue $updated 'section' $script:sectionBox.Text.Trim(); Set-ArticlePropertyValue $updated 'date' $script:dateBox.Text.Trim()
  Set-ArticlePropertyValue $updated 'readingTime' $script:readingBox.Text.Trim(); Set-ArticlePropertyValue $updated 'excerpt' $script:excerptBox.Text.Trim()
  Set-ArticlePropertyValue $updated 'titleFont' $script:fontBox.Text.Trim(); Set-ArticlePropertyValue $updated 'titleColor' $script:colorBox.Text.Trim()
  $all = @(Get-Articles $root); for ($i = 0; $i -lt $all.Count; $i++) { if ($all[$i].slug -eq $script:selectedArticle.slug) { $all[$i] = $updated } }
  Save-Articles $all $root; Write-ProjectLog "GUI 保存文章：$($updated.slug)" 'INFO' $root
  Refresh-Articles; [Windows.Forms.MessageBox]::Show('文章属性已保存。', 'ProjectMe')
}

function New-ArticleFromGui {
  $dialog = New-Object Windows.Forms.Form; $dialog.Text = '新建文章'; $dialog.Size = New-Object Drawing.Size(460, 370); $dialog.StartPosition = 'CenterParent'; $dialog.FormBorderStyle = 'FixedDialog'; $dialog.MaximizeBox = $false
  $fields = @{}
  $definitions = @(@('Slug', '标识'), @('Title', '标题'), @('Category', '类别'), @('Excerpt', '摘要'), @('Tags', '标签（逗号分隔）'))
  for ($i = 0; $i -lt $definitions.Count; $i++) { $label = New-Label $definitions[$i][1] 24 (22 + $i * 48) 100; $box = New-TextBox 126 (20 + $i * 48) 285; $dialog.Controls.Add($label); $dialog.Controls.Add($box); $fields[$definitions[$i][0]] = $box }
  $fields.Tags.Text = @($script:config.newArticle.tags) -join ', '
  $ok = New-Object Windows.Forms.Button; $ok.Text = '创建'; $ok.Location = New-Object Drawing.Point(126, 270); $ok.Size = New-Object Drawing.Size(120, 34)
  $cancel = New-Object Windows.Forms.Button; $cancel.Text = '取消'; $cancel.Location = New-Object Drawing.Point(260, 270); $cancel.Size = New-Object Drawing.Size(120, 34)
  $cancel.DialogResult = 'Cancel'; $dialog.CancelButton = $cancel; $dialog.Controls.Add($ok); $dialog.Controls.Add($cancel)
  $ok.Add_Click({
    try {
      foreach ($key in @('Slug','Title','Category','Excerpt')) { if ([string]::IsNullOrWhiteSpace($fields[$key].Text)) { throw "${key} 不能为空。" } }
      $tags = @($fields.Tags.Text -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
      & (Join-Path $root 'New-Article.ps1') -Slug $fields.Slug.Text.Trim() -Title $fields.Title.Text.Trim() -Category $fields.Category.Text.Trim() -Excerpt $fields.Excerpt.Text.Trim() -Tags $tags -Date $script:config.newArticle.date -ReadingTime $script:config.newArticle.readingTime | Out-Null
      $dialog.DialogResult = 'OK'; $dialog.Close()
    } catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message, '创建失败') }
  })
  [void]$dialog.ShowDialog($script:form); Refresh-Articles
}

function Start-Preview {
  if ($script:serveProcess -and -not $script:serveProcess.HasExited) { return }
  $port = [int]$script:portBox.Text
  $script:serveProcess = Start-Process powershell -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $root 'serve.ps1'),'-Port',$port) -PassThru -WindowStyle Hidden
  Write-ProjectJsonAtomic -Value ([pscustomobject]@{ pid = $script:serveProcess.Id; port = $port; started = (Get-Date).ToString('o') }) -Path (Join-Path $root '.projectme-serve.json')
  $script:serviceLabel.Text = "服务运行中 · 端口 $port · PID $($script:serveProcess.Id)"; $script:serviceLabel.ForeColor = [Drawing.Color]::ForestGreen
}

function Stop-Preview {
  if ($script:serveProcess -and -not $script:serveProcess.HasExited) { Stop-Process -Id $script:serveProcess.Id -Force -ErrorAction SilentlyContinue }
  $state = Join-Path $root '.projectme-serve.json'; if (Test-Path $state) { Remove-Item $state -Force }
  $script:serviceLabel.Text = '服务未运行'; $script:serviceLabel.ForeColor = [Drawing.Color]::DimGray
}

$script:form = New-Object Windows.Forms.Form; $script:form.Text = "ProjectMe 管理器 · $(Get-DisplayVersion $script:info)"; $script:form.Size = New-Object Drawing.Size(1120, 720); $script:form.MinimumSize = New-Object Drawing.Size(920, 620); $script:form.StartPosition = 'CenterScreen'; $script:form.BackColor = [Drawing.Color]::WhiteSmoke
$header = New-Object Windows.Forms.Panel; $header.Dock = 'Top'; $header.Height = 74; $header.BackColor = [Drawing.Color]::FromArgb(31, 41, 55); $script:form.Controls.Add($header)
$brand = New-Label 'ProjectMe' 24 13 240; $brand.Font = New-Object Drawing.Font('Segoe UI', 22, [Drawing.FontStyle]::Bold); $brand.ForeColor = [Drawing.Color]::White; $header.Controls.Add($brand)
$version = New-Label "个人文集管理器  ·  $(Get-DisplayVersion $script:info)" 26 45 300; $version.ForeColor = [Drawing.Color]::LightGray; $header.Controls.Add($version)
$script:search = New-TextBox 18 92 330; $script:search.Text = ''; $script:search.Add_TextChanged({ Refresh-Articles }); $script:form.Controls.Add($script:search)
$searchHint = New-Label '搜索文章标题' 24 96 150; $searchHint.ForeColor = [Drawing.Color]::Gray; $script:form.Controls.Add($searchHint)
$script:countLabel = New-Label '0 篇文章' 235 130 110; $script:countLabel.ForeColor = [Drawing.Color]::DimGray; $script:form.Controls.Add($script:countLabel)
$script:list = New-Object Windows.Forms.ListBox; $script:list.Location = New-Object Drawing.Point(18, 160); $script:list.Size = New-Object Drawing.Size(330, 440); $script:list.Font = New-Object Drawing.Font('Segoe UI', 10); $script:list.IntegralHeight = $false; $script:list.Add_SelectedIndexChanged({ Load-SelectedArticle }); $script:form.Controls.Add($script:list)
$newButton = New-Object Windows.Forms.Button; $newButton.Text = '+ 新建文章'; $newButton.Location = New-Object Drawing.Point(18, 615); $newButton.Size = New-Object Drawing.Size(150, 34); $newButton.Add_Click({ New-ArticleFromGui }); $script:form.Controls.Add($newButton)
$refreshButton = New-Object Windows.Forms.Button; $refreshButton.Text = '刷新'; $refreshButton.Location = New-Object Drawing.Point(178, 615); $refreshButton.Size = New-Object Drawing.Size(80, 34); $refreshButton.Add_Click({ Refresh-Articles }); $script:form.Controls.Add($refreshButton)

$editor = New-Object Windows.Forms.GroupBox; $editor.Text = '文章属性'; $editor.Location = New-Object Drawing.Point(370, 92); $editor.Size = New-Object Drawing.Size(710, 370); $script:form.Controls.Add($editor)
$script:titleBox = New-TextBox 125 28 550; $script:categoryBox = New-TextBox 125 62 250; $script:tagsBox = New-TextBox 125 96 550; $script:sectionBox = New-TextBox 125 130 250; $script:dateBox = New-TextBox 475 62 200; $script:readingBox = New-TextBox 475 130 200; $script:excerptBox = New-TextBox 125 164 550; $script:fontBox = New-TextBox 125 198 250; $script:colorBox = New-TextBox 475 198 200
foreach ($pair in @(@('标题', $script:titleBox, 24, 32), @('类别', $script:categoryBox, 24, 66), @('标签', $script:tagsBox, 24, 100), @('节', $script:sectionBox, 24, 134), @('日期', $script:dateBox, 374, 66), @('阅读时间', $script:readingBox, 374, 134), @('摘要', $script:excerptBox, 24, 168), @('目录字体', $script:fontBox, 24, 202), @('目录颜色', $script:colorBox, 374, 202))) { $editor.Controls.Add((New-Label $pair[0] $pair[2] $pair[3] 85)); $editor.Controls.Add($pair[1]) }
$script:fileLabel = New-Label '尚未选择文章' 24 238 550; $script:fileLabel.ForeColor = [Drawing.Color]::DimGray; $editor.Controls.Add($script:fileLabel)
$saveButton = New-Object Windows.Forms.Button; $saveButton.Text = '保存属性'; $saveButton.Location = New-Object Drawing.Point(125, 275); $saveButton.Size = New-Object Drawing.Size(130, 36); $saveButton.Add_Click({ Save-SelectedArticle }); $editor.Controls.Add($saveButton)
$openButton = New-Object Windows.Forms.Button; $openButton.Text = '打开正文'; $openButton.Location = New-Object Drawing.Point(265, 275); $openButton.Size = New-Object Drawing.Size(130, 36); $openButton.Add_Click({ if ($script:selectedArticle) { Start-Process notepad.exe (Join-Path $root "articles\$($script:selectedArticle.file)") } }); $editor.Controls.Add($openButton)

$toolsBox = New-Object Windows.Forms.GroupBox; $toolsBox.Text = '预览与维护'; $toolsBox.Location = New-Object Drawing.Point(370, 480); $toolsBox.Size = New-Object Drawing.Size(710, 170); $script:form.Controls.Add($toolsBox)
$script:portBox = New-TextBox 125 30 90 ([string]$script:config.serve.port); $toolsBox.Controls.Add((New-Label '预览端口' 24 34 85)); $toolsBox.Controls.Add($script:portBox)
$startButton = New-Object Windows.Forms.Button; $startButton.Text = '启动预览'; $startButton.Location = New-Object Drawing.Point(235, 28); $startButton.Size = New-Object Drawing.Size(110, 34); $startButton.Add_Click({ try { Start-Preview } catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message, '启动失败') } }); $toolsBox.Controls.Add($startButton)
$stopButton = New-Object Windows.Forms.Button; $stopButton.Text = '停止预览'; $stopButton.Location = New-Object Drawing.Point(355, 28); $stopButton.Size = New-Object Drawing.Size(110, 34); $stopButton.Add_Click({ Stop-Preview }); $toolsBox.Controls.Add($stopButton)
$webButton = New-Object Windows.Forms.Button; $webButton.Text = '打开网站'; $webButton.Location = New-Object Drawing.Point(475, 28); $webButton.Size = New-Object Drawing.Size(110, 34); $webButton.Add_Click({ Start-Process "http://localhost:$($script:portBox.Text)/" }); $toolsBox.Controls.Add($webButton)
$checkButton = New-Object Windows.Forms.Button; $checkButton.Text = '运行项目自检'; $checkButton.Location = New-Object Drawing.Point(24, 82); $checkButton.Size = New-Object Drawing.Size(130, 34); $checkButton.Add_Click({ try { $result = & (Join-Path $root 'Check-ProjectMe.ps1') 2>&1 | Out-String; [Windows.Forms.MessageBox]::Show($result, '项目自检') } catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message, '项目自检失败') } }); $toolsBox.Controls.Add($checkButton)
$logButton = New-Object Windows.Forms.Button; $logButton.Text = '查看日志'; $logButton.Location = New-Object Drawing.Point(165, 82); $logButton.Size = New-Object Drawing.Size(110, 34); $logButton.Add_Click({ $log = Join-Path $root 'logs\projectme-cli.log'; if (Test-Path $log) { Start-Process notepad.exe $log } }); $toolsBox.Controls.Add($logButton)
$script:serviceLabel = New-Label '服务未运行' 300 87 300; $script:serviceLabel.ForeColor = [Drawing.Color]::DimGray; $toolsBox.Controls.Add($script:serviceLabel)

Refresh-Articles
[void]$script:form.ShowDialog()
Stop-Preview
} catch {
  $message = "GUI 启动失败：$($_.Exception.Message)"
  try { Write-ProjectLog "$message`n$($_.ScriptStackTrace)" 'ERROR' $root } catch { }
  try { [Windows.Forms.MessageBox]::Show("$message`n`n日志：$root\logs\projectme-cli.log", 'ProjectMe GUI 启动失败', 'OK', 'Error') | Out-Null } catch { }
  Write-Host "`n$message" -ForegroundColor Red
  Write-Host "详细信息已写入：$root\logs\projectme-cli.log"
  Read-Host '按 Enter 关闭此窗口'
  exit 1
}
