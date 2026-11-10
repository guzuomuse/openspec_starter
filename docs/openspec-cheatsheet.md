# OpenSpec 改造 cheat-sheet

OpenSpec v1.17.0，本仓库实操积累。每条结论要么实测过，要么读过 CLI 源码；
拿不准的条目会明确标「未验证」，别当事实用。

---

## 1. 它到底是什么

**状态机 + prompt 编译器。** 不是执行引擎，不是编排器。

运行时链路：

```
用户提问
  → agent 选中 skill（一段 markdown prompt）
    → 执行 openspec CLI
       ├─ status        读文件，算状态
       ├─ instructions  读文件 + config + schema，编译成一段 prompt
       └─ validate      校验文件格式
    → agent 按 prompt 写文件、写代码
```

三条不变式：

- `openspec/` 里的纯文本既是计划，也是状态。没有数据库、没有隐藏状态。
- 它**不执行代码、不碰 git、没有事件系统**。docs 全文与 CLI dist 里搜 `hook` / `plugin` / `event` 均无命中。
- 所有"质量"要求都只能是 prompt 层的约定，不是强制。

---

## 2. schema 的真实字段全集

源码：`dist/core/artifact-graph/types.js`（zod 定义，比文档权威）。

| 层级 | 字段 | 必填 | 说明 |
|---|---|---|---|
| 顶层 | `name` / `version` | ✅ | `version` 是正整数，不影响行为 |
| 顶层 | `description` | — | 只用于 `openspec schemas` 展示 |
| 顶层 | `artifacts` | ✅ | 非空数组，上限 1000 |
| 顶层 | `apply` | — | 可省略，省略则用默认 |
| artifact | `id` | ✅ | **完全自由**，不限于内置四个 |
| artifact | `generates` | ✅ | 相对 change 目录，支持 glob / brace / extglob |
| artifact | `description` | ✅ | 进 prompt 的标题行 |
| artifact | `template` | ✅ | 相对 `templates/` |
| artifact | `instruction` | — | 进 prompt 的正文 |
| artifact | `requires` | — | artifact id 列表，默认 `[]` |
| apply | `requires` | ✅ | 非空，必须是已声明的 artifact id |
| apply | `tracks` | — | 进度文件，通常是 `tasks.md` |
| apply | `instruction` | — | **替换**内置 apply 指令 |

三个推论：

1. **没有 hooks / events / gates / success_criteria。** `instructions` 输出里的 `<success_criteria>` 是硬编码占位（`<!-- To be defined in schema validation rules -->`）。
2. zod 默认 strip 未知字段 → **拼错的字段被静默忽略**，validate 不报。
3. artifact 完成的判据是「`generates` 匹配到文件」，**不读内容**。

---

## 3. 五层改造点

| 层 | 位置 | 能改什么 | 生效 | 会被覆盖吗 |
|---|---|---|---|---|
| L1 | `openspec/config.yaml` | `context` / `rules.<artifact-id>` / `operations.apply\|archive.guidance` | 下次跑 CLI | 不会 |
| L2 | `openspec/schemas/<name>/` | artifact 清单、顺序、依赖、模板、instruction、apply 门槛与追踪文件 | 下次跑 CLI | **不会**（`update` 不碰 schemas） |
| L3 | 自有 skill 目录 | 多步流程（apply→review→fix 之类） | agent 自动匹配或点名 | 不会（只要目录名不是受管的 6 个） |
| L4 | `openspec config profile` | 装哪 12 个 workflow 里的哪些、skill / command / 两者 | `openspec update` | 全局设置 |
| L5 | git hook / CI | 真·强制 | 提交 / 推送 | 域外 |

---

## 4. 指令优先级（实测）

`openspec instructions apply` 的输出顺序：

```
### Instruction                            ← schema.apply.instruction
### Project Context (required instruction input)   ← config.context
### Operation Guidance (advisory)                 ← config.operations.apply.guidance
```

- **`schema.apply.instruction` 是替换而非追加**：写了自己的，内置那句 "Read context files, work through pending tasks..." 就完全消失。
- 三段的语义由 CLI 自己打印：Instruction 是控制值，context 是 required，guidance 是 advisory。
- apply skill 里写死了裁决：guidance 与"控制值"冲突时**可以不遵守并说明理由**。

