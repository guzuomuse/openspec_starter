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
| `scripts/` | 逐文件 SHA256 | 一致 → 跳过；不同 → 备份后覆盖（`check-review.mjs`、`mutate-check.mjs` 走这条） |
| `.codebuddy/skills/openspec-*/`、`.opencode/skills/openspec-*/`、`commands/opsx*` | — | **不分发**（CLI 受管，靠 `openspec update`） |

参数：`-Target`（必填）、`-Agents`（默认 `opencode,codebuddy`）、`-DryRun`、`-Force`、`-SkipSelfCheck`。
备份写到 `%TEMP%\openspec-starter-backup\<时间戳>\`，不往项目里塞 `.bak`。

**升级后自检**：装完在目标项目里跑一次"还能跑起来吗"——有 `test/` 就跑 `node --test`，
有 `package.json` 且含 `test` 脚本就跑 `npm test`，有 `openspec/changes/*/review.md` 就逐个跑门禁。
测试失败 → **退出码 3**，并提示先 `git diff`（也可能是升级前就红的）；门禁非 0 只警告，
因为"review 还阻塞着"是项目的合法状态。`-SkipSelfCheck` 可跳过。

## `scripts/mutate-check.mjs`：变异测试台

verification 透镜要回答的是"**哪一行**让它变绿"。`tasks.md` 的自证只能证明"整段实现是载荷"，
逐行的归属要靠变异：把源码改坏，看有没有断言变红。

```bash
node scripts/mutate-check.mjs mutations.mjs                                   # 默认 node --test
node scripts/mutate-check.mjs mutations.mjs --cmd "node --test test/x.test.mjs"
```

清单是 ESM 文件，导出一个 `{ id, file, note?, apply(source) }` 数组。脚本把整棵树复制到临时目录
（跳过 `.git`/`node_modules`/构建产物），基线先跑绿，然后逐条改坏 → 跑测试 → 归类：

| 判定 | 含义 | 怎么办 |
|---|---|---|
| `KILLED` | 有断言杀掉它 | 好 |
| `SURVIVED` | 改坏了仍全绿 | 那处没有区分力 → 删冗余，或补一条只有它能过的断言，记 `low`/`verification` |
| `NOOP` | `apply` 没改动任何字符 | 用法错误，重写变异，不能算 KILLED |

**等价变异**（改写法、不改行为，如 `out += x` → `out = out + x`）存活是正常的，从清单里删掉即可。
任何 `SURVIVED` 或 `NOOP` 都让退出码非 0，所以它可以当门禁用。工作区一个字节都不动。

## `scripts/check-review.mjs` 的约定

它把 review 结论变成退出码，**只读结构、不读叙述**：

- `## Verdict` 里 `high N / medium N` 的 N 是**仍未处理**的条数，必须为 0；
  括号里写"均已 fixed"不构成豁免（v1 就是信这句话被绕过的）。
- 每个 finding 写成 `### F<n> [high|medium|low]` + 一行 `- 状态：<...>`；
  状态以 `fixed` / `rejected` / `closed` 开头才算关闭，**缺 `- 状态：` 一律算 open**。
- Verdict 与 Findings 反推结果不一致 → 阻塞（不可信）。

改这套判据时，必须同步改 SKILL 第 5、6 节——两边描述的得是同一套格式。

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
