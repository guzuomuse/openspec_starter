#Requires -Version 5.1
<#
.SYNOPSIS
  把本仓库（openspec-starter 模板）的 OpenSpec 扩展装进一个已存在的项目。

.DESCRIPTION
  本仓库根目录就是模板：新项目直接 git clone 或 GitHub "Use this template" 即可开箱使用。
  这个脚本是给**已经存在**的项目（已有 openspec/，比如老项目升级）补装/升级用的。

  复制源是仓库根，`_starter/`、`docs/`、`README.md`、`AGENTS.md`、`.git` 都不参与复制。

  更新策略（不判断"文件归谁"，只看能不能安全决定）：
    - schema 目录：读 schema.yaml 的 version 比对，同版本静默跳过
    - config.yaml：只在没有自定义 context/rules 时整份写入；否则只改 schema: 这一行
    - scripts/：逐文件哈希比对，一致跳过（review 门禁脚本走这条）
    - 自有 skill（`openspec-custom-*`）：内容一致则跳过，否则备份后覆盖。
      受管的 `openspec-*` skill 与 `commands/opsx*` 属于 CLI，不在这里分发——
      它们由 `openspec init` / `openspec update` 负责。

.EXAMPLE
  pwsh ./_starter/install.ps1 -Target C:\proj\my-existing-project

.EXAMPLE
  pwsh ./_starter/install.ps1 -Target . -DryRun

.EXAMPLE
  pwsh ./_starter/install.ps1 -Target . -Agents codebuddy -Force
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Target,

    [string[]]$Agents = @("opencode", "codebuddy"),

    [switch]$Force,

    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

# 仓库根 = 模板内容（本脚本在 _starter/ 下）
$root = Split-Path $PSScriptRoot -Parent
$schemaName = "tdd-flow"
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupRoot = Join-Path ([System.IO.Path]::GetTempPath()) "openspec-starter-backup\$stamp"

function Write-Step($text) { Write-Host "==> $text" -ForegroundColor Cyan }
function Write-Info($verb, $path, $note) {
    $line = "    {0,-7} {1}" -f $verb, $path
    if ($note) { $line = $line + "  (" + $note + ")" }
    Write-Host $line
}
function Write-Warn($text) { Write-Host "!!  $text" -ForegroundColor Yellow }

function Backup-Item([string]$path, [string]$relName) {
    if (-not (Test-Path $path)) { return }
    if ($DryRun) { return }
    if (-not (Test-Path $backupRoot)) {
        New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
    }
    $dest = Join-Path $backupRoot $relName
    Copy-Item -Recurse $path $dest -Force
    Write-Host "        backup -> $dest" -ForegroundColor DarkGray
}

function Get-SchemaVersion([string]$path) {
    if (-not (Test-Path $path)) { return $null }
    $hit = Select-String -Path $path -Pattern '^version:\s*(\d+)' | Select-Object -First 1
    if (-not $hit) { return $null }
    return [int]$hit.Matches[0].Groups[1].Value
}

function Get-ContentHash([string]$path) {
    # 文本文件先规范化行尾，避免 CRLF/LF 差异导致永远判定"内容不同"
    $ext = [System.IO.Path]::GetExtension($path).ToLowerInvariant()
    $textExts = @('.md', '.yaml', '.yml', '.json', '.txt', '.ps1', '.sh', '.mjs', '.js', '.ts')
    if ($textExts -contains $ext) {
        $text = [System.IO.File]::ReadAllText($path) -replace "`r`n", "`n"
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try { return [System.BitConverter]::ToString($sha.ComputeHash($bytes)) }
        finally { $sha.Dispose() }
    }
    return (Get-FileHash $path -Algorithm SHA256).Hash
}

