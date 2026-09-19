@echo off
REM ProjectMe 下载阻止解除脚本（只解除，不撤销）
REM 首次下载后双击运行一次；Update-ProjectMe.ps1 与 Manage-Plugins.ps1 也会自动调用它。
setlocal
cd /d "%~dp0"
echo 正在解除本目录 PowerShell 脚本的「来自 Internet」阻止...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$f = @(Get-ChildItem -LiteralPath '%~dp0' -Filter *.ps1 -Recurse -File -ErrorAction SilentlyContinue); $f | Unblock-File -ErrorAction SilentlyContinue; Write-Host ('ProjectMe: 已解除 ' + $f.Count + ' 个 .ps1 文件的下载阻止'); exit 0"
pause
endlocal
exit /b 0
