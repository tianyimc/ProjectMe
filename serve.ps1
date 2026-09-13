param([int]$Port = 4173)

$root = (Split-Path -Parent $MyInvocation.MyCommand.Path)
$requestedPort = $Port
$listener = $null
$started = $false
$statePath = Join-Path $root '.projectme-serve.json'

$mimeTypes = @{
  '.html' = 'text/html; charset=utf-8'
  '.css' = 'text/css; charset=utf-8'
  '.js' = 'text/javascript; charset=utf-8'
  '.json' = 'application/json; charset=utf-8'
  '.md' = 'text/markdown; charset=utf-8'
}

function Send-Response($stream, [int]$status, [byte[]]$body, [string]$contentType) {
  $statusText = if ($status -eq 200) { 'OK' } else { 'Not Found' }
  $header = "HTTP/1.1 $status $statusText`r`nContent-Type: $contentType`r`nContent-Length: $($body.Length)`r`nConnection: close`r`n`r`n"
  $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($header)
  try {
    $stream.Write($headerBytes, 0, $headerBytes.Length)
    $stream.Write($body, 0, $body.Length)
    $stream.Flush()
  }
  catch {
    # Browsers can cancel requests while navigating or refreshing; this is not a server-fatal error.
  }
}

try {
  while (-not $started -and $Port -lt ($requestedPort + 20)) {
    try {
      $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
      $listener.Start()
      $started = $true
    }
    catch {
      $errorCode = if ($_.Exception.InnerException) { $_.Exception.InnerException.ErrorCode } else { $null }
      if ($errorCode -ne 10048) { throw }
      if ($listener) { $listener.Stop() }
      $listener = $null
      $Port++
    }
  }
  if (-not $started) { throw "No available port found between $requestedPort and $($requestedPort + 19)." }
  if ($Port -ne $requestedPort) { Write-Warning "Port $requestedPort is busy; using port $Port instead." }
  $previewState = @{ pid = $PID; port = [int]$Port; started = (Get-Date).ToString('o') } | ConvertTo-Json -Compress
  [System.IO.File]::WriteAllText($statePath, "$previewState`r`n", [System.Text.UTF8Encoding]::new($false))
  Write-Host "ProjectMe preview: http://localhost:$Port/"
  Write-Host '关闭此窗口即可停止服务。'
  while ($listener.Server.IsBound) {
    if (-not $listener.Pending()) { Start-Sleep -Milliseconds 100; continue }
    $client = $null
    $stream = $null
    try {
      $client = $listener.AcceptTcpClient()
      $stream = $client.GetStream()
      $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::ASCII)
      $requestLine = $reader.ReadLine()
      while ($reader.ReadLine()) { }
      $relativePath = if ($requestLine -match '^GET\s+([^\s?]+)') { [System.Uri]::UnescapeDataString($Matches[1].TrimStart('/')) } else { '' }
      if ([string]::IsNullOrWhiteSpace($relativePath)) { $relativePath = 'index.html' }
      $candidate = [System.IO.Path]::GetFullPath((Join-Path $root $relativePath))
      if (-not $candidate.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path $candidate -PathType Leaf)) {
        Send-Response $stream 404 ([System.Text.Encoding]::UTF8.GetBytes('Not found')) 'text/plain; charset=utf-8'
        continue
      }
      $extension = [System.IO.Path]::GetExtension($candidate).ToLowerInvariant()
      $contentType = if ($mimeTypes.ContainsKey($extension)) { $mimeTypes[$extension] } else { 'application/octet-stream' }
      Send-Response $stream 200 ([System.IO.File]::ReadAllBytes($candidate)) $contentType
    }
    catch {
      Write-Warning "处理客户端请求失败，服务器继续运行：$($_.Exception.Message)"
    }
    finally {
      if ($stream) { $stream.Dispose() }
      if ($client) { $client.Close() }
    }
  }
}
finally {
  if (Test-Path $statePath -PathType Leaf) {
    try {
      $currentState = Get-Content -Raw -Encoding UTF8 $statePath | ConvertFrom-Json
      if ([int]$currentState.pid -eq $PID) { Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue }
    } catch { }
  }
  if ($listener) { $listener.Stop() }
}
