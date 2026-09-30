# Share Extension

职责只有“接收 → 入队 → 反馈 → 完成”。

## 支持输入
- URL
- text
- image
- video/file（按平台与大小限制处理）

## 禁止
- 长视频分析
- 完整 AI 解析
- 完整食谱编辑
- 强制选择分类
- 阻塞等待后台完成

必要时通过 App Group/shared container 与主 App 协作。

参考：
https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Share.html
