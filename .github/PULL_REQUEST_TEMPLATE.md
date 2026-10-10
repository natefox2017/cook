## GitHub Issue / 可独立交付的 Todo

Refs #

- GitHub Issue URL：
- 已完成 Todo 编号（需在 Issue 逐项 `[x]` 并附 commit/test）：
- 未完成 Todo 编号（没有写 None；部分完成不得 Done）：
- 本 PR 是否只对应一个独立交付 Issue：是 / 否（如否说明耦合原因）：

## 唯一 Todoist Board 领取与状态（必填）

- 官方看板：[Cook — Development Kanban](https://app.todoist.com/app/project/6hj76CCMgwhrRp6m)
- 对应**唯一** Todoist 卡片链接：
- 领取前卡片状态：Ready
- 领取操作：Ready → In Progress，随后 `fetch_object` 回读：PASS / BLOCKED
- Claim / 会话标识（记在 GitHub Issue，并非原生 Todoist assignee）：
- 领取时间 UTC：
- 已核对最新默认分支/分支/Issue/PR、依赖及其他 AI 任务：PASS / BLOCKED
- PR 提交后将 Todoist 卡片移至 **In Review** 并回读状态：PASS / BLOCKED
- 本次提交后 Issue Checkbox/PR 链接与 Todoist 卡片同步：PASS / BLOCKED

> 仅可从 Todoist **Ready** 领取；Backlog、In Progress、In Review、Blocked、Done 都不能直接领取。移动/回读不是原子互斥锁；如发现冲突，立即停止并在 Issue 记下恢复方式。GitHub Issue labels/assignee、聊天记录或分支名不能代替真实 Todoist 领取。
> Todoist 的 **Done 是 Section，不是任务完成操作**：验收通过后只移动到 Done，并回读 `checked=false`、保留卡片可见；严禁调用 Todoist 任务完成。

## 改动摘要与边界

- 背景/现有实现（按本次 Issue，不能依赖历史聊天）：
- 本次做了什么（输入/输出、边界/异常）：
- 修改的真实路径 / API / 数据结构：
- 禁止修改/兼容性及已核对的相关需求或技术规范：
- 已检查的可复用代码/成熟开源方案及许可证（非新增功能填 N/A）：

## 独立验收 / 运行证据

- 已执行的准确测试命令、fixture、环境与 PASS/FAIL：
- 未执行的测试（明确 **NOT RUN**）、设备/staging/production 前置要求：
- 必要设计稿状态与资源 ID（非 UI 填 N/A）：
- UI 截图 / 录屏（非 UI 填 N/A）：
- 是否产生新用户可见文字以及多语言要求：
- 原行为回归、失败处理和待审核项：

## 安全与风险检查

- [ ] 未泄露 secret、令牌和个人数据
- [ ] 不包含未授权生产数据库/RLS/权限、计费、CI/发布策略、破坏性迁移（涉及任何一项必须说明并提前获得授权）
- [ ] 没有无关重构、恢复旧分支覆盖已合并功能或删除失败测试
- [ ] 对每个已完成 Todo，Issue Checkbox、实际测试及 Commit/PR 证据已即时同步
- [ ] 已向 Todoist 卡片补上本 PR 链接并更新 In Review 后实际回读

## Done 后操作（当前 PR 合并≠全部验收）

- 所有必要测试、审核和验收通过、PR 合并、Issue 的全部必要 Todo 都被 `[x]` 勾选，才允许将 Todoist 卡片**移动到 Done Section**。
- Done 卡片保持 Todoist **未完成** 状态、可见；回读验证后关闭 GitHub Issue；必要子 Issue 未全完成时不能关闭父 Issue。
- 尚欠验收/存在阻塞则保持 **In Review / Blocked** 并更新 Issue，不得宣称整个任务完成。

## 原项目 PR/CI 约定（保留）

- `main` 只接受独立分支 PR；依仓库可信轻量自动合并流程处理符合条件的普通 PR，不把自动合并当成 Xcode/真机/生产验收证明。
- 真正未完成的工作使用 Draft；仅在完成实施任务后，按 `AGENTS.md` 指定的 `<!-- auto-ready: complete -->` 或 `auto-ready` 标签允许自动转 Ready，不得提前设置。
- PR 前同步最新 main，核对入门、品牌、导航、订阅合同；不得通过旧分支覆盖它们。不要为普通 Bug 强制更新 docs/README；长期需求/技术规范变化时才更新并相互引用 Issue。
- 仅当 Issue 的**完整约定范围已经满足并可以结案**才使用 `Closes #...`；部分源代码交付使用 `Refs #...`。
