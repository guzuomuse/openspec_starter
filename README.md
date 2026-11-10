# OpenSpec Starter

一个**可直接克隆**的 OpenSpec 项目模板：`tdd-flow` 工作流（proposal → specs → design → seams → tasks，
任务成对切成 `[RED]`/`[GREEN]`）和三透镜代码审查 skill 都已经配好，克隆完就能开工，不需要跑安装脚本。

## 用它开一个新项目

**推荐：从模板建仓库。** `origin` 从一开始就指向你自己的仓库，不存在推错地方的可能：

```bash
gh repo create my-new-project --template guzuomuse/openspec_starter --private --clone
cd my-new-project
```

不想用命令行，就在 GitHub 仓库页点 **Use this template → Create a new repository**。
两种方式生成的新仓库都**不带本模板的提交历史**（一次初始提交）。

**只要本地目录、不建远端**（纯试验、不打算 push）：

```bash
git clone --depth 1 https://github.com/guzuomuse/openspec_starter 新目录
cd 新目录 && rm -rf .git && git init -b main
```

> ⚠️ 别在裸 `git clone` 出来的目录里直接 `git push`：那时 `origin` 还指着模板仓库，
> 你的提交会被推到模板上。上面两种方式已经把这个问题从根上去掉了，这条只是解释为什么不再推荐裸克隆。

克隆下来就已经是这样一个项目：

```
openspec/           # schema、config、specs、changes
.codebuddy/         # codebuddy 的 skills 与 commands（含自定义 review skill）
.opencode/          # opencode 的同款副本
AGENTS.md           # 提交约定与工作流约定
docs/               # 设计与踩坑记录（可删）
_starter/           # 升级工具（可删）
```

## 开工

```bash
openspec list --specs                      # 看已有什么能力（刚克隆时是空的）
openspec new change <change-name>          # 新建一个 change
```

之后按 schema 的阶段走：`proposal → specs → design → seams → tasks`，再 `openspec apply`，
收口时跑 `openspec-custom-code-review`。也可以直接用斜杠命令（`/opsx:propose`、`/opsx:apply` 等）。

## 前提

- **openspec CLI 1.17.x**（`openspec --version`）。仓库里的受管文件是 1.17.0 生成的；
  你本机 CLI 升级后，在项目里跑一次 `openspec update` 让它们对齐。
- 编辑器装了 **opencode** 或 **codebuddy** 之一 —— 两者各自读自己目录下的 skills/commands。

## 谁归谁管（重要）

| 路径 | 来源 | 能不能手改 |
|---|---|---|
| `openspec/config.yaml` | ours（覆写 init 默认） | 能，按项目改 context / rules |
| `openspec/schemas/tdd-flow/` | ours（fork 自 spec-driven） | 能，但改完要升 `version` |
| `.codebuddy/skills/openspec-custom-code-review/`<br>`.opencode/skills/openspec-custom-code-review/` | ours（两份副本，必须同步） | 能 |
| `.codebuddy/skills/openspec-*/`、`.codebuddy/commands/opsx/`<br>`.opencode/skills/openspec-*/`、`.opencode/commands/opsx-*.md` | `openspec init` 生成 | **别手改**，`openspec update` 会重写 |
| `AGENTS.md` | ours | 能 |

`openspec-custom-` 前缀就是"这不是官方受管文件"的标记。

## 升级工作流本身

模板更新后（schema 升版、skill 改判据），已有项目用 starter 仓库里的脚本同步：

```bash
pwsh <starter 仓库路径>/_starter/install.ps1 -Target . -DryRun   # 先看会改什么
pwsh <starter 仓库路径>/_starter/install.ps1 -Target .
```

脚本按 `schema.yaml` 的 `version` 与文件内容比对决定覆盖，最多动你 `config.yaml` 的 `schema:` 那一行，
受管的 `openspec-*` 文件一概不碰。**新项目不需要这个脚本**，克隆就够了。

## 参考

- [`docs/openspec-cheatsheet.md`](docs/openspec-cheatsheet.md)：设计取舍、实测记录、踩过的坑（唯一维护地）
- [`_starter/README.md`](_starter/README.md)：维护者视角（改什么必须升 version、两份副本怎么同步、怎么发布模板）
- 适配 **OpenSpec 1.17.0**，`schema` 系列命令仍是 experimental，升级 CLI 前先看 `openspec --version`
