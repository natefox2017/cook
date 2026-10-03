# Recipe Import Pipeline V1

契约版本：1.0.0，Issue #6 / **待人工审阅的冻结候选**。未实现来源适配器、原生收件或后端；不得据此对外宣称平台已支持。机器结构见 [JSON Schema](schemas/import-v1.schema.json)；API 见 [OpenAPI](schemas/import-v1.openapi.json)。

## 1. 已验证范围与路线依据

[Recipe Keeper 官网](https://recipekeeperonline.com/)描述网页导入、照片/OCR 与导入后编辑；[ReciMe 官方 FAQ](https://www.recime.app/)描述社交来源及图片导入。两者共同产品模式支持“外部收集 → 私人食谱 → 可编辑”，不能证明 Cook 具备任何平台适配，也不能证明其内部队列/算法。下列耐久收件设计是依据 Apple 平台约束制定的 Cook 契约，不冒充竞品内部开发实践。

2026-10-03 的公开样本、方法与结果见 [验证矩阵](import-fixtures/README.md)。首批工程顺序：先公开 Recipe JSON-LD 网页，再文字/用户提供图片；中文社交平台先保留来源并提供文字/图片降级，完成真实分享、证据抓取及解析验收后再升级支持等级。视频 ASR/OCR/关键帧是能力边界，当前未实现或验证。

## 2. 收件与退出的硬边界

`received` 有两种明确的作用域，不得互相冒充：

| 作用域 | received 承诺 | queued 承诺 |
|---|---|---|
| App Group 本地收件箱 | 输入及附件已在共享容器耐久提交，可由主 App 恢复 | 本地不使用 queued；网络待发送仍是 received |
| 服务端 ImportJob | 输入/可读附件引用、owner、幂等记录和待入队 outbox 已在事务中提交 | job 与队列消息已耐久提交，可由消费者领取 |

Share Extension 只有在 **全部输入附件完成复制、校验和验证、manifest 耐久提交** 后才允许显示“已收下”并调用 completeRequest。NSItemProvider 返回的临时 URL、内存数组、UserDefaults 中一个标志、正在发出的 HTTP 请求均不算成功。磁盘满、容器不可用、受保护文件不可读时，不报成功，不丢弃原始输入；返回可重试失败。扩展不等待网络或 AI，不要求打开主 App。

本地 manifest 使用 `LocalEnvelope`。以 client_request_id 建独立目录：先写 staging 附件，flush/close；计算 size/hash；写 staging manifest；同步文件与目录后原子提交到 inbox。所有文件提交成功才可报告 received。扩展与主 App 通过单一 InboxStore 串行/跨进程协调访问；不得两方写同一 manifest。主 App 崩溃扫描只读取已提交 manifest，未提交 staging 清理前确认无活动写入。具体 fsync/协调/数据保护实现须原生故障注入验收。

account_id 可为空以可靠收件；未登录时留本地，登录后明确绑定当前账号，已绑定其他账号的收件不自动上传。附件路径只能相对该 envelope 目录，拒绝绝对路径、`..` 与符号链接逃逸。

## 3. 断网上传与恢复

主 App 启动/回前台/网络恢复扫描 inbox；uploading 不是锁，重启先与 background session 任务核对，仍在传输则接管回调，任务不存在则用原请求 ID/附件 hash 恢复上传；无网络、无认证或系统未调度时保留输入。background URLSession 仅改善传输机会，不能承诺扩展退出后立即启动主 App/执行解析。按 Apple 要求共享容器、扩展专属 background session identifier；后台上传用已复制文件。

每个 envelope 顺序：上传附件并确认 available → POST /recipe-imports → 持久保存服务器 job_id 与 acknowledged → 清理本地可重建副本。响应丢失使用原 client_request_id 重放；不能换 ID。401 等认证恢复后再试；429 遵守 Retry-After；超时/5xx 采用有抖动的指数退避（初始 2s，最大 5min，每轮最多 5 次），耗尽后保留本地并等待前台/用户重试，不无限忙循环。磁盘回收不得删除尚未 acknowledged 的输入。

已收到服务端 received 也可 acknowledged：服务端已承担恢复责任。服务端 outbox 扫描负责将 received 推到 queued；客户端不靠重复分享触发服务端恢复。收到 job 后轮询 GET，服务端状态更新时间用于判断停滞；暂时停滞不向用户谎报 failed。

## 4. 状态机与事务

status 表达生命周期，stage 表达内部阶段；无百分比假进度。

| 当前 status | 允许下一状态 | 条件 |
|---|---|---|
| received | queued / failed | outbox 入队成功 / 不可恢复输入问题 |
| queued | extracting / failed | 消费者获租约 / 输入不再可用 |
| extracting | parsing / queued / failed | 证据准备 / 可恢复错误退避 / 无法继续 |
| parsing | validating / queued / failed | 候选生成 / provider 暂时失败 / 不可恢复 |
| validating | completed / needs_review / queued / failed | 事务写食谱 / 局部结果与标记 / 暂时故障 / 无可用结果 |
| completed / needs_review | 无 | 终态；用户编辑改变食谱状态，不改已完成 job |
| failed | queued | 明确重试且 recoverable；保留 job_id、输入与累计次数 |

stage 顺序 receive → enqueue → resolve → extract → parse → validate → deduplicate → done；extracting 包含 resolve/extract，validating 包含 validate/deduplicate。终态 stage=done。queued 的 stage=enqueue，received 的 stage=receive。重试回 queued 并记录下一次时间，不增加额外产品状态。

消费者每次取得有效租约开始处理才增加 attempt_count；GET/重复 POST 不增加。默认每轮 5 次自动尝试，耗尽进入 failed + recoverable=true，明确重试可再开一轮。租约失效的 worker 不得提交（递增 lease generation/fencing token）；崩溃后由可见性超时重新领取，checkpoint/evidence 可复用，消息只有终态事务提交后 ack。队列可见性窗口内的投递保证不等于全流程 exactly-once。

job+幂等记录+outbox 同事务；入队/推进 queued 同事务或可证明等价的 outbox 重放；食谱+证据关联+终态同事务。DB 与 Storage 不跨服务原子：先登记 pending → 上传/校验 → available，只有 available 可入队；孤儿清理由独立恢复器负责。

## 5. Evidence-first 解析

依次尝试结构化网页数据 → caption/正文 → 字幕/ASR → OCR → 关键帧，已有足够证据即停止昂贵回退。搜索引擎摘要、评论、智能文稿不能自动视作作者原始食谱。网页 JSON-LD 的 recipeInstructions 可是 string、HowToStep[] 或 HowToSection[]，先规范化，不能把字符串长度当步骤数量。

保留 original_url、platform 与可取得的 author/source_title；canonical URL 只在成功验证目标后建立，不覆盖 original_url。字段记录 evidence_ids、origin、confidence、user_confirmed。缺数值保持 null，quantity_text 保存“适量/少许”；推断不能伪装 extracted。ready 至少需要可用标题、非空食材、可执行步骤和无关键冲突；只有实质缺失/冲突/推断才标记 needs_review，“盐适量”独自不触发。全无食谱证据时 failed，仍保留 job/source/input；有局部内容时保存 needs_review 食谱。

## 6. 幂等、去重与用户修改

- 同 owner+client_request_id、同输入摘要：返回同 job；不同输入：409 IDEMPOTENCY_CONFLICT。摘要包括原始 URL/文字或附件 hash；不包含有时效的 signed URL。
- 来源去重按 owner+可信 canonical URL/平台内容 ID；重定向前不猜 ID，未知 query 参数不盲目删除。不同请求重复来源允许复用已有 job/recipe，并保留本次原 URL 的接收记录。跨账号绝不去重/透露命中。
- 内容 hash 只用于同来源/evidence 重放；标题+食材相似仅给候选，不自动合并。用户删除后重放旧 request 不复活食谱；返回原 job 的 recipe_id=null，不能引用已删除实体。
- 用户写入/确认/清空/删除字段均以稳定实体 ID 的 field_path 与 revision 记录 user precedence；数组索引不是身份。PATCH expected_revision 不匹配返回 409，整批原子执行。
- 重解析只替换非 user 字段；worker 读取 base revision，提交时再检查锁/版本。冲突产生候选 review marker，不能覆盖用户值，不能复活用户删除的食材/步骤。用户未修改且证据改善可更新。新一轮重解析使用新 job 并引用既有 recipe，不让旧终态倒退；该触发 API 待后续 Issue，当前不增加入口。

## 7. 错误与降级

| 错误 | 自动重试 | 保留/下一步 |
|---|---|---|
| PRIVATE_OR_LOGIN_REQUIRED / FETCH_BLOCKED / UNSUPPORTED_SOURCE | 否 | 来源+局部证据；add_text / add_image |
| FETCH_TIMEOUT / PROVIDER_TIMEOUT / INTERNAL_ERROR | 有界 | 原始输入/evidence；retry |
| RATE_LIMITED | Retry-After 后有界 | 不丢任务 |
| PARSE_INCOMPLETE | 不盲重试 | 有局部结果 needs_review + edit_partial；全无结果 add_text |
| MEDIA_TOO_LARGE / INVALID_INPUT | 否 | 保留本地输入；更换输入 |
| ARTIFACT_NOT_READY | 状态确认后 | 先完成上传 |
| AUTH_REQUIRED | 不自动忙重试 | reauthenticate；不换 owner |

recoverable 表示同任务可重试；suggested_action 是领域动作，不是 UI 设计。添截图/文字属于新的补充输入任务并关联来源，具体关联入口后续实现 Issue 冻结。不绕登录墙/验证码，不拿用户评论补作者缺失的步骤。

## 8. 尚须实现验收

- 飞行模式分享后扩展结束、主 App 杀死/重启仍能恢复完整输入。
- manifest/附件各写入点杀进程、磁盘满、锁屏、App Group 并发读写与账号切换。
- 上传完成响应丢失、POST 响应丢失、重复分享、服务器事务/消息 ack 失败。
- 租约过期双 worker、重复消息、用户修改并发、清空/删除字段、已删除食谱重放。
- 真机来源分享 UTType/多附件、登录/私有内容、短链、中文文本/OCR 与实际 AI 解析质量。

以上均未执行。本阶段只执行公开 HTTP 探测与机器契约校验。
