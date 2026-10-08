# Recipe Import Pipeline

## 1. 目标

把 URL、文字、图片、视频等外部输入转成“有证据、可编辑、可追溯”的结构化食谱。

## 2. 处理顺序

```
receive
  ↓
resolve source
  ↓
extract structured/web metadata
  ↓
caption/body/text
  ↓
subtitle/transcript/ASR
  ↓
OCR
  ↓
key-frame visual evidence
  ↓
AI parse
  ↓
normalize
  ↓
validate
  ↓
deduplicate
  ↓
ready / needs_review
```

优先使用更直接、更可靠的信息源，不要一上来就让视觉模型“看完整视频猜菜谱”。

## 3. Evidence-first

每一个可疑字段允许记录：
- value
- normalized_value
- source_type
- source_excerpt / timestamp / frame id
- confidence
- user_confirmed

source_type 示例：
- webpage_structured_data
- caption
- article_body
- subtitle
- asr
- ocr
- visual
- user

## 4. AI 防幻觉

必须遵守：
- 原文“适量”就保存为“适量”，不要擅自变成 5g。
- 无证据的精确温度、时间、克数不得自动补齐为事实。
- 可推断内容必须标记为 inferred，不能冒充 extracted。
- 低置信度不阻止保存整份食谱，但应进入 needs_review。
- 用户确认后的值优先级最高。

## 5. 完整度判定

### ready
能让用户基本照着完成烹饪，且关键字段没有高风险冲突。

### needs_review
例如：
- 菜名/主体不确定
- 多个关键食材冲突
- 关键步骤缺失
- 视觉推断和语音/文字矛盾
- 份量换算存在歧义

“盐适量”本身不是 needs_review。

## 6. 重复检测

优先级：
1. canonical source URL
2. platform content ID
3. normalized URL hash
4. content fingerprint
5. title + ingredient fingerprint（仅辅助）

同一来源重复分享时，不重复创建食谱；允许更新“最近收藏时间”。

## 7. 失败降级

- 私有内容/登录墙：保存来源 + 已拿到的信息，提示截图/文字补充。
- 视频抓取失败：继续尝试 caption/article/source page。
- ASR 失败：若文字信息足够仍可 ready。
- AI provider 失败：job 可重试，不丢原始 evidence。
- 解析部分成功：保存 partial recipe，不丢结果。

## 8. Job 幂等

每个 import job 需要：
- idempotency_key
- source_fingerprint
- stage
- attempt_count
- last_error_code
- timestamps

Worker 所有写入都必须允许安全重试。


## 9. 导入协议与部署边界（2026-10-08）

- 协议参考 [API_CONTRACT.md](API_CONTRACT.md) / [import-v1.openapi.json](schemas/import-v1.openapi.json) / [import-v1.schema.json](schemas/import-v1.schema.json)。
- Share Extension 写入本地可恢复 receipt 并返回宿主 App；不能把 `Saved to RecipePouch` 误认为 Supabase 已接受。App 后续转送，服务端确认后才更新 receipt 的 `acknowledged_job_id`。
- `received` 表示服务器持久化任务；`queued` 表示消息入队确认。worker 才进入 extracting/parsing/validating，成功后 job=completed，结果 recipe=ready 或 needs_review；两条状态轴不可混用。
- 发生认证丢失、网络失败、队列未确认、重试或账户切换时，保留原始 receipt/source/evidence，不静默丢弃、不跨 owner 转移。
- URL 输入保留用户提交的 `original_url`；只有实际解析到来源页面后才记录 `canonical_url`。网页正文或结构化数据分别标记 `article_body` / `webpage_structured_data`，字段引用其 evidence ID；裸文本输入保留原文，不能伪造网页 URL。
- 缺失字段保持缺失，并把需要补充的字段路径放入 `review_fields`。含糊用量、范围或“适量”保留原文；不能可靠规范化时 `normalized_value` 为空。Schema 与请求处理应拒绝无主机 HTTPS URL、凭据、非标准端口、空白文本和互斥输入；本地 fixture validator 也显式检查这些输入，但不证明在线 API 已执行这些规则。抓取失败不得伪称已有网页证据。
- 具体公开来源研究记录见 [import-fixtures/observations.json](import-fixtures/observations.json)：帮助文档不等于真实 URL 解析，也不等于 iOS 第三方 Share → 队列 → 食谱的端到端验收。

