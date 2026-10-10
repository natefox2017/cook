## 对应 Issue / Todo
Refs #

- 已完成的 Todo ID：T__
- 剩余 Todo ID：T__（如无填 None）
- 完成的 Todo 已在 Issue 勾选并附上 PR/测试证据：是 / 否

## GitHub Projects Kanban 领取信息（必填）
- Project URL：
- Project item URL：
- Claim ID（独立会话，不只填 GitHub 用户名）：
- Claimed At（UTC）：
- 领取后再次读取并确认独占：PASS / BLOCKED
- 当前看板状态：In Review / Blocked / Done
- 本次处理 Todo 后已同步 Kanban：PASS / BLOCKED

> GitHub Projects Kanban 是**唯一领取入口**：未在 Project 中领取且回读确认成功，不允许提交业务开发 PR。Issue 关联、评论、标签及 GitHub assignee 不能代替 Kanban 领取。仅为创建看板而进行的 #299 治理引导 PR 属一次性例外，不能借此开展产品功能。

> 非需求变更（Bug、UI 修复、性能、安全、重构、测试、运维）必须关联 GitHub Issue；优先复用已有 Issue，没有才新建。修复原因、进度、验收证据与未完成项写在 Issue，不另建 Markdown 记录。

> 仅当 Issue 的**完整约定验收范围**已满足、允许结案时，才改为 `Closes #...`；只有源码/设计文档落地但真实运行仍阻塞时用 `Refs #...`，不要触发自动关闭。

## 改动
-

## 文件范围
-

## 验证
- [ ] 单元/集成测试
- [ ] 每完成一项 Todo 已立即勾选 Issue，并同步 Projects Kanban 的状态/领取字段；未执行的测试如实写 NOT RUN
- [ ] 无无关重构

> **文档不是每次 PR 的必选修改。** 只有用户确认需求、设计规范或长期接口契约发生变化，或明确要求修改文档时，才更新对应需求文档；普通修 Bug/优化不修改 `docs/`、README。

## UI
- [ ] 非 UI 改动
- [ ] 已核对 `docs/UI_DESIGN_APPROVALS.md` 对应 UI 状态（APPROVED / SCOPED / PENDING），不把用户明确要求开发误当成额外审批门禁
- 设计资源 ID：

## 运行证据（如实写 NOT RUN）
- 静态/单元验证：
- Xcode / signed iPhone：
- 后端 / staging / 生产：
- 新功能是否仍 feature-gated（未交付时不得露出可点击死入口）：

## 高风险检查
- [ ] 无权限/RLS变化
- [ ] 无数据库破坏性迁移
- [ ] 无 CI/发布策略变化
- [ ] 无 secret/凭据

如勾选不了以上任意一项，请在 PR 正文解释并走人工确认。

## 自动合并交付约定
- **已领取且完成实现 Todo 的任务才提交普通 PR**。提交前确认 GitHub Projects 项目状态为 `In Review`、Claim ID 为当前会话并已更新 Issue 的 Todo。自动合并机器人主要校验代码/PR条件，不会替你证明 Projects 已领取或验收；如未能读写 Projects，应停止业务开发，不能借自动合并绕过。
- 若代码还未完成，保留 Draft；完成后由提交者根据 `AGENTS.md` 的完成标记或标签让机器人自动转为 Ready。不要提前把未完成任务标记为可合并。
- 本仓库轻量自动合并并非 Xcode / 真机测试通过证明；PR 正文必须写清已跑和未跑的测试。
