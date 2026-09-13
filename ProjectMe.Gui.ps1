try {
  $ErrorActionPreference = 'Stop'
  $root = Split-Path -Parent $MyInvocation.MyCommand.Path
  . (Join-Path $root 'ProjectMe.Common.ps1')

  Add-Type -AssemblyName PresentationFramework
  Add-Type -AssemblyName PresentationCore
  Add-Type -AssemblyName WindowsBase
  Add-Type -AssemblyName System.Xaml

  $script:info = Get-ProjectInfo $root
  $script:config = Get-ProjectConfig $root
  $script:articles = @()
  $script:visibleArticles = @()
  $script:selectedArticle = $null
  $script:articleSortProperty = ''
  $script:articleSortAscending = $true
  $script:serveProcess = $null
  $script:timelineEntries = @()
  $script:visibleTimelineEntries = @()
  $script:selectedTimelineEntry = $null

  function Get-Control([string]$Name) { return $script:window.FindName($Name) }
  function Set-ControlText([object]$Control, [object]$Value) { $Control.Text = if ($null -eq $Value) { '' } else { [string]$Value } }
  function Show-Message([string]$Message, [string]$Title = 'ProjectMe') { [System.Windows.MessageBox]::Show($script:window, $Message, $Title, 'OK', 'Information') | Out-Null }
  function Show-Error([string]$Message, [string]$Title = '操作失败') { [System.Windows.MessageBox]::Show($script:window, $Message, $Title, 'OK', 'Error') | Out-Null }

  function Set-Theme {
    $isDark = $false
    try { $isDark = ((Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name AppsUseLightTheme -ErrorAction Stop).AppsUseLightTheme -eq 0) } catch { }
    $palette = if ($isDark) {
      @{ WindowBackground = '#171A21'; SurfaceBackground = '#20242D'; SurfaceMuted = '#282E39'; SidebarBackground = '#111318'; SidebarActive = '#2D6CDF'; SidebarText = '#EEF2F7'; SidebarMuted = '#98A2B3'; TextPrimary = '#F5F7FA'; TextSecondary = '#AAB4C3'; BorderBrush = '#3A4352'; InputBackground = '#1B1F27'; AccentBrush = '#4F8CFF'; AccentSoftBrush = '#29446F'; PurpleBrush = '#9B7BFF' }
    } else {
      @{ WindowBackground = '#F4F6F9'; SurfaceBackground = '#FFFFFF'; SurfaceMuted = '#EEF1F5'; SidebarBackground = '#172033'; SidebarActive = '#2D6CDF'; SidebarText = '#F3F6FB'; SidebarMuted = '#AAB7CA'; TextPrimary = '#1D2735'; TextSecondary = '#667085'; BorderBrush = '#D9E0EA'; InputBackground = '#FFFFFF'; AccentBrush = '#2D6CDF'; AccentSoftBrush = '#DCE9FF'; PurpleBrush = '#7654D9' }
    }
    $brushConverter = New-Object Windows.Media.BrushConverter
    foreach ($key in $palette.Keys) { $brush = $brushConverter.ConvertFromString([string]$palette[$key]); if ($brush -isnot [Windows.Media.Brush]) { throw "主题资源 $key 未生成有效画刷。" }; $script:window.Resources[$key] = $brush }
  }

  function Set-Fonts {
    $normalPath = Join-Path $root 'fonts\SourceHanSansSC-Normal-2.otf'; $mediumPath = Join-Path $root 'fonts\SourceHanSansSC-Medium-2.otf'
    if (-not (Test-Path $normalPath -PathType Leaf) -or -not (Test-Path $mediumPath -PathType Leaf)) { throw '字体文件缺失。' }
    $normal = @([Windows.Media.Fonts]::GetFontFamilies([Uri]$normalPath))[0]; $medium = @([Windows.Media.Fonts]::GetFontFamilies([Uri]$mediumPath))[0]
    if ($null -eq $normal -or $null -eq $medium) { throw '无法加载 fonts\ 目录中的思源黑体字体。' }
    $script:window.Resources['BodyFontFamily'] = $normal; $script:window.Resources['TitleFontFamily'] = $medium
  }

  function Get-PowerShellHost {
    $command = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if (-not $command) { $command = Get-Command powershell.exe -ErrorAction SilentlyContinue }
    if (-not $command) { throw '找不到 PowerShell 启动程序。' }
    return $command.Source
  }

  function Set-Page([ValidateSet('articles','maintenance','timeline')][string]$Page) {
    $pages = @{ articles = 'ArticlesPage'; maintenance = 'MaintenancePage'; timeline = 'TimelinePage' }
    $headers = @{ articles = 'ArticlesHeaderPanel'; maintenance = 'MaintenanceHeaderPanel'; timeline = 'TimelineHeaderPanel' }
    foreach ($key in $pages.Keys) {
      $visibility = 'Collapsed'
      if ($key -eq $Page) { $visibility = 'Visible' }
      (Get-Control $pages[$key]).Visibility = $visibility
      (Get-Control $headers[$key]).Visibility = $visibility
    }
    foreach ($name in @('ArticlesNavButton','MaintenanceNavButton','TimelineNavButton')) {
      $button = Get-Control $name; $resourceKey = 'SidebarBackground'
      if (($name -eq 'ArticlesNavButton' -and $Page -eq 'articles') -or ($name -eq 'MaintenanceNavButton' -and $Page -eq 'maintenance') -or ($name -eq 'TimelineNavButton' -and $Page -eq 'timeline')) { $resourceKey = 'SidebarActive' }
      $button.Background = $script:window.Resources[$resourceKey]
    }
    if ($Page -eq 'articles') { Refresh-Articles }
    if ($Page -eq 'timeline') { Refresh-Timeline }
  }

  function Stop-Preview {
    Stop-ProjectPreview -Root $root -Ports @(4173, 4174) | Out-Null
    if ($script:serveProcess -and -not $script:serveProcess.HasExited) { Stop-Process -Id $script:serveProcess.Id -Force -ErrorAction SilentlyContinue }
    $script:serveProcess = $null
    try {
      (Get-Control 'ServiceStatusText').Text = '预览未运行'
      (Get-Control 'MaintenanceServiceText').Text = '预览未运行'
    } catch { }
  }

  function Start-Preview([object]$PortControl = (Get-Control 'PortBox')) {
    if ($script:serveProcess -and -not $script:serveProcess.HasExited) { return }
    $port = 0; if (-not [int]::TryParse($PortControl.Text, [ref]$port) -or $port -lt 1 -or $port -gt 65535) { throw '端口必须是 1 到 65535 之间的数字。' }
    $existingState = Get-PreviewState -Root $root
    if ($existingState -and $existingState.port) {
      $existingPid = Get-ListeningPreviewProcessId -Port ([int]$existingState.port)
      if ($existingPid) {
        $script:serveProcess = Get-Process -Id $existingPid -ErrorAction SilentlyContinue
        $text = "预览运行中 · $($existingState.port) · PID $existingPid"
        (Get-Control 'ServiceStatusText').Text = $text
        (Get-Control 'MaintenanceServiceText').Text = $text
        (Get-Control 'StatusText').Text = '本地预览已启动'
        return
      }
      Stop-ProjectPreview -Root $root | Out-Null
    }
    $stalePid = Get-ListeningPreviewProcessId -Port $port
    if ($stalePid) {
      $script:serveProcess = Get-Process -Id $stalePid -ErrorAction SilentlyContinue
      $text = "预览运行中 · $port · PID $stalePid"
      (Get-Control 'ServiceStatusText').Text = $text
      (Get-Control 'MaintenanceServiceText').Text = $text
      (Get-Control 'StatusText').Text = '本地预览已启动'
      return
    }
    $script:serveProcess = Start-Process (Get-PowerShellHost) -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $root 'serve.ps1'),'-Port',$port) -PassThru -WindowStyle Hidden
    Write-ProjectJsonAtomic -Value ([pscustomobject]@{ pid = $script:serveProcess.Id; port = $port; started = (Get-Date).ToString('o') }) -Path (Join-Path $root '.projectme-serve.json')
    $text = "预览运行中 · $port · PID $($script:serveProcess.Id)"; (Get-Control 'ServiceStatusText').Text = $text; (Get-Control 'MaintenanceServiceText').Text = $text; (Get-Control 'StatusText').Text = '本地预览已启动'
  }

  function Refresh-Articles {
    $script:articles = @(Get-Articles $root | Sort-Object @{Expression = { if ($null -ne $_.order) { [double]$_.order } else { 0 } }; Descending = $true })
    $query = (Get-Control 'SearchBox').Text.Trim(); $script:visibleArticles = @($script:articles | Where-Object { -not $query -or $_.title -like "*$query*" -or $_.category -like "*$query*" -or $_.section -like "*$query*" })
    if ($script:articleSortProperty) {
      $propertyName = $script:articleSortProperty
      $sortDescending = -not $script:articleSortAscending
      $script:visibleArticles = @($script:visibleArticles | Sort-Object @{ Expression = { $_.$propertyName }; Descending = $sortDescending })
    }
    $articleGrid = Get-Control 'ArticleGrid'
    $articleGrid.ItemsSource = $script:visibleArticles
    foreach ($column in @($articleGrid.Columns)) {
      if ([string]$column.SortMemberPath -eq $script:articleSortProperty) {
        $direction = if ($script:articleSortAscending) { [System.ComponentModel.ListSortDirection]::Ascending } else { [System.ComponentModel.ListSortDirection]::Descending }
        $column.SortDirection = $direction
      } else {
        $column.SortDirection = $null
      }
    }
    (Get-Control 'StatusText').Text = "$($script:visibleArticles.Count) 篇文章"
    if ($script:visibleArticles.Count -gt 0) { (Get-Control 'ArticleGrid').SelectedIndex = 0 } else { Clear-ArticleEditor }
  }

  function Clear-ArticleEditor {
    $script:selectedArticle = $null; foreach ($name in @('TitleBox','CategoryBox','SectionBox','TagsBox','DateBox','ReadingTimeBox','ExcerptBox','FontBox','ColorBox')) { Set-ControlText (Get-Control $name) '' }; (Get-Control 'ArticleFileText').Text = '尚未选择文章'; (Get-Control 'DeleteArticleButton').IsEnabled = $false
  }

  function Load-SelectedArticle {
    $article = (Get-Control 'ArticleGrid').SelectedItem; if ($null -eq $article) { Clear-ArticleEditor; return }; $script:selectedArticle = $article
    Set-ControlText (Get-Control 'TitleBox') $article.title; Set-ControlText (Get-Control 'CategoryBox') $article.category; Set-ControlText (Get-Control 'SectionBox') $article.section; Set-ControlText (Get-Control 'TagsBox') (@($article.tags) -join ', '); Set-ControlText (Get-Control 'DateBox') $article.date; Set-ControlText (Get-Control 'ReadingTimeBox') $article.readingTime; Set-ControlText (Get-Control 'ExcerptBox') $article.excerpt; Set-ControlText (Get-Control 'FontBox') $article.titleFont; Set-ControlText (Get-Control 'ColorBox') $article.titleColor; (Get-Control 'ArticleFileText').Text = "文件：articles\$($article.file)"; (Get-Control 'DeleteArticleButton').IsEnabled = $true
  }

  function Save-SelectedArticle {
    if ($null -eq $script:selectedArticle) { Show-Error '请先选择一篇文章。'; return }; $title = (Get-Control 'TitleBox').Text.Trim(); $color = (Get-Control 'ColorBox').Text.Trim()
    if ([string]::IsNullOrWhiteSpace($title)) { Show-Error '标题不能为空。'; return }; if ($color -and -not (Test-ProjectColor $color)) { Show-Error '目录标题颜色格式无效。'; return }
    $updated = $script:selectedArticle.PSObject.Copy(); Set-ArticlePropertyValue $updated 'title' $title; Set-ArticlePropertyValue $updated 'category' (Get-Control 'CategoryBox').Text.Trim(); Set-ArticlePropertyValue $updated 'section' (Get-Control 'SectionBox').Text.Trim(); Set-ArticlePropertyValue $updated 'tags' @((Get-Control 'TagsBox').Text -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }); Set-ArticlePropertyValue $updated 'date' (Get-Control 'DateBox').Text.Trim(); Set-ArticlePropertyValue $updated 'readingTime' (Get-Control 'ReadingTimeBox').Text.Trim(); Set-ArticlePropertyValue $updated 'excerpt' (Get-Control 'ExcerptBox').Text.Trim(); Set-ArticlePropertyValue $updated 'titleFont' (Get-Control 'FontBox').Text.Trim(); Set-ArticlePropertyValue $updated 'titleColor' $color
    $all = @(Get-Articles $root); for ($i = 0; $i -lt $all.Count; $i++) { if ($all[$i].slug -eq $script:selectedArticle.slug) { $all[$i] = $updated } }; Save-Articles $all $root; Write-ProjectLog "WPF GUI 保存文章：$($updated.slug)" 'INFO' $root; Refresh-Articles; Show-Message '文章属性已保存。'
  }

  function Delete-SelectedArticleFromGui {
    if ($null -eq $script:selectedArticle) { Show-Error '请先选择一篇文章。'; return }
    $all = @(Get-Articles $root)
    if ($all.Count -le 1) { Show-Error '项目中至少需要保留一篇文章，无法删除最后一篇。'; return }
    $article = $script:selectedArticle
    $dialog = New-Object Windows.Window; $dialog.Title = '删除文章'; $dialog.Owner = $script:window; $dialog.Width = 620; $dialog.Height = 330; $dialog.ResizeMode = 'NoResize'; $dialog.WindowStartupLocation = 'CenterOwner'; $dialog.Background = $script:window.Resources['WindowBackground']
    $panel = New-Object Windows.Controls.StackPanel; $panel.Margin = New-Object Windows.Thickness(28)
    $heading = New-Object Windows.Controls.TextBlock; $heading.Text = '此操作不可恢复'; $heading.FontSize = 20; $heading.FontWeight = 'SemiBold'; $heading.Foreground = [Windows.Media.Brushes]::Firebrick; $panel.Children.Add($heading) | Out-Null
    $warning = New-Object Windows.Controls.TextBlock; $warning.Text = '删除后将同时移除文章索引、Markdown 正文和时间轴中的对应条目。Obsidian 源文件不会被删除，下次导入仍可能重新创建此文章。'; $warning.TextWrapping = 'Wrap'; $warning.Margin = New-Object Windows.Thickness(0,14,0,14); $warning.Foreground = $script:window.Resources['TextPrimary']; $panel.Children.Add($warning) | Out-Null
    $details = New-Object Windows.Controls.TextBlock; $details.Text = "标题：$($article.title)`n文件：articles\$($article.file)"; $details.TextWrapping = 'Wrap'; $details.Margin = New-Object Windows.Thickness(0,0,0,18); $details.Foreground = $script:window.Resources['TextSecondary']; $panel.Children.Add($details) | Out-Null
    $confirm = New-Object Windows.Controls.CheckBox; $confirm.Content = '确认删除'; $confirm.Foreground = $script:window.Resources['TextPrimary']; $panel.Children.Add($confirm) | Out-Null
    $buttons = New-Object Windows.Controls.StackPanel; $buttons.Orientation = 'Horizontal'; $buttons.HorizontalAlignment = 'Right'; $buttons.Margin = New-Object Windows.Thickness(0,22,0,0)
    $cancel = New-Object Windows.Controls.Button; $cancel.Content = '取消'; $cancel.Add_Click({ $dialog.DialogResult = $false })
    $delete = New-Object Windows.Controls.Button; $delete.Content = '删除文章'; $delete.IsEnabled = $false; $delete.Background = [Windows.Media.Brushes]::Firebrick; $delete.Foreground = [Windows.Media.Brushes]::White; $delete.Add_Click({ $dialog.DialogResult = $true })
    $confirm.Add_Checked({ $delete.IsEnabled = $true }); $confirm.Add_Unchecked({ $delete.IsEnabled = $false })
    $buttons.Children.Add($cancel) | Out-Null; $buttons.Children.Add($delete) | Out-Null; $panel.Children.Add($buttons) | Out-Null; $dialog.Content = $panel
    if (-not $dialog.ShowDialog()) { return }
    try {
      $result = Remove-ProjectArticle -Root $root -Slug $article.slug
      Write-ProjectLog "WPF GUI 删除文章：$($result.file)，清除时间轴条目 $($result.removedTimelineEntries) 条" 'INFO' $root
      Refresh-Articles
      Show-Message "已删除文章：$($result.title)"
    } catch {
      Write-ProjectLog ("WPF GUI 删除文章失败：{0}`n{1}" -f $_.Exception.Message, $_.ScriptStackTrace) 'ERROR' $root
      Show-Error $_.Exception.Message '删除失败'
    }
  }

  function New-ArticleFromGui {
    $dialog = New-Object Windows.Window; $dialog.Title = '新建文章'; $dialog.Owner = $script:window; $dialog.Width = 520; $dialog.Height = 450; $dialog.ResizeMode = 'NoResize'; $dialog.WindowStartupLocation = 'CenterOwner'; $dialog.Background = $script:window.Resources['WindowBackground']; $panel = New-Object Windows.Controls.StackPanel; $panel.Margin = New-Object Windows.Thickness(28); $fields = @{}
    foreach ($definition in @(@('Slug','标识'),@('Title','标题'),@('Category','类别'),@('Excerpt','摘要'),@('Tags','标签（逗号分隔）'))) { $label = New-Object Windows.Controls.TextBlock; $label.Text = $definition[1]; $label.Foreground = $script:window.Resources['TextSecondary']; $panel.Children.Add($label) | Out-Null; $box = New-Object Windows.Controls.TextBox; $box.Margin = New-Object Windows.Thickness(0,4,0,12); $box.Padding = New-Object Windows.Thickness(9,6,9,6); $panel.Children.Add($box) | Out-Null; $fields[$definition[0]] = $box }
    $fields.Tags.Text = @($script:config.newArticle.tags) -join ', '; $buttons = New-Object Windows.Controls.StackPanel; $buttons.Orientation = 'Horizontal'; $buttons.HorizontalAlignment = 'Right'; $cancel = New-Object Windows.Controls.Button; $cancel.Content = '取消'; $cancel.Add_Click({ $dialog.DialogResult = $false }); $create = New-Object Windows.Controls.Button; $create.Content = '创建文章'; $create.Background = $script:window.Resources['AccentBrush']; $create.Foreground = [Windows.Media.Brushes]::White
    $create.Add_Click({ try { foreach ($key in @('Slug','Title','Category','Excerpt')) { if ([string]::IsNullOrWhiteSpace($fields[$key].Text)) { throw "$key 不能为空。" } }; $tags = @($fields.Tags.Text -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }); & (Join-Path $root 'New-Article.ps1') -Slug $fields.Slug.Text.Trim() -Title $fields.Title.Text.Trim() -Category $fields.Category.Text.Trim() -Excerpt $fields.Excerpt.Text.Trim() -Tags $tags -Date $script:config.newArticle.date -ReadingTime $script:config.newArticle.readingTime | Out-Null; $dialog.DialogResult = $true } catch { Show-Error $_.Exception.Message '创建失败' } })
    $buttons.Children.Add($cancel) | Out-Null; $buttons.Children.Add($create) | Out-Null; $panel.Children.Add($buttons) | Out-Null; $dialog.Content = $panel; if ($dialog.ShowDialog()) { Refresh-Articles; (Get-Control 'StatusText').Text = '文章已创建' }
  }

  function Show-TextDialog([string]$Title, [string]$Text, [string]$ConfirmLabel = '关闭') {
    $dialog = New-Object Windows.Window; $dialog.Title = $Title; $dialog.Owner = $script:window; $dialog.Width = 760; $dialog.Height = 560; $dialog.WindowStartupLocation = 'CenterOwner'; $dialog.Background = $script:window.Resources['WindowBackground']; $panel = New-Object Windows.Controls.DockPanel; $panel.Margin = New-Object Windows.Thickness(22); $box = New-Object Windows.Controls.TextBox; $box.Text = $Text; $box.IsReadOnly = $true; $box.TextWrapping = 'Wrap'; $box.AcceptsReturn = $true; $box.VerticalScrollBarVisibility = 'Auto'; $box.HorizontalScrollBarVisibility = 'Auto'; $box.Margin = New-Object Windows.Thickness(0,0,0,14); [Windows.Controls.DockPanel]::SetDock($box,'Top'); $panel.Children.Add($box) | Out-Null; $button = New-Object Windows.Controls.Button; $button.Content = $ConfirmLabel; $button.HorizontalAlignment = 'Right'; $button.Add_Click({ $dialog.DialogResult = $true }); $panel.Children.Add($button) | Out-Null; $dialog.Content = $panel; return $dialog.ShowDialog()
  }

  function Get-AuthorUrl { $url = [string]$script:info.authorUrl; if ([string]::IsNullOrWhiteSpace($url)) { $url = 'https://tianyimc.com' }; return $url }
  function Get-LicenseName { $name = [string]$script:info.licenseName; if ([string]::IsNullOrWhiteSpace($name)) { $name = [string]$script:info.license }; if ([string]::IsNullOrWhiteSpace($name)) { $name = 'MIT 许可证' }; return $name }
  function New-AuthorLink {
    $link = New-Object Windows.Documents.Hyperlink
    $link.NavigateUri = [Uri](Get-AuthorUrl)
    $link.Foreground = $script:window.Resources['AccentBrush']
    $link.Inlines.Add((New-Object Windows.Documents.Run -ArgumentList ([string]$script:info.author)))
    $link.Add_RequestNavigate({ param($sender, $eventArgs) try { Start-Process $eventArgs.Uri.AbsoluteUri } catch { }; $eventArgs.Handled = $true })
    return $link
  }

  function Show-AboutDialog {
    $info = $script:info
    $dialog = New-Object Windows.Window; $dialog.Title = '关于 ProjectMe'; $dialog.Owner = $script:window; $dialog.Width = 760; $dialog.Height = 560; $dialog.WindowStartupLocation = 'CenterOwner'; $dialog.Background = $script:window.Resources['WindowBackground']
    $panel = New-Object Windows.Controls.DockPanel; $panel.Margin = New-Object Windows.Thickness(22)
    $button = New-Object Windows.Controls.Button; $button.Content = '关闭'; $button.HorizontalAlignment = 'Right'; $button.Margin = New-Object Windows.Thickness(0,14,0,0); $button.Add_Click({ $dialog.DialogResult = $true }); [Windows.Controls.DockPanel]::SetDock($button,'Bottom'); $panel.Children.Add($button) | Out-Null
    $paragraph = New-Object Windows.Documents.Paragraph
    $paragraph.Inlines.Add((New-Object Windows.Documents.Run -ArgumentList ([string]$info.description)))
    $paragraph.Inlines.Add((New-Object Windows.Documents.LineBreak))
    $paragraph.Inlines.Add((New-Object Windows.Documents.Run -ArgumentList "版本：$(Get-DisplayVersion $info)`n作者："))
    $paragraph.Inlines.Add((New-AuthorLink))
    $paragraph.Inlines.Add((New-Object Windows.Documents.Run -ArgumentList "`n$($info.copyright)`n`n核心基于 HTML + CSS + JavaScript，无后端依赖；命令行管理器基于 PowerShell；GUI 管理器基于 WPF + PowerShell。`n许可证：$(Get-LicenseName)`n作者主页：$(Get-AuthorUrl)"))
    $document = New-Object Windows.Documents.FlowDocument; $document.Blocks.Add($paragraph); $document.Foreground = $script:window.Resources['TextPrimary']; $document.FontSize = 14
    $viewer = New-Object Windows.Controls.FlowDocumentScrollViewer; $viewer.Document = $document; $viewer.VerticalScrollBarVisibility = 'Auto'; $viewer.Background = $script:window.Resources['SurfaceBackground']; $viewer.Padding = New-Object Windows.Thickness(18)
    $panel.Children.Add($viewer) | Out-Null
    $dialog.Content = $panel
    return $dialog.ShowDialog()
  }

  function Ensure-TimelinePriorities([object[]]$Entries) {
    foreach ($group in @($Entries | Where-Object { -not $_.disabled -and $_.date } | Group-Object date)) { $ordered = @($group.Group | Sort-Object @{Expression={ if ($null -ne $_.priority) { [int]$_.priority } else { 999999 } }}, slug); for ($i = 0; $i -lt $ordered.Count; $i++) { if ($null -eq $ordered[$i].PSObject.Properties['priority']) { $ordered[$i] | Add-Member -NotePropertyName priority -NotePropertyValue ($i + 1) -Force } else { $ordered[$i].priority = $i + 1 } } }
  }

  function Refresh-Timeline {
    $timeline = Get-Timeline $root; $script:timelineEntries = @($timeline.entries); Ensure-TimelinePriorities $script:timelineEntries; $query = (Get-Control 'TimelineSearchBox').Text.Trim(); $script:visibleTimelineEntries = @($script:timelineEntries | Where-Object { -not $query -or @($_.title,$_.slug,$_.description) -join ' ' -like "*$query*" } | ForEach-Object { $copy = $_.PSObject.Copy(); $stateText = '启用'; if ($copy.disabled) { $stateText = '已禁用' }; $copy | Add-Member -NotePropertyName StateText -NotePropertyValue $stateText -Force; $copy }); (Get-Control 'TimelineGrid').ItemsSource = $script:visibleTimelineEntries; if ($script:visibleTimelineEntries.Count -gt 0) { (Get-Control 'TimelineGrid').SelectedIndex = 0 } else { Clear-TimelineEditor }; (Get-Control 'StatusText').Text = "$($script:visibleTimelineEntries.Count) 条时间轴记录"
  }

  function Clear-TimelineEditor { $script:selectedTimelineEntry = $null; (Get-Control 'TimelineArticleText').Text = '尚未选择时间轴文章'; Set-ControlText (Get-Control 'TimelineDateBox') ''; Set-ControlText (Get-Control 'TimelinePriorityBox') ''; Set-ControlText (Get-Control 'TimelineDescriptionBox') ''; (Get-Control 'TimelineEnabledBox').IsChecked = $false }
  function Load-TimelineEntry { $entry = (Get-Control 'TimelineGrid').SelectedItem; if ($null -eq $entry) { Clear-TimelineEditor; return }; $script:selectedTimelineEntry = $script:timelineEntries | Where-Object { $_.slug -eq $entry.slug } | Select-Object -First 1; (Get-Control 'TimelineArticleText').Text = "$($script:selectedTimelineEntry.title)  ·  $($script:selectedTimelineEntry.slug)"; Set-ControlText (Get-Control 'TimelineDateBox') $script:selectedTimelineEntry.date; Set-ControlText (Get-Control 'TimelinePriorityBox') $script:selectedTimelineEntry.priority; Set-ControlText (Get-Control 'TimelineDescriptionBox') $script:selectedTimelineEntry.description; (Get-Control 'TimelineEnabledBox').IsChecked = -not [bool]$script:selectedTimelineEntry.disabled }

  function Show-ArticlePicker {
    $dialog = New-Object Windows.Window; $dialog.Title = '选择时间轴文章'; $dialog.Owner = $script:window; $dialog.Width = 720; $dialog.Height = 620; $dialog.WindowStartupLocation = 'CenterOwner'; $dialog.Background = $script:window.Resources['WindowBackground']; $panel = New-Object Windows.Controls.DockPanel; $panel.Margin = New-Object Windows.Thickness(20); $search = New-Object Windows.Controls.TextBox; $search.ToolTip = '搜索文章'; $search.Margin = New-Object Windows.Thickness(0,0,0,12); [Windows.Controls.DockPanel]::SetDock($search,'Top'); $panel.Children.Add($search) | Out-Null; $list = New-Object Windows.Controls.ListBox; $list.DisplayMemberPath = 'title'; $panel.Children.Add($list) | Out-Null; $buttons = New-Object Windows.Controls.StackPanel; $buttons.Orientation = 'Horizontal'; $buttons.HorizontalAlignment = 'Right'; [Windows.Controls.DockPanel]::SetDock($buttons,'Bottom'); $cancel = New-Object Windows.Controls.Button; $cancel.Content = '取消'; $cancel.Add_Click({ $dialog.DialogResult = $false }); $ok = New-Object Windows.Controls.Button; $ok.Content = '选择'; $ok.Background = $script:window.Resources['AccentBrush']; $ok.Foreground = [Windows.Media.Brushes]::White; $ok.Add_Click({ if ($null -eq $list.SelectedItem) { Show-Error '请选择一篇文章。' '选择文章'; return }; $dialog.DialogResult = $true }); $buttons.Children.Add($cancel) | Out-Null; $buttons.Children.Add($ok) | Out-Null; $panel.Children.Add($buttons) | Out-Null; $dialog.Content = $panel
    $refresh = { $q = $search.Text.Trim(); $list.ItemsSource = @($script:articles | Where-Object { -not $q -or $_.title -like "*$q*" -or $_.slug -like "*$q*" }) }; $search.Add_TextChanged($refresh); & $refresh; if ($dialog.ShowDialog()) { return $list.SelectedItem }; return $null
  }

  function Select-TimelineArticle { $article = Show-ArticlePicker; if ($null -eq $article) { return }; $existing = $script:timelineEntries | Where-Object { $_.slug -eq $article.slug } | Select-Object -First 1; if ($existing) { $script:selectedTimelineEntry = $existing } else { $script:selectedTimelineEntry = [pscustomobject]@{ slug = $article.slug; title = $article.title; date = ''; description = ''; disabled = $false; priority = 1 } }; (Get-Control 'TimelineArticleText').Text = "$($article.title)  ·  $($article.slug)"; $defaultDate = ''; if ($article.date -match '^\d{8}$') { $defaultDate = $article.date }; $defaultPriority = 1; if ($script:selectedTimelineEntry.priority) { $defaultPriority = $script:selectedTimelineEntry.priority }; if (-not (Get-Control 'TimelineDateBox').Text) { Set-ControlText (Get-Control 'TimelineDateBox') $defaultDate }; Set-ControlText (Get-Control 'TimelinePriorityBox') $defaultPriority; Set-ControlText (Get-Control 'TimelineDescriptionBox') $script:selectedTimelineEntry.description; (Get-Control 'TimelineEnabledBox').IsChecked = $true }

  function Save-TimelineEntryFromGui {
    if ($null -eq $script:selectedTimelineEntry) { Show-Error '请先选择或选入一篇文章。'; return }; $date = (Get-Control 'TimelineDateBox').Text.Trim(); $priority = 0; if ($date -notmatch '^\d{8}$') { Show-Error '日期必须是有效的 YYYYMMDD。'; return }; try { [datetime]::ParseExact($date,'yyyyMMdd',$null) | Out-Null } catch { Show-Error '日期必须是有效的 YYYYMMDD。'; return }; if (-not [int]::TryParse((Get-Control 'TimelinePriorityBox').Text,[ref]$priority) -or $priority -lt 1) { Show-Error '优先级必须是大于 0 的整数。'; return }
    $timeline = Get-Timeline $root; $entries = @($timeline.entries); Ensure-TimelinePriorities $entries; $entry = $entries | Where-Object { $_.slug -eq $script:selectedTimelineEntry.slug } | Select-Object -First 1; if ($null -eq $entry) { $entry = [pscustomobject]@{ slug = $script:selectedTimelineEntry.slug; title = $script:selectedTimelineEntry.title; date = $date; description = ''; disabled = $false; priority = 1 }; $entries += $entry }; $entry.date = $date; $entry.description = (Get-Control 'TimelineDescriptionBox').Text; $entry.disabled = -not [bool](Get-Control 'TimelineEnabledBox').IsChecked; if ($null -eq $entry.PSObject.Properties['priority']) { $entry | Add-Member -NotePropertyName priority -NotePropertyValue $priority -Force } else { $entry.priority = $priority }; $article = $script:articles | Where-Object { $_.slug -eq $entry.slug } | Select-Object -First 1; if ($article) { $entry.title = $article.title }
    Ensure-TimelinePriorities $entries; Save-Timeline ([pscustomobject]@{ entries = @($entries) }) $root; Write-ProjectLog "WPF GUI 保存时间轴：$($entry.slug)" 'INFO' $root; Refresh-Timeline; Show-Message '时间轴条目已保存。'
  }

  function Remove-TimelineEntryFromGui { if ($null -eq $script:selectedTimelineEntry) { Show-Error '请先选择一个时间轴条目。'; return }; $entry = $script:timelineEntries | Where-Object { $_.slug -eq $script:selectedTimelineEntry.slug } | Select-Object -First 1; if ($entry) { $entry.disabled = $true; Save-Timeline ([pscustomobject]@{ entries = @($script:timelineEntries) }) $root; Refresh-Timeline; Show-Message '时间轴条目已禁用。' } }

  function Run-ProjectCheck { try { $result = & (Join-Path $root 'Check-ProjectMe.ps1') 2>&1 | Out-String; Show-TextDialog '项目自检' $result '关闭' | Out-Null } catch { Show-Error $_.Exception.Message '项目自检失败' } }
  function Open-Log { $log = Join-Path $root 'logs\projectme-cli.log'; if (Test-Path $log) { Start-Process notepad.exe $log } else { Show-Message '目前还没有日志。' } }

  function Load-SnapshotsFromGui { $version = (Get-Control 'RollbackVersionBox').Text.Trim(); if (-not (Test-ProjectVersion $version)) { Show-Error '版本号格式必须是 X.X.X。'; return }; (Get-Control 'SnapshotGrid').ItemsSource = @(Get-VersionSnapshots -Root $root -Version $version); (Get-Control 'StatusText').Text = "已加载 v$version 快照" }
  function Rollback-VersionFromGui { $snapshot = (Get-Control 'SnapshotGrid').SelectedItem; if ($null -eq $snapshot) { Show-Error '请先加载并选择一个快照。'; return }; if ([System.Windows.MessageBox]::Show($script:window,"确认回滚到：$($snapshot.Name)？`n当前项目会先备份到 old\reseted\。",'回滚版本','YesNo','Warning') -ne 'Yes') { return }; try { $backup = Restore-ProjectSnapshot -Root $root -Snapshot $snapshot.FullName; Write-ProjectLog "WPF GUI 回滚成功：$($snapshot.FullName)；备份：$backup" 'INFO' $root; Show-Message "回滚完成。`n回滚前备份：$backup`n`n请关闭并重新启动 ProjectMe。" } catch { Write-ProjectLog "WPF GUI 回滚失败：$($_.Exception.Message)`n$($_.ScriptStackTrace)" 'ERROR' $root; Show-Error $_.Exception.Message '回滚失败' } }

  $xamlPath = Join-Path $root 'ProjectMe.Gui.xaml'; $xamlText = [IO.File]::ReadAllText($xamlPath,[Text.UTF8Encoding]::new($true)); $reader = New-Object Xml.XmlNodeReader ([xml]$xamlText); $script:window = [Windows.Markup.XamlReader]::Load($reader); Set-Theme; Set-Fonts
  $script:window.Title = "$($script:info.title) · $(Get-DisplayVersion $script:info)"; (Get-Control 'SidebarVersionText').Text = Get-DisplayVersion $script:info; (Get-Control 'HeaderSubtitleText').Text = "$($script:info.description) · Windows WPF 管理器"; (Get-Control 'PortBox').Text = [string]$script:config.serve.port; (Get-Control 'MaintenancePortBox').Text = [string]$script:config.serve.port; (Get-Control 'ServiceStatusText').Text = '预览未运行'; (Get-Control 'MaintenanceServiceText').Text = '预览未运行'; (Get-Control 'CurrentVersionText').Text = "当前版本：$(Get-DisplayVersion $script:info)"

  (Get-Control 'ArticlesNavButton').Add_Click({ Set-Page articles }); (Get-Control 'MaintenanceNavButton').Add_Click({ Set-Page maintenance }); (Get-Control 'TimelineNavButton').Add_Click({ Set-Page timeline }); (Get-Control 'AboutNavButton').Add_Click({ Show-AboutDialog })
  (Get-Control 'ArticleGrid').Add_Sorting({ param($sender, $eventArgs) $propertyName = [string]$eventArgs.Column.SortMemberPath; if (-not $propertyName) { $eventArgs.Handled = $true; return }; if ($script:articleSortProperty -ne $propertyName) { $script:articleSortProperty = $propertyName; $script:articleSortAscending = $true } elseif ($script:articleSortAscending) { $script:articleSortAscending = $false } else { $script:articleSortProperty = ''; $script:articleSortAscending = $true }; $eventArgs.Handled = $true; Refresh-Articles }); (Get-Control 'SearchBox').Add_TextChanged({ Refresh-Articles }); (Get-Control 'ArticleGrid').Add_SelectionChanged({ Load-SelectedArticle }); (Get-Control 'RefreshButton').Add_Click({ Refresh-Articles }); (Get-Control 'NewArticleButton').Add_Click({ New-ArticleFromGui }); (Get-Control 'SaveArticleButton').Add_Click({ try { Save-SelectedArticle } catch { Show-Error $_.Exception.Message } }); (Get-Control 'OpenArticleButton').Add_Click({ if ($script:selectedArticle) { $target = if ($script:selectedArticle.path) { Join-Path $root ([string]$script:selectedArticle.path) } else { Join-Path $root "articles\$($script:selectedArticle.file)" }; Start-Process notepad.exe $target } }); (Get-Control 'DeleteArticleButton').Add_Click({ Delete-SelectedArticleFromGui })
  (Get-Control 'StartPreviewButton').Add_Click({ try { Start-Preview } catch { Show-Error $_.Exception.Message '启动预览失败' } }); (Get-Control 'StopPreviewButton').Add_Click({ Stop-Preview }); (Get-Control 'OpenSiteButton').Add_Click({ Start-Process "http://localhost:$((Get-Control 'PortBox').Text)/" }); (Get-Control 'CheckButton').Add_Click({ Run-ProjectCheck }); (Get-Control 'LogButton').Add_Click({ Open-Log })
  (Get-Control 'MaintenanceStartButton').Add_Click({ try { Start-Preview (Get-Control 'MaintenancePortBox') } catch { Show-Error $_.Exception.Message '启动预览失败' } }); (Get-Control 'MaintenanceStopButton').Add_Click({ Stop-Preview }); (Get-Control 'MaintenanceForceStopButton').Add_Click({ if ([System.Windows.MessageBox]::Show($script:window,'会强制停止占用端口号4173、4174的进程','强停所有预览','YesNo','Warning') -eq 'Yes') { Stop-Preview; Show-Message '已强制停止 4173、4174 端口上的预览进程。' '强停所有预览' } }); (Get-Control 'MaintenanceOpenSiteButton').Add_Click({ Start-Process "http://localhost:$((Get-Control 'MaintenancePortBox').Text)/" }); (Get-Control 'MaintenanceCheckButton').Add_Click({ Run-ProjectCheck }); (Get-Control 'MaintenanceLogButton').Add_Click({ Open-Log }); (Get-Control 'LoadSnapshotsButton').Add_Click({ Load-SnapshotsFromGui }); (Get-Control 'RollbackButton').Add_Click({ Rollback-VersionFromGui })
  (Get-Control 'TimelineSearchBox').Add_TextChanged({ Refresh-Timeline }); (Get-Control 'TimelineRefreshButton').Add_Click({ Refresh-Timeline }); (Get-Control 'TimelineGrid').Add_SelectionChanged({ Load-TimelineEntry }); (Get-Control 'TimelineSelectButton').Add_Click({ Select-TimelineArticle }); (Get-Control 'TimelineChooseArticleButton').Add_Click({ Select-TimelineArticle }); (Get-Control 'TimelineSaveButton').Add_Click({ try { Save-TimelineEntryFromGui } catch { Show-Error $_.Exception.Message } }); (Get-Control 'TimelineRemoveButton').Add_Click({ Remove-TimelineEntryFromGui })
  # --- 插件宿主 ---
  # 插件在 plugins\<插件名>\plugin.json 中声明自己占用的 GUI 控件；这些控件在 XAML 中默认隐藏，
  # 只有插件启用且初始化成功时才显示，因此插件被禁用或整个文件夹被删除时入口都不会出现。
  $script:plugins = @(Get-ProjectPlugins -Root $root -Config $script:config | Where-Object { $_.Enabled })
  $script:claimedControls = @{}
  foreach ($plugin in $script:plugins) {
    $guiFunction = ''
    if ($null -ne $plugin.Manifest.PSObject.Properties['gui'] -and $null -ne $plugin.Manifest.gui) { $guiFunction = [string]$plugin.Manifest.gui.function }
    if ([string]::IsNullOrWhiteSpace($guiFunction)) { Write-ProjectLog "已启用插件：$($plugin.Id)（无 GUI 入口）" 'INFO' $root; continue }
    try {
      . ($plugin.EntryPath)
      & $guiFunction
      foreach ($controlName in @($plugin.Manifest.gui.controls)) {
        $name = [string]$controlName
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        if ($script:claimedControls.ContainsKey($name)) { Write-ProjectLog "插件 $($plugin.Id) 与 $($script:claimedControls[$name]) 都声明了控件 $name，以 $($plugin.Id) 为准。" 'WARN' $root }
        $script:claimedControls[$name] = $plugin.Id
        $control = $script:window.FindName($name)
        if ($null -ne $control) { $control.Visibility = 'Visible' }
        else { Write-ProjectLog "插件 $($plugin.Id) 声明的控件不存在：$name" 'WARN' $root }
      }
      Write-ProjectLog "已启用插件：$($plugin.Id)" 'INFO' $root
    } catch {
      Write-ProjectLog "插件 $($plugin.Id) 初始化失败，入口保持隐藏：$($_.Exception.Message)`n$($_.ScriptStackTrace)" 'ERROR' $root
    }
  }

  $script:window.Add_Closed({ Stop-Preview }); (Get-Control 'AuthorLink').Add_RequestNavigate({ param($sender, $eventArgs) try { Start-Process $eventArgs.Uri.AbsoluteUri } catch { }; $eventArgs.Handled = $true }); Refresh-Articles; Set-Page articles; [void]$script:window.ShowDialog()
} catch {
  $message = "WPF GUI 启动失败：$($_.Exception.Message)"; try { Write-ProjectLog "$message`n$($_.ScriptStackTrace)" 'ERROR' $root } catch { }; try { [System.Windows.MessageBox]::Show("$message`n`n日志：$root\logs\projectme-cli.log",'ProjectMe WPF 启动失败','OK','Error') | Out-Null } catch { }; Write-Host "`n$message" -ForegroundColor Red; Write-Host "详细信息已写入：$root\logs\projectme-cli.log"; Read-Host '按 Enter 关闭此窗口'; exit 1
}
