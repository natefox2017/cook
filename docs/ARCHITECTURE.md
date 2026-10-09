# Architecture V1

## 1. 技术边界

V1 客户端：
- Native iOS
- SwiftUI
- Share Extension

后端：
- Supabase Postgres
- Supabase Edge Functions (Deno/TypeScript)
- Supabase Storage
- Supabase Queues / pgmq

AI：
- OpenAI-compatible provider router
- 后端调用，客户端不持有 provider secret

该组合复用此前 cookapp 已验证过的基础能力，但本仓库重新以当前 V1 产品基线为准，不继承旧 UI/旧需求。

## 2. 高层结构：实际来源流与待批准能力

**Current iOS code path (not a claim that the remote worker is deployed):**

```
Third-party Share Sheet / Browser
            |
            v
iOS Share Extension (URL/text; image/PDF receive code, limited activation)
            |
            | atomic App Group receipt + source, then complete host request
            v
Main Recipe Pals App (on launch/foreground)
            |
            | signed-in owner checks; submit/refresh idempotent job
            v
Supabase recipe-imports API [requires separately verified deployment]
            |
            v
owner-scoped Postgres + PGMQ queue
            |
            v
recipe-import-worker [server only; deployment and providers unverified]
  |- public HTTPS safe fetch, JSON-LD and page text
  |- owner-checked text artifacts
  |- optional approved OCR (disabled without provider)
  |- review fields and source evidence
            |
            v
Main App owner-scoped result mapping / recipe review [must verify end-to-end]
```

**Planned next-phase additions, not currently shipped:** AI dialogue and version proposals [#238/#241](https://github.com/natefox2017/cook/issues/238); lawful media ASR/keyframes and multiple candidates [#239/#240](https://github.com/natefox2017/cook/issues/239). Separate optional public recipe publishing [#242](https://github.com/natefox2017/cook/issues/242) → guest-readable Web [#243](https://github.com/natefox2017/cook/issues/243) → poster/QR [#244](https://github.com/natefox2017/cook/issues/244) sits behind an isolated privacy-filtered public snapshot, **never a direct public read of RecipeStore/user_snapshots**. New approved features need controlled staging [#250](https://github.com/natefox2017/cook/issues/250), selected-release evidence [#251](https://github.com/natefox2017/cook/issues/251) and separately approved production deployment.

## 3. Share Extension 原则

Share Extension 当前只负责：
1. 读取 extension context 中的 URL/text；有 image/PDF 附件接收代码，但实际 activation 以 `ShareExtension/Info.plist` 为准，不能宣称支持任意视频。
2. 做轻量校验，将来源写入 App Group 的可恢复本地收件记录。
3. **确认本地记录成功后立即结束 host request**。本地 `received` 不等于云端持久化，更不等于已识别并存入食谱。
4. 由**主 App** 在用户有效授权及网络可用时提交/重试 owner-scoped server import job；查询 worker 结果并按用户编辑优先规则入库。

禁止在扩展里长时间等待云端 AI、把未确认内容标记为解析成功或偷偷绑定其他账号。

禁止：
- 在 Extension 内等待完整 AI 推理
- 在 Extension 内跑长视频解析
- 把 Extension 当完整食谱编辑器

Apple 官方资料：
- https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Share.html
- https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionScenarios.html

## 4. 异步任务

导入使用 durable queue。

官方参考：
- https://supabase.com/docs/guides/queues
- https://supabase.com/docs/guides/queues/consuming-messages-with-edge-functions

基本原则：
- job 创建后立即返回
- worker 幂等
- 消息失败不直接丢失
- 重试有上限
- poison job 转 dead-letter/failed 状态
- 所有阶段写可观察日志

## 5. 安全

内容抓取必须防：
- SSRF
- DNS rebinding
- 私网/环回地址
- 非 HTTP(S) scheme
- 重定向绕过
- 超大 HTML/媒体
- MIME 伪造
- 过长下载/转码任务

默认：
- 手动逐跳校验 redirect
- URL allow/deny policy
- 下载 size/time limit
- Storage 隔离原始产物和生成产物
- 用户只能访问自己拥有的 job/recipe/artifact

## 6. 可替换性

以下必须有接口层，避免供应商锁死：
- AI provider
- transcription provider
- webpage extractor
- media artifact storage

客户端不得直接依赖某个具体 AI 模型名。
