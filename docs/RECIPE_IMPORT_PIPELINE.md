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
