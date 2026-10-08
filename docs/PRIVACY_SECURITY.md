# Privacy & Security

## 1. 数据最小化

只收集完成食谱导入、同步、做饭和购物所必需的数据。

外部导入可能涉及：
- URL
- 网页正文
- caption
- 图片/视频片段
- OCR/ASR 文本
- AI 解析结果

必须在隐私说明中明确哪些内容会发往服务端/第三方 AI 或 OCR/ASR 服务。

## 2. 原始媒体留存

原始媒体不是永久资产。

不同 artifact 的保留策略：
- retention duration
- delete-on-success?
- delete-on-account-delete
- troubleshooting retention

Recipe import 原始附件在上传未完成时保留最多 2 小时；确认上传后保留 7 天，到期由受 secret 保护的清理函数经 Storage API 删除对象并保留最小 `expired` 元数据。附件 API 提供 owner-scoped 删除操作，但当前 App 没有单个附件的删除入口；删除账户时会清理 `recipe-import-artifacts` bucket。图片/PDF 分享导入只保留私有原件并返回 `needs_review`，当前不做 OCR/ASR/视频解析，也不声称已解析附件。

## 3. 权限

- Postgres 开启 RLS。
- recipe/job/artifact/grocery/meal plan 全部绑定 owner。
- service role 仅服务端。
- AI provider key 不下发客户端。
- Share Extension 不保存长期 secret。

## 4. 外部抓取安全

URL 抓取必须：
- 仅 HTTP/HTTPS
- 拒绝 localhost、link-local、private network、metadata endpoints
- DNS 解析后再次校验
- 每次 redirect 重新校验
- 限制响应体、媒体大小和耗时
- 校验 MIME/signature

## 5. 删除

发布前必须支持：
- 删除单个食谱及关联私有产物
- 删除账户及用户数据
- 清理孤儿 import artifacts
- 后台队列中的用户任务可撤销/失效

## 6. 版权/来源

Recipe 保存的是用户个人整理后的食谱数据。
必须保留 original source URL 与可取得的作者/平台信息，避免把第三方内容伪装成平台原创。
不得默认重新公开发布第三方内容。
