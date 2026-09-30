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
