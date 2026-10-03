# CookCore

无 UI 的纯 Swift library，不是可安装 App，不包含 Share Extension。

```sh
swift test --package-path ios/CookCore
```

`IngredientAmount` 保留原始用量文字，数值/单位仅由调用方提供已证实的数据。
`scaled(by:)` 只做正倍数 Decimal 乘法：未知数值保持未知，原文保持不变，精度损失/溢出/下溢拒绝。不解析文字、不换单位、不推断置信度。

该类型是本地领域工具，不是冻结的 API/数据库模型。导入合同冻结后由独立 adapter 接入，禁止直接添加 Codable 把它当传输格式。

产品最低版本为 iOS 18.0，主 App Bundle ID 为用户指定的 `com.modelhub.cook`。Package 尚未接入 App target，不承担 Bundle ID 或签名配置；team、App Group 实际 provisioning 待验证。Swift 6 工具链用于当前基础验证。
