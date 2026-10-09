# Product & Platform References

产品规划优先观察已经上线并长期运营产品中反复出现的做法，不从空白臆造流程。

## ReciMe

当前可验证的导入模式：
- TikTok / Instagram 从系统分享菜单导入
- 优先 caption
- 缺失时尝试视频音频
- 再尝试原始食谱网页

参考：
- https://recime.app/help/en/articles/11661452-import-from-tiktok
- https://recime.app/help/en/articles/11596425-import-from-instagram

对 Recipe 的启发：
- Share Sheet 是核心入口
- 分享动作应尽量少
- 来源解析需要多级 fallback

Recipe 的改进：
- Share Extension 不要求用户等待完整解析
- 解析在后台异步完成
- 视觉/OCR 作为补充证据
- 只有异常字段打扰用户

## Recipe Keeper

当前长期存在的核心能力：
- 个人食谱库
- 网站导入
- Instagram/TikTok
- 相机/照片/PDF OCR
- 搜索
- 份量调整
- shopping list
- meal planner

参考：
- https://www.recipekeeperonline.com/

对 Recipe 的启发：
- “私人食谱库 → 做饭 → 购物 → 计划”是稳定闭环
- 手动/扫描入口不能删除，但不应压过自动导入

## Apple

Share Extension：
- https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Share.html
- https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionScenarios.html

原则：
扩展尽快完成 host request；潜在长上传使用后台传输/共享容器，不把长任务留在扩展生命周期里。

## Supabase

Queues：
- https://supabase.com/docs/guides/queues
- https://supabase.com/docs/guides/queues/consuming-messages-with-edge-functions

用于导入任务的 durable asynchronous processing。

## Cooking 体验：下一阶段参考产品

研究目的：观察**已上线**食谱 App 的实际持续运营功能，提炼重复出现的烹饪交互，而不是复刻旧代码或照搬某张商业 UI。

| 参考 | 已上线的产品做法 | 提炼到 Recipe Pals | 参考链接 |
| --- | --- | --- | --- |
| Paprika（iOS） | 时间识别/点时间开始 timer；多个 timer 可管理；到点有系统通知音；食材可缩放 | 现有多 timer 上加提前/到点不同提示，安全复用当前 deadline | https://www.paprikaapp.com/help/ios/ |
| ReciMe（官方说明 2026-08 更新） | 点击指令中高亮食材查看当前份量；点温度查看转换；支持配方份量/公英制转换 | Recipe Detail 与 Cooking Mode 的轻量原生参数信息卡，不增加冗长备注 | https://recime.app/help/en/articles/11596272-how-can-i-get-the-most-out-of-recime |
| Crouton | 单步骤 Cooking 视图里集成 hands-free、计时器等操作 | 语音控制只加在现有 Cooking 视图，不创建第五个 Tab | https://mwm.ai/apps/crouton-recipe-manager/1461650987 |
| Tamarin | 明示的 next/previous/read step/voice timer 指令，用户主动启用语音助理 | 先做明确的 Next/Previous/Repeat 闭集指令；不造全局 AI 语音对话系统 | https://jointamarin.com/ |

### Apple API 和开源复用边界

- 本地完成/提前通知优先复用 `UserNotifications.UNNotificationSound`：资源在设备上，自定义音频用 Apple 支持的格式且**短于 30 秒**，尊重系统静音/专注模式。 https://developer.apple.com/documentation/usernotifications/unnotificationsound
- 语音指令优先 `Speech.SFSpeechRecognizer` + `AVAudioEngine`；识别授权与麦克风授权由用户明确同意。端侧能力要先检查 `supportsOnDeviceRecognition`，不能在不支持时谎称离线。 https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition
- 朗读当前步骤可直接使用 `AVSpeechSynthesizer`。 https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer
- 开源候选 `SwiftSpeech`（MIT）：参考其 SwiftUI 麦克风权限/会话/识别包装，开发前先确认 iOS 18+/Swift 6 兼容性、维护情况和依赖成本；不要为了几个固定指令引入过大的模型。 https://github.com/Cay-Zhang/SwiftSpeech
- 参数信息卡优先用 SwiftUI `.popover` / `.sheet`，在紧凑 iPhone 走原生底部呈现，不引入新 UI 库。 https://developer.apple.com/documentation/swiftui/presentationadaptation

