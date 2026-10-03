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
- 内容卡片全部玻璃化或多层玻璃叠加
- 一屏堆大量卡片
- 后台管理感
- 社交 Feed 感
- 无意义状态徽章

## 3. 平台基线

iOS 使用 SwiftUI 与 Apple Human Interface Guidelines。

在 UI 设计未 APPROVED 前：
- 不锁定最终品牌色
- 不锁定最终圆角/阴影 token
- 不提交正式页面实现

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

## 6. 2026-10-03 用户修订：Liquid Glass

用户要求保留当前布局，整体改为 iOS Liquid Glass，并使用 Claude 字体观感；这是视觉修订输入，不是对修订后页面的明确“确认”。所有页面继续 PENDING，正式 UI 仍被门禁阻止。

### 材质与层次

- 功能层：底部三 Tab、导航/工具栏及重要操作使用系统 Liquid Glass。内容层：暖白阅读底、食物照片、菜名、来源、食材与步骤；不把每张食谱卡片做玻璃。
- iOS Tab Bar 是浮在内容上方的胶囊，左右与下方有可见间隔，内容可从其下方经过。精确间距由系统安全区域与原生 TabView 决定；设计图不是固定像素实现规范。添加继续在右上，Tab Bar 不承担添加动作。
- 优先 regular 材质以保障标签可读；clear 只适合视觉丰富媒体上的小控件并需要检查背景对比，本批不把 clear 作为全局默认。
- 主按钮可使用绿色强调的 glassProminent，次按钮可用 glass；文字和图标保持可读，不能对整个按钮连同文字设置统一 opacity 来伪装材质。无全局固定透明度百分比。
- 同一玻璃层内部选中态使用薄填充/色调，不在玻璃内重复叠加另一块完整玻璃。
- 导航、工具栏、表单与模态优先原生组件；避免自绘背景覆盖系统材质与滚动边缘效果。
- 降低透明度、增强对比度、减少动态效果及深色模式需单独原生验证。静态图片无法证明折射、按压变形、滚动背景或系统设置适配。

### 字体

已在 Claude 实际公开登录页读取可见元素的计算样式：大标题的 family 为 anthropic-serif，操作按钮为 anthropic-sans；中文回退包含 PingFang SC（苹方）。证据见 [截图](../design/review-2026-10-03/claude-typography-reference.png) 与 [计算样式记录](../design/review-2026-10-03/claude-font-evidence.json)。此证据只覆盖公开登录页，未读取登录后的回答界面。

本批图片以该字体层级为参考：温和书籍衬线大标题、清晰中文正文与操作文字。ImageGen 无法保证真实字体 family 或字形逐像素一致，图片内中文衬线标题为视觉近似；不声称已嵌入 Claude 字体。尚未取得项目可嵌入字体授权，不下载/提交专有字体。正式 UI 前需冻结合法可用 font family 与中文回退，并验证动态字体。

### 官方依据（2026-10-03 查询）

- [Apple HIG Materials](https://developer.apple.com/design/human-interface-guidelines/materials)：功能层与内容层，regular/clear，避免过量使用。
- [Apple HIG Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars)：悬浮于内容、仅一级导航、保留各 Tab 导航状态。
- [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)：系统组件采用材质、减少自定义控件背景、可访问性设置。
- [SwiftUI glassProminent](https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/glassprominent)：强调按钮玻璃样式；[Glass](https://developer.apple.com/documentation/swiftui/glass) 支持材质与 tint。

以上是设计依据，不是 Cook 已有实现。iOS 部署版本与旧系统回退由工程任务确定，本设计不自行更改技术基线。
