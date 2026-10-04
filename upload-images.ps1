# ============================================================
# upload-images.ps1
# GitHub 永久图床 - 批量上传图片，自动生成链接与 Codex 读图话术
# 用法1: 把图片放到 桌面\图床\待上传 文件夹，双击“双击上传.bat”
# 用法2: 把图片/文件夹直接拖到 “双击上传.bat” 图标上
# ============================================================
param(
    [string[]]$Paths
)

# 不用 Stop，避免 git 的警告信息(stderr)被误判成致命错误
$ErrorActionPreference = "Continue"

# ---- 配置 ----
$User       = "wanghao14811291-ship-it"
$Repo       = "image-bed"
$Branch     = "main"
$RepoDir    = "C:\Users\14811\GitHub\image-bed"
$DesktopDir = "C:\Users\14811\Desktop\图床"
$Inbox      = Join-Path $DesktopDir "待上传"
$LinksFile  = Join-Path $DesktopDir "links.txt"
$Exts       = @(".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".svg")
$CodexLimit = 900KB      # GitHub contents 接口内联返回的安全大小
$CompressExts = @(".png", ".jpg", ".jpeg", ".bmp", ".webp")

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

# ---- 辅助: 生成不冲突的目标文件名 ----
function Resolve-Target($dir, $name) {
    $target = Join-Path $dir $name
    if (Test-Path -LiteralPath $target) {
        $base = [System.IO.Path]::GetFileNameWithoutExtension($name)
        $ext  = [System.IO.Path]::GetExtension($name)
        $suffix = -join ((1..4) | ForEach-Object { '{0:x}' -f (Get-Random -Maximum 16) })
        $target = Join-Path $dir "$base-$suffix$ext"
    }
    return $target
}

# ---- 辅助: 压缩为 JPEG，返回最终文件大小 ----
function Compress-Jpeg($src, $dst, $maxWidth, $quality) {
    Add-Type -AssemblyName System.Drawing
    $img = [Drawing.Image]::FromFile($src)
    try {
        $w = [Math]::Min($maxWidth, $img.Width)
        $h = [int]($img.Height * $w / $img.Width)
        $bmp = New-Object Drawing.Bitmap $w, $h
        try {
            $g = [Drawing.Graphics]::FromImage($bmp)
            $g.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $g.DrawImage($img, 0, 0, $w, $h)
            $enc = [Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
                Where-Object { $_.MimeType -eq 'image/jpeg' }
            $ep = New-Object Drawing.Imaging.EncoderParameters 1
            $ep.Param[0] = New-Object Drawing.Imaging.EncoderParameter(
                [Drawing.Imaging.Encoder]::Quality, [long]$quality)
            $bmp.Save($dst, $enc, $ep)
        } finally { $g.Dispose(); $bmp.Dispose() }
    } finally { $img.Dispose() }
    return (Get-Item -LiteralPath $dst).Length
}

# ---- 复制进仓库(按月分目录) ----
New-Item -ItemType Directory -Force $Inbox | Out-Null
$month   = Get-Date -Format "yyyy-MM"
$destDir = Join-Path $RepoDir "images\$month"
New-Item -ItemType Directory -Force $destDir | Out-Null

# 建立本地仓库已有图片的 SHA256 索引，避免推送失败后重试造成重复图片
$existingByHash = @{}
Get-ChildItem -LiteralPath (Join-Path $RepoDir "images") -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
    $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    if (-not $existingByHash.ContainsKey($hash) -or $_.LastWriteTime -gt $existingByHash[$hash].LastWriteTime) {
        $existingByHash[$hash] = $_
    }
}

$results = @()
foreach ($f in $files) {
    # 1) 原图入库；如果仓库中已有相同内容，直接复用，不重复复制
    $sourceHash = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
    if ($existingByHash.ContainsKey($sourceHash)) {
        $target = $existingByHash[$sourceHash].FullName
    } else {
        $target = Resolve-Target $destDir $f.Name
        Copy-Item -LiteralPath $f.FullName -Destination $target -Force
        $existingByHash[$sourceHash] = Get-Item -LiteralPath $target
    }
    $savedName = Split-Path $target -Leaf

    # 2) 准备 Codex 可读的小图(<=900KB)
    $codexRel = $null
    if ($f.Length -le $CodexLimit) {
        # 原图本身够小，连接器可直接读
        $codexRel = "images/$month/$savedName"
    } elseif ($CompressExts -contains $f.Extension.ToLower()) {
        $base = [System.IO.Path]::GetFileNameWithoutExtension($savedName)
        $smallName = "$base-codex.jpg"
        $smallTarget = Join-Path $destDir $smallName
        $tries = @(
            @{ w = 1280; q = 55 },
            @{ w = 1280; q = 40 },
            @{ w = 960;  q = 40 },
            @{ w = 960;  q = 25 }
        )
        $ok = $false
        if (Test-Path -LiteralPath $smallTarget) {
            $ok = $true
            $codexRel = "images/$month/$smallName"
        }
        if (-not $ok) {
            foreach ($t in $tries) {
                try {
                    $sz = Compress-Jpeg $f.FullName $smallTarget $t.w $t.q
                    if ($sz -le $CodexLimit) { $ok = $true; break }
                } catch {
                    Start-Sleep -Milliseconds 200
                }
            }
        }
        if ($ok) {
            $codexRel = "images/$month/" + (Split-Path $smallTarget -Leaf)
        } else {
            Write-Host "警告: $($f.Name) 压缩后仍超过 900KB，未生成 Codex 小图。" -ForegroundColor Yellow
        }
    } else {
        Write-Host "提示: $($f.Name) 为 $($f.Extension) 格式且超过 900KB，已跳过自动压缩。" -ForegroundColor Yellow
    }

    # 3) 组装链接
    $relParts = "images/$month/$savedName" -split '/'
    $encRel   = ($relParts | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
    $results += [pscustomobject]@{
        Original  = $f.FullName
        Name      = $savedName
        Raw       = "https://raw.githubusercontent.com/$User/$Repo/$Branch/$encRel"
        Mirror    = "https://cdn.jsdmirror.com/gh/$User/$Repo@$Branch/$encRel"
        Gcore     = "https://gcore.jsdelivr.net/gh/$User/$Repo@$Branch/$encRel"
        CodexPath = $codexRel
    }
}

# ---- 提交并推送 ----
Set-Location $RepoDir
git add -A
$ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
git commit -m "upload $($results.Count) image(s) $ts" | Out-Null
git branch -M $Branch

$pushOk = $false
for ($attempt = 1; $attempt -le 2; $attempt++) {
    Write-Host ""
    if ($attempt -eq 1) {
        Write-Host "正在同步远端并推送..." -ForegroundColor Cyan
    } else {
        Write-Host "推送失败，正在重新同步远端后重试..." -ForegroundColor Yellow
        Start-Sleep -Seconds 2
    }

    git fetch origin $Branch
    if ($LASTEXITCODE -ne 0) {
        Write-Host "无法连接 GitHub 或远端读取失败。" -ForegroundColor Red
        continue
    }

    git rebase "origin/$Branch"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "自动同步远端变更时发生冲突，已停止。请检查本地仓库后再推送。" -ForegroundColor Red
        git rebase --abort
        exit 1
    }

    git push -u origin $Branch
    if ($LASTEXITCODE -eq 0) {
        $pushOk = $true
        break
    }
}

if (-not $pushOk) {
    Write-Host ""
    Write-Host "推送失败。图片已在本地仓库，但请根据上面的 Git 原始错误排查；修复后重新双击运行即可，不会丢图。" -ForegroundColor Red
    exit 1
}

# ---- 生成 Codex 话术 ----
function Build-CodexPrompt($r) {
    if (-not $r.CodexPath) { return $null }
    return "请通过 GitHub 连接器的 fetch_file（读取文件内容，不是元数据查询）读取仓库 " +
        "$User/$Repo 中的文件 `"$($r.CodexPath)`"。该文件小于 1MB，返回 JSON 的 content 字段是内联 base64；" +
        "请去掉 content 中的换行，base64 解码保存为图片并查看，然后回答：（在此写你的问题）"
}

# ---- 输出 ----
$logLines = @("===== $ts =====")
$codexPrompts = @()
foreach ($r in $results) {
    Write-Host ""
    Write-Host "图片: $($r.Name)" -ForegroundColor Cyan
    Write-Host "RAW  (发给普通AI): $($r.Raw)" -ForegroundColor White
    Write-Host "镜像 (国内浏览器): $($r.Mirror)" -ForegroundColor Green
    $logLines += "$($r.Name)`r`n  RAW:    $($r.Raw)`r`n  MIRROR: $($r.Mirror)"
    $cp = Build-CodexPrompt $r
    if ($cp) {
        Write-Host "CODEX 读取路径: $($r.CodexPath)" -ForegroundColor Yellow
        Write-Host "CODEX 话术:" -ForegroundColor Yellow
        Write-Host $cp
        $codexPrompts += $cp
        $logLines += "  CODEX_PATH: $($r.CodexPath)`r`n  CODEX_PROMPT: $cp"
    }
}
$logLines += ""
Add-Content -Path $LinksFile -Value ($logLines -join "`r`n") -Encoding UTF8

# 剪贴板: 有 Codex 话术则复制话术，否则复制 RAW 链接
if ($codexPrompts.Count -gt 0) {
    Set-Clipboard -Value ($codexPrompts -join "`r`n`r`n")
} else {
    Set-Clipboard -Value (($results | ForEach-Object { $_.Raw }) -join "`r`n")
}

# 收件箱原图直接删除(用途为临时给 Codex 看；远程副本 3 小时后由 GitHub Actions 自动清理)
foreach ($r in $results) {
    try {
        if ($r.Original.StartsWith($Inbox)) {
            Remove-Item -LiteralPath $r.Original -Force
        }
    } catch {}
}

Write-Host ""
Write-Host "完成！共 $($results.Count) 张。" -ForegroundColor Green
if ($codexPrompts.Count -gt 0) {
    Write-Host "Codex 话术已复制到剪贴板，粘贴给 Codex 后在末尾补上你的问题即可。" -ForegroundColor Green
} else {
    Write-Host "RAW 链接已复制到剪贴板。" -ForegroundColor Green
}
Write-Host "历史记录: $LinksFile" -ForegroundColor Green
