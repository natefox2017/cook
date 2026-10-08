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

该组合以当前产品基线为准；本次架构契约未部署，不把其他仓库或旧聊天的结果作为本项目验收。

## 2. 高层结构

```
Third-party App / Browser
        |
        v
iOS Share Extension
        |
        | durable receive (offline-capable)
        v
App Group Inbox --> iOS uploader / background URLSession
        | authenticated, idempotent create import job
        v
Supabase API / Edge Function + transactional outbox
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
3. 复制全部附件，校验后耐久提交 App Group LocalEnvelope。
4. 此时才可报告本地 received（已收下）；可选发起后台传输，主 App 负责恢复。
5. 完成 host request；不等待服务器 job 创建或完整解析。

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

## 7. Issue #6 导入边界与恢复

当前 [导入协议](RECIPE_IMPORT_PIPELINE.md) / [API](API_CONTRACT.md) / [机器契约](schemas/import-v1.schema.json) 为待人工审阅冻结候选。App Group InboxStore 是本地耐久收件责任方，服务端 received 是 DB + input references + outbox 耐久责任转移点，queued 才表示入队。具体收件、租约 fencing、退避、去重、用户修改事务与故障验收由导入协议定义。

契约要求断网可收件；iOS 不保证后台执行时机，处理最终依赖系统调度/主 App 恢复和服务器 worker，不能宣称扩展结束即已经整理完成。扩展和 App 的共享容器访问需跨进程协调；原生权益/App Group 与数据保护配置另行 Issue/人工审批。

Supabase 官方 [Queues](https://supabase.com/docs/guides/queues) 的窗口内投递保证不能替代业务写入幂等和过期 worker 防护；[Private Storage](https://supabase.com/docs/guides/storage/buckets/fundamentals) 要求按对象授权访问。2026-10-03 已查 changelog 与 PostgreSQL 15.19/17.11 变更；本阶段无迁移/SQL/环境部署，未验证实际 pgmq/RLS/Storage 配置。

来源样本的 Mac HTTP 可获取性也不代表 Edge Functions 出口可获取性；上线适配前必须在计划运行环境重测 HTTP、内容质量、超时/体积、短链与认证限制。公开抓取测试脚本不是生产 SSRF 过滤器。
