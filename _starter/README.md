# _starter/ — 维护者说明

本仓库有两个身份：

1. **模板**：仓库根就是新项目的骨架，`git clone` / GitHub "Use this template" 直接可用。
2. **安装器**：`install.ps1` 把同一份内容装进**已存在**的项目（老项目升级用）。

一份内容，两种用法。根目录没有第二份副本，所以不存在"改了根目录忘了改 payload"。

## 为什么新项目走"从模板建仓库"，而不是裸 `git clone`

`git clone <模板> <新目录>` 会留下 `origin` 指向模板仓库，且带着模板的提交历史。第一次 `git push`
就污染模板——这不是靠"记得跑 `git remote remove origin`"能解决的，是把坑交给了记性。

所以：
- **要远端**：`gh repo create <name> --template guzuomuse/openspec_starter --clone`
  （或 GitHub 的 Use this template）→ 新仓库一次初始提交、origin 指向自己。
- **只要本地**：`git clone --depth 1 … && rm -rf .git && git init -b main`。

模板仓库的 `is_template` 标记就是这个方案的前提，别关掉它。
（`gh repo edit guzuomuse/openspec_starter --template` 可重新打开。）

## install.ps1 干什么

```bash
pwsh ./_starter/install.ps1 -Target C:\proj\some-existing-project -DryRun   # 先看计划
pwsh ./_starter/install.ps1 -Target C:\proj\some-existing-project
```

复制源是**仓库根**；`_starter/`、`docs/`、`README.md`、`AGENTS.md`、`.git` 不参与复制。
目标里必须有 `openspec/`（即已经 `openspec init` 过），否则直接报错。

| 对象 | 判据 | 结果 |
|---|---|---|
| `openspec/schemas/tdd-flow/` | 读 `schema.yaml` 的 `version` | 目标版本 < 源版本 → 备份后覆盖；相同 → 跳过 |
| `openspec/config.yaml` | 有无 `context:` / `rules:` / `operations:` | 无 → 整份写入；有 → **只改 `schema:` 这一行** |
| `.opencode/skills/openspec-custom-*`、`.codebuddy/skills/openspec-custom-*` | 目录内容逐文件 SHA256 | 一致 → 跳过；不同 → 备份后覆盖 |
| `.codebuddy/skills/openspec-*/`、`.opencode/skills/openspec-*/`、`commands/opsx*` | — | **不分发**（CLI 受管，靠 `openspec update`） |

参数：`-Target`（必填）、`-Agents`（默认 `opencode,codebuddy`）、`-DryRun`、`-Force`。
备份写到 `%TEMP%\openspec-starter-backup\<时间戳>\`，不往项目里塞 `.bak`。

## 维护纪律

1. **改 `openspec/schemas/tdd-flow/` 里任何内容，必须把 `schema.yaml` 的 `version` 加 1。**
   `version` 是唯一的升级信号，忘了升版，已装项目会判定"已是最新"而静默跳过。
2. **两份 review skill 副本必须同步**（`.codebuddy/skills/…` 与 `.opencode/skills/…`，方案 A：各工具读自己目录）。
   改一份立刻复制另一份，否则两边判据会无声分叉。
3. **受管文件别手改**：`.codebuddy/skills/openspec-*/`、`.opencode/skills/openspec-*/`、
   `commands/opsx*` 由 `openspec init` 生成，本仓库里这份来自 **openspec 1.17.0**。
   CLI 大版本升级后，在一个干净项目里重新 `openspec init` 并把这些文件替换进来。
4. **`docs/openspec-cheatsheet.md` 是文档的唯一维护地**，别在消费者项目里另写一份。

## 不要重复造的两件事

- 不要为了"新项目开箱即用"再加生成脚本：克隆本身就是分发机制。
- 不要为升级引入自研版本机制：`schema.yaml` 的 `version` + 文件哈希够用。

## 发布模板

GitHub 仓库 **Settings → General → Template repository ✓**，等价命令：

```bash
gh repo edit guzuomuse/openspec_starter --template
```

之后仓库页会出现 "Use this template"，用它创建的新仓库**不带本仓库的提交历史**。

## 历史

- 2026-11-11 之前是 `payload/` + 根目录 `install.ps1` 的纯安装器布局，每建一个项目都要跑一次脚本，
  且根目录与 `payload/` 两份内容要手工同步。
- 2026-11-11 改造成"根目录即模板"，`install.ps1` 降到 `_starter/` 只服务已有项目。
- 内容来源：`openspec_projects/lesson1`（openspec 1.17.0 生成的受管文件 + 我们的 schema/skill）。
