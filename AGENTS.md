# 项目约定

## 提交

- 每次修改完成后立即 commit，除非用户明确要求暂不提交，或仍有未解决的失败/冲突要说明。
- 提交前至少跑一遍 `seams.md` 里写明的测试命令，以及 `openspec validate --strict`。
- 提交信息用简体中文，沿用 Conventional Commits 前缀：`feat` / `fix` / `refactor` / `docs` / `test` / `chore`。
- 计划产物（`openspec/`）和 AI 工具配置（`.opencode/`、`.codebuddy/`）与应用代码一起纳入版本控制。

## 工作流

- 遵循 `openspec/config.yaml` 的 tdd-flow：proposal → specs → design → seams → tasks → apply → review → archive。
- 任何实现开始前，必须先有对应的失败测试。
- 测试命令只写在 `seams.md`，`tasks.md` 里引用接缝编号，不重复命令。
