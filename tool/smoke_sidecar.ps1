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

    # 存储源全链路：创建本地目录源 → 列根目录 → 删除。
    $headers = @{
        Authorization  = $login.data.token
        "Content-Type" = "application/json"
    }
    $storage = @{
        mount_path            = "/s_smoke001"
        order                 = 0
        driver                = "Local"
        cache_expiration      = 30
        custom_cache_policies = ""
        status                = ""
        addition              = (@{ root_folder_path = "$tmp"; show_hidden = $false } | ConvertTo-Json -Compress)
        remark                = "冒烟测试"
        disabled              = $false
        disable_index         = $false
        enable_sign           = $false
        web_proxy             = $false
        webdav_policy         = "302_redirect"
        proxy_range           = $false
        down_proxy_url        = ""
        disable_proxy_sign    = $false
        order_by              = ""
        order_direction       = ""
        extract_folder        = ""
        seed_policy           = "inherit"
    } | ConvertTo-Json

    $created = Invoke-RestMethod -Uri "http://127.0.0.1:$port/api/admin/storage/create" `
        -Method Post -Headers $headers -Body $storage -TimeoutSec 20
    if (-not $created.data.id) { throw "创建存储源失败：$($created | ConvertTo-Json -Depth 4)" }
    $storageId = $created.data.id
    Start-Sleep -Milliseconds 800

    $listing = Invoke-RestMethod -Uri "http://127.0.0.1:$port/api/fs/list" -Method Post `
        -Headers $headers -Body (@{ path = "/s_smoke001"; page = 1; per_page = 5; refresh = $true } | ConvertTo-Json) `
        -TimeoutSec 20
    if ($listing.code -ne 200) { throw "列目录失败：$($listing | ConvertTo-Json -Depth 4)" }

    $deleted = Invoke-RestMethod -Uri "http://127.0.0.1:$port/api/admin/storage/delete?id=$storageId" `
        -Method Post -Headers $headers -TimeoutSec 20
    if ($deleted.code -ne 200) { throw "删除存储源失败：$($deleted | ConvertTo-Json -Depth 4)" }

    Write-Host "OK: 引擎冒烟通过（ping + 登录 + 驱动 $count 个 + 存储源增删列）"
}
finally {
    if (-not $proc.HasExited) { $proc.Kill() }
    Remove-Item Env:\OPENLIST_ADMIN_PASSWORD -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