## 10. 当前 Worker 公开页面源码能力

以下描述的是仓库中的 Worker 源码，不代表 Edge Function 已部署或真实来源已验收：

- URL 只经现有受限公开 HTTPS 抓取器读取；DNS 地址固定到已验证的公网 IPv4，逐跳重定向重新验证。请求不带用户 Cookie，也不执行 JavaScript。
- 首选 Schema.org Recipe JSON-LD。缺失字段时再从可见 `article` / `main` 正文和页面直接内嵌的 transcript/caption 文本补充；文本 track 仅读取公开的 `.vtt` / `.webvtt`，不抓取视频或其他媒体二进制。
- 正文与字幕各自作为 `article_body`、`caption` 或 `subtitle` evidence 保存来源 URL 与 excerpt。只有明确标注的 Ingredients/Steps 等段落会映射为食材/步骤字段；字段引用对应 evidence ID，已存在的 JSON-LD 字段优先保留。
- 登录/付费墙、封锁、无正文或需要客户端 JavaScript 渲染时不尝试绕过。可抓取但没有足够来源内容时保留原始 URL，返回 `needs_review`；无法安全取得页面时也保留 URL，并返回无伪造网页 evidence 的 `needs_review` 结果。

## 11. 当前来源支持范围

| 来源 | 入口与处理 | 结果边界 |
| --- | --- | --- |
| 公开 HTTPS 食谱页 | 手动导入或分享 URL；本地和 worker 保留来源 URL，worker 读取安全可访问的结构化数据、正文和公开字幕证据 | 字段证据充分时可保存；缺失或不确定字段进入 `needs_review` |
| 文字 | 手动粘贴或分享；本地/worker 只解析有明确标题、食材、步骤语义的文字 | 原文保留；不猜精确用量 |
| 图片 | 手动添加可使用现有本地 Vision OCR；分享图片作为私有 artifact 上传并关联 job | 分享队列当前不运行 OCR/图像识别；保存原件并以 `needs_review` 等待补充 |
| PDF/文字文件 | 手动添加可使用现有 PDFKit/UTF-8 文本读取；分享 PDF/文字文件作为私有 artifact 上传并关联 job | 分享队列不提取附件文字；保存原件并以 `needs_review` 等待补充 |
| 视频、音频、登录墙或需客户端渲染的页面 | 当前后台队列不下载媒体、不绕过访问控制 | 保留可用的来源信息并提示补充；不声称完成媒体解析 |

分享附件的上传 intent 两小时失效，已确认 artifact 保留七天。附件 API 提供 owner-scoped 删除操作，但当前 App 没有单个附件的删除入口；到期清理函数需要由受信任的项目 scheduler 每日调用。
- 本路径不做 ASR、OCR、模型补全、视频二进制抓取或平台登录。源码支持不证明线上 DNS/TLS/redirect 行为、VTT 来源可访问性或端到端 Share 交接。

## 12. 原始附件删除与保留边界

- Recipe Detail 的来源区允许二次确认删除个人私有图片/文件原件；该操作与删除 Recipe 分离。API 只按 JWT 所属 owner 和 artifact UUID 定位私有对象，不接受客户端自选 Storage path。账户切换时不在新账户的本地库记录删除成功。
- 删除成功将服务端 artifact 标记为 `expired`，新的签名下载请求不能再成功；原始 Job 与字段 evidence 仍保留，旧版本快照继续可读。客户端在 `RecipeImportRecord.sourceArtifactDeletedAt` 存储本地 tombstone，避免误展示已删除原件入口；未含此字段的旧快照默认为未删除。
- 上传意向过期为 2 小时，可用附件有效期为 7 天；到期服务端清理 endpoint 每日由受信任的调度器调用一次，密钥使用 `RECIPE_IMPORT_ARTIFACT_CLEANUP_SECRET` 环境配置，不能提交至仓库。部署/真实 Storage 验证见 #141 / #135，代码合并不代表已在生产生效。

