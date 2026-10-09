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

## Planned extensions (2026-10-09, **NOT YET FROZEN OR IMPLEMENTED**)

The historical V1 field list above records the existing private/import domain. Do **not** retrofit production migrations or public Web by reading this proposal as deployed schema:

- [#247 Recipe metadata](https://github.com/natefox2017/cook/issues/247): optional difficulty/cuisine/dietary tags, equipment, ingredient section IDs, yield, rights-qualified step media, preparation tips and **provenance-backed** nutrition. Maintain Codable/old snapshots and linked ingredient IDs; no inferred calorie/allergen guarantees.
- [#238/#241 AI proposal](https://github.com/natefox2017/cook/issues/238): a separate owner-scoped source/job/AI-session and reviewed edit proposal contract; record `extracted`, `AI_suggested`, `user_confirmed`, source evidence and expected revision. Do not persist unapproved model output as verified original facts.
- [#240 multiple candidates](https://github.com/natefox2017/cook/issues/240): one source may identify multiple Recipe candidates with distinct stable IDs and evidence spans. Avoid reusing source fingerprints as child IDs.
- [#242 sharing](https://github.com/natefox2017/cook/issues/242): **new isolated public snapshot schema** for individually authorized, versioned, revocable and privacy-filtered recipe fields; public request never serializes the private `Recipe`/`user_snapshots` wholesale. No automatic public profile/feed.
- [#245 invitations](https://github.com/natefox2017/cook/issues/245): retain first-party aggregate page/CTA events separately from an optional explicitly claimed invitation; no per-user installation inference from App Store clicks.

The shared field changes must be frozen and backward-compatible before parallel UI/worker implementation. Controlled staging is [#250](https://github.com/natefox2017/cook/issues/250) and a user-selected release scope gets [#251](https://github.com/natefox2017/cook/issues/251) verification.
