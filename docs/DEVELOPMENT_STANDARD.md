# Development Standard

## 1. Issues、Todoist Board、PR 与规范文档的边界

- **GitHub Issues** 是需求、Todo、Bug、技术债、测试、验收和交付证据的唯一任务记录；每个可独立交付的任务有独立 Issue 和可验证的 `- [ ]` Checkbox。大需求用父/子 Issue；前置依赖明确关联。
- **[Cook Todoist Board](https://app.todoist.com/app/project/6hj76CCMgwhrRp6m)** 是唯一领取与状态入口，一仓库一个项目、一独立 Issue 一卡片，卡片只包含仓库标识、Issue 编号/链接、PR 链接。采用且仅采用 `Backlog → Ready → In Progress → In Review → Done` 和独立 `Blocked` 栏；**不得用 GitHub Labels、Assignee、聊天记忆或分支作为领取凭证**。
- **领取**：从 Ready 读 Issue/最新代码/PR/依赖 → 二次确认 Ready 且没有竞争开发 → 将卡片移 In Progress → 立即回读确认 → 在 Issue 留下领取会话 ID/UTC/分支后开工。原生 Todoist assignee 不强制。Todoist 状态更新并非原子锁，发现同时领取/不同步必须停止协调；不要无故自建复杂分布式锁。
- **PR**：一个独立交付原则上一 Issue + 一卡片 + 一 PR；PR 提交移动 In Review，完成每条 Todo 立即勾选 Issue 并关联实际 Commit、测试、PR。只在必要测试和验收通过、PR 已合并且 Todo 都完成后移动 Done、回读并关闭 Issue。Todoist Done 卡片保持可见，**只移动栏目，不调用“完成任务”**；部分完成禁止 Done。
- **Markdown**：仅记长期有效需求、架构、技术设计、编码/测试/协作规范，不写任务、Bug、开发进度、临时交接；普通修复不强制更新文档，长期契约确有变化才更新并与 Issue 相互引用。

### GitHub Issue 零上下文十要素（所有功能、Bug、测试、研究均适用）

1. 背景与实际问题；2. 目标与可观察结果；3. 当前代码/已有实现与缺口；4. 真实文件、模块、页面、接口、数据库等修改范围（不适用明确 N/A）；5. 操作流程、输入/输出、交互、边界与异常；6. 项目架构、版本、编码、安全、兼容及禁止修改约束；7. 前置 Issue、关联 PR、设计/技术文档与冲突文件；8. 每条可验证 Checkbox 验收标准；9. 测试步骤/命令/fixture/预期、失败处理和 `NOT RUN`；10. PR/Commit、真实测试证据、GitHub Todo/状态与 Todoist 交付同步。

任何不了解历史聊天的 AI 应能独立读当前 GitHub 与该 Issue 开始实施并客观验收。不得使用“参考上次”之类无上下文指令；不确定的信息写“待核实”及确认方式。达不到十要素的任务留在 Backlog，前置依赖/冲突未解决者不能标 Ready。

## 2. 分支与 Worktree

- main 仅接收 PR。
- 每个 Issue 使用独立分支；并行任务优先独立 worktree。
- 共享 Schema/API 变更先串行冻结，再并行。
- 禁止多个 Agent 同时修改同一个核心文件。

建议分支：
- `codex/<issue>-<slug>`
- `fix/<issue>-<slug>`
- `docs/<issue>-<slug>`

## 3. 产品规划与 UI 开发

产品/功能开发计划的依据是**已经上线并长期运营或商业成功的同类产品**，结合现有开源组件和 Apple/Supabase 能力；先验证对标产品的实际使用做法与许可证，再检查当前代码，禁止按照旧内部执行流程无条件重复造轮子。



UI 实现应遵循 `docs/DESIGN_SYSTEM.md`，并复用当前产品中的页面模式和可用参考资源。

`docs/UI_DESIGN_APPROVALS.md` 用于记录 UI 方向和决策，不构成独立的开发门禁。用户明确要求实现 UI 时，可直接着手；遇到会改变产品范围或用户流程的歧义时，再先澄清。

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

高风险操作需要用户**事先明确授权或已批准的现行需求范围**：真实生产权限/RLS、CI/安全策略改动、破坏性数据迁移/删除、Apple 计费配置、公开用户私人数据和生产部署。UI 的明确需求可直接开发；`SCOPED` 是设计范围，不表示已上线。普通 PR 可由仓库可信轻量自动合并机器人处理，但**自动合并不等于用户体验/运行验收或部署许可**。

## 6. 变更纪律

- 先核验当前代码，再处理审查意见。
- 最小化改动范围。
- 不顺手重构不相关模块。
- 不删除失败测试。
- 不靠注释掩盖未实现逻辑。
- 不提交 secret、真实 token、生产凭据。

## 7. 完成定义

- 每个 Issue 的必要验收 Checkbox 全部通过，测试证据和实际执行环境可查；`NOT RUN` 不得报告为通过。
- 提交并按仓库规则审核/合并关联 PR，解决关键阻塞与相关依赖；纯研究任务可用 Issue 中可验证交付代替无意义 PR。
- 每完成一项 Todo 立即回写 GitHub Checkbox、Commit/PR/测试结果，保持 Todoist 状态一致；PR 提交转 In Review。
- Issue 验收通过后将对应 Todoist 卡片**移动至 Done 栏**，实际回读确认仍为未完成/可见，再关闭 GitHub Issue；父 Issue 等必要子任务完成后关闭。
- 只有长期有效需求、设计或技术规则变更才同步相关 Markdown；普通 Bug 不改规范文档。
- 无权限、领取竞争、数据不一致、外部设备/环境未验证时保留 Issue 与 Todoist 卡片，在 Issue 解释阻塞与恢复条件，禁止虚报完成。