function Test-DirSame([string]$left, [string]$right) {
    if (-not (Test-Path $left)) { return $false }
    $a = @(Get-ChildItem -Recurse -File $left | ForEach-Object { $_.FullName.Substring($left.Length).TrimStart('\', '/') })
    $b = @(Get-ChildItem -Recurse -File $right | ForEach-Object { $_.FullName.Substring($right.Length).TrimStart('\', '/') })
    if ($a.Count -ne $b.Count) { return $false }
    if (Compare-Object -ReferenceObject $a -DifferenceObject $b) { return $false }
    foreach ($rel in $a) {
        if ((Get-ContentHash (Join-Path $left $rel)) -ne (Get-ContentHash (Join-Path $right $rel))) { return $false }
    }
    return $true
}

# ---- 0. 前置检查 ------------------------------------------------------------
if (-not (Test-Path (Join-Path $root "openspec/schemas/$schemaName/schema.yaml"))) {
    throw "在 $root 找不到 openspec/schemas/$schemaName/schema.yaml，脚本必须放在仓库的 _starter/ 下。"
}
if (-not (Test-Path $Target)) {
    throw "目标目录不存在: $Target"
}
$Target = (Resolve-Path $Target).Path

if (-not (Test-Path (Join-Path $Target "openspec"))) {
    throw @"
目标里没有 openspec/ 目录。这个脚本只服务已有项目。
新项目请直接用模板：git clone <模板地址> <新目录>，不需要跑安装脚本。
"@
}

if ($DryRun) {
    Write-Host "DRY RUN - 只打印计划，不写任何文件" -ForegroundColor Magenta
}

# ---- 1. schema --------------------------------------------------------------
Write-Step "schema: $schemaName"

$srcSchemaDir = Join-Path $root "openspec/schemas/$schemaName"
$targetSchemaDir = Join-Path $Target "openspec/schemas/$schemaName"
$payloadVersion = Get-SchemaVersion (Join-Path $srcSchemaDir "schema.yaml")
$targetVersion = Get-SchemaVersion (Join-Path $targetSchemaDir "schema.yaml")

$installSchema = $false
if (-not (Test-Path $targetSchemaDir)) {
    Write-Info "add" "openspec/schemas/$schemaName" "version $payloadVersion"
    $installSchema = $true
}
elseif ($null -eq $targetVersion) {
    Write-Info "update" "openspec/schemas/$schemaName" "目标读不到 version，按旧版处理"
    $installSchema = $true
}
elseif ($targetVersion -lt $payloadVersion) {
    Write-Info "update" "openspec/schemas/$schemaName" "version $targetVersion -> $payloadVersion"
    $installSchema = $true
}
elseif ($Force) {
    Write-Info "force" "openspec/schemas/$schemaName" "version $targetVersion"
    $installSchema = $true
}
else {
    Write-Info "skip" "openspec/schemas/$schemaName" "已是最新 (version $targetVersion)"
}

if ($installSchema -and -not $DryRun) {
    Backup-Item $targetSchemaDir "schemas/$schemaName"
    if (Test-Path $targetSchemaDir) { Remove-Item -Recurse -Force $targetSchemaDir }
    New-Item -ItemType Directory -Force -Path (Split-Path $targetSchemaDir) | Out-Null
    Copy-Item -Recurse $srcSchemaDir $targetSchemaDir
}

# ---- 2. config.yaml ---------------------------------------------------------
Write-Step "config: openspec/config.yaml"

$cfgSrc = Join-Path $root "openspec/config.yaml"
$cfgDst = Join-Path $Target "openspec/config.yaml"

if (-not (Test-Path $cfgDst)) {
    Write-Info "add" "openspec/config.yaml"
    if (-not $DryRun) { Copy-Item $cfgSrc $cfgDst }
}
else {
    $text = Get-Content $cfgDst -Raw
    $hasOwnContent = ($text -match "(?m)^context:") -or ($text -match "(?m)^rules:") -or ($text -match "(?m)^operations:")

    if ((-not $hasOwnContent) -or $Force) {
        $why = if ($Force) { "force" } else { "目标无自定义 context/rules" }
        Write-Info "update" "openspec/config.yaml" "整份写入，$why"
        if (-not $DryRun) {
            Backup-Item $cfgDst "config.yaml"
            Copy-Item $cfgSrc $cfgDst -Force
        }
    }
    else {
        $lines = @(Get-Content $cfgDst)
        $current = $null
        foreach ($line in $lines) {
            if ($line -match '^schema:\s*(\S+)') { $current = $Matches[1]; break }
        }

        if ($current -eq $schemaName) {
            Write-Info "skip" "openspec/config.yaml" "schema 已是 $schemaName"
        }
        elseif ($null -eq $current) {
            Write-Info "update" "openspec/config.yaml" "追加 schema: $schemaName"
            if (-not $DryRun) {
                Backup-Item $cfgDst "config.yaml"
                Set-Content -Path $cfgDst -Value (@("schema: $schemaName") + $lines) -Encoding utf8
            }
        }
        elseif ($current -eq "spec-driven") {
            Write-Info "update" "openspec/config.yaml" "schema: spec-driven -> $schemaName"
            if (-not $DryRun) {
                Backup-Item $cfgDst "config.yaml"
                $new = $lines | ForEach-Object {
                    if ($_ -match '^schema:\s*spec-driven\s*$') { "schema: $schemaName" } else { $_ }
                }
                Set-Content -Path $cfgDst -Value $new -Encoding utf8
            }
        }
        else {
            Write-Warn "config.yaml 的 schema 是 '$current'，不是 spec-driven，未改动。确认要换用 -Force。"
        }
    }
}

# ---- 3. scripts（ours） -----------------------------------------------------
Write-Step "scripts"

$srcScripts = Join-Path $root "scripts"
if (Test-Path $srcScripts) {
    $dstScripts = Join-Path $Target "scripts"
    Get-ChildItem $srcScripts -File | ForEach-Object {
        $dst = Join-Path $dstScripts $_.Name
        if ((Test-Path $dst) -and ((Get-ContentHash $dst) -eq (Get-ContentHash $_.FullName)) -and -not $Force) {
            Write-Info "skip" "scripts/$($_.Name)" "内容一致"
        }
        else {
            $verb = if (Test-Path $dst) { "update" } else { "add" }
            Write-Info $verb "scripts/$($_.Name)"
            if (-not $DryRun) {
                New-Item -ItemType Directory -Force -Path $dstScripts | Out-Null
                Backup-Item $dst "scripts/$($_.Name)"
                Copy-Item $_.FullName $dst -Force
            }
        }
    }
}
else {
    Write-Warn "仓库里没有 scripts/，跳过。"
}

# ---- 4. 自有 skill（openspec-custom-*） -------------------------------------
Write-Step "skills: openspec-custom-*"

foreach ($agent in $Agents) {
    $srcSkills = Join-Path $root ".$agent/skills"
    if (-not (Test-Path $srcSkills)) {
        Write-Warn "仓库里没有 .$agent/skills，跳过该工具目录。"
        continue
    }
    $dstSkills = Join-Path $Target ".$agent/skills"

    Get-ChildItem $srcSkills -Directory | Where-Object { $_.Name -like "openspec-custom-*" } | ForEach-Object {
        $name = $_.Name
        $dst = Join-Path $dstSkills $name

        if ((Test-DirSame $dst $_.FullName) -and -not $Force) {
            Write-Info "skip" ".$agent/skills/$name" "内容一致"
        }
        else {
            $verb = if (Test-Path $dst) { "update" } else { "add" }
            Write-Info $verb ".$agent/skills/$name"
            if (-not $DryRun) {
                New-Item -ItemType Directory -Force -Path $dstSkills | Out-Null
                Backup-Item $dst "$agent/$name"
                if (Test-Path $dst) { Remove-Item -Recurse -Force $dst }
                Copy-Item -Recurse $_.FullName $dst
            }
        }
    }
}

Write-Warn "受管文件（openspec-* skill、commands/opsx*）不在此分发。CLI 升级后请在目标项目跑 openspec update。"

# ---- 5. 自检 ----------------------------------------------------------------
if ($DryRun) {
    Write-Host ""
    Write-Host "DRY RUN 结束，未写入任何文件。" -ForegroundColor Magenta
    return
}

Write-Step "校验 schema"
Push-Location $Target
try {
    openspec schema validate $schemaName
}
finally {
    Pop-Location
}

Write-Host ""
Write-Host "安装完成。接下来：" -ForegroundColor Green
Write-Host "  openspec schemas                          # 应看到 $schemaName (project)"
Write-Host "  openspec new change <name> --schema $schemaName"
