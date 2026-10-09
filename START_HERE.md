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

用户于 2026-10-07 明确要求“把 ui 界面功能写好提交上去”。本轮已实现原生 App 与客户端本地闭环；先读 [实现与验收记录](docs/IOS/UI_IMPLEMENTATION.md)，再打开 `ios/Recipe.xcodeproj`。

当前主导航为 Recipes / Plan / Groceries / Profile 四个 Tab。技术工程统一使用 `Recipe` 命名，用户可见品牌使用 Recipe Pals。用户在当前对话中明确要求直接实现的 UI/功能可直接开发，并在 Issue/PR 中记录实际状态。

当前阶段禁止：
- 擅自增加社区、Feed、关注、评论、点赞等功能
- 把“手动录入”提升为主入口
- 在 Share Extension 内执行长耗时 AI 解析
- AI 猜测未出现的精确用量并当作事实保存

总入口 Issue：#1
