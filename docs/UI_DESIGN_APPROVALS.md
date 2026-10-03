# UI Design Approvals

只有 **APPROVED** 页面/状态允许正式 UI 开发。final 文件名、布局方向反馈与文档 PR 合并均不构成审批。

## 当前主资源 · 2026-10-03 Liquid Glass

关联 [Issue #9](https://github.com/natefox2017/cook/issues/9)、[设计审阅包](../design/review-2026-10-03/README.md)。状态板从左到右定位；确认一帧不批准同板其他页面或未画状态。

| ID | 页面/状态 | 主资源 | 状态 | 备注 |
| --- | --- | --- | --- | --- |
| UI-001 | 首次启动/导入教学 | TBD | PENDING | 独立教学图未补 |
| UI-002 | 默认食谱库 | 下列A/B/C | PENDING | 尚未选择最终布局 |
| UI-002-A | 双列照片候选 | [LG版](../design/review-2026-10-03/library-a-glass.png) | PENDING | 6个食谱；悬浮三Tab |
| UI-002-B | 单列来源候选 | [LG版](../design/review-2026-10-03/library-b-glass.png) | PENDING | 4个食谱；悬浮三Tab |
| UI-002-C | 已收藏大照片候选 | [LG版](../design/review-2026-10-03/library-c-glass.png) | PENDING | 私人收藏；不是推荐Feed |
| UI-002-L | 食谱库读取中 | [LG版](../design/review-2026-10-03/library-states-glass.png) | PENDING | 左帧；不是AI进度 |
| UI-002-E | 食谱库空数据 | [LG版](../design/review-2026-10-03/library-states-glass.png) | PENDING | 中帧；分享教学/粘贴链接 |
| UI-002-X | 食谱库读取错误 | [LG版](../design/review-2026-10-03/library-states-glass.png) | PENDING | 右帧；重新加载/添加 |
| UI-003 | 添加食谱菜单 | [LG版](../design/review-2026-10-03/primary-pages-glass.png) | PENDING | 第2帧；自动导入优先 |
| UI-004 | 待完善首次进入 | [LG版](../design/review-2026-10-03/intake-review-edit-glass.png) | PENDING | 第3帧；一个疑点，未默认选值 |
| UI-005 | 食谱详情 | [LG版](../design/review-2026-10-03/primary-pages-glass.png) | PENDING | 第1帧；来源/做饭/购物 |
| UI-005-S | 按份量加入购物 | [LG版](../design/review-2026-10-03/servings-timer-glass.png) | PENDING | 第1帧；P1，适量保留，不覆盖原食谱 |
| UI-006 | 做饭模式布局 | [LG版](../design/review-2026-10-03/servings-timer-glass.png) | PENDING | 第2至4帧；无全局NAV；未画状态不获批 |
| UI-006-T0 | 计时未启动 | [LG版](../design/review-2026-10-03/servings-timer-glass.png) | PENDING | 第2帧；03:00开始 |
| UI-006-TP | 计时暂停 | [LG版](../design/review-2026-10-03/servings-timer-glass.png) | PENDING | 第3帧；01:42继续/重置 |
| UI-006-TD | 计时到时 | [LG版](../design/review-2026-10-03/servings-timer-glass.png) | PENDING | 第4帧；不自动跳步/完成食谱 |
| UI-007 | 购物清单 | [LG版](../design/review-2026-10-03/primary-pages-glass.png) | PENDING | 第3帧；6条示例；子页未设计 |
| UI-008 | 简单周计划 | TBD | PENDING | 二级能力，本批不扩页 |
| UI-009 | 我的/设置总览 | [LG版](../design/review-2026-10-03/primary-pages-glass.png) | PENDING | 第4帧；账户/导入/数据；子页未设计 |
| UI-010 | Share Extension收下 | [LG版](../design/review-2026-10-03/intake-review-edit-glass.png) | PENDING | 第1帧；可靠保存后快速结束 |
| UI-011 | Share Extension接收失败 | [LG版](../design/review-2026-10-03/intake-review-edit-glass.png) | PENDING | 第2帧；未保存，重试/打开Cook可选 |
| UI-012 | 编辑食谱主表单 | [LG版](../design/review-2026-10-03/intake-review-edit-glass.png) | PENDING | 第4帧；新编号；来源与适量保留 |
| UI-013 | 主App部分解析结果 | [LG版](../design/review-2026-10-03/import-partial-glass.png) | PENDING | 补截图/文字；不是扩展接收失败 |

## 尚未覆盖

教学、周计划、编辑键盘/校验/保存失败/退出确认、导入整理中条目、无结果搜索、完整食材展开、未知原始份量、运行中/停止确认/烹饪完成、权限、深色模式与设置子页没有本批独立图。主页面确认不会自动解除这些状态的门禁。

## 修订与确认记录

| 日期 | 记录 | 状态解释 |
| --- | --- | --- |
| 2026-10-03 | 七张Drive图逐张查看，保存项目相关原图副本；五入口与V1冲突 | 原图PENDING，仅追溯 |
| 2026-10-03 | 用户说“整体布局先就这样没问题”，同时要求Liquid Glass、Claude字体与悬浮NAV | 布局方向反馈；修订图继续PENDING，没有明确逐页“确认” |
| 2026-10-03 | 无-glass后缀的同名生成稿被本批替换 | SUPERSEDED，从未APPROVED，仅修订历史 |
| 2026-10-03 | 内置ImageGen完成-glass主资源，Apple规范和Claude计算样式另有证据 | 待人工确认；未正式实现/未原生实测 |

请明确确认页面ID、候选或状态及资源版本。例如“确认UI-002-B、UI-010、UI-011的2026-10-03 LG版”。只有明确列出的页面改APPROVED，选定首页后其他首页候选才能标SUPERSEDED。

## 状态定义

- PENDING：未确认
- APPROVED：用户明确回复“确认”，且可定位页面与版本
- REJECTED：需重做
- SUPERSEDED：被同名新设计替换

禁止把“看起来没问题”“大概这样”“先做着”视为APPROVED。

## 用户直接授权代码实现（2026-10-03）

用户随后明确要求“设计图就不用改了，你直接写代码吧”，并要求返回、工具栏与底部 tab 使用系统组件、先适配英文并建立多语言框架。本次按该明确指令实现主 App 本地功能（Issue #14），首页采用 A 的布局方向。此授权覆盖本次代码工作，不将已有 PENDING 图片改为 APPROVED；真机交互与视觉验收仍待完成。详见 [实施记录](../design/review-2026-10-03/IMPLEMENTATION.md) 与 [iOS 说明](../ios/README.md)。
