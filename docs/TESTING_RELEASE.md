# Testing & Release

## 1. 测试层级

### Domain unit tests
- ingredient normalization
- unit conversion
- duplicate fingerprint
- job state transition
- confidence/needs_review rules

### Import fixture tests
为不同来源保存脱敏 fixture：
- caption-only
- article structured data
- transcript-only
- OCR-only
- mixed/conflicting evidence
- private/login-wall
- malformed URL
- duplicate URL

### Backend integration tests
- RLS
- queue retry/idempotency
- artifact ownership
- worker partial failure
- provider timeout
- SSRF/redirect protection

### iOS tests
- Share Extension input types
- shared-container handoff
- job creation
- offline/error state
- recipe domain decoding
- navigation/state restoration

### UI snapshot/visual QA
只有 APPROVED 页面进入视觉验收。
设计参考图与运行截图逐屏对比，失败页面单独修复，不用其他页面 PASS 掩盖。

## 2. CI 最小集

早期 CI 只保留高价值检查：
- format/lint
- unit tests
- backend tests
- iOS build/test（可运行环境）
- migration validation

不要为了“看起来完整”添加大量慢且无收益的 workflow。

## 3. Release Gate

V1 内测前必须验证：
- Share Extension 端到端
- 导入失败可降级
- AI 不伪造精确用量
- 同一链接重复导入不重复建食谱
- 用户数据隔离
- 删除账户/数据策略已定义
- 隐私说明覆盖外部 URL/媒体/AI 处理

## 本机环境诊断（2026-10-03，Issue #8）

| 项目 | 实际只读结果 | 验证边界 |
|---|---|---|
| Xcode | 27.0 / 27A266a | `xcodebuild -version` |
| Swift | Apple Swift 6.4 | `swift --version` |
| SDK | iOS / iOS Simulator 27.0 | SDK 是编译工具，不是运行时 |
| 模拟设备类型 | 包含 iPhone 18 Pro、iPhone 18 Pro Max | 用户口述名称尚待确认 |
| Simulator Runtime | 0 | `xcrun simctl list runtimes` |
| 可用模拟器 | 0 | `xcrun simctl list devices available` |
| 连接真机 | 0 | `xcrun devicectl list devices`，仅当前发现结果 |
| 签名 identity | 0 valid identities | 当前默认 keychain 搜索范围 |
| provisioning profile | 两个标准用户目录均为 0 | 不代表服务端没有 profile |
| Xcode 团队缓存 | 一个 free provisioning team 记录 | 缓存不证明当前登录/服务端可用；不提交账号/Team ID |
| 仓库 App 配置 | 无 xcodeproj、xcconfig、entitlements | bundle id、最低系统、签名尚未定义 |

未安装 Runtime，未创建证书/标识/profile，未改系统设置，也未触碰其他项目。

### 个人团队能力判断

[Apple 官方能力表](https://developer.apple.com/help/account/reference/supported-capabilities-ios) 当前 App groups 行的 ADP、ADEP、Apple Developer 三列均为 yes（核验网页 HTML 的图标，纯文本抓取会丢失勾选）。不能断言免费个人团队不支持 App Groups。
[Apple 账号说明](https://developer.apple.com/help/account/basics/about-your-developer-account) 将非会员 Xcode 团队称为 Personal Team；免费真机 profile 有 7 天期限，并有 App ID/设备数量限制。
[App Group 配置文档](https://developer.apple.com/documentation/xcode/configuring-app-groups) 要求 iOS 组注册。官方可用不等于本账号已验证。

Share Extension 真机验收仍需：选定团队与标识 → 主 App/扩展分别生成 profile → 检查二者签名 entitlements 中相同 App Group → 安装同一构建 → 从第三方 App 分享 → 扩展成功持久入队后完成 host request → 主 App 可读取任务 → 重启后仍可继续。现阶段没有 App/扩展 target、可用 profile 或连接设备，以上全部未验证。

### 配置候选（待用户明确决定，未写入工程）

- 模拟器：iPhone 18 Pro Max。存在此设备类型；需安装匹配 iOS Runtime 后才能创建/运行，具体下载体积与版本先在 Xcode Components 确认。
- 最低版本：候选 iOS 18；已有基础库只用 Foundation，可在该目标 SDK 下编译。此选项是兼容范围建议，不是正式产品基线。
- 开发标识候选：`com.natefox.cook.dev`；扩展 `com.natefox.cook.dev.share`；共享组 `group.com.natefox.cook.dev`。借用仓库 owner 作为候选命名来源，尚未验证归属或可注册性，不是生产标识。
- 签名：使用本机已有个人团队，经 Xcode 当前登录状态及实际 provisioning 校验；不把账号信息提交到 Git。

### 本次验证与可复现命令

`swift test --package-path ios/CookCore`：6 个 Swift Testing 测试函数（参数化输入共 13 个执行案例）通过。XCTest 显示 0 项是该 package 使用 Swift Testing 的正常输出，不能漏看随后 Swift Testing 结果。

无 Runtime 也可编译库：

```sh
mkdir -p /tmp/cook-ios-core-build
xcrun --sdk iphoneos swiftc -swift-version 6 -parse-as-library -emit-module \
  -module-name CookCore -target arm64-apple-ios18.0 \
  -sdk "$(xcrun --sdk iphoneos --show-sdk-path)" \
  ios/CookCore/Sources/CookCore/IngredientAmount.swift \
  -emit-module-path /tmp/cook-ios-core-build/CookCore.swiftmodule
xcrun --sdk iphonesimulator swiftc -swift-version 6 -parse-as-library -emit-module \
  -module-name CookCore -target arm64-apple-ios18.0-simulator \
  -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
  ios/CookCore/Sources/CookCore/IngredientAmount.swift \
  -emit-module-path /tmp/cook-ios-core-build/CookCoreSimulator.swiftmodule
```

两项为库 module 编译，未链接/签名 App，未运行 iOS 测试；模拟器运行、个人团队 App 安装、扩展共享容器均仍待验证。
