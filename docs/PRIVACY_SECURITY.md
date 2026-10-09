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

Recipe import 原始附件在上传未完成时保留最多 2 小时；确认上传后保留 7 天，到期由受 secret 保护的清理函数经 Storage API 删除对象并保留最小 `expired` 元数据。附件 API 提供 owner-scoped 删除操作，**目前 Recipe Detail 已有“Delete Original Attachment”原件删除入口**；删除账户时必须清理 `recipe-import-artifacts` bucket。图片/扫描 PDF 可能经**显式批准且默认禁用**的 OCR provider 处理，未经授权不能外送；未配置/未验收时仍需保留来源与 `needs_review`。视频音轨/关键帧解析仍是 #239 的计划能力，不能冒称上线。

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

## 7. 新增用户授权公开分享（**规划中，尚未部署**）

- 原有私有 Recipe/notes/account/source artifacts **默认不公开**；用户必须明确选择单个 Recipe 的可公开字段范围和许可。新公开只读快照与私有 RLS 库隔离；撤销/删除后 URL、OG 预览、图片/CDN 必须停止公开。
- 第三方未经授权食谱步骤/摄影不可自动全文重发；只在用户持有必要权利时公开，其他情况用授权范围内摘要与可信来源链接，不得 AI 伪造出处。见 [#242](https://github.com/natefox2017/cook/issues/242)、[#243](https://github.com/natefox2017/cook/issues/243)、[专门分享方案](PRODUCT/RECIPE_PUBLIC_SHARING_V1.md)。
- 分享长图与二维码编码的目标必须是已获同意的 HTTPS 公共页面；同一设备可点击链接为首选，不强制扫码。Web 浏览不用登录，不因拒绝安装而隐藏用户已授权步骤。
- 邀请统计只记录有保留期限的**聚合**访问/点击；实名邀请关系需要被邀请者**自愿确认**，不得从 IP、设备指纹或未授权 Apple 安装数据恢复身份。不自动群发营销邮件或发奖励；#245/**未来** #246 另行治理。
- 公开站点、第三方 AI 处理、健康/营养数据及奖励激励上线前逐项完成地区隐私/版权、App Store 审查和 [#250 staging](https://github.com/natefox2017/cook/issues/250) / [#251 发布验收](https://github.com/natefox2017/cook/issues/251)，并更新用户隐私说明、删除/export 范围。
