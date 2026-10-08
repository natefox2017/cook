# Design System

状态：DIRECTION / 未最终视觉确认

## 1. 设计读法

这是面向普通做饭用户的原生移动工具，不是管理后台。

界面原则：
- 内容优先
- 图片驱动
- 低信息密度
- 单屏单任务
- 做饭时可快速扫读
- 不把 AI 过程当视觉主角

## 2. 视觉方向

关键词：
- 现代
- 安静
- 私人食谱册
- 真实食物照片
- 原生 iOS
- 克制动效

避免：
- AI 紫色渐变
- 过度玻璃拟态
- 一屏堆大量卡片
- 后台管理感
- 社交 Feed 感
- 无意义状态徽章

## 3. 平台基线

iOS 使用 SwiftUI 与 Apple Human Interface Guidelines。

当前填充/控件主色：`#42A85A`，浅色与深色模式一致。浅色模式的文字与图标使用高对比同色系前景 `#216B42`。

圆角与阴影 token 暂不锁定。

## 4. 页面信息层级

### 食谱库
优先展示：
- 食物图片
- 菜名
- 来源/状态的必要信息

“待完善”是轻提醒，不做任务中心。

### 食谱详情
第一屏优先：
- 成品图
- 菜名
- 来源
- 份量/时间
- 食材
- 开始烹饪

营养、厨具、标签、备注属于次级信息。

### Share Extension
只展示：
- 来源摘要
- 接收成功/失败
- 必要的重试/打开 App

不得承载完整编辑器。

## 5. 交互

- Loading 优先骨架/明确阶段，不使用长时间无解释 spinner。
- Error 必须带下一步动作。
- 触控目标遵循 iOS 可访问性要求。
- 支持动态字体、VoiceOver、深色模式的结构性兼容。

## 6. UI typography and spacing contract (2026-10-09)

This contract applies to RecipePouch SwiftUI screens. Keep the implemented
**Lora** font and green palette; do not reinstate older exploratory fonts.

- **Navigation titles:** let the native iOS navigation bar and safe area
  determine top alignment. Root tabs use the large title (34 pt); pushed
  pages and sheets use the inline title (17 pt). Do not create a second
  in-content heading that duplicates the navigation title.
- **Heading sizes:** hero 34 pt, page 28 pt, section 22 pt, card 20 pt.
  **Content sizes:** body 17 pt, secondary 15 pt, footnote 13 pt.
  Use `RecipeTheme.heading` and Dynamic Type-aware `RecipeTheme.text`.
  Functional large text in Cooking Mode is deliberately exempt.
- **Spacing:** horizontal page inset 20 pt, content start 8 pt below the
  native navigation content area, compact text gaps 4 / 8 pt, related
  controls 12 pt, list sections 16 pt, and major groups 24 pt.
  Shared values live in `RecipeSpacing`. For a scrolling secondary page use
  `recipePageContentInsets()`; native List/Form screens use an 8-pt top
  scroll-content margin. The system navigation bar retains responsibility for
  status-bar and top-title placement.
- **Colors:** primary text uses system `.primary`, supporting information
  uses `.secondary`, links and accents use
  `RecipeTheme.accentForeground`, and actions use
  `RecipeTheme.accent` (`#42A85A`). Preserve high contrast in dark mode.
- **Concise UI copy:** remove decorative slogans, redundant counters,
  unnecessary explanations, and duplicate headings. Preserve actionable
  labels, error/recovery guidance, destructive-action disclosures,
  subscription and legal text, actual user recipe content, and accessibility
  labels. Necessary helper copy should generally fit one line.
- **Navigation:** root tabs retain native tab bar; pushed screens hide it;
  the focused cooking flow remains tab-free. The Share Extension is a
  separate native host and shows only concise receipt or failure content.

Before release, check the updated pages on iPhone simulator and device at
standard and accessibility Dynamic Type sizes, in light/dark appearance.

### Compact copy versus essential information

A single-line limit is appropriate for decorative metadata at standard text
sizes; it is **not** appropriate for recovery errors, account warnings,
or a StoreKit trial-price/renewal disclosure. At Accessibility Dynamic Type
sizes, navigation/setting labels may wrap; never shrink normal body labels
to a fraction of their specified type scale. For subscription choices use a
horizontal title/price row when it fits and a vertical arrangement when not.
Maintain the 24-pt profile/settings icon column consistently and preserve
all VoiceOver text.
