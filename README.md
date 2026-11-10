# OpenSpec Starter

**这不是 OpenSpec 本身，而是叠在 OpenSpec 之上的自定义扩展包。**

装完之后，你的 OpenSpec 项目会多出一套 TDD 工作流和一套三透镜代码审查流程。

适配 **OpenSpec 1.17.0**（`schema` 系列命令仍是 experimental，升级前先看 `openspec --version`）。

---

## 装了什么

| 内容 | 类型 | 说明 |
|---|---|---|
| `tdd-flow` schema | 自定义 workflow | `proposal → specs → design → seams → tasks`，任务成对切成 `[RED]`/`[GREEN]` 切片 |
| `tdd-guide.md` | 判定标准（外置） | 好测试、三个反模式、mock 边界、红的两步 |
| `openspec-custom-code-review` skill | 自有 skill | 三透镜并行审查：spec / verification / standards，分诊后自动修无歧义项 |
| `config.yaml` | 项目配置 | 选 `tdd-flow`，带 context 与 rules |

设计取舍、实测记录、以及一堆踩过的坑，见 [`docs/openspec-cheatsheet.md`](docs/openspec-cheatsheet.md)。

## 前提

1. 目标项目已经跑过 `openspec init`（`.codebuddy/` 或 `.opencode/` 已存在）
2. 本机 `openspec --version` 为 1.17.x

## 安装

```bash
# 第一次：克隆到项目外面，只克隆这一次
git clone <this-repo> C:\my_projects\openspec-starter

# 之后每个新项目：只跑安装脚本
cd C:\proj\my-new-project
openspec init --tools opencode,codebuddy      # 先让 CLI 生成受管文件
pwsh C:\my_projects\openspec-starter\install.ps1 -Target .
```

为什么克隆到项目外面：starter 是**安装器**，不是项目骨架。每个项目里都放一份拷贝的话，
升级时要挨个项目 `git pull`；只留一份，升级就只有一个地方。

### 参数

| 参数 | 默认 | 说明 |
|---|---|---|
| `-Target` | 必填 | 目标项目根目录 |
| `-Agents` | `opencode,codebuddy` | 把 skill 分发到哪些工具目录 |
| `-DryRun` | 关 | 只打印计划，不写任何文件 |
| `-Force` | 关 | 强制重写，无视版本与内容比对 |

## 更新策略

脚本**不判断"文件归谁"**，只看能不能安全决定：

| 对象 | 判据 | 结果 |
|---|---|---|
| `openspec/schemas/tdd-flow/` | 读 `schema.yaml` 的 `version` | 目标版本 < 源版本 → 备份后覆盖；相同 → 静默跳过 |
| `openspec/config.yaml` | 有无 `context:` / `rules:` / `operations:` | 无（init 默认）→ 整份写入；有 → **只改 `schema:` 这一行** |
| `.opencode/skills/…`、`.codebuddy/skills/…` | 目录内容逐文件 SHA256 | 一致 → 跳过；不同 → 备份后覆盖 |

所以重复安装是幂等的（第二次全 `skip`），用户自己写的 `context` / `rules` 不会被冲掉——脚本最多动 `schema:` 那一行。

备份一律写到 `%TEMP%\openspec-starter-backup\<时间戳>\`，不往项目里塞 `.bak`。

### 维护约定：改 schema 必须升 `version`

`version` 是唯一的升级信号。改了 `payload/openspec/schemas/tdd-flow/` 里的任何内容，
就把 `schema.yaml` 的 `version` 加 1，否则已装过的项目会判定"已是最新"而跳过。

## 升级

```bash
cd C:\my_projects\openspec-starter
git pull

cd C:\proj\my-new-project
pwsh C:\my_projects\openspec-starter\install.ps1 -Target . -DryRun   # 先看会改什么
pwsh C:\my_projects\openspec-starter\install.ps1 -Target .
```

不加 `-Force` 也能升级：脚本按 `version` 与内容比对决定覆盖，只动该动的部分。

## 目录结构

```
openspec-starter/
├── install.ps1
├── payload/                    # 会被复制进目标项目的东西
│   ├── openspec/
│   │   ├── config.yaml
│   │   └── schemas/tdd-flow/
│   └── skills/
│       └── openspec-custom-code-review/
└── docs/openspec-cheatsheet.md # 设计原理与踩坑记录
```

## 它做不到什么

- **不会替你 `openspec init`**：那一步要选工具，脚本代劳会选错。
- **没有强制力**：红绿顺序、测试质量、review 结论，全靠 prompt 自觉 + 人工把关。
  CLI 只检查文件存在、delta 语法、checkbox 数量——**不校验勾选顺序**。
- **不覆盖你的 `config.yaml`**：有自定义内容时只打印合并建议。

## 加新内容

往 `payload/` 里丢就行，脚本会遍历目录，不写死文件名：

- 新 schema → `payload/openspec/schemas/<name>/`
- 新 skill → `payload/skills/<name>/`
