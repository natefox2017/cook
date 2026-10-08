# Recipe

把第三方平台和网页里的做饭内容，一键收进自己的食谱库，并自动整理成可执行食谱。

## V1 核心闭环

```
第三方平台 / 网页
        ↓
系统分享 → Recipe
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

设计资源与审批历史见 [UI_DESIGN_APPROVALS.md](docs/UI_DESIGN_APPROVALS.md)。2026-10-07 用户已明确要求实现 UI 功能并提交；本轮的实现范围、验证结果和后端边界见 [UI_IMPLEMENTATION.md](docs/IOS/UI_IMPLEMENTATION.md)。

## 技术方向

- iOS: SwiftUI
- 导入入口: iOS Share Extension
- Backend: Supabase Postgres + Edge Functions
- Async: Supabase Queues / pgmq
- Storage: Supabase Storage
- AI: OpenAI-compatible provider router

## 当前状态

已建立原生 SwiftUI iPhone App，最低 iOS 18，主 App Bundle ID 继续使用已注册的 `com.modelhub.cook`，以保留现有安装身份。用 Xcode 26.2 或更新版本打开 `ios/Recipe.xcodeproj`，选择共享的 `Recipe` scheme 后运行。

客户端包含食谱库、搜索/筛选/收藏、详情与编辑、网页/文字/照片/文档导入、烹饪计时、购物清单、简单周计划及本地设置。用户数据原子保存到本机；首启为空库，演示数据只通过明确入口加载。

网页导入仅处理实际存在的 Schema.org Recipe；照片文字由 Apple Vision 在设备上识别。无法识别时保留来源供补充，不把示例食谱当识别结果。Supabase 账户/同步、社交视频 AI 解析、Share Extension 和后台耐久导入队列仍是后续集成范围，本次没有部署生产后端。

检查命令：

```sh
swift test --package-path ios/RecipeCore
xcodebuild -project ios/Recipe.xcodeproj -scheme Recipe \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.2' \
  CODE_SIGNING_ALLOWED=NO test
```

CI 使用可用的 iPhone 17 Pro Max 模拟器验证大屏布局；不把它称为尚未实际运行的 iPhone 18 Pro Max 真机验收。签名安装需在 Xcode 中选择自己的开发团队。

总入口 Issue: #1
