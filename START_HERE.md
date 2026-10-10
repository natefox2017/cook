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

## 产品和开发约束

以仓库最新 `main` 的原生 Recipe iOS 实现为技术基线；阅读 [历史 UI 方案](docs/IOS/UI_IMPLEMENTATION.md) 仅供设计溯源，功能完成度和验收以最新代码及 Linear Issue 为准。使用 `ios/Recipe.xcodeproj` 构建应用。

当前主导航为 Recipes / Plan / Groceries / Profile 四个 Tab。技术工程统一使用 `Recipe` 命名，用户可见品牌使用 Recipe Pals。经用户批准的 UI/功能仍须先建立或复用 Linear DEV Issue，并从无人领取的 Todo 进入 In Progress，核对负责人、依赖和当前 main 后方可开发。

当前阶段禁止：
- 擅自增加社区、Feed、关注、评论、点赞等功能
- 把“手动录入”提升为主入口
- 在 Share Extension 内执行长耗时 AI 解析
- AI 猜测未出现的精确用量并当作事实保存

唯一任务入口：[Linear DEV Recipe Pals Development](https://linear.app/gengyun/project/recipe-pals-development-8c015c72cb6a)。

## 当前任务领取入口

只从 [Linear DEV Recipe Pals Development](https://linear.app/gengyun/project/recipe-pals-development-8c015c72cb6a) 读取任务、Todo、Bug、测试及验收，不再查询旧 GitHub Issues 或过期 Markdown 快照作为待办。开工前核对最新 main、开放 PR、Linear Issue 依赖及负责人；只有无负责人、依赖已满足的 Todo 可以领取。领取后设置 In Progress、确认 assignee 并立即回读；提交独立 PR 后进入 In Review，合并且必要验收通过才标记 Done。

旧 GitHub Issue 和历史审核快照只用于证据溯源，详见 [DEV-40](https://linear.app/gengyun/issue/DEV-40)；发布时间和测试结果以 [DEV-49](https://linear.app/gengyun/issue/DEV-49) 为准。
