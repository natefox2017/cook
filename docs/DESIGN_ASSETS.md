# Cook 食谱 App — 页面说明与设计图索引

更新日期：2026-09-30

建议仓库位置：`docs/DESIGN_ASSETS.md`

## 仓库页面编号与图片索引

本仓库的正式 UI 页面编号以 [UI_DESIGN_APPROVALS.md](UI_DESIGN_APPROVALS.md) 为准。下表把本目录的图片内容对应到当前页面登记；状态均沿用审批表，本文不把任何页面标为已确认。

| 图片索引 | 图片内容 | 仓库页面 ID | 当前审批状态 |
| --- | --- | --- | --- |
| IMG-001 | 推荐首页 | 暂无对应；仓库默认首页为食谱库 | 范围待核对 |
| IMG-002 | 我的食谱 | UI-002 食谱库 | PENDING |
| IMG-003 | 食谱详情 | UI-005 食谱详情 | PENDING |
| IMG-004 | 烹饪模式 | UI-006 做饭模式 | PENDING |
| IMG-005 | 添加食谱菜单 | UI-003 添加食谱菜单 | PENDING |
| IMG-006 | 购物清单 | UI-007 购物清单 | PENDING |
| IMG-007 | 个人中心 | UI-009 我的/设置 | PENDING |

其余审批页面（首次启动/导入教学、待完善、简单周计划、Share Extension 成功/失败）在此 Google Drive 图集中没有独立对应图。开发前必须按审批表取得明确确认。

## 资源登记规则

- 未确认设计图不得作为正式 UI 开发输入；审批状态以 `docs/UI_DESIGN_APPROVALS.md` 为准。
- 同一页面更新时替换原资源，避免多个平行权威版本。
- 本文只登记可见内容、文件位置和页面对应关系，不把 PENDING 改为 APPROVED。
- 图片索引编号 IMG 与审批表 UI 编号分开使用，按上表映射。

## 资源入口

