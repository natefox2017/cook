# AGENTS.md

## 1. 真相源

- 产品范围：`docs/PRODUCT_BASELINE_V1.md`
- 用户流程：`docs/USER_FLOWS.md`
- UI 方向：`docs/DESIGN_SYSTEM.md`
- UI 审批：`docs/UI_DESIGN_APPROVALS.md`
- 技术架构：`docs/ARCHITECTURE.md`
- 导入协议：`docs/RECIPE_IMPORT_PIPELINE.md`
- 数据结构：`docs/DATA_MODEL.md`
- 开发协作：`docs/DEVELOPMENT_STANDARD.md`

出现冲突时以上文件优先，禁止从旧聊天、旧截图或旧分支自行推断新需求。

## 2. UI 门禁

所有 UI 相关功能必须：
1. 先生成/提供设计图或现有参考图。
2. 在 `docs/UI_DESIGN_APPROVALS.md` 登记。
3. 用户明确回复“确认”后，状态改为 APPROVED。
4. 只有 APPROVED 页面才允许写正式 UI。

没有设计图时先补设计图，不允许 AI 自由发挥页面。

## 3. 产品硬规则

- 正常收藏路径：第三方分享 → 选择 Cook → “已收下” → 返回原 App。
- 分享扩展只负责接收和入队，不等待完整解析。
- 正常导入不要求用户逐条确认；只有异常/低置信度信息进入“待完善”。
- 手动录入保留，但属于兜底入口。
- 原始来源 URL、来源平台、作者/标题（可取得时）必须保留。
- 不做社区 Feed、用户发帖、关注、点赞、评论、达人主页。
- AI 不得把“适量/少许/未知”伪造成精确克数。

## 4. 开发规则

- GitHub Issue 是任务入口；每个 Issue 明确输入、输出、文件范围、验收标准和依赖。
- 禁止直接在 main 上开发；使用独立分支/Worktree。
- 共享接口/Schema 先冻结，再并行开发。
- PR 默认 Squash；UI、设计、CI、权限、安全相关改动必须人工确认。
- 修复审查问题前先在当前代码中复现/确认，禁止照单全改。
- 不删除失败测试来“修 CI”。

## 5. 代码边界

V1 推荐：
- iOS：SwiftUI
- Share Extension：原生 iOS Share Extension
- 后端：Supabase Postgres + Edge Functions
- 异步任务：Supabase Queues / pgmq
- 文件：Supabase Storage
- AI：OpenAI-compatible provider router

除非 Issue 明确要求，不自行引入第二套 UI 框架、第二个数据库或第二套队列。