→ 想要硬，写进 `schema.apply.instruction`；写进 `operations.*.guidance` 只能算"建议"。

---

## 5. `openspec update` 的覆盖边界（实测）

| 对象 | 结果 |
|---|---|
| 改过的受管 skill（`openspec-apply-change/SKILL.md`） | ❌ 被整篇重写，改动作废 |
| 自有名 skill（`.opencode/skills/openspec-custom-code-review/`） | ✅ 存活，不列出、不改、不删 |
| `openspec-` 前缀的自定义 skill | ✅ 也存活（不在映射表里），但不建议这么起名 |
| `openspec/schemas/` | ✅ 完全不碰 |

受管范围 = profile 那 6 个 workflow id 映射出的目录，逐字节比对，有差异就重写。

---

## 6. 硬边界清单

CLI 能看见的：

- 文件是否存在（artifact 完成）
- delta spec 的语法（`### Requirement:` / `#### Scenario:` / 500 字符上限）
- 依赖图（`requires` 引用、环路、`apply.requires`）
- checkbox 的 `[ ]` / `[x]`

CLI 看不见的：

- 测试是否真的先红后绿（**只数 checkbox 总数，不校验顺序**，先勾 1.6 再勾 1.1 也不报错）
- 断言是否同义反复
- 测试是否打在内约定的接缝上
- 代码是否最小实现

→ 这些只能靠 prompt 约束 + 人工 review + 外部 CI。

---

## 7. 本仓库的 tdd-flow 设计

```
proposal  (requires: [])
├─ specs   (requires: proposal)
│    └─ seams  (requires: specs)
└─ design  (requires: proposal)

tasks  (requires: specs, design, seams)
apply  (requires: [tasks], tracks: tasks.md)
```

| 产物 | 放什么 | 关键约束 |
|---|---|---|
| `proposal.md` | Why（≥50 字符）/ What / Capabilities / Impact | 最短，别写成设计文档 |
| `specs/` | 可观察行为、输入输出、错误条件 | 中文 `## Purpose` 需约 50 字才能过 `--strict`；MODIFIED 必须整块替换 |
| `design.md` | 决策与理由、备选方案、风险 | 始终产出（在依赖图上）；深度分档——简单变更几行即可 |
| `seams.md` | 接缝（公共边界）、覆盖行为、**测试命令**、盲区 | 测试只写在接缝上；新接缝先问再补 |
| `tasks.md` | 成对的 `[RED]` / `[GREEN]` 切片 + 末尾 review 收口组 | 不重复写命令，只引用 seam 编号；切片数按行为复杂度（通常 1-3 对） |
| `apply.instruction` | 9 条循环硬规则（8 条红绿 + 第 9 条收口） | 替换内置指令 |
| `tdd-guide.md` | 好测试 / 三反模式 / mock 边界 / 红的两步 | 外置，不进 prompt，不被 update 覆盖 |

设计取舍：

- **接缝文件化**：参考 skill 说"先与用户确认接缝"，落成 `seams.md` 才可审、可 commit。
- **反模式结构化成模板**："禁止横向切片"变成"任务必须成对编号"，从建议升级为形状。
- **长文档外置**：`tdd-guide.md` 放在 schema 目录，instruction 只写一行路径，省每次的 prompt。
- **design 深度分档，而不是"可选/必需"打架**：`design.md` 在依赖图上，CLI 只认文件是否存在，所以
  原句"create only if any apply"与 `tasks.requires: design` 互相矛盾，agent 只能自行解释（实测中这种
  结构别扭消耗的注意力比 11 条 findings 还多）。v2 改成"始终产出，深度按变更复杂度分档"。
- **切片数跟复杂度走，不跟行为条数走**：实测用 6 对切片写 10 行代码，后半段全是"已知会红"，信息量接近零。
  v2 规则：通常 1-3 对，只有新接缝 / 新分支族 / 状态机才加对。

### review 接线（四重，强度递减）