- [项目 Google Drive 根目录](https://drive.google.com/drive/folders/1HoQGZZQ9jsrAHXljJI0WtlPclLtT4GdQ)
- [design_assets 目录](https://drive.google.com/drive/folders/1GyU1BraeKQEzwO8s-rCZP0IHqysmwMop)
- [ios-v1-final 页面设计图目录](https://drive.google.com/drive/folders/1fl1WncejwGDad5jbbOcNjmaIKmEOkbVk)
- 云盘相对目录：`design_assets/ios-v1-final/`

本索引覆盖以上目录当前实际存在的 7 张页面设计图。页面说明依据图片可见内容整理；交互说明用于解释入口，不代表相关代码已实现。文件名中的 final 不单独作为用户审核通过的证据；开发前仍需核对对应设计的确认记录。

## 页面与设计图对应表

| 页面编号 | 页面 | 说明 | 云盘原始文件名 | 设计图地址 |
| --- | --- | --- | --- | --- |
| IMG-001 | 首页 | 发现推荐食谱并进入分类、已保存食谱和季节合集。 | `UI-001-home-final.png` | [查看设计图](https://drive.google.com/file/d/1CeE7hr0D0ltZ_MMna8RCQRaWvz7Y00mG/view) |
| IMG-002 | 我的食谱 | 集中浏览、搜索和筛选已保存食谱。 | `UI-002-recipes-final.jpeg` | [查看设计图](https://drive.google.com/file/d/1R0FHplovG_ifhgwba3FmVCcGCbbmqzUG/view) |
| IMG-003 | 食谱详情 | 查看单个食谱的介绍、食材和步骤，并开始烹饪。 | `UI-003-recipe-detail-final.jpeg` | [查看设计图](https://drive.google.com/file/d/1zUSkURsiTX5NmfP8EUiORJ7Tj7nroOXS/view) |
| IMG-004 | 烹饪模式 | 按步骤完成烹饪，并使用当前步骤的计时器。 | `UI-005-add-recipe-final.jpeg` | [查看设计图](https://drive.google.com/file/d/1sD7UYc9egFmbXoH4QuqWqIvVtgkDJcf2/view) |
| IMG-005 | 添加食谱 | 提供链接导入、拍照、相册导入和手动创建食谱的入口。 | `UI-004-cooking-mode-final.jpeg` | [查看设计图](https://drive.google.com/file/d/1CBJH0G8nAfdh4vc99Q39OwZo8tszNaMk/view) |
| IMG-006 | 购物清单 | 按食材类别查看购物条目和采购状态。 | `UI-006-groceries-final.jpeg` | [查看设计图](https://drive.google.com/file/d/1rmiLcW9bzT5fqKCqsqQH6wqbl21LsNis/view) |
| IMG-007 | 个人中心 | 展示账户资料及个人功能、偏好和账户操作入口。 | `UI-007-profile-final.jpeg` | [查看设计图](https://drive.google.com/file/d/1L7GEiFZlWZMUwXrVwL72N3wKeeK8IFdn/view) |

## 文件名与图片内容不一致

实际打开图片后发现以下两项错位。本索引按图片内容建立关联，未修改云盘原文件。

| 云盘文件名 | 实际图片内容 | 本文对应页面 | 建议纠正后的名称 |
| --- | --- | --- | --- |
| `UI-004-cooking-mode-final.jpeg` | Add a Recipe，添加食谱 | IMG-005 | `UI-005-add-recipe-final.jpeg` |
| `UI-005-add-recipe-final.jpeg` | Cooking Mode，烹饪模式 | IMG-004 | `UI-004-cooking-mode-final.jpeg` |

重命名时按 Drive 文件 ID 辨认原文件，保留本文对应关系，避免只按名称替换而互相覆盖。

## 逐页说明

### IMG-001 首页

**页面用途：** 发现推荐食谱并进入分类、已保存食谱和季节合集。

**设计内容：** 大幅推荐食谱照片；Cook 品牌与搜索、头像入口；推荐菜名、用时、难度及 Open Recipe；分类横向列表；Recently Saved；In Season Now；底部导航。

**主要交互：** 推荐卡片和已保存卡片进入食谱详情；分类与合集入口进入对应列表。

**设计图：** [UI-001-home-final.png](https://drive.google.com/file/d/1CeE7hr0D0ltZ_MMna8RCQRaWvz7Y00mG/view)

**Google Drive 目录：** [design_assets/ios-v1-final](https://drive.google.com/drive/folders/1fl1WncejwGDad5jbbOcNjmaIKmEOkbVk)

**云盘相对路径：** `design_assets/ios-v1-final/UI-001-home-final.png`

**Drive 文件 ID：** `1CeE7hr0D0ltZ_MMna8RCQRaWvz7Y00mG`

### IMG-002 我的食谱

**页面用途：** 集中浏览、搜索和筛选已保存食谱。

**设计内容：** My Recipes 标题；搜索框；All、Meals、Desserts、Favorites 筛选；食谱数量与 Sort；双列食谱卡片、收藏按钮、用时和难度；Recipes 导航选中。

**主要交互：** 食谱卡片进入详情；搜索、筛选、排序作用于食谱列表；收藏按钮切换收藏状态。

**设计图：** [UI-002-recipes-final.jpeg](https://drive.google.com/file/d/1R0FHplovG_ifhgwba3FmVCcGCbbmqzUG/view)

**Google Drive 目录：** [design_assets/ios-v1-final](https://drive.google.com/drive/folders/1fl1WncejwGDad5jbbOcNjmaIKmEOkbVk)

**云盘相对路径：** `design_assets/ios-v1-final/UI-002-recipes-final.jpeg`

**Drive 文件 ID：** `1R0FHplovG_ifhgwba3FmVCcGCbbmqzUG`

### IMG-003 食谱详情

**页面用途：** 查看单个食谱的介绍、食材和步骤，并开始烹饪。

**设计内容：** 顶部菜品照片、返回和保存入口；菜名、用时、份数、难度、简介；Ingredients 食材缩略图及数量；Steps Preview；Start Cooking。

**主要交互：** 返回来源页面；Start Cooking 进入烹饪模式；See All 展开或进入完整食材、步骤视图，其具体展示方式需补充设计。

**设计图：** [UI-003-recipe-detail-final.jpeg](https://drive.google.com/file/d/1zUSkURsiTX5NmfP8EUiORJ7Tj7nroOXS/view)

**Google Drive 目录：** [design_assets/ios-v1-final](https://drive.google.com/drive/folders/1fl1WncejwGDad5jbbOcNjmaIKmEOkbVk)

**云盘相对路径：** `design_assets/ios-v1-final/UI-003-recipe-detail-final.jpeg`

**Drive 文件 ID：** `1zUSkURsiTX5NmfP8EUiORJ7Tj7nroOXS`

### IMG-004 烹饪模式

**页面用途：** 按步骤完成烹饪，并使用当前步骤的计时器。

**设计内容：** 顶部菜品照片、返回与更多入口；菜名、用时和难度；步骤进度（图示 Step 3 of 6）；当前步骤标题与说明；03:00 计时器、暂停和停止；Previous 与 Next Step。

**主要交互：** 前后按钮切换步骤；计时器提供暂停、停止操作；更多菜单和完成状态的具体界面尚未在本图展示。

**设计图：** [UI-005-add-recipe-final.jpeg](https://drive.google.com/file/d/1sD7UYc9egFmbXoH4QuqWqIvVtgkDJcf2/view)

**Google Drive 目录：** [design_assets/ios-v1-final](https://drive.google.com/drive/folders/1fl1WncejwGDad5jbbOcNjmaIKmEOkbVk)

**云盘相对路径：** `design_assets/ios-v1-final/UI-005-add-recipe-final.jpeg`

**Drive 文件 ID：** `1sD7UYc9egFmbXoH4QuqWqIvVtgkDJcf2`

### IMG-005 添加食谱

**页面用途：** 提供链接导入、拍照、相册导入和手动创建食谱的入口。

**设计内容：** Add a Recipe 标题；链接输入框与 Import；Take a Photo；Import from Photos；Create Manually；底部中央加号入口。

**主要交互：** 链接导入提交所填地址；拍照与相册入口选择图像；手动入口进入编辑表单。图中网站名称仅为设计示例，不代表已验证支持。

**设计图：** [UI-004-cooking-mode-final.jpeg](https://drive.google.com/file/d/1CBJH0G8nAfdh4vc99Q39OwZo8tszNaMk/view)

**Google Drive 目录：** [design_assets/ios-v1-final](https://drive.google.com/drive/folders/1fl1WncejwGDad5jbbOcNjmaIKmEOkbVk)

**云盘相对路径：** `design_assets/ios-v1-final/UI-004-cooking-mode-final.jpeg`

**Drive 文件 ID：** `1CBJH0G8nAfdh4vc99Q39OwZo8tszNaMk`

### IMG-006 购物清单

**页面用途：** 按食材类别查看购物条目和采购状态。

**设计内容：** Groceries 标题；All Lists 与 Filter；条目和来源食谱数量摘要；Produce、Proteins、Pantry 分组；食材图片、名称、数量、勾选圆圈与右侧箭头；Groceries 导航选中。

**主要交互：** 切换清单、筛选条目、展开或收起分组、勾选采购状态；条目详情界面需单独补充。

**设计图：** [UI-006-groceries-final.jpeg](https://drive.google.com/file/d/1rmiLcW9bzT5fqKCqsqQH6wqbl21LsNis/view)

**Google Drive 目录：** [design_assets/ios-v1-final](https://drive.google.com/drive/folders/1fl1WncejwGDad5jbbOcNjmaIKmEOkbVk)

**云盘相对路径：** `design_assets/ios-v1-final/UI-006-groceries-final.jpeg`

**Drive 文件 ID：** `1rmiLcW9bzT5fqKCqsqQH6wqbl21LsNis`

### IMG-007 个人中心

**页面用途：** 展示账户资料及个人功能、偏好和账户操作入口。

**设计内容：** 头像、姓名、邮箱、Edit Profile；Saved Recipes、Meal Plan、Notifications、Appearance、Help & Support；Account Settings、Terms & Privacy、Sign Out；版本信息；Profile 导航选中。

**主要交互：** 已保存食谱进入我的食谱；其他菜单指向对应功能页。当前仅关联个人中心总览图，不将菜单子页视为已有设计图。

**设计图：** [UI-007-profile-final.jpeg](https://drive.google.com/file/d/1L7GEiFZlWZMUwXrVwL72N3wKeeK8IFdn/view)

**Google Drive 目录：** [design_assets/ios-v1-final](https://drive.google.com/drive/folders/1fl1WncejwGDad5jbbOcNjmaIKmEOkbVk)

**云盘相对路径：** `design_assets/ios-v1-final/UI-007-profile-final.jpeg`

**Drive 文件 ID：** `1L7GEiFZlWZMUwXrVwL72N3wKeeK8IFdn`

## 共用视觉与导航

7 张图共用 Cook 品牌、暖白底色、绿色操作按钮、衬线大标题、食物摄影及圆角卡片。底部导航包含 Home、Recipes、中央添加按钮、Groceries、Profile。详情与烹饪图中 Home 呈选中状态；其他来源进入详情时的导航状态需与实际导航规则核对。

图中的菜名、姓名、邮箱、计时数值和版本号是界面示例，不能作为真实用户资料或实际应用版本。购物清单图的摘要与分组数量存在示例数字不一致，实际显示应以数据计算结果为准。

## 尚未提供独立设计图的界面与状态

当前目录没有以下入口的独立设计图：搜索结果、分类列表、季节合集、完整食材/步骤视图、导入过程与结果、拍照/相册权限、手动编辑表单、清单详情、编辑资料、饮食计划、通知设置、外观设置、帮助支持、账户设置、条款隐私以及退出确认。加载、空数据、错误、烹饪完成等状态也未单独提供。以上记录表示当前图集覆盖范围，不自动扩大本期开发范围。

## 后续维护与 GitHub 关联方式

1. 页面需求或 Issue 使用本文页面编号，并引用对应设计图的 Drive 链接，避免仅贴根目录而无法定位。
2. 图片优先保存到 GitHub；暂时无法入库时使用本文的 Google Drive 地址。以后入库后，将对应页面的主设计图链接更新为真实仓库路径，同时保留 Drive 链接用于追溯。
3. 同一设计修改后更新原资源或对应记录，记录版本日期和用户确认状态；不得继续引用旧图实现新版页面。
4. 新增页面时补齐页面编号、用途、可见模块、交互说明、原始文件名、Drive 文件 ID 和设计图地址。
5. 本文位于 `docs/DESIGN_ASSETS.md`；产品范围以 `docs/PRODUCT_BASELINE_V1.md` 为准，审批状态以 `docs/UI_DESIGN_APPROVALS.md` 为准。


## 2026-10-03 批准前候选与关键状态（Issue #9）

七张 Drive 图已再次实际打开并逐张核对，未修改云盘。原图副本位于 [references](../design/review-2026-10-03/references/)，仅为追溯来源；旧五入口导航不是 V1 实现依据。IMG-001 推荐首页没有当前产品范围定义，不建立新 UI 页面 ID，也不保留为默认首页。

本批所有资源与交互说明均 **PENDING**，未实现/未原生实测。用户随后要求统一改为 Liquid Glass、悬浮 NAV 与 Claude 字体观感；下表是修订后唯一主资源。无 -glass 后缀的同名文件仅为修订历史，已被本批替换，禁止拿旧版实现。

| 资源 ID | 资源与审阅位置 | 页面 / 状态 | 状态 |
| --- | --- | --- | --- |
| DES-20261003-A-LG | [library-a-glass.png](../design/review-2026-10-03/library-a-glass.png) | UI-002-A 双列照片食谱库 | PENDING |
| DES-20261003-B-LG | [library-b-glass.png](../design/review-2026-10-03/library-b-glass.png) | UI-002-B 单列来源食谱库 | PENDING |
| DES-20261003-C-LG | [library-c-glass.png](../design/review-2026-10-03/library-c-glass.png) | UI-002-C 已收藏大照片食谱库 | PENDING |
| DES-20261003-I-LG | [intake-review-edit-glass.png](../design/review-2026-10-03/intake-review-edit-glass.png)，左起四帧 | UI-010 / UI-011 / UI-004 / UI-012 | PENDING |
| DES-20261003-L-LG | [library-states-glass.png](../design/review-2026-10-03/library-states-glass.png)，左起三帧 | UI-002-L / UI-002-E / UI-002-X | PENDING |
| DES-20261003-T-LG | [servings-timer-glass.png](../design/review-2026-10-03/servings-timer-glass.png)，左起四帧 | UI-005-S / UI-006-T0 / UI-006-TP / UI-006-TD | PENDING |
| DES-20261003-M-LG | [primary-pages-glass.png](../design/review-2026-10-03/primary-pages-glass.png)，左起四帧 | UI-005 / UI-003 / UI-007 / UI-009 | PENDING |
| DES-20261003-P-LG | [import-partial-glass.png](../design/review-2026-10-03/import-partial-glass.png) | UI-013 主 App 部分结果降级 | PENDING |

### 导航建议

以 PRODUCT_BASELINE_V1.md 三 Tab 为硬约束：食谱（默认）／购物／我的。添加为食谱页右上动作；周计划仍是食谱库二级能力，不另占 Tab。候选 A/B/C 是同一私人收藏库的不同密度，不引入推荐数据源。详情从哪个 Tab 进入就返回哪个导航栈，不能沿用旧图 Home 选中。模态、扩展与专注做饭模式的导航可见性需在对应状态图确认。

### 关键状态与缺口

本批补接收成功/未可靠保存失败、疑点字段、编辑表单、库加载/空/错误、份量与计时；另补主 App 已保存部分结果的截图/文字降级。完整状态语义、原图核对、官方依据、生成提示与尚未画出的状态见 [设计资源 README](../design/review-2026-10-03/README.md)。图片只说明静态布局，不能证明系统玻璃材质、无障碍或后台计时已验收。

### 修订验收边界

液态玻璃只用于功能控件与导航，正文/照片保持内容层。字体 family 的实际观察与可嵌入字体选择分开，见 DESIGN_SYSTEM.md。最终图已目视确认三 Tab 和来源/适量信息；计时板误加全局 NAV 的中间稿未入库，主页面板错误选中态已修正。主页面板是长图审阅资源，导航下方虽留空，间距与内容下穿效果仍需要原生 TabView、安全区域和真实滚动验收，不能从位图固定透明度或精确尺寸。

UI-010 新图不含额外成功确认按钮；自动结束 host request 的行为见 README，不能因图中省略说明就等待完整解析。UI-004 新图为首次进入，未默认选推断字段，保存动作等选择后启用。旧暖白版审核状态记录作为 SUPERSEDED（从未 APPROVED），旧 Drive 图保持原始 PENDING 追溯，不改云盘。
