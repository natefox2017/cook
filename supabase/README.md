# Supabase

V1 后端边界：
- migrations/
- functions/
- storage policies
- queue/worker
- OpenAPI

## 原则
- 客户端只拿用户权限内数据。
- provider secret 只在服务端。
- 导入任务通过 durable queue 处理。
- migrations 可回溯、可审查。
- RLS 与数据所有权是发布门禁。

Queues:
https://supabase.com/docs/guides/queues
