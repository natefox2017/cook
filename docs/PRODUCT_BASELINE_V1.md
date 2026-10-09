# 产品基线 V1

## 1. 产品定位

Recipe 是个人食谱收集与烹饪工具。

核心价值：
> 把用户在第三方平台刷到的做饭内容，以接近“收藏一次视频”的成本，自动变成可以直接照着做的结构化食谱。

产品路径参考已经长期运营的 ReciMe 与 Recipe Keeper 的共同模式：
- 外部内容导入
- 私人食谱库
- 购物清单
- 做饭使用
- 简单膳食计划

V1 不建设社区。

## 2. 第一优先级

### P0
- iOS Share Extension 导入链接/文本/图片
- App 内粘贴链接导入
- 异步 AI 食谱解析
- 食谱库
- 待完善
- 食谱详情
- 编辑食谱
- 做饭模式
- 搜索
- 收藏
- 购物清单
- 来源追溯
- 重复食谱检测

### P1
- 截图/拍照导入
- 粘贴整段文字
- PDF/相册导入
- 简单周计划
- 份量换算
- 计时器

### 明确保留但降级
- 手动创建食谱

### V1 不做
- Feed
- 发帖
- 关注/粉丝
- 点赞
- 评论
- 公开主页
- 达人体系
- 社区推荐流
- 用户之间的公开食谱市场

## 3. 导航

当前 V1 底部四个主 Tab（以最新已合并客户端实现为准）：
1. Recipes（食谱）
2. Plan（周计划）
3. Groceries（购物清单）
4. Profile（我的）

原始三 Tab / 周计划二级入口是已过期的早期规划。以 `ios/Recipe/RecipeApp.swift` 四 Tab 和已批准的原生 Liquid Glass 方案（UI-016/017）为准，避免后续代理依据旧流程重写导航。


### 2026-10-09 用户明确批准的下一阶段扩展（**尚未完成**）

原本仅供自己收藏的产品定位继续生效，但用户已经授权规划**自愿的单菜分享**，不代表允许公开整个食谱库、建社区或公开用户主页。

- P0：证据可追溯的 AI 对话生成与食材智能替换，可保存草稿、确认差异、手动编辑。任务 [#238](https://github.com/natefox2017/cook/issues/238) / [#241](https://github.com/natefox2017/cook/issues/241)。
- P1：合法可访问视频/音频/关键帧解析与多菜识别；被拒绝、登录墙/DRM/不合法来源一律保留原始链接并 fallback。任务 [#239](https://github.com/natefox2017/cook/issues/239) / [#240](https://github.com/natefox2017/cook/issues/240)。
- P0：扩充专业 Recipe 详情可选字段、UI 与新按钮；不伪造难度、营养、含糊用量。任务 [#247](https://github.com/natefox2017/cook/issues/247) / [#248](https://github.com/natefox2017/cook/issues/248)。
- P0：用户主动授权才可公开**单个**食谱快照；生成精美长图+二维码+可点击 URL，受限只读 Web 供未安装者看步骤和 App 下载入口。任务 [#242](https://github.com/natefox2017/cook/issues/242) / [#243](https://github.com/natefox2017/cook/issues/243) / [#244](https://github.com/natefox2017/cook/issues/244)。
- P1/P2：自愿邀请码归因 [#245](https://github.com/natefox2017/cook/issues/245)，奖励方案 [#246](https://github.com/natefox2017/cook/issues/246) 需后续审批与反作弊；不是承诺无许可逐人跟踪 App Store 安装。

这里新增的 Web 仅是公开共享食谱的**只读落地页**，不是完整 Web 客户端；仍不做社区 feed、粉丝、公开用户主页。具体竞品和合规约束见 [ROADMAP.md](ROADMAP.md) 与 [产品专题方案](PRODUCT/RECIPE_PUBLIC_SHARING_V1.md)。

### V1 食谱导出（D3 已确认）

- Profile 与 Settings → Data & Privacy 均提供 recipe-only `recipepouch.recipes` v1 JSON 与可在浏览器离线打开的 HTML。
- JSON 保留原始来源、原始用量、食谱详情、Favorites、Collections 及关系；HTML 仅输出已保存的食谱文字内容，明确不附带照片、购物、计划和设备设置。
- 原有全本地库 JSON 快照可以作为额外导出选项，但不得称为可恢复备份；当前没有 App 内恢复导入功能。
- 用系统文件导出实现保存、取消及失败反馈，不另建导出后端。

## 4. 成功标准

- 正常导入主动操作最多 2 次：分享 + 选择 App。
- 分享扩展不要求选分类、改菜名或等待 AI。
- AI 信息完整时自动入库。
- AI 信息不完整时仍保存，并精确标记待确认字段。
- 用户任何时候可返回原始来源核对。
- 导入失败必须提供可继续的降级路径，而不是只有“重试”。

## 5. 关键状态

导入任务：
- received
- queued
- extracting
- parsing
- validating
- completed
- needs_review
- failed

食谱：
- ready
- needs_review
- archived
