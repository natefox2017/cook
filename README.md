# Cook

把第三方平台和网页里的做饭内容，一键收进自己的食谱库，并自动整理成可执行食谱。

## V1 核心闭环

```
第三方平台 / 网页
        ↓
系统分享 → Cook
        ↓
“已收下”并立即返回
        ↓
后台异步解析
        ↓
自动入库 / 待完善
        ↓
我的食谱
        ↓
做饭 / 购物清单 / 简单周计划
```

V1 **不做社区**：不做 Feed、发帖、关注、点赞、评论、达人主页。

## 开发入口

先读：
1. [START_HERE.md](START_HERE.md)
2. [AGENTS.md](AGENTS.md)
3. [产品基线](docs/PRODUCT_BASELINE_V1.md)
4. [用户流程](docs/USER_FLOWS.md)
5. [架构](docs/ARCHITECTURE.md)

UI 开发必须先通过 [UI_DESIGN_APPROVALS.md](docs/UI_DESIGN_APPROVALS.md) 的确认门禁。

## 技术方向

- iOS: SwiftUI
- 导入入口: iOS Share Extension
- Backend: Supabase Postgres + Edge Functions
- Async: Supabase Queues / pgmq
- Storage: Supabase Storage
- AI: OpenAI-compatible provider router

## 当前状态

仓库处于 V1 基线初始化阶段。正式 UI 尚未确认，因此只建立产品、技术与目录边界，不提前实现页面。

总入口 Issue: #1
