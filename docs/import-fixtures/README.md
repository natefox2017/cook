# 首批来源实测矩阵

2026-10-03，北京时间 12:17:29–12:17:36（JSON 内 UTC）。Issue #6，Mac 本地 curl GET：无 cookies/账号、无 JavaScript 执行、无媒体下载、无 ASR/OCR/AI 调用。每 URL 单次有限请求（前一轮相同条件复测也得到相同能力等级）；只保存 URL、HTTP、长度/hash、标题与结构统计，原网页/媒体未入库。脚本不是生产抓取器。

**没有任何平台完成 Cook 原生分享 → 入队 → 解析 → 食谱的端到端验收。** “URL 可表示”是机器 Input 能接收 http(s) 的结构能力，iOS 分享 UTType、短链与服务端入口均待实现；不是已验证收件。

| 来源 / 真实样本 | 实际 HTTP / 证据 | 可下的结论 | 食谱成功解析 / 发布支持 |
|---|---|---|---|
| [下厨房：猫厨房·番茄炒蛋](https://m.xiachufang.com/recipe/1000357/) | 200；Recipe JSON-LD；作者、4 条食材、步骤 string 269 字符 | 本样本结构提取可行；需拆分字符串步骤，非 269 步 | 未执行归一化/AI/原生，待验证 |
| [Good Food：Easy pancakes](https://www.bbcgoodfood.com/recipes/easy-pancakes) | 200；Recipe JSON-LD；作者、6 条食材、5 项步骤 | 本样本结构提取可行 | 未执行完整领域解析，待验证 |
| [美食天下：创意菜—番茄炒蛋](https://m.meishichina.com/blog/165984/) | 403；Just a moment；无 Recipe | 当前环境被拦截；不能根据搜索可见正文声称支持 | 未成功；保留来源+文字/图片 |
| [Bilibili：YaYa·番茄炒蛋](https://www.bilibili.com/video/BV1zW411i7Wx/) | 200；无标题/Recipe/中文目标标题 | 当前简单 HTTP 提取未得食谱正文；不是确定登录墙原因 | 未成功；保留来源+文字/图片 |
| [抖音：番茄炒蛋教程](https://www.douyin.com/video/7676101794792282102) | 200；无标题/Recipe/中文目标标题 | 页面壳并不等于视频/字幕可获取 | 未成功；保留来源+文字/图片 |
| [YouTube：小高姐·番茄炒蛋](https://www.youtube.com/watch?v=k_YkQSTvjLk) | 200；目标标题可得；无 Recipe JSON-LD | 元数据可得；探测未提取描述/字幕 | 未成功；描述/字幕/ASR 待验证 |
| 小红书 | 此轮未找到可复测公开食谱 URL；没有用首页冒充样本 | 样本缺口，短链/登录态需真实分享补测 | 完全待验证 |
| TikTok / Instagram | 此轮未测 | ReciMe 官方宣称不能转移为 Cook 能力 | 完全待验证 |
| 文字 / 图片 / PDF | 本轮仅结构正反例 | 无真机分享/OCR/PDF 质量证据 | 待验证；PDF 仍按产品 P1 |

原始统计见 [observations.json](observations.json)。`has_steps_marker` 只是全文含“步骤”，可能来自评论或脚本，不是步骤提取证据。HTTP 200 不是解析成功；单一公开样本不代表整个平台稳定支持。本文矩阵来自本轮实际请求，不从搜索摘要推断。

## 官方产品与平台依据

- [Recipe Keeper](https://recipekeeperonline.com/)官网描述网页导入、照片/OCR、导入后编辑及离线访问；这是厂商宣称，未操作该 App，也未推断其内部架构。
- [ReciMe FAQ](https://www.recime.app/)列出社交来源/截图；这是厂商支持宣称，未实测，更不证明中文平台或 Cook 支持。
- [Apple 共享数据/后台传输](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionScenarios.html)：共享容器与协调访问、扩展后台传输配置是实现依据；后台执行时机仍不受 Cook 保证。
- [Supabase Queues](https://supabase.com/docs/guides/queues)、[Private Storage](https://supabase.com/docs/guides/storage/buckets/fundamentals)：耐久队列、可见性窗口、私有对象访问语义；本阶段未配置任何服务。
- [Supabase changelog](https://supabase.com/changelog)、[2026-09-25 PostgreSQL breaking changes](https://supabase.com/changelog/postgres-15-19-17-11-breaking-changes)：已查看，本阶段仅契约，无数据库变更；实施迁移时重新核查。

## 复测与契约校验

```sh
python3 docs/import-fixtures/probe.py
python3 -m venv /tmp/cook-contract-venv
/tmp/cook-contract-venv/bin/pip install jsonschema==4.25.1 openapi-spec-validator==0.7.2
/tmp/cook-contract-venv/bin/python docs/import-fixtures/validate_contract.py
```

探测会改写本目录 observations.json；运行前检查 Git 状态。依赖只装临时环境，不引入产品运行时。契约例子是自制合成输入，不冒充真实食谱解析结果。校验不能证明事务耐久性、iOS 故障恢复或 AI 正确率；对应待验收项在导入协议末节。
