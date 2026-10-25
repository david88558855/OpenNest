# 本地/手动打包入口：调用 CI 同一个脚本，仅产出便携版 zip（安装程序已永久移除）。
param(
    [string]$Flutter = "flutter",
    [string]$Version = ""
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $root

if (-not (Test-Path "windows\runner\main.cpp")) {
    Write-Host "==> 未发现 windows/ 工程，先执行 tool/bootstrap_windows.ps1" -ForegroundColor Yellow
    & "$root\tool\bootstrap_windows.ps1" -Flutter $Flutter
}

& "$root\tool\ci_build_windows.ps1" -Flutter $Flutter -Version $Version
Get-ChildItem "$root\dist" | Format-Table Name, Length
