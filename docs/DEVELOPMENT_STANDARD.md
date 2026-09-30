# Development Standard

## 1. GitHub 是项目中枢

需求、任务、代码、PR、版本与验收记录全部落 GitHub。

每个开发 Issue 必须包含：
- 背景/目标
- 输入
- 输出
- 允许修改的文件范围
- 验收标准
- 依赖
- 相关设计资源 ID
- 测试要求

## 2. 分支与 Worktree

- main 仅接收 PR。
- 每个 Issue 使用独立分支；并行任务优先独立 worktree。
- 共享 Schema/API 变更先串行冻结，再并行。
- 禁止多个 Agent 同时修改同一个核心文件。

建议分支：
- `codex/<issue>-<slug>`
- `fix/<issue>-<slug>`
- `docs/<issue>-<slug>`

## 3. UI 开发

UI 代码之前必须检查：
- `docs/UI_DESIGN_APPROVALS.md`
- `docs/DESIGN_ASSETS.md`

没有 APPROVED 设计：
- 可以建 domain/service/test 骨架
- 可以写无视觉耦合的逻辑
- 不允许自由设计正式页面

## 4. 接口先行

并行开发前优先冻结：
- import job state machine
- API request/response schema
- domain model
- error code
- storage contract

不要让多个 Agent 各自发明字段。

## 5. PR

PR 必须包含：
- 做了什么
- 为什么
- 影响范围
- 验证方式
- 截图/录屏（UI）
- 对应 Issue

默认 Squash。

必须人工确认：
- UI/设计
- 权限/RLS
- CI
- 安全策略
- 数据迁移
- 删除/破坏性变更

## 6. 变更纪律

- 先核验当前代码，再处理审查意见。
- 最小化改动范围。
- 不顺手重构不相关模块。
- 不删除失败测试。
- 不靠注释掩盖未实现逻辑。
- 不提交 secret、真实 token、生产凭据。

## 7. 完成定义

Issue “代码写完”不等于完成。

必须满足：
- 验收项全部通过
- 测试通过
- 文档同步
- 无未解释的行为变化
- PR 已审查/按规则确认
