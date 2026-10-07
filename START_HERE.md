# START_HERE

本文件是仓库唯一开发入口。

## 先读顺序

1. `AGENTS.md`
2. `docs/PRODUCT_BASELINE_V1.md`
3. `docs/USER_FLOWS.md`
4. `docs/DESIGN_SYSTEM.md`
5. `docs/UI_DESIGN_APPROVALS.md`
6. `docs/ARCHITECTURE.md`
7. `docs/RECIPE_IMPORT_PIPELINE.md`
8. `docs/DATA_MODEL.md`
9. `docs/DEVELOPMENT_STANDARD.md`
10. `docs/TESTING_RELEASE.md`

## 当前阶段

用户于 2026-10-07 明确要求“把 ui 界面功能写好提交上去”。本轮已实现原生 App 与客户端本地闭环；先读 [实现与验收记录](docs/IOS/UI_IMPLEMENTATION.md)，再打开 `ios/Cook.xcodeproj`。

本轮以 main 的三 Tab 产品范围和已存设计资源为依据，复用 PR #10 的 `IngredientAmount`。历史设计审批表不被追溯改写为已批准；本轮新增 UI、工程和 CI 改动随 PR 交付审阅。

当前阶段禁止：
- 未确认 UI 就直接写正式页面
- 擅自增加社区、Feed、关注、评论、点赞等功能
- 把“手动录入”提升为主入口
- 在 Share Extension 内执行长耗时 AI 解析
- AI 猜测未出现的精确用量并当作事实保存

总入口 Issue：#1
