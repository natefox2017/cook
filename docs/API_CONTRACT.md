# API Contract V1

Issue #6：1.0.0 **待人工审阅冻结候选**。结构以 [OpenAPI 3.1](schemas/import-v1.openapi.json) 和 [JSON Schema 2020-12](schemas/import-v1.schema.json) 为准；语义/跨实体约束由本文及 [导入协议](RECIPE_IMPORT_PIPELINE.md) 共同约束。未部署。

所有导入端点 bearer 认证，owner 从认证上下文取得，不接受调用方填写 owner。时间为 UTC RFC3339，实体 ID/client_request_id 为 UUID；未知字段拒绝，null 表示无信息，省略不表示清空。

| 接口 | 请求 | 成功 |
|---|---|---|
| POST /recipe-imports | CreateImport：version、client_request_id、互斥 Input（url / text / available artifact_ids） | 202 Receipt：耐久 received 或 queued；幂等/来源命中 200 返回现有状态 job |
| GET /recipe-imports/{job_id} | 已授权任务 UUID | 200 Job：status、stage、attempt_count、next_retry_at、recipe_id、review_count、error、时间 |
| GET /recipes/{id} | 已授权食谱 UUID | 200 Recipe：source、ingredients、steps、provenance、review_markers 与 revision |
| PATCH /recipes/{id} | expected_revision + edits | 200 新 Recipe；冲突 409，整批回滚 |

202 绝不代表解析成功；queued 只承诺队列已保存，received 只承诺 job+输入+outbox 已保存。已存在 completed/needs_review job 的重放允许 200 返回终态。客户端确认响应中的 client_request_id，再耐久存 server_job_id。

PATCH field_path 使用 `/ingredients/<UUID>/<field>`、`/steps/<UUID>/<field>` 或顶层字段，不接受数组 index。允许字段必须由 Recipe 定义逐一校验，禁止 id/owner/source/provenance/revision 的客户端改写；quantity 与时间必须满足 schema，set null 是显式用户清空；remove 仅可删除 ingredients/steps 的整项（保留 tombstone）。新增整项 set 到新 UUID 路径且内容 id 匹配；linked_ingredient_ids 必须属于该 recipe 的未删除项。origin=user、user_confirmed=true 由服务器生成。schema 的通用 edit value 不能替代服务端按 field_path 的类型检查。

Error 为统一结构：code、message（非判断依据）、recoverable、suggested_action、request_id、retry_after_seconds。HTTP：400 INVALID_INPUT、401 AUTH_REQUIRED、403 已认证但无权限、404 不存在或不应披露、409 幂等/版本冲突、413 MEDIA_TOO_LARGE、429 RATE_LIMITED、500 INTERNAL_ERROR、503 暂时不可用。后台抓取/解析错误放 Job.error；不能把平台 HTTP 403 当 Cook API 403。终态 completed 的 error=null；needs_review 可包含 PARSE_INCOMPLETE。

上传边界：当前 POST 仅接受已授权且 available 的 artifact_ids。上传 URL 签发/完成确认端点尚未冻结，后续 Storage 实现 Issue 必须补充后才能实现附件端到端，不能直接从客户端传任意 storage_key/远程 signed URL 入队。Storage 的领域 contract 见 DATA_MODEL；附件还没 available 返回 ARTIFACT_NOT_READY。

既有范围保留：GET /recipes 的搜索/分页/收藏排序、POST /recipes/{id}/groceries 的安全份量合并仍属于产品基线；本次不把未定参数假称已冻结。上传、补充输入、重解析触发与用户删除接口同样留后续接口 Issue，不能由客户端各自发明。

版本：兼容新增必须显式升级并同步 schema/正反例；删除字段、修改状态/含义属于 major。合并并经人工审阅后才对后续实现冻结，本 PR 不代表实现验收。