产品边界：这些都是**功能设计参考**，不代表 Recipe Pals 已经实现。参数信息来自可验证的食谱字段，精确 `°C ↔ °F` 与同维度单位换算可以计算；模糊用量、重量↔容量、营养数值没有证据不可自动填充。

下一步具体开发与验收定义：[Timer sounds #231](https://github.com/natefox2017/cook/issues/231)、[Voice controls #232](https://github.com/natefox2017/cook/issues/232)、[Tap-to-explain #233](https://github.com/natefox2017/cook/issues/233)。

## Deployed recipe product research for 2026-10-09 AI / Sharing / Detail additions

| Shipped source | Feature that can be verified | Product implication |
| --- | --- | --- |
| [Samsung Food recipe sharing, official 2026](https://support.samsungfood.com/hc/en-us/articles/18588679568532-How-to-Share-Your-Saved-Recipes-with-Anyone) | Copy link, email, SMS, WhatsApp and web viewable without app/login | Native share sheet with **clickable link as primary**; shareable poster/QR as bonus |
| [Samsung Food creator/right restrictions](https://support.samsungfood.com/hc/en-us/articles/18365296571412-Getting-Started-with-Samsung-Food-Communities) | Original content restrictions for Community reposts | Private by default, check authorization before publishing imported recipe instructions/images |
| [Samsung Food recipe page](https://support.samsungfood.com/hc/en-us/articles/18588916048276-Recipe-Page-101) | Hero, creator, prep/cook/servings, ingredient/step/nutrition, Save/Plan/Share | Detail must prioritize usable metadata and actions, hide unavailable fields |
| [ReciMe product](https://recime.app/help/en/articles/11594896-qu-est-ce-que-recime) | Import, scale, cook, meal planning, nutrition | Keep 1-tap import/cook continuity; no need to invent a community |
| [Honeydew AI Edit](https://honeydewcook.com/support/en/using-the-app/ai-edit/) | Plain text edits and before/after save/discard | User approves AI ingredient substitutions; preserve prior version |
| [Paprika iOS](https://paprikaapp.com/help/ios/) | Ingredient conversions, timers in directions, prep/cook and notes | Reuse current timers/scaling; #233 handles contextual parameter tap |

### QR and installation measurement: source boundaries

- [Ipsos US QR-menu experience](https://www.ipsos.com/en-us/qr-code-menus-are-growing-even-less-popular): 65% have used restaurant QR menus but preference is much lower. QR understanding is **not proof of best performance as a share link**, so provide clickable URL as primary.
- [YouGov US 2025–26 OOH advertising](https://yougov.com/en-us/articles/55200-ooh-effectiveness-americans-frequently-notice-out-of-home-advertising-many-act-on-what-they-see): 12% reported QR/NFC action in outdoor-ad context, not general QR usage.
- [Apple Universal Links](https://developer.apple.com/documentation/xcode/allowing-apps-and-websites-to-link-to-your-content) and [Smart App Banners](https://developer.apple.com/documentation/webkit/promoting-apps-with-smart-app-banners): installed app deep link vs browser landing, not automatic store-install referral attribution.
- [App Store Connect campaign analytics](https://developer.apple.com/help/app-store-connect-analytics/acquisition/campaign-links/): privacy-limited **aggregate** campaign metrics; not proof of specific invitee identity.
- [Apple privacy/fingerprinting](https://developer.apple.com/app-store/user-privacy-and-data-use/): no device fingerprinting or hidden cross-site person linking.

Full plans: [AI](PRODUCT/AI_RECIPE_EXPERIENCE_2026-10-09.md), [Share → Web → Growth](PRODUCT/RECIPE_PUBLIC_SHARING_V1.md), [Recipe detail audit](PRODUCT/RECIPE_DETAIL_COMPETITOR_AUDIT_2026-10-09.md).
