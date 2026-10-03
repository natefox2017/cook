# Product & Platform References

核验日期：2026-10-03。只使用以下官方公开资料；本轮未安装或操作三个产品，没有导入成功率、延迟、离线冲突或恢复备份实测。官网营销、帮助文档与 Cook 推导分开记录。官方页面可能更新，Paprika 使用正式 Paprika 3 iOS 手册，不采用 Paprika 4 beta 作为已发布基线。

产品长期功能支持观察使用闭环，不提供团队实际开发顺序、商业收入或技术内部实现的证据。尤其不能把 ReciMe 官网用户数量宣称当作独立验证的商业成功。

## 官方证据与差异

| 主题 | ReciMe | Recipe Keeper | Paprika 3 | Cook 的推导/取舍 |
|---|---|---|---|---|
| 收进来 | 社交分享；caption、音频、原网页 fallback [R1/R2] | 网站/社交与扫描 OCR [K1] | 网页下载，失败手工剪贴 [P1] | 分享核心入口；后台异步和字段证据是 Cook 规则，不能声称竞品都这样实现 |
| 私人整理 | 自定义 cookbooks [R3] | course/category 与 favorites [K1] | 多分类与独立 favorites [P1] | 建议平级多归属食谱册+喜欢，减少两套组织体系；多归属依据 Paprika，不假设 ReciMe 关系基数 |
| 做饭/准备 | 份量调整、分步阅读 [R4] | 份量调整 [K1] | 份量缩放、步骤计时 [P1] | 基础份量与单计时进入首个闭环（D2 已确认）；不能说三者都证实提供同一种计时行为 |
| 购物/计划 | 食谱购物与计划 [R4/R5] | 清单与计划 [K1] | 清单与计划 [P1] | 购物首个闭环，周计划 V1 后段；无需计划就能加入购物 |
| 离线 | 本轮未找到足以明确离线范围的官方说明 | 官网宣称食谱在线/离线可用 [K1] | iOS 官方商店描述本地食谱可离线 [P2] | 定义自己的文本/购物验收，不从食谱离线外推购物冲突行为 |
| 导出 | 单食谱 PDF/打印 [R6] | 可打印/分享 cookbook [K1] | 批量 HTML/专用格式 [P1] | 建议 JSON+HTML 食谱导出；单份 PDF 不等于全量可恢复备份 |
| 账户 | 官方说明同账户同步 [R7] | 官网说明跨设备同步，未证明首次登录时点 [K1] | cloud sync 可选 [P1] | 首次登录时点由 Cook 云解析/所有权约束决定，不能照搬本地产品 |

### ReciMe 来源

- R1：[Import from TikTok](https://recime.app/help/en/articles/11661452-import-from-tiktok)。说明系统分享路径与文字/音频/原网页 fallback。平台菜单可能含 More 等动作，不能据此承诺所有平台固定两次点按。
- R2：[Import from Instagram](https://recime.app/help/en/articles/11596425-import-from-instagram)。说明系统分享至 ReciMe；没有披露队列、处理耗时或后台保证。
- R3：[How do I create a cookbook](https://recime.app/help/en/articles/13571088-how-do-i-create-a-cookbook-on-recime)。自定义册创建/改名；2026-02-03 更新。
- R4：[What is ReciMe?](https://recime.app/help/en/articles/11594896-what-is-recime)。帮助中心概述整理、购物、计划、缩放及做饭功能；不采用其营养/协作范围。
- R5：[How to Use Your Meal Plan](https://www.recime.app/help/en/articles/14999930-how-to-use-your-meal-plan)。2026-05-07 更新，计划联动购物；不是 Cook 购物必须先计划的依据。
- R6：[Can I print or export my recipes?](https://recime.app/help/en/articles/11626121-can-i-print-or-export-my-recipes)。2026-08-09 更新，单食谱 PDF/打印/链接分享。
- R7：[Account across multiple devices](https://recime.app/help/en/articles/11626072-can-you-share-your-recime-account-across-multiple-devices)。说明登录同账户后同步，不证明匿名首次使用或无需账户。

### Recipe Keeper 来源

- K1：[官方产品页](https://recipekeeperonline.com/)。营销资料列网站/Instagram/TikTok、相机/照片/PDF OCR、分类与喜欢、份量、购物、计划、离线食谱和打印册。未核验支持网站数量、OCR 准确率、离线购物写入/重启或数据恢复，未从本页确认计时和首次账户行为。

### Paprika 来源

- P1：[Paprika 3 iOS User Guide](https://www.paprikaapp.com/help/ios/)。重点章节：Categorizing Recipes、Built-In Categories、Timers、Scaling & Converting Ingredients、Groceries、Paprika Cloud Sync、Export Recipes。多分类关联与喜欢独立；缩放带入购物；cloud sync 可选；批量 HTML/专用格式。图片按需下载说明离线媒体不能一概承诺。
- P2：[官方 iOS App Store 描述](https://apps.apple.com/us/app/paprika-recipe-manager-3/id1303222868)。开发者功能说明本地数据与离线食谱访问；本轮没有设备实测。

## 重复出现的做法与路线依据

共同能力是外部导入、私人整理、烹饪阅读/数量调整、食谱进入购物以及计划。Cook 据此将“收藏 → 找到 → 做饭 → 购物”作为首个可用闭环，把周计划、高级换算、营养、协作和多平台后移。此处是产品路线推导，不声称竞品披露了相同开发流程。

组织命名、离线冷启动、数量不确定性、购物快照、登录时点和导出内容以 PRODUCT_BASELINE_V1.md 为产品规则/验收依据。2026-10-03 用户明确确认 D1–D4 四项 A；官方证据不代替用户批准，本次产品规则确认也不代替 UI 设计图批准。

## Apple（保留平台参考）

- [Share Extension](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Share.html)
- [Extension Scenarios](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionScenarios.html)

扩展生命周期与后台传输须由工程任务继续核验。本轮产品研究没有测试扩展完成时限。Cook 只在可靠接收后反馈成功，解析不占用扩展等待。

## Supabase（保留平台参考）

- [Queues](https://supabase.com/docs/guides/queues)
- [Consuming messages with Edge Functions](https://supabase.com/docs/guides/queues/consuming-messages-with-edge-functions)

属于工程任务的异步处理参考；本轮未核验其实现配置，不新增第二队列或修改 API/Schema。
