# 项目约定

## 提交

- 每次修改完成后立即 commit，除非用户明确要求暂不提交，或仍有未解决的失败/冲突要说明。
- 提交前至少跑一遍 `seams.md` 里写明的测试命令，以及 `openspec validate --all --strict`。
  注意：**不带 `--all` 的 `openspec validate --strict` 什么都不校验**，它打印
  `Nothing to validate` 并返回 0——那是假绿，别拿它当门禁。
- 提交信息用简体中文，沿用 Conventional Commits 前缀：`feat` / `fix` / `refactor` / `docs` / `test` / `chore`。
- 计划产物（`openspec/`）和 AI 工具配置（`.opencode/`、`.codebuddy/`）与应用代码一起纳入版本控制。

## 工作流

- 遵循 `openspec/config.yaml` 的 tdd-flow：proposal → specs → design → seams → tasks → apply → review → archive。
- 任何实现开始前，必须先有对应的失败测试。
- 测试命令只写在 `seams.md`，`tasks.md` 里引用接缝编号，不重复命令。
- **review 结论要过门禁**：勾 `tasks.md` 的 review 收口框、或 archive 之前，跑
  `node scripts/check-review.mjs openspec/changes/<change>/review.md`，退出码必须为 0。
  CLI 只数复选框、不读 `review.md` 的 verdict，这个脚本是唯一能把结论变成可执行判据的环节。
- TDD 逐切片提交会留下"当时还不符 spec"的中间态提交，这是正常的：不要 checkout 中间版本当可用版本。