| 位置 | 作用 | 强度 |
|---|---|---|
| `tasks.md` 末尾「Review 收口」组的复选框（编号随行为组数量变化，如 `2.1` / `3.1`） | 不勾则 `all_done` 不成立 | 状态机（最硬） |
| `schema.apply.instruction` 第 9 条 | 控制值，替换内置指令 | 高 |
| `config.operations.apply.guidance` | advisory，可合法忽略 | 低 |
| `.opencode/skills/openspec-custom-code-review/` + `.codebuddy/skills/openspec-custom-code-review/` | 审查具体怎么做（每家一份，方案 A） | 执行层 |

每个工具目录下三个文件：`SKILL.md`（主流程：定范围 → 三透镜 → triage → route → fix → 复跑 →
收口）+ `references/verification-lens.md`（B 轴判据全文）+ `references/standards-baseline.md`（C 轴 smell 基线）。

三透镜，各自独立报告，**不合并、不重排**（合并会让一个轴遮蔽另一个）：

- **spec**：实现是否逐个场景符合 `specs/`；含范围蔓延
- **verification**：每个改动面的回归，是否有一条会变红的断言钉住
- **standards**：仓库文档化标准优先 + smell 基线（一律判断而非硬违规）

Triage 到 Route 的关键分界：`patch`（无歧义）／`decision_needed`（要用户意图）／`defer`（非本次引入）。
只有 `patch` 才自动修，且**修复本身必须先补一条失败测试**。

**能不能自动拍板，判据不是严重度，是两件事**（`patch` 只说明修法清楚，不说明可以自己决定）：

| | 修复会让 design 已写下的选择失效？否 | 是 |
|---|---|---|
| 回滚成本低 | 直接修，记一笔 | 自动修 + 必须同步改 design |
| 回滚成本高 | 问 | 问 |

三条边界：`specs/`、`proposal.md`、`seams.md` 的契约段落永远不许自动改（要改就是 `decision_needed`）；
**低优先级 + 有歧义时默认"记录限制"而不是"改行为"**（写进 design 的 Non-Goals 或扩写 seams 盲区，
零行为漂移、可逆）；每条自动决策必须有证据，每轮最多 3 条，单独记进 `## Auto-decided` 区。

取/弃：

- **取**：两轴分离（code-review）、三态判定真伪 + 路由三分（bmad）、
  "回归能否让某条断言变红"（verification-gap）、smell 基线
- **弃**：uv 模板渲染、repo 外临时 triage 文件、issue tracker 依赖、
  model capability 要求、仪式化的 step-01/05
- **新增**：修复走红绿；复跑最多两轮，仍不通过就停下交人；自动决策走两问矩阵 + 三条护栏

**修复分两类，不能一套规则套到底**（实测得出）：

- **行为错**（算错、漏分支、顺序错）→ 红绿：先补一条失败的测试，再修
- **缺验证**（verification gap：行为现状是对的，只是没钉子）→ 补的测试会直接绿，
  所以改用**红证**：故意把实现改坏一次，确认新断言变红，再改回。否则无法证明钉子有效

红证会顺手抓到第三种情况：钉子和缺陷不匹配（测试红的地方不是你预期的位置）。

**门禁任务必须排除自己。** review 的收口复选框既是门禁（`all_done` 的条件），又要在 review
完成后才勾——这两个要求天然循环。入口条件必须写成"**除** review 收口任务外的复选框全勾"，
否则 agent 只能自行解释（opencode 实测时就撞上了这个歧义）。

产物：`openspec/changes/<change>/review.md`，随 change 一起归档。

**方案 A 的唯一纪律：两份副本必须同步。** skill 放在每个工具自己的目录（`.opencode/skills/openspec-custom-code-review/`
与 `.codebuddy/skills/openspec-custom-code-review/`），不搞中立目录。代价是两份文件，所以改一份就同步另一份，
或约定一份为源、另一份用 diff/哈希校验。别让它们无声分叉。

---

## 8. 魔改包全貌（改了什么 / 怎么复现）

### 8.1 文件地图

只有标 **ours** 的是我们写的；其余是 `openspec init` 生成的受管文件，**别手改**（`update` 会重写）。

