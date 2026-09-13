param(
  [Parameter(Mandatory = $true)] [string]$Slug,
  [Parameter(Mandatory = $true)] [string]$Title,
  [Parameter(Mandatory = $true)] [string]$Category,
  [Parameter(Mandatory = $true)] [string]$Excerpt,
  [string[]]$Tags = @('随笔'),
  [string]$Date = (Get-Date -Format 'yyyy.MM.dd'),
  [string]$ReadingTime = '3 分钟阅读',
  [string]$Section = '',
  [string]$TitleFont = '',
  [string]$TitleColor = ''
)

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $root 'ProjectMe.Common.ps1')
$indexPath = Join-Path $root 'articles.json'
$articlesPath = Join-Path $root 'articles'
$markdownPath = Join-Path $articlesPath "$Slug.md"

if ($Slug -notmatch '^[a-z0-9-]+$') { throw 'Slug must use lowercase letters, numbers, and hyphens.' }
if (Test-Path $markdownPath) { throw "Article file already exists: $markdownPath" }
if (-not [string]::IsNullOrWhiteSpace($TitleColor) -and -not (Test-ProjectColor $TitleColor)) { throw 'TitleColor must be a valid CSS color.' }

$articles = @(Get-Articles $root)
if ($articles.slug -contains $Slug) { throw "Article slug already exists: $Slug" }

[System.IO.File]::WriteAllText($markdownPath, "# $Title`r`n`r`n在这里开始写下文章。`r`n", [System.Text.UTF8Encoding]::new($false))
$newArticle = [ordered]@{
  slug = $Slug; title = $Title; date = $Date; category = $Category
  tags = @($Tags); readingTime = $ReadingTime; excerpt = $Excerpt; file = "$Slug.md"
  section = $Section; titleFont = $TitleFont; titleColor = $TitleColor
}
$articles += [pscustomobject]$newArticle
Save-Articles $articles $root

Write-Output "Created: articles/$Slug.md"
Write-Output 'Updated: articles.json'
