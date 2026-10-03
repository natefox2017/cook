# iOS Architecture V1

## Stack

- SwiftUI
- Swift Concurrency
- iOS Share Extension

## Modules

App
- Features
- Domain
- Data
- Services
- Shared UI

Share Extension
- Receive URL/text/media
- Create import request
- Return immediately

## Rules

Share Extension must not:
- run long AI tasks
- parse videos
- become a full editor

Long processing belongs to backend.

## Parallel Development Boundaries

iOS agents can work independently on:
- UI screens
- navigation
- networking
- domain models
- tests

Shared contracts must be frozen first.

## 无视觉基础（Issue #8）

`ios/CookCore` 是无第三方依赖的 Swift Package，可独立运行领域测试。
当前只实现用量保存和明确数值的份量倍数换算；不增加 API DTO、job 字段或数据持久化协议。
App/Share Extension 后续通过 adapter 使用该库，网络和共享容器接入等待导入合同冻结。

所有页面仍为 PENDING，不创建启动页、占位页面或扩展反馈 UI。
没有 App target、bundle identifier、entitlements、签名设置；库编译不代表 App 构建。

参考 [Recipe Keeper 官方说明](https://recipekeeperonline.com/)：其已上线产品提供外部导入、私人食谱管理和份量调整。这属于官网宣称，本任务未实测其 App，也不能由此推断其内部工程流程。用量库对应当前 Cook 基线的安全换算要求；份量功能优先级仍为 P1。