## 13. 可选的私有图片/扫描 PDF OCR（#117 阶段实现）

- Worker 仅对 owner 校验通过、仍有效、`recipe-import-artifacts` 私有 Bucket 内的 image 或 `application/pdf` 使用 OCR。上传 10 MB 上限不变；OCR 必须限制图片每页不超过 4,000 万像素、扫描 PDF 不超过 20 页、总识别文本不超过 100,000 字符、请求最长 8 秒。
- 默认**禁用任何 OCR 外部发送**。只有项目持有人明确批准服务及个人数据处理后，才可在服务端配置 `RECIPE_IMPORT_OCR_APPROVED=true`、`RECIPE_IMPORT_OCR_PROVIDER_URL`、`RECIPE_IMPORT_OCR_APPROVED_HOST`、`RECIPE_IMPORT_OCR_API_KEY`。URL 必须为 HTTPS，主机与独立 allowlist 精确匹配，禁止重定向；禁止把 key 写入 iOS、Git、Issue 或日志。
- OCR Provider 应接收 `application/octet-stream` 请求，附带 `X-OCR-Content-Type`、`X-OCR-Max-Pages` 和 `X-OCR-Max-Pixels-Per-Page` 边界，返回 JSON `{ "pages": [{ "page_number": 1, "text": "...", "confidence": 0.98, "pixel_count": 1500000 }] }`；配置的服务必须在解码前执行页数/像素/时间上限。生产启用前还必须确认服务的访问政策、数据保留、区域合规与成本。
- 接入结果按 `ocr` evidence 记录页码、来源 artifact UUID、原文 excerpt 和 confidence；低于 0.85 的字段强制 review，含糊用量不填规范化数值。空文本、异常响应、配额不足、服务超时或未配置 Provider 均保留私有原件并进入 `needs_review`，不伪装为识别成功。
- 仓库 mock fixture 只说明契约/安全边界；未运行真实 OCR 供应商、未部署 Edge/Storage/Queue，相关线上测试仍由 #135/#138/#141 承接。

## 14. 私有 PDF 的可选中文本提取（#116 补充）

- 本项目复用 [UnJS unpdf](https://github.com/unjs/unpdf) 的 Edge/serverless Mozilla PDF.js build（MIT 许可，`npm:unpdf@1.8.1`），不实现自制 PDF 二进制解析器。仅当已通过 owner / artifact UUID / Storage 路径 / 有效期校验后，Worker 才从私有 Bucket 下载原件。
- 文件限制 10 MB、PDF 1–20 页、总提取文字不超过 100,000 字符；配置 PDF.js `maxImageSize=16777216`，逐页读取文字层以避免全页并发提取。8 秒为 best-effort 操作期限，复杂恶意 PDF 仍需 Edge runtime 资源隔离与 staging 测试，不应把源码检查视为 CPU 可抢占超时保障。
- 只有可从 PDF 文字层抽取的内容可进入字段；每页单独保存 `user / extracted` evidence（原始 artifact UUID + 页码 + excerpt），字段引用对应 evidence ID。份量原文不被强行转换为数字；食材/步骤缺失则继续 `needs_review`。
- 只有扫描 PDF 没有文字层时才可能尝试单独配置并经持有人授权的 OCR（#117）；默认未批准 Provider 时保留 PDF 原件及来源记录，返回明确的 `PDF_NO_SELECTABLE_TEXT` / `needs_review`。解析器失败、过多页和超限也不虚构成功结果。
- `artifactPDF_test.ts` 包含构造的真实 PDF 1.4 文字层 fixture 与页码/缺失/越界负例。新增 npm 依赖与 `deno.lock` 必须由具备 Deno 的受控环境更新并运行 `deno test`，当前提交不代表构建/线上验收 PASS；详见 #134/#135/#141。
