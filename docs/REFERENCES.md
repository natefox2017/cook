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

对 Cook 的启发：
- Share Sheet 是核心入口
- 分享动作应尽量少
- 来源解析需要多级 fallback

Cook 的改进：
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

对 Cook 的启发：
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
