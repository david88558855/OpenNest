# 引擎冒烟：确认随包二进制能在本机起服务、响应健康检查并完成登录。
# 只在 CI 的 Windows job 里跑；不依赖 Flutter。
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$exe = Join-Path $root "assets\bin\windows\openlist.exe"
if (-not (Test-Path $exe)) { throw "缺少引擎：$exe（先执行 tool/fetch_openlist.sh windows）" }

$tmp = Join-Path $env:TEMP ("opennest-smoke-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

# 固定端口足够（CI 机器干净）；本地跑若冲突，改这里即可。
$port = 28917
$password = "smoke-password-1234567890"
$config = @{
    force      = $true
    scheme     = @{ address = "127.0.0.1"; http_port = $port; https_port = -1 }
    database   = @{ type = "sqlite3"; db_file = "$tmp\data.db"; table_prefix = "x_" }
    jwt_secret = "smoke-secret-value"
    token_expires_in = 48
    temp_dir   = "$tmp\temp"
    s3         = @{ enable = $false }
    ftp        = @{ enable = $false }
    sftp       = @{ enable = $false }
}
Set-Content -Path "$tmp\config.json" -Value ($config | ConvertTo-Json -Depth 6) -Encoding utf8

$env:OPENLIST_ADMIN_PASSWORD = $password
$proc = Start-Process -FilePath $exe `
    -ArgumentList @("--data", $tmp, "--config", "$tmp\config.json", "server") `
    -PassThru -NoNewWindow `
    -RedirectStandardOutput "$tmp\out.log" -RedirectStandardError "$tmp\err.log"

$ok = $false
try {
    for ($i = 0; $i -lt 80; $i++) {
        Start-Sleep -Milliseconds 500
        if ($proc.HasExited) { break }
        try {
            $res = Invoke-WebRequest -Uri "http://127.0.0.1:$port/ping" -TimeoutSec 2 -UseBasicParsing
            if ($res.Content -match "pong") { $ok = $true; break }
        } catch { }
    }
    if (-not $ok) {
        Write-Host "---- stderr ----"
        Get-Content "$tmp\err.log" -ErrorAction SilentlyContinue | Select-Object -Last 40
        Write-Host "---- stdout ----"
        Get-Content "$tmp\out.log" -ErrorAction SilentlyContinue | Select-Object -Last 40
        throw "引擎未在 40 秒内响应健康检查"
    }

    $body = @{ username = "admin"; password = $password } | ConvertTo-Json
    $login = Invoke-RestMethod -Uri "http://127.0.0.1:$port/api/auth/login" `
        -Method Post -Body $body -ContentType "application/json" -TimeoutSec 15
    if (-not $login.data.token) { throw "登录未返回令牌：$($login | ConvertTo-Json -Depth 4)" }

    $drivers = Invoke-RestMethod -Uri "http://127.0.0.1:$port/api/admin/driver/names" `
        -Headers @{ Authorization = $login.data.token } -TimeoutSec 15
    $count = @($drivers.data).Count
    if ($count -lt 50) { throw "驱动数量异常：$count" }

    Write-Host "OK: 引擎冒烟通过（ping + 登录 + 驱动 $count 个）"
}
finally {
    if (-not $proc.HasExited) { $proc.Kill() }
    Remove-Item Env:\OPENLIST_ADMIN_PASSWORD -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
