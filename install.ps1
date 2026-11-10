#Requires -Version 5.1
<#
.SYNOPSIS
  把 OpenSpec Starter 的扩展装进一个已初始化的 OpenSpec 项目。

.DESCRIPTION
  四件事：校验目标 → 装 schema → 处理 config 的 schema 行 → 分发 skill → 自检。
  不执行 openspec init（那一步需要你自己选工具）。

  更新策略（不判断"文件归谁"，只看能不能安全决定）：
    - schema 目录：读 schema.yaml 的 version 比对，同版本静默跳过
    - config.yaml：只在没有自定义 context/rules 时整份写入；否则只改 schema: 这一行
    - skill 目录：内容一致则跳过，否则备份后覆盖

.EXAMPLE
  pwsh ./install.ps1 -Target C:\proj\my-new-project

.EXAMPLE
  pwsh ./install.ps1 -Target . -DryRun

.EXAMPLE
  pwsh ./install.ps1 -Target . -Agents opencode -Force
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

$root = $PSScriptRoot
$payload = Join-Path $root "payload"
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
if (-not (Test-Path $payload)) {
    throw "payload/ 不存在，脚本必须和 payload/ 放在同一个仓库里。"
}
if (-not (Test-Path $Target)) {
    throw "目标目录不存在: $Target"
}
$Target = (Resolve-Path $Target).Path

if (-not (Test-Path (Join-Path $Target "openspec"))) {
    throw "目标里没有 openspec/ 目录。请先在该项目里运行 openspec init，再执行本脚本。"
}

if ($DryRun) {
    Write-Host "DRY RUN - 只打印计划，不写任何文件" -ForegroundColor Magenta
}

# ---- 1. schema --------------------------------------------------------------
Write-Step "schema: $schemaName"

$payloadSchemaDir = Join-Path $payload "openspec/schemas/$schemaName"
$targetSchemaDir = Join-Path $Target "openspec/schemas/$schemaName"
$payloadVersion = Get-SchemaVersion (Join-Path $payloadSchemaDir "schema.yaml")
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
    Copy-Item -Recurse $payloadSchemaDir $targetSchemaDir
}

# ---- 2. config.yaml ---------------------------------------------------------
Write-Step "config: openspec/config.yaml"

$cfgSrc = Join-Path $payload "openspec/config.yaml"
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

# ---- 3. skills --------------------------------------------------------------
Write-Step "skills"

foreach ($agent in $Agents) {
    $agentSkills = Join-Path $Target ".$agent/skills"

    Get-ChildItem (Join-Path $payload "skills") -Directory | ForEach-Object {
        $name = $_.Name
        $dst = Join-Path $agentSkills $name

        if ((Test-DirSame $dst $_.FullName) -and -not $Force) {
            Write-Info "skip" ".$agent/skills/$name" "内容一致"
        }
        else {
            $verb = if (Test-Path $dst) { "update" } else { "add" }
            Write-Info $verb ".$agent/skills/$name"
            if (-not $DryRun) {
                New-Item -ItemType Directory -Force -Path $agentSkills | Out-Null
                Backup-Item $dst "$agent/$name"
                if (Test-Path $dst) { Remove-Item -Recurse -Force $dst }
                Copy-Item -Recurse $_.FullName $dst
            }
        }
    }
}

# ---- 4. 自检 ----------------------------------------------------------------
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
