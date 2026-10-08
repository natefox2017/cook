# Data Model V1

这里只冻结领域模型，不冻结具体 SQL 列名。迁移实现前再落数据库细节。

## 1. User
- id
- profile/settings
- created_at

## 2. Recipe
- id
- owner_id
- title
- cover_artifact_id
- servings
- prep_time
- cook_time
- status: ready | needs_review | archived
- source_id
- created_at
- updated_at

## 3. RecipeIngredient
- id
- recipe_id
- raw_text
- name
- quantity
- unit
- preparation
- order
- evidence_id
- confidence
- user_confirmed

数量和单位允许为空；“适量”不得强制转换为伪精确数值。

## 4. RecipeStep
- id
- recipe_id
- order
- title?
- instruction
- temperature?
- linked_ingredient_ids[]
- timers[]
  - id
  - label
  - duration_seconds
- evidence_id
- confidence
- user_confirmed

兼容说明：
- 旧客户端/旧本地 JSON 的单个 `duration_seconds` 读取时迁移为一个默认 timer。
- 新数据仍编码第一枚 timer 的 legacy duration，保证升级期向后兼容。
- 时间范围、"until done" 等不精确信息不得自动转为精确 timer。

## 5. RecipeSource
- id
- recipe_id
- platform
- original_url
- canonical_url
- external_content_id?
- author_name?
- source_title?
- captured_at

## 6. Evidence
- id
- import_job_id
- type
- raw/derived artifact reference
- excerpt?
- timestamp_start?
- timestamp_end?
- frame_ref?
- confidence?

## 7. ImportJob
- id
- owner_id
- source_input_type
- source_input
- source_fingerprint
- idempotency_key
- stage
- status
- attempt_count
- last_error_code?
- last_error_message?
- recipe_id?
- created_at
- updated_at

## 8. Artifact
- id
- owner_id
- kind: original | screenshot | audio | transcript | ocr | keyframe | cover
- storage_path
- mime_type
- size
- checksum
- retention_policy

## 9. GroceryItem
- id
- owner_id
- normalized_name
- display_name
- quantity?
- unit?
- checked
- source_recipe_ids[]
- note?

只在单位可安全换算时合并数量。

## 10. MealPlanEntry
- id
- owner_id
- date
- meal_slot?
- recipe_id
- servings?

V1 为简单计划，不引入复杂营养/家庭协作模型。

## 11. RecipeCollection
- id
- owner_id
- name
- created_at
- updated_at

Collection 是用户自定义的平级食谱册。Favorites 仍由 Recipe.isFavorite 独立表示，不作为可删除 Collection。

## 12. RecipeCollectionMembership
- recipe_id
- collection_id

一个 Recipe 可属于多个 Collection；同一 recipe_id + collection_id 组合唯一。删除 Collection 只删除 membership，不删除 Recipe；删除 Recipe 清理对应 membership。

### 本地 snapshot 兼容
- snapshot v2 增加 collections[] 与 collectionMemberships[]。
- v1 文件缺少这两个字段时按空数组读取，不伪造历史 membership。
- 下一次成功保存或导出使用 v2。
- 旧 `cook.collections` 仅迁移 Collection 名称；没有证据的 recipe membership 不推断。

## 13. 导入冻结候选 1.0.0（Issue #6）

[机器模型](schemas/import-v1.schema.json) 的 `$defs` 是导入交换结构，不冻结 SQL 表/列，也不取代上文非导入领域。差异以本节解释：

- ImportJob 的 `status` 取产品既有八状态；`stage` 取处理阶段，不能把二者混用。API Job 不暴露原始输入/owner；内部仍保存 owner、输入摘要、source_input、idempotency_key、outbox/checkpoint/lease generation、最后错误。`error` 为统一 Error，保留每次错误审计，API 只返回最近一次。
- Recipe 增加单调整数 revision；partial recipe 的 title 可 null，status=needs_review。RecipeSource 在交换层内嵌；原始 URL 对文字/图片输入可 null，canonical URL 未确认可 null，platform=`unknown` 可用。内部保存每次接收记录（原 URL、client_request_id、时间），不能因来源去重丢掉用户原分享地址。
- Ingredient 增加 quantity_text；quantity=null + quantity_text="适量" 是正确数据。Step 中时间统一秒、温度摄氏；未证实单位不得偷偷换算。稳定 UUID 排序用 order，排序更新不改变 field_path。
- 单一 evidence_id 升为 FieldProvenance.evidence_ids[]，支持冲突多证据；user_confirmed/confidence/origin 按字段而非整条食材存。ReviewMarker 指向同样的稳定 field_path。食谱内引用的证据必须属于同 owner，不能指向其他账号。
- FieldProvenance revision 与食谱提交版本对应；origin=user 即 user_confirmed=true，推断必须 origin=inferred。用户显式删除使用持久 tombstone；恢复解析不得复活。此等跨字段语义由服务端事务校验，schema 只做形状校验。
- ready 要求 title、ingredients、steps 可用且 review_markers 无关键未决问题；needs_review 可缺字段。archived 食谱不能被后台重解析恢复 ready。

## 14. Artifact / Storage contract

不新增数据库/队列；沿用 Supabase Storage。对象必须私人访问（具体 bucket/RLS/权限另行人工审阅），不把公开网页来源当成用户附件公开的理由。存对象 key，禁止存会过期的 signed URL 作为永久引用。

内部逻辑 key：`<owner UUID>/<artifact UUID>/original` 或 `<owner UUID>/<artifact UUID>/derived/<kind>`；key 由服务端生成，不由客户端任意指定。kind 沿用 original/screenshot/audio/transcript/ocr/keyframe/cover，派生产物通过 parent_artifact_id 关联原始产物。写入不可变（新版本新 artifact ID），不覆盖用户原件。

pending → available（字节数、SHA-256、实际 MIME 与上传意图一致）或 rejected；available → deleted 仅显式删除/获批准保留策略。输入引用全部 available 才允许入队；下载消费者每次确认 owner 与可用性，签名过期重新授权获取，不变更 artifact ID。DB pending 但对象存在可校验恢复；对象缺失不能标 available；孤儿对象先核对 manifest/job 引用再清理。

source_until_user_delete：原始用户输入随来源/任务保留至用户明确删除（具体政策仍待隐私审阅）；derived_rebuildable：派生可重建，不能在活动 job/checkpoint/evidence 引用期间清理。本 PR 不决定天数、配额，不执行清理。后续上传接口 Issue 必须冻结实际文件大小/MIME 上限、配额/保留政策，再实现传输；当前公开探测 5MiB/25s 只是实验上限，不是产品限制。

LocalEnvelope 属于 App Group 文件格式，不是服务器 ImportJob：account_id 可 null、local_status received/uploading/acknowledged/blocked；schema 中所有附件引用相对已提交目录，hash/size 在耐久提交前验证。
