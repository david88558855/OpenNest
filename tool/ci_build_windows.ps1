# Windows 便携版构建：只产出 zip，不生成任何安装程序。
# 运行环境：Windows + Visual Studio（Desktop development with C++）+ Flutter SDK。
param(
    [string]$Flutter = "flutter",
    [string]$Version = ""
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $root

if (-not $Version) {
    $pubspec = Get-Content -Raw -Path "pubspec.yaml"
    if ($pubspec -match '(?m)^version:[ \t]*([0-9]+[.][0-9]+[.][0-9]+)') {
        $Version = $Matches[1]
    } else {
        throw "无法从 pubspec.yaml 解析版本号"
    }
}

# windows/ 平台目录不入库：由 Flutter 官方模板在本机/CI 生成，避免与当前 SDK 版本错配。
if (-not (Test-Path "windows\runner\main.cpp")) {
    Write-Host "==> 未发现 windows/ 工程，用 Flutter 官方模板生成" -ForegroundColor Cyan
    & $Flutter create --platforms=windows --org com.opennest --project-name opennest .
    if ($LASTEXITCODE -ne 0) { throw "flutter create --platforms=windows 失败" }
}

# 程序图标与 Android 启动图标同源（assets/windows/app_icon.ico，由 tool/gen_app_icons.py 生成）
$iconSrc = "assets\windows\app_icon.ico"
if (Test-Path $iconSrc) {
    Copy-Item $iconSrc "windows\runner\resources\app_icon.ico" -Force
    Write-Host "==> 已应用程序图标（与 Android 启动图标一致）"
}

Write-Host "== OpenNest $Version · Windows x64 portable =="

& $Flutter config --no-analytics | Out-Null
& $Flutter --version
if ($LASTEXITCODE -ne 0) { throw "flutter --version 失败" }
& $Flutter pub get
if ($LASTEXITCODE -ne 0) { throw "flutter pub get 失败" }
& $Flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw "flutter build windows 失败" }

$bundle = "build\windows\x64\runner\Release"
if (-not (Test-Path $bundle)) { throw "构建产物不存在：$bundle" }

New-Item -ItemType Directory -Force -Path dist | Out-Null
$name = "OpenNest-$Version-windows-x64-portable"
$stage = Join-Path "dist" $name
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
Copy-Item -Recurse $bundle $stage
New-Item -ItemType Directory -Force -Path (Join-Path $stage "userdata") | Out-Null

# 内嵌引擎必须与主程序同目录：启动时按 <主程序目录>/openlist.exe 查找。
$engine = "assets\bin\windows\openlist.exe"
if (-not (Test-Path $engine)) {
    throw "缺少内嵌引擎：$engine（先执行 bash tool/fetch_openlist.sh windows）"
}
Copy-Item $engine (Join-Path $stage "openlist.exe") -Force
Write-Host "==> 已打入内嵌引擎 openlist.exe（$([math]::Round((Get-Item $engine).Length / 1MB, 1)) MB）"

$zip = Join-Path "dist" "$name.zip"
if (Test-Path $zip) { Remove-Item -Force $zip }
Compress-Archive -Path "$stage\*" -DestinationPath $zip -Force
Remove-Item -Recurse -Force $stage

$hash = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
"$hash  $name.zip" | Out-File -Encoding ascii "$zip.sha256"
Write-Host "OK: $zip ($((Get-Item $zip).Length) 字节)"
Write-Host "SHA256: $hash"
