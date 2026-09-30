# API Contract V1

正式实现时以 OpenAPI 文件为机器可读真相源；本文件先冻结语义。

## POST /recipe-imports

创建异步导入任务。

Request：
- input_type: url | text | image | file
- url/text/artifact reference
- client_request_id
- optional platform hint

Response：
- job_id
- status: received | queued
- existing_recipe_id?（命中幂等/重复时）

必须快速返回，不等待 AI 完成。

## GET /recipe-imports/{job_id}

Response：
- job_id
- stage
- status
- progress_hint?
- recipe_id?
- review_count?
- error_code?
- recoverable
- suggested_action?

## GET /recipes

支持：
- pagination
- search
- status
- favorite
- sort

搜索至少覆盖：
- title
- ingredient normalized name
- step text

## GET /recipes/{id}

返回：
- recipe
- ingredients
- steps
- source
- review markers
- cover
- user edits

## PATCH /recipes/{id}

允许修改用户拥有的食谱字段。
用户修改必须记录 user_confirmed / precedence，不被下一次后台重解析静默覆盖。

## POST /recipes/{id}/groceries

按 servings 生成购物项。
仅在单位可安全换算时合并。

## Error shape

统一：
- code
- message
- recoverable
- suggested_action?
- request_id

示例：
- INVALID_INPUT
- UNSUPPORTED_SOURCE
- PRIVATE_OR_LOGIN_REQUIRED
- FETCH_BLOCKED
- FETCH_TIMEOUT
- MEDIA_TOO_LARGE
- PARSE_INCOMPLETE
- PROVIDER_TIMEOUT
- RATE_LIMITED
- INTERNAL_ERROR

客户端不能只按 HTTP 状态码决定 UI。
