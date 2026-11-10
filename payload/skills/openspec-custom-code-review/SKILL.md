---
name: openspec-custom-code-review
description: Review a finished OpenSpec change along three independent lenses (spec, verification, standards), triage the findings, and fix the unambiguous ones with a failing test first. Use after apply completes, before archive, or when the user says "review this change" / "跑一下 review".
---

# OpenSpec Custom Code Review

> 自定义 skill：`openspec-custom-` 前缀表示它不是 OpenSpec 官方生成的受管文件，
> 因此 `openspec update` 不会碰它。

一个 change 的 apply 完成之后、archive 之前跑。三透镜并行找缺陷，分诊成一份清单，
能自动修的修掉（先补失败测试），修不掉的交回给人。

产物固定写到 `openspec/changes/<change>/review.md`，随 change 一起归档。

## 输入

| 参数 | 默认 |
|---|---|
| change 名 | 从对话或 `openspec list` 推断，唯一时直接用 |
| 固定点 | 默认 `HEAD`，即审工作区未提交改动；给了 commit/branch 就审 `git diff <point>...HEAD` |

## 0. 先定范围，再开工

1. `openspec status --change <name> --json`，确认所有 artifact 完成。
   再读 `tasks.md`：**除 review 收口任务之外**的复选框必须全部已勾。
   review 收口任务（模板里的 `## Review 收口` 组，通常是最后一个复选框）由本次 review
   结束时才勾，它**不在**入口条件里——否则"全勾才 review"和"review 完才勾"就成死循环了。
   实现任务没勾完就不要 review，先回去 apply。
2. 确认固定点能解析（`git rev-parse <point>`），且 diff 非空
   （`git diff <point> --stat` 或 `git status --porcelain`）。
   **ref 错或 diff 为空在这里就失败**，不要留到子代理里才发现。
3. 记下 diff 命令和提交列表，后面每个透镜都要用。

## 1. 三透镜并行

三个子代理**同时**发起、前台等待。每个透镜只看自己的轴，
不要替别的透镜下判断，也不要给跨轴的优先级。

透镜 prompt 里只给路径和命令，不要把 diff 正文塞进去——让子代理自己读。

### 透镜 A：spec（实现是否符合契约）

给子代理：change 的 `specs/**/*.md` 路径 + diff 命令。要求：

- 逐个场景核对：`WHEN/THEN` 在代码里是否真的成立。
- 报三类：(a) spec 要求但缺失或只做了一半；(b) diff 里有、spec 没要求（范围蔓延）；
  (c) 看起来实现了但实现是错的。
- 每条结论引用 spec 里的原文行。
- 没有 `specs/`（`skip_specs: true`）时跳过本透镜并记录。

### 透镜 B：verification（改动是否被真测试钉住）

给子代理：diff 命令 + `seams.md` + 测试目录路径。
判定标准全文见 `references/verification-lens.md`，核心一句：

> 对每个改动面，说出最小的真实回归，然后问：**这个回归会让某条断言失败吗？**

不会 → 记一条 gap。同时检查测试质量：同义反复、断言源码文本、只测不抛错、
mock 调用次数、端到端透传但没检查改动结果。

### 透镜 C：standards（是否符合仓库标准）

给子代理：diff 命令 + 仓库里记录编码规范的文件（`CONTRIBUTING.md`、
`docs/` 下的规范、`.editorconfig` 之外的约定）+ `references/standards-baseline.md`。
规则：**仓库文档化的标准永远优先**；baseline 里的 smell 一律是判断而非硬违规；
工具已经强制的（lint、格式、类型）跳过。

### 失败处理

任一透镜失败、超时或返回空：记下它的名字，用剩下的继续，
**最后必须报告"本次 review 不完整"**，不能说成干净通过。

## 2. Triage

等三个透镜全部回来再开始，边收边判会漏。

