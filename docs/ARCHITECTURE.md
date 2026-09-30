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

## 2. 高层结构

```
Third-party App / Browser
        |
        v
iOS Share Extension
        |
        | create import job
        v
Supabase API / Edge Function
        |
        v
recipe-import queue
        |
        v
Import Worker
  |- source resolver
  |- content extractor
  |- ASR / OCR / vision
  |- AI parser
  |- normalizer
  |- quality validator
  |- duplicate detector
        |
        +--> Storage (raw/derived artifacts)
        |
        +--> Postgres (recipe + evidence + job)
        |
        v
iOS App realtime/poll refresh
```

## 3. Share Extension 原则

Share Extension 只负责：
1. 读取 extension context 的 URL/text/image/video 等输入。
2. 做轻量本地校验。
3. 写入共享容器/发起短请求或后台传输。
4. 创建 import job。
5. 立即完成 host request。

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
