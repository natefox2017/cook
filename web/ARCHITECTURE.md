# Recipe Pals 官网架构

本方案对应 [DEV-308](https://linear.app/gengyun/issue/DEV-308)，沿用 [APP 设计规范](../docs/DESIGN_SYSTEM.md) 和 [公开分享合同](../docs/PRODUCT/RECIPE_PUBLIC_SHARING_V1.md)。

## 技术选择

使用 Next.js App Router、React 和原生 CSS，不新增 CMS、登录系统、数据库或 UI 框架。Next.js 适合本项目：介绍与协议适合静态 HTML，分享链接需要请求时读取最新内容和撤回状态；同一服务可以提供这两类页面。

部署选择 `output: 'standalone'`，运行在 Node.js 22+ 后面。纯 `output: 'export'` 需要构建时知道所有动态路径，无法自然承载 APP 随时生成的新分享字符串，而且不提供请求时的服务端快照读取。本需求采用 Node 服务包，首页仍静态生成。

官方资料：

- [Dynamic Segments](https://nextjs.org/docs/app/api-reference/file-conventions/dynamic-routes)：动态路径参数。
- [Route Handlers](https://nextjs.org/docs/app/api-reference/file-conventions/route)：请求时处理 GET，精确返回 HTML 与 HTTP 状态。
- [Standalone output](https://nextjs.org/docs/app/api-reference/config/next-config-js/output)：独立服务构建与文件追踪。
- [Static exports](https://nextjs.org/docs/app/guides/static-exports)：静态导出的动态路径限制。
- [Metadata](https://nextjs.org/docs/app/getting-started/metadata-and-og-images)：官网静态元信息；分享页沿用已有 HTML 渲染器输出安全 OG 标题/摘要。

## 页面与路径

| 路径 | 作用 | 渲染/收录 |
| --- | --- | --- |
| `/` | APP 介绍、主要能力、下载入口 | 静态生成，可收录 |
| `/download` | iPhone App Store 下载，协议入口 | 运行时校验下载配置；无有效地址则明确未开放 |
| `/privacy` | 隐私协议草稿，正式发布前替换 | 静态生成，草稿 noindex |
| `/terms` | 用户协议草稿，正式发布前替换 | 静态生成，草稿 noindex |
| `/r/[slug]` | 用户主动分享的单道菜谱 | 请求时渲染，no-store、noindex |
| `/robots.txt`、`/sitemap.xml` | 官网搜索引擎元信息 | sitemap 只含官网公开页面，不含用户分享链接 |

分享链接：`https://官网域名/r/字符串`。复用 APP 已有 `RecipePublicShareURL` 合同，字符串为 8–128 位 `A–Z a–z 0–9 _ -`。官网不是分享创建服务，不自行生成或猜测用户 token。APP 经现有 owner 发布 API 获取服务器分配的 opaque slug，再组合官网 URL；接收方点开即可读取。

保留 `/r/`，不改成 `/share/`，避免破坏 iOS 现有 URL 校验与分享海报。URL 字符串不能替代授权：公共 API 必须确认该分享已明确发布、权限有效且未撤回。

## 数据流

```text
APP owner 明确授权发布 → 现有分享服务 → 随机 opaque slug
                                       ↓
访客 → 官网 /r/slug → 服务端 HTTPS 公共快照 API /slug
                    → 8 字段白名单校验 → 转义 HTML → 访客浏览器
```

复用 `web/lib/public-recipe.mjs` 的字段、来源 URL、HTML 转义校验和阅读器输出，复用 `public-api.mjs` 的 MIME、UTF-8 与 2 MiB 响应限制，复用 `recipe-server.mjs` 的 HTTPS API 地址校验。校验模块在 `web/lib/` 共享，原有测试合并到 `web/test/`。官网 `lib/share.mjs` 负责 fetch、状态与导航整合，Route Handler 不加载私人 `Recipe`/同步数据。

成功页不需要 JavaScript、不登录、不要求安装 APP；原生 checkbox 支持食材勾选。公开响应只能包含 `title, summary, sourceURL, servings, prepMinutes, cookMinutes, ingredients, steps`。缺省份量和时间不补造。

## 缓存与错误

- 单次 API GET，8 秒超时，不跟随重定向，不携带用户凭据。配置拒绝 IP、本地地址、端口、查询串等不合法形状；API 域名应由部署方固定为经批准的服务。
- 无效 slug、不存在、撤回/过期上游 `404/410` → 访客 `404`，不泄露原因或私人字段。
- API 未配置、超时、上游故障、非法 JSON/字段 → `503`，显示稍后重试，不展示示例数据。
- 分享 HTML 包含 OG 标题/摘要，输出 `noindex/nofollow/noarchive`、严格 CSP 和 `private, no-store`。所有读取每次重新验证撤回。代理/CDN 同样不得缓存分享内容。
- 公开页面不提供列表、站内全库搜索、用户主页、关注或公共社区。既有页面可能被接收方截图或保存，撤回无法删除对方保存的副本。

## 视觉与移动适配

直接使用 APP 的本地 Lora 可变字体及 OFL。绿色前景 `#216B42`、APP 主色 `#42A85A`、暖白背景、克制照片排版；高对比按钮使用绿色前景色做背景。首页桌面双列、手机单列；导航、阅读区域、下载按钮随宽度重排。按钮至少 44px，提供键盘焦点、跳转正文、减少动效支持，长菜谱文字可断行。

UI 默认英文，遵循仓库当前 APP 语言合同。没有新增 Android 包、未验证的 App Store 链接、价格承诺或测试用户数据。协议内容不从技术隐私文档推断法律承诺，当前标为预发布草稿。

## 构建与上线边界

`npm run package` = 生产构建 + standalone 目录复制 + 静态资源/本地素材 + `.tar.gz`。所有服务依赖位于 `web/` 内，`outputFileTracingRoot` 指向 `web/`；部署包内直接包含 `server.js`、`start.mjs`、`run.sh` 和运行资源。实际 `.env` 不进入部署包。

官网只有 `web/` 一个项目；旧阅读器保留为 `lib/recipe-server.mjs` 测试兼容模块，不再单独维护 package.json 或 CSS。`run.sh` 提供统一开发、验证、打包及启动入口，`admin/` 不受影响。开发可用同一仓库，无需更改 APP 模块、数据库或 Supabase schema。

真实域名、已验证下载链接、法律定稿以及真实分享服务/撤回/匿名访问验收是部署输入。Universal Links/AASA 需要具体 APP Team ID、bundle ID 与域名关联验证，本轮不伪造关联文件。正式发布依照 [DEV-71](https://linear.app/gengyun/issue/DEV-71)、[DEV-73](https://linear.app/gengyun/issue/DEV-73) 和 [DEV-49](https://linear.app/gengyun/issue/DEV-49) 的相关上线合同完成。
