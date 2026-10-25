# 生成 Windows 平台工程（Flutter 官方模板），随后即可 flutter build windows。
# 平台目录由 Flutter 自身生成，避免手写 C++ runner 与当前 Flutter 版本不匹配。
param(
    [string]$Flutter = "flutter"
)
$ErrorActionPreference = "Stop"
Write-Host "==> 生成 windows/ 平台目录" -ForegroundColor Cyan
& $Flutter create --platforms=windows --org com.opennest --project-name opennest .
Write-Host "==> 恢复依赖" -ForegroundColor Cyan
& $Flutter pub get
Write-Host "完成。运行 flutter run -d windows 或 flutter build windows --release" -ForegroundColor Green