| 路径 | 来源 | 作用 |
|---|---|---|
| `openspec/config.yaml` | ours（覆写 init 默认） | schema 选择、`context`、`rules`、`operations.*.guidance` |
| `openspec/schemas/tdd-flow/schema.yaml` | ours（fork 自 spec-driven） | 5 个 artifact 的依赖图、模板、instruction + 9 条 apply 指令 |
| `openspec/schemas/tdd-flow/templates/*.md` | 3 个来自 fork，2 个 ours | `proposal` / `spec` / `design` 原样；`tasks` 改写；`seams` 新增 |
| `openspec/schemas/tdd-flow/tdd-guide.md` | ours | 实现阶段判定标准（外置，不进 prompt） |
| `.opencode/skills/openspec-custom-code-review/` | ours | review 工作流，3 个文件 |
| `.codebuddy/skills/openspec-custom-code-review/` | ours（副本，方案 A） | 同上 |
| `.opencode/skills/openspec-*/` + `.opencode/commands/opsx-*.md` | openspec init | 受管，`update` 重写 |
| `.codebuddy/skills/openspec-*/` + `.codebuddy/commands/opsx/*.md` | openspec init | 受管，`update` 重写 |
| `AGENTS.md` | ours | 项目约定（提交、测试、工作流） |
| `_starter/install.ps1` | ours | 只给**已有项目**升级用；新项目靠克隆，不需要它 |
| `docs/openspec-cheatsheet.md` | ours | 本文（唯一维护地） |

### 8.2 复现（新项目）

**仓库根就是模板，克隆即用**（2026-11-11 起；此前是 `payload/` + 安装脚本的布局）：

```bash
git clone https://github.com/guzuomuse/openspec_starter 新目录
cd 新目录
git remote remove origin        # 或用 GitHub "Use this template"，新仓库不带历史
```

老项目（已有 `openspec/`）用 `_starter/install.ps1` 补装/升级，见 `_starter/README.md`。

为什么不再"每次跑一次安装脚本"：装脚本的三条判据（version / config 有无自定义 / 内容哈希）本来是给
**升级**用的——把一处改动分发到 N 个项目；新项目开局靠克隆就能完成，多一次脚本执行只是摩擦。

没有 starter 时的手工复现是 5 步：`schema fork` → 覆盖 `schema.yaml` → 覆盖 `tasks` 模板并新增
`seams` 模板 → 新增 `tdd-guide.md` → 覆写 `config.yaml` 并分发 skill。

### 8.3 与官方能力的边界

| 能力 | 谁提供 | 备注 |
|---|---|---|
| artifact 依赖图、apply 状态机、delta 合并 | OpenSpec | 原生 |
| `schema fork / validate / which` | OpenSpec 1.17 | **experimental**，每次输出都带提示，升级可能变 |
| 5 个 artifact 的顺序与判定、红绿切片、接缝清单 | 我们 | 纯 `schema.yaml` + templates |
| 三透镜 review | 我们 | 自有 skill，不依赖 CLI 任何能力 |
| 真·强制（顺序、红绿、review 质量） | **谁都没有** | 只能靠 prompt 自觉 + 人 + 外部 CI |

### 8.4 更新策略（为什么不做"所有权判断"）

官方**没有任何 ownership 机制**。`openspec update` 的做法是"重新生成 → 逐字节比对 → 不同就写"，
从不判断文件是否被用户改过；`schema.yaml` 的 `version` 文档明确"不影响行为"；
官方 schema 文档也确认不存在 owner / generatedBy / 校验和 / 锁文件。

所以 starter 不引入清单文件，也不加 `# managed-by` 注释，改用三条各自成立的判据：

| 对象 | 判据 | 结果 |
|---|---|---|
| schema 目录 | `schema.yaml` 的 `version` | 目标 < 源 → 备份后覆盖；相同 → 跳过（**用户改动因此被保护**） |
| `config.yaml` | 有无 `context:` / `rules:` / `operations:` | 无（init 默认）→ 整份写入；有 → **只改 `schema:` 一行** |
| 自有 skill 目录（`openspec-custom-*`） | 逐文件 SHA256 | 一致 → 跳过；不同 → 备份后覆盖 |

受管文件（`openspec-*` skill、`commands/opsx*`）**不在分发范围**：它们绑定 CLI 版本，只能靠
`openspec init` / `openspec update` 生成。安装脚本碰它们，等于用一个项目的 CLI 版本去覆盖另一个。

