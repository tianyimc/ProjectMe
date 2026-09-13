$ErrorActionPreference = 'Stop'
$root = Join-Path ([IO.Path]::GetTempPath()) ("projectme-timeline-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $root 'articles') -Force | Out-Null
try {
  @'
[
  {"slug":"alpha","title":"Alpha","date":"","category":"Test","tags":["test"],"readingTime":"1","excerpt":"Alpha","file":"alpha.md"},
  {"slug":"beta","title":"Beta","date":"20230203","category":"Test","tags":["test"],"readingTime":"1","excerpt":"Beta","file":"beta.md"}
]
'@ | Set-Content -LiteralPath (Join-Path $root 'articles.json') -Encoding UTF8
  'Alpha' | Set-Content -LiteralPath (Join-Path $root 'articles\alpha.md') -Encoding UTF8
  'Beta' | Set-Content -LiteralPath (Join-Path $root 'articles\beta.md') -Encoding UTF8
  '{"entries":[]}' | Set-Content -LiteralPath (Join-Path $root 'timeline.json') -Encoding UTF8
  Copy-Item (Join-Path $PSScriptRoot 'Timeline.ps1') (Join-Path $root 'Timeline.ps1')
  Copy-Item (Join-Path $PSScriptRoot 'ProjectMe.Common.ps1') (Join-Path $root 'ProjectMe.Common.ps1')
  Copy-Item (Join-Path $PSScriptRoot 'Check-ProjectMe.ps1') (Join-Path $root 'Check-ProjectMe.ps1')

  $timeline = Join-Path $root 'Timeline.ps1'
  & powershell -NoProfile -ExecutionPolicy Bypass -File $timeline -Root $root -Action select -Slug alpha -Date '20240102' -Description 'origin'
  & powershell -NoProfile -ExecutionPolicy Bypass -File $timeline -Root $root -Action edit -Slug alpha -Date '20240103' -Description 'revision'
  & powershell -NoProfile -ExecutionPolicy Bypass -File $timeline -Root $root -Action remove -Slug alpha
  & powershell -NoProfile -ExecutionPolicy Bypass -File $timeline -Root $root -Action select -Slug alpha -Date '20240104' -Description 'restored'
  @('2', 'second') | powershell -NoProfile -ExecutionPolicy Bypass -File $timeline -Root $root -Action select -Slug beta -Query beta -Date '20240104'
  @('1', 'edited after same day') | powershell -NoProfile -ExecutionPolicy Bypass -File $timeline -Root $root -Action edit -Slug alpha -Date '20240104'

  $data = Get-Content -Raw -LiteralPath (Join-Path $root 'timeline.json') | ConvertFrom-Json
  $entry = @($data.entries | Where-Object slug -eq 'alpha')
  if ($entry.Count -ne 1 -or $entry[0].disabled -or $entry[0].date -ne '20240104') { throw 'Timeline select/edit/remove regression failed.' }
  $beta = @($data.entries | Where-Object slug -eq 'beta')
  if ($beta.Count -ne 1 -or $beta[0].priority -ne 3 -or $beta[0].description -ne 'second') { throw 'Same-day priority regression failed.' }
  if ($entry[0].priority -ne 1 -or $entry[0].description -ne 'edited after same day') { throw 'Interactive same-day edit regression failed.' }
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'Check-ProjectMe.ps1') | Out-Host
  Write-Output 'Timeline regression test passed.'
} finally {
  if (Test-Path $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
