# UI Design Approvals

> 本文只维护长期产品范围、交互与技术设计，不维护任务状态或开发进度；任务、依赖和验收以 [Linear DEV Recipe Pals Development](https://linear.app/gengyun/project/recipe-pals-development-8c015c72cb6a) 为准。

本表用于记录 UI 方向和决策，不构成开发门禁；当前任务中用户的明确指令优先。**审批状态 ≠ 功能是否已实现或真机是否验收。** 例如 UI-002/003 的旧设计图仍 PENDING，但对应 SwiftUI 页面已经存在；不得据 PENDING 重写页面。2026-10-09 新需求只确认了功能方向，详见下表 SCOPED（不虚报为最终视觉 APPROVED）。

| ID | 页面/状态 | 设计资源 | 状态 | 备注 |
|---|---|---|---|---|
| UI-001 | 首次启动/导入教学 | `DESIGN_SYSTEM.md` + IMG-002/IMG-007 现有 iOS 视觉基线 | APPROVED | 2026-10-08 用户明确要求补齐；2026-10-09 用户要求三步全屏配图引导，顺序为 AI、链接、社交；首屏文案明确 Create with AI，不得被旧收藏标题覆盖，标题单行叠加在图片上；右上角 Skip 进入订阅页；主路径为 Share → Recipe Pals，Add Recipe 仅作兜底 |
| UI-002 | 食谱库 | TBD | PENDING | 默认首页 |
| UI-003 | 添加食谱菜单 | TBD | PENDING | 自动导入优先 |
| UI-004 | 待完善 | TBD | PENDING | 只展示异常字段 |
| UI-005 | 食谱详情 | 现有 Recipe Detail UI + `DESIGN_SYSTEM.md` | APPROVED | 2026-10-08 用户明确要求不再单独画设计稿，直接按现有 UI 与功能完善详情页 |
| UI-006 | 做饭模式 | 现有 Cooking Mode UI + `DESIGN_SYSTEM.md` | APPROVED | 2026-10-08 用户明确要求按现有 UI 延伸；保持单步骤大字号并补步骤食材、温度、多计时与进度 |
| UI-007 | 购物清单 | TBD | PENDING | 合并/勾选/编辑 |
| UI-008 | 简单周计划 | TBD | PENDING | 二级能力 |
| UI-009 | 我的/设置（文字精简） | 用户截图（本次对话） | APPROVED | 仅删除辅助性小字；保留全部页面模块、入口和操作，不调整布局 |
| UI-010 | Share Extension 成功 | TBD | PENDING | 快速结束 |
| UI-011 | Share Extension 失败/降级 | TBD | PENDING | 可继续操作 |
| UI-013 | Recipe Pals App 启动页 | [RecipePouch 启动页方案](DESIGN/proposals/2026-10-07/recipepouch-launch-screen.svg) | PENDING | Apple HIG 系统启动画面：浅色/深色使用首屏画布纯色背景，不放文字或品牌图标；待用户确认后接入 |
| UI-014 | 全部页面间距与菜单图标统一 | [当前页面截图与间距修正提案](DESIGN/proposals/2026-10-07/spacing-normalization/README.md) | APPROVED | 统一页面标题、分组标题和卡片间距；菜单图标取消圆形底；保留全部模块与功能 |
| UI-015 | 首次启动/Premium 计划 | `DESIGN_SYSTEM.md` + IMG-007 个人中心视觉基线 | APPROVED | 2026-10-08 用户明确要求补齐；2026-10-09 用户要求图片式付费页并明确年费、月费、免费三种选择；2026-10-09 要求单屏、右上角弱化关闭、功能权益及底部 CTA；2026-10-09 要求减少重复文案、增加呼吸感；2026-10-09 要求重新设计排版，突出短标签与留白；2026-10-09 指定 Product Design 依据 App 与实际功能实现：共用套餐卡、配图、短标签、原生主按钮，大字体可滚动；用户最新要求功能改为左对齐图标文字行，套餐纵向排列（月付在上、年付在下）并默认选中年付，免费使用为轻量文字入口；StoreKit 实时产品信息，保留免费继续、恢复购买和法律链接 |
| UI-016 | 周日期条与底部 Liquid Glass 导航 | [2026-10-08 设计提案](DESIGN/proposals/2026-10-08/navigation-and-week-strip/README.md) + 用户提供的 Recipe / Meal Plan / Tab 截图 | APPROVED | 2026-10-08 用户明确要求直接修改；压低周日期卡并改用系统原生四 Tab 与安全区 |
| UI-017 | 二级页面隐藏底部 Tab | [二级页面导航示意](DESIGN/proposals/2026-10-08/secondary-page-navigation/README.md) | APPROVED | 2026-10-08 用户确认；根页面保留 UI-016 已批准的系统 Liquid Glass Tab，进入二级页面后隐藏，返回根页面后恢复 |

| UI-018 | Cloud Sync 状态、首次同步选择与冲突处理 | 现有 Settings UI + `DESIGN/proposals/2026-10-08/cloud-sync/README.md` | APPROVED | 2026-10-08 用户明确要求不再单独画设计稿，继续按现有 UI/功能开发；直接延伸 Settings 实现实时状态、Sync Now、首次合并和逐项冲突选择 |

| UI-019 | 登录 UI 与底部弹窗 | 现有 Profile / RecipeTheme / AccountView | APPROVED | 2026-10-08 用户要求直接修改登录页及弹出方式；Profile 账户入口改为底部 sheet，Apple 登录优先，邮箱按需展开，成功后关闭，回调可展开恢复密码；不改 Supabase Auth 契约 |

| UI-020 | Google 与 Apple 登录一致性 | Google 官方品牌规范 + Apple HIG + 现有 Account Sheet | APPROVED | 2026-10-08 用户明确要求补齐 Google 登录、统一 Apple/Google 按钮外观并符合各自官方规范；共用 50pt 高度及 14pt 圆角，保留 Google G 品牌四色与 Apple 系统按钮；生产 OAuth 配置与真实设备测试仍需验收 |

| UI-021 | 全页面字体与间距统一 | `DESIGN_SYSTEM.md` + `ios/Recipe/Design/RecipeTheme.swift` | APPROVED | 2026-10-09 用户要求直接执行：原生标题位置与字号统一、页面间距/颜色规范化，清理冗余说明文案，保留必要提示、数据和功能。 |

| UI-022 | Recipe Pals 登录页品牌与控件修正 | 已批准 AppIcon.png + RecipeTheme + 用户登录页截图 | APPROVED | 2026-10-09 用户明确要求直接修正 logo、标题、按钮及右上角关闭图标；使用锅形品牌图标、Recipe Pals 标题、Lora 与 #42A85A 邮箱主按钮，Apple/Google 使用白色胶囊控件并保留官方标识，关闭入口为灰色叉号；不改认证契约 |

## 2026-10-09 新功能设计方向（SCOPED，尚无已验收定版视觉）

| ID | 页面/状态 | 依据 | 状态 | 实现与验收边界 |
| --- | --- | --- | --- | --- |
| UI-023 | AI 识别链接与对话完善草稿 | [DEV-79](https://linear.app/gengyun/issue/DEV-79) + [AI 体验方案](PRODUCT/AI_RECIPE_EXPERIENCE_2026-10-09.md) | SCOPED | 自动完成优先，信息不足才追问，保留人工编辑；未实现 |
| UI-024 | AI 替换食材与前后版本对比 | [DEV-76](https://linear.app/gengyun/issue/DEV-76) | SCOPED | 允许接受/拒绝/复制新菜谱；不能改写用户确认的原始事实 |
| UI-025 | 多食谱候选选择 | [DEV-77](https://linear.app/gengyun/issue/DEV-77) | SCOPED | 只有多菜证据足够才显示，不侵入单菜快速流程 |
| UI-026 | 食谱详情专业字段与信息层级 | [DEV-52](https://linear.app/gengyun/issue/DEV-52)、[DEV-51](https://linear.app/gengyun/issue/DEV-51)、已有 [DEV-81](https://linear.app/gengyun/issue/DEV-81) | SCOPED | 延伸既有 UI，新增可选字段/弹层，信息无证据则隐藏 |
| UI-027 | 用户自主公开食谱入口 | [DEV-73](https://linear.app/gengyun/issue/DEV-73) | SCOPED | Private 默认、授权与撤回，不属于社区公开 Feed |
| UI-028 | 匿名可读单食谱 Web 页和 App 下载 CTA | [DEV-71](https://linear.app/gengyun/issue/DEV-71) | SCOPED | 只有真实域名与可公开快照可用后才能上线 |
| UI-029 | 长图海报、二维码与原生分享菜单 | [DEV-68](https://linear.app/gengyun/issue/DEV-68) | SCOPED | 图 + 可点击链接双入口，二维码不强制扫码 |
| UI-030 | Cooking 倒计时音效与按需语音控制 | [DEV-86](https://linear.app/gengyun/issue/DEV-86)、[DEV-84](https://linear.app/gengyun/issue/DEV-84) | SCOPED | 不常驻麦克风；声音遵循系统策略；不抢占现有计时/操作 |

## 状态定义
- PENDING：尚无明确 UI 决策记录
- APPROVED：用户已明确同意或直接要求执行对应方向
- REJECTED：需重做
- SUPERSEDED：已被同名新设计替换

- SCOPED：用户明确要求加入功能并允许规划开发，但尚无经过实机验收的新增页面设计；具体以关联 Issue/现有设计规范为准，不构成必须先画图才能开发的门禁。