**关键认识**：`config.yaml` 里真正必须落到目标项目的只有 `schema:` 一行，其余（context / rules /
operations）是用户资产。把"整文件覆盖"降级成"改一行"，"这文件归谁"的问题就消失了——
不需要猜，也不需要额外状态。

另抄了官方两条做法：`-DryRun` 与真跑**共用同一条代码路径**（预览不会说谎）；
重复安装幂等（第二次全 skip）。

### 8.5 实测覆盖

| change | 跑了什么 | 结果 |
|---|---|---|
| `add-duration-parser` | 首次全链路 propose→apply→archive | 6/6，3 个测试 |
| `add-duration-seconds` | 用户自跑，MODIFIED 增量 | 合并干净，5 个场景 |
| `add-duration-days` | 全链路 + 三透镜 review + 红证 | 9 测试；4 条 finding（2 medium 已钉、1 low 已修、1 low 转决策） |
| `add-duration-weeks` | **opencode 独立跑通** | 12 测试；medium 1 + low 1 + rejected 1；F2 追到上一轮 F4 同根因 |

---

## 9. 踩坑记录

| 坑 | 现象 | 处理 |
|---|---|---|
| 中文 Purpose 太短 | archive 时 `carried Purpose is under 50 characters`，`--strict` 失败 | 中文按单字计数，写满约 50 字；已写进 specs instruction |
| 首次红是"模块不存在" | `ERR_MODULE_NOT_FOUND`，不是断言失败 | 允许这种红；补空壳再跑，确认红在断言上 |
| 横向切片诱惑 | 想先写完所有测试再实现 | 模板强制成对，禁止批量 |
| 改内置 skill | 下次 `update` 整篇重写 | 只改 schema / config / 自有 skill |
| profile 被迁移 | `core` → `custom`（workflows 不变） | 无影响；复位用 `openspec config profile core` |
| `update` 改全局配置 | 每次 `--dry-run` 都列 `~/.../openspec/config.json` | 正常，与本项目无关 |
| 中立目录 `.agents/skills/` | 实测 opencode 与 codebuddy 都不加载（探针 skill 没进可用列表） | 放弃中立，改方案 A：各工具目录各一份，命名 `openspec-custom-<功能>` |
| 中文 Why / Purpose 太短 | `Why section must be at least 50 characters`、`carried Purpose is under 50 characters` | 都按字符计数、中文约需 50 字；已同时写进 proposal 与 specs 的 instruction |
| 增量改动的"红灯意外通过" | 加天单位时，1.2 的通用正则顺手让 1.3 的 `1d2h` 直接绿 | 断言保留（非空转），该对切片标 `[RED→绿]` 并记录原因；这是切片粒度问题，不是测试问题 |

---

## 10. 常用命令

```bash
openspec schemas                        # 列出可见 schema 及来源
openspec schema which <name>            # 这个 schema 从哪加载、被谁 shadow
openspec schema validate <name>         # 改完 schema 必跑
openspec schema fork spec-driven <new>  # fork 一份来改
openspec new change <name> --schema <s> # 用指定 schema 建 change
openspec status --change <name>         # artifact 完成度 + blocked 原因
openspec instructions <id> --change <n> # 取某个 artifact 的 prompt
openspec instructions apply --change <n># 取 apply 的 prompt（含进度与 guidance）
openspec validate <name> --strict       # 严格校验 change
openspec validate <spec> --type spec --strict
openspec validate --archived            # 校验已归档的 change
openspec archive <name> -y              # 合并 delta + 搬到 archive/
openspec update --dry-run --json        # 看 update 会动哪些文件
```

---

## 11. 未验证清单

- 自制 schema 的 `apply.instruction` 在**跨 agent / 跨模型**下是否稳定被遵守。已在本仓库 4 个 change
  上跑过（codebuddy 2 次、opencode 1 次），但仍靠自觉，没做过对抗性测试。
- 三透镜 review 在**大代码库**上的信噪比。当前只测过 15 行函数和 12 条测试，子代理没有噪声压力。
- 多文件 `tracks`（`tracks: "**/tasks.md"`）的实际使用手感。
- `stores`（多仓库）与自定义 schema 的组合。
- `verify` 工作流的实际产出质量。
- npm 一键安装包：尚未实现（结论见对话，没落进本文件）。
