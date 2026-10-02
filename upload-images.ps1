# ============================================================
# upload-images.ps1
# GitHub 永久图床 - 批量上传图片并生成直链
# 用法1: 把图片放到 桌面\图床\待上传 文件夹，双击“双击上传.bat”
# 用法2: 把图片/文件夹直接拖到 “双击上传.bat” 图标上
# ============================================================
param(
    [string[]]$Paths
)

$ErrorActionPreference = "Stop"

# ---- 配置 ----
$User       = "wanghao14811291-ship-it"
$Repo       = "image-bed"
$Branch     = "main"
$RepoDir    = "C:\Users\14811\GitHub\image-bed"
$DesktopDir = "C:\Users\14811\Desktop\图床"
$Inbox      = Join-Path $DesktopDir "待上传"
$Archive   = Join-Path $DesktopDir "已上传"
$LinksFile  = Join-Path $DesktopDir "links.txt"
$Exts       = @(".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".svg")

if (-not $Paths -or $Paths.Count -eq 0) { $Paths = @($Inbox) }

# ---- 收集图片 ----
$files = @()
foreach ($p in $Paths) {
    if (-not (Test-Path -LiteralPath $p)) {
        Write-Host "跳过(路径不存在): $p" -ForegroundColor Yellow
        continue
    }
    $item = Get-Item -LiteralPath $p
    if ($item.PSIsContainer) {
        $files += Get-ChildItem -LiteralPath $p -Recurse -File |
            Where-Object { $Exts -contains $_.Extension.ToLower() }
    } elseif ($Exts -contains $item.Extension.ToLower()) {
        $files += $item
    }
}
$files = $files | Sort-Object FullName -Unique

if ($files.Count -eq 0) {
    New-Item -ItemType Directory -Force $Inbox | Out-Null
    Write-Host ""
    Write-Host "没有找到图片。请把图片放进: $Inbox 然后重新双击运行。" -ForegroundColor Yellow
    exit 0
}

# ---- 复制进仓库(按月分目录, 重名自动加后缀) ----
New-Item -ItemType Directory -Force $Inbox | Out-Null
$month   = Get-Date -Format "yyyy-MM"
$destDir = Join-Path $RepoDir "images\$month"
New-Item -ItemType Directory -Force $destDir | Out-Null

$results = @()
foreach ($f in $files) {
    $name   = $f.Name
    $target = Join-Path $destDir $name
    if (Test-Path -LiteralPath $target) {
        $base = [System.IO.Path]::GetFileNameWithoutExtension($name)
        $ext  = $f.Extension
        $suffix = -join ((1..4) | ForEach-Object { '{0:x}' -f (Get-Random -Maximum 16) })
        $name   = "$base-$suffix$ext"
        $target = Join-Path $destDir $name
    }
    Copy-Item -LiteralPath $f.FullName -Destination $target -Force

    $relParts = "images/$month/$name" -split '/'
    $encRel   = ($relParts | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
    $raw = "https://raw.githubusercontent.com/$User/$Repo/$Branch/$encRel"
    $cdn = "https://cdn.jsdelivr.net/gh/$User/$Repo@$Branch/$encRel"
    $results += [pscustomobject]@{ Original = $f.FullName; Name = $name; Raw = $raw; Cdn = $cdn }
}

# ---- 提交并推送 ----
Set-Location $RepoDir
git add -A
$ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
git commit -m "upload $($results.Count) image(s) $ts" 2>&1 | Out-Null
git push origin $Branch 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "推送失败(可能是网络抖动)。图片已在本地仓库，网络恢复后重新双击运行即可，不会丢图。"
}

# ---- 输出链接 ----
$logLines = @("===== $TS =====")
foreach ($r in $results) {
    Write-Host ""
    Write-Host "图片: $($r.Name)" -ForegroundColor Cyan
    Write-Host "RAW(发给AI): $($r.Raw)" -ForegroundColor White
    Write-Host "CDN(国内看): $($r.Cdn)" -ForegroundColor DarkGray
    $logLines += "$($r.Name)`r`n  RAW: $($r.Raw)`r`n  CDN: $($r.Cdn)"
}
$logLines += ""
Add-Content -Path $LinksFile -Value ($logLines -join "`r`n") -Encoding UTF8

# RAW 链接复制到剪贴板
Set-Clipboard -Value (($results | ForEach-Object { $_.Raw }) -join "`r`n")

# 收件箱里的原图归档
$archDir = Join-Path $Archive (Get-Date -Format "yyyy-MM-dd")
New-Item -ItemType Directory -Force $archDir | Out-Null
foreach ($r in $results) {
    try {
        if ($r.Original.StartsWith($Inbox)) {
            Move-Item -LiteralPath $r.Original -Destination (Join-Path $archDir (Split-Path $r.Original -Leaf)) -Force
        }
    } catch {}
}

Write-Host ""
Write-Host "完成！共上传 $($results.Count) 张。RAW 链接已复制到剪贴板，直接粘贴给 AI 即可。" -ForegroundColor Green
Write-Host "全部历史链接记录在: $LinksFile" -ForegroundColor Green
