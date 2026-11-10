#Requires -Version 5.1
<#
.SYNOPSIS
  把 OpenSpec Starter 的扩展装进一个已初始化的 OpenSpec 项目。

.DESCRIPTION
  只做四件事：校验目标 → 复制 schema → 写入 config → 分发 skill → 自检。
  不执行 openspec init（那一步需要你自己选工具）。

.EXAMPLE
  pwsh ./install.ps1 -Target C:\proj\my-new-project

.EXAMPLE
  pwsh ./install.ps1 -Target . -Agents opencode -Force
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Target,

    [string[]]$Agents = @("opencode", "codebuddy"),

    [switch]$Force
)

$ErrorActionPreference = "Stop"

$root = $PSScriptRoot
$payload = Join-Path $root "payload"

function Write-Step($text) { Write-Host "==> $text" -ForegroundColor Cyan }
function Write-Warn($text) { Write-Host "!!  $text" -ForegroundColor Yellow }

if (-not (Test-Path $payload)) {
    throw "payload/ 不存在，脚本必须和 payload/ 放在同一个仓库里。"
}

# ---- 1. 校验目标 ------------------------------------------------------------
if (-not (Test-Path $Target)) {
    throw "目标目录不存在: $Target"
}
$Target = (Resolve-Path $Target).Path

if (-not (Test-Path (Join-Path $Target "openspec"))) {
    throw "目标里没有 openspec/ 目录。请先在该项目里运行 openspec init，再执行本脚本。"
}

# ---- 2. schema --------------------------------------------------------------
$schemaSrc = Join-Path $payload "openspec/schemas/tdd-flow"
$schemaDst = Join-Path $Target "openspec/schemas/tdd-flow"

if ((Test-Path $schemaDst) -and -not $Force) {
    Write-Warn "openspec/schemas/tdd-flow 已存在，跳过（加 -Force 覆盖）"
}
else {
    if (Test-Path $schemaDst) { Remove-Item -Recurse -Force $schemaDst }
    New-Item -ItemType Directory -Force -Path (Split-Path $schemaDst) | Out-Null
    Copy-Item -Recurse $schemaSrc $schemaDst
    Write-Step "已安装 schema: tdd-flow"
}

# ---- 3. config.yaml ---------------------------------------------------------
$cfgSrc = Join-Path $payload "openspec/config.yaml"
$cfgDst = Join-Path $Target "openspec/config.yaml"

$isDefaultConfig = $true
if (Test-Path $cfgDst) {
    $existing = Get-Content $cfgDst -Raw
    $hasCustom = ($existing -match "(?m)^rules:") -or ($existing -match "(?m)^context:")
    $isSpecDriven = $existing -match "(?m)^schema:\s*spec-driven\s*$"
    if (-not $isSpecDriven -or $hasCustom) { $isDefaultConfig = $false }
}

if ($isDefaultConfig -or $Force) {
    if (Test-Path $cfgDst) { Copy-Item $cfgDst "$cfgDst.bak" -Force }
    Copy-Item $cfgSrc $cfgDst -Force
    Write-Step "已写入 openspec/config.yaml"
}
else {
    Write-Warn "openspec/config.yaml 已有自定义内容，未覆盖（原文件备份为 config.yaml.bak）"
    Write-Host "   把下面这些字段手工合并进去：" -ForegroundColor Yellow
    Get-Content $cfgSrc | ForEach-Object { Write-Host "     $_" }
}

# ---- 4. skills --------------------------------------------------------------
foreach ($agent in $Agents) {
    $agentSkills = Join-Path $Target ".$agent/skills"
    New-Item -ItemType Directory -Force -Path $agentSkills | Out-Null

    Get-ChildItem (Join-Path $payload "skills") -Directory | ForEach-Object {
        $dst = Join-Path $agentSkills $_.Name
        if ((Test-Path $dst) -and -not $Force) {
            Write-Warn ".$agent/skills/$($_.Name) 已存在，跳过（加 -Force 覆盖）"
        }
        else {
            if (Test-Path $dst) { Remove-Item -Recurse -Force $dst }
            Copy-Item -Recurse $_.FullName $dst
            Write-Step "已安装 skill: .$agent/skills/$($_.Name)"
        }
    }
}

# ---- 5. 自检 ----------------------------------------------------------------
Write-Step "校验 schema"
Push-Location $Target
try {
    openspec schema validate tdd-flow
}
finally {
    Pop-Location
}

Write-Host ""
Write-Host "安装完成。接下来：" -ForegroundColor Green
Write-Host "  openspec schemas                          # 应看到 tdd-flow (project)"
Write-Host "  openspec new change <name> --schema tdd-flow"