1. **归一化**：每条 finding 编 `R1`、`R2`…，带 `source`（哪个透镜）、`title`、
   `detail`、`location`。**此时不要合并去重**，会把线索弄丢。
2. **验真**：这条声称的行为真的能发生吗？顺着调用方、上游守卫读，
   尽量给出确定的能 / 不能。给不出证据的，判 `maybe-false`。
   不要因为"和刚否掉的 R3 很像"就否掉 R5——除非两者指向同一处同一行为。
3. **定级**：只看单次发生的后果，不看多稀有、不看好不好修。
   - `high`：数据丢失/损坏、安全暴露、静默算错、无绕法的路径断裂
   - `medium`：坏了但会被发现并能绕过，或影响面有限
   - `low`：外观问题、轻微不便
   - `false`：不成立（附上什么推翻了它）
   - `maybe-false`：证据不足（附上什么能定案）
4. **去重**：按**根因**分组，不按文件位置。同位置可能是两个不同的 bug。
   每组取最高的 verdict，记住成员的 `R` 编号和来源。
5. **拒绝**：`false` 一律拒；`low` 且修复成本大于收益的拒。

## 3. Route

每条去重后的 finding 归入三类之一：

| 路由 | 判据 |
|---|---|
| `patch` | 修法无歧义、不新增公共接口、不靠猜测的状态 |
| `decision_needed` | 需要用户意图才能修对。列出选项各一行 + 推荐哪个及理由 |
| `defer` | 不是本次改动引入的问题 |

判据里的"无歧义"要严格：拿不准就 `decision_needed`，**不许猜着改**。

## 4. Fix（只修 `patch`）

每条 `patch` 必须按红绿走，修复本身也是 TDD：

1. 先写一条能复现该缺陷的测试，运行，确认它失败（红）。这条测试就是回归证据。
2. 再做最小修复，运行，确认变绿，且原有测试仍全绿。
3. 在 `review.md` 里把该条标成 `fixed`，附上测试名和命令。

修复不得改动 `specs/`、`proposal.md`、`seams.md` 的意图段落。
真要改契约，那是 `decision_needed`，交回给人。

## 5. 复跑与收口

修完重跑三透镜，**只审这一轮的修复**。最多两轮。

结束后：

| 状态 | 条件 |
|---|---|
| ✅ 通过 | 没有 open 的 high/medium |
| ⚠️ 有条件通过 | 只剩 `defer` 和已拒绝项 |
| ⛔ 阻塞 | 还有 open 的 high/medium，或任一透镜失败 |

阻塞时不要自行 archive。

## 6. 写 `review.md`

```markdown
# Review: <change>

## Verdict
<通过 / 有条件通过 / 阻塞> — high N / medium N / low N / rejected N
透镜：spec ok / verification ok / standards 失败（原因）

## Findings

### F1 [high] <一行标题>
- 来源：spec + verification
- 位置：`file:line`
- 证据：<能发生，以及会发生什么>
- 路由：patch
- 状态：fixed（回归测试 `test/xxx.test.mjs` "..."）

### F2 [medium] <标题>
- 路由：decision_needed
- 选项：A ...（推荐）／B ...

## 已拒绝
- R3 [false] <标题> — 推翻依据：<...>
```

## 什么不算缺陷

- 编译器 / 类型检查器 / lint 已经保证的
- 本次没碰的代码的既有问题（可以提，但归 `defer`）
- 单纯的"覆盖率低"、"没有测试文件"
- 风格偏好，且仓库没有文档化这条规范
- 没有证据支撑的"这里可能会出问题"

## 反模式

- 把三个透镜的结论揉成一份排序清单 —— 两个轴会互相遮蔽。
- 为了显得有产出而硬凑 low 级 finding。
- 修 `decision_needed` 的项 —— 那是在替用户做决定。
- 修复不带回归测试 —— 下次重构会再漏一遍。
- 复跑超过两轮 —— 说明问题需要人来看。
