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
- instruction
- duration_seconds?
- temperature?
- linked_ingredient_ids[]
- evidence_id
- confidence
- user_confirmed

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
