# Development Standard

## 1. 任务管理：Linear Issues + Board / GitHub PR / 规范 Markdown

- **[Linear Cook 项目](https://linear.app/gengyun/project/cook-recipe-pals-development-8c015c72cb6a) 的 Issue** 是需求、Todo、Bug、测试、依赖、验收及证据唯一任务源；Board 是领取、负责人和进度唯一事实来源。**GitHub 私有仓库**只存代码、Commit、分支、CI、PR、审查和合并。**Markdown**只记长期有效的产品、设计、架构、数据/API、工程标准；不管理任务、Bug、开发进度与临时测试记录。
- 独立任务一张 Linear Issue、原则上一 PR；大需求用父/子 Issue 管理，建立前置依赖。优先小而完整、低耦合可并行交付；先复用现有能力、成熟开源方案及许可证，避免不同 AI 同时修改同一文件。
- **六态规范**：Backlog → Ready → In Progress → In Review → Done，另有 Blocked；只有 Ready 且未分配负责人、前置依赖已满足可领取。领取前查最新 main/分支/PR/Linear Issue，设置 Linear assignee 与 In Progress 后**立即回读**核实；发生冲突立即停止。Linear 状态更新不是原子互斥锁。team 未配置 Ready/Blocked 时，留 Backlog 并在迁移工作 GEN-40 标注阻塞，不得用 Todo/Canceled 替代。
- 完成每项 Todo 当即更新 Linear Checkbox、Commit/PR/测试证据。PR 创建关联 `GEN-n` 并转 In Review；PR 合并只代表代码交付，不代表验收 Done。只有所有必要测试/验收通过后，更新 Done 并回读；父 Issue 等必要子 Issue 完成。Blocked 记原因、恢复条件和当前分支。原 GitHub Issue 仅历史索引，不得继续新建任务或使用 Todoist 领取。

### 零上下文任务的十项必备信息

1. 背景/现象与业务原因。
2. 目标/预期可观察交付。
3. 当前实现：最新代码路径、相关 PR、已完成与缺少的功能。
4. 修改范围：准确模块、文件、页面、接口、数据模型/数据库（无则写 N/A）。
5. 行为需求：完整业务流程、输入/输出示例、交互、边界与异常处理。
6. 技术约束：架构、编码、兼容、安全、禁止修改及可复用组件/开源许可。
7. 依赖：前置 Linear Issue、关联 PR、长期需求/技术文档及文件冲突。
8. 验收：能逐项复现且明确预期的 `- [ ]` Checkbox。
9. 测试：真实命令、fixture、场景、PASS/FAIL/NOT RUN、失败处理。
10. 交付：对应分支/PR/Commit、证据、Todo 与 Linear 状态同步/交接。

任何没有历史聊天记忆的 AI 都必须能凭 Linear Issue、当前 GitHub main 和长期规范单独实施、测试、验收。不确定信息写 `待核实` 及核实方式；内容不全不得 Ready。普通 Bug/测试修复不要无故修改 Markdown 文档；规范或契约确实改变时再更新长期文档并引用 Linear Issue。

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

`docs/UI_DESIGN_APPROVALS.md` 用于记录 UI 方向和决策，不构成独立的视觉审批门禁。用户明确提出 UI 需求时无须再次申请设计批准，但**仍必须先创建/复用 Cook Linear Issue，按 Linear Board Ready → In Progress 完成负责人和状态回读后才能修改代码**；只有需求实质歧义才需澄清。

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

高风险操作需要用户**事先明确授权或已批准的现行需求范围**：真实生产权限/RLS、CI/安全策略改动、破坏性数据迁移/删除、Apple 计费配置、公开用户私人数据和生产部署。UI 的明确需求仅免除重复设计审批，**不免除 Linear Issue 与 Board 领取**；`SCOPED` 是设计范围，不表示已上线。普通 PR 可由仓库可信轻量自动合并机器人处理，但**自动合并不等于用户体验/运行验收或部署许可**。

## 6. 变更纪律

- 先核验当前代码，再处理审查意见。
- 最小化改动范围。
- 不顺手重构不相关模块。
- 不删除失败测试。
- 不靠注释掩盖未实现逻辑。
- 不提交 secret、真实 token、生产凭据。

## 7. 完成定义

- Linear Issue 的必要验收 Checkbox 全部通过，测试命令、实际环境及 PASS/FAIL/NOT RUN 证据可核实。
- 关联 PR 合并并满足所有必要依赖；不需要改代码的研究可由 Linear Issue 中独立验证的交付物结案。
- 每项 Todo 立即回写 Linear，不在 GitHub Issues 或 Markdown 重复记录任务。
- PR 打开进入 In Review；合并后仍需验收。全部完成才转 Linear Done，并回读确认；父任务待全部必要子 Issue 完成。
- 仅长期产品/技术契约实际变化时才编辑相关 Markdown；任何未测试、不具备环境或权限的情况不得宣称 Done。
- GitHub 与 Linear 状态不一致、并发领取竞争或 Ready/Blocked 未配置时必须停止相关任务并记录实际阻塞，不得使用 GitHub Labels 或旧 Todoist 作为替代领取入口。
